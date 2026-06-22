// ============================================================
//  Animation.pde — the animation engine (MIDI-ready).
//
//  Turns the otherwise-static sketch into a continuously-animated one. The tile
//  LAYOUT is stable per seed (motif mi/mk/flip fixed in collectTile), so
//  animation never rebuilds tiles — it only modulates RENDER-TIME geometry each
//  frame: band/arc width, wing-disc size, motif/tile rotation, arc grow/shrink.
//
//  THREE LAYERS
//  ------------
//  1. Registry (AnimState `anim`): a handful of normalized -1..+1 values, the
//     single place anything writes "how much" of each effect. volatile so a
//     future MIDI thread (see setAnimValue) can write them safely.
//  2. Sources: for now, one LFO per value (driveAnimFromLFOs) on a deterministic
//     clock (animSeconds). Later a MIDI/CC handler writes the SAME registry via
//     setAnimValue and the LFOs are skipped (animSource == 1).
//  3. Snapshot: draw() calls snapshotAnim() ONCE at frame start, copying the
//     registry into plain frame-globals (animBandScale, ...) that the render
//     reads read-only — so the bg/shadow/fg passes of one frame always agree and
//     a mid-frame external write can't tear a frame.
//
//  CONNECTION SAFETY: disc scaling (and colour, reserved) preserve the seamless
//  1/3-2/3 cross-tile connection; band width, arc sweep/radius, and rotation
//  intentionally BREAK it while moving (expressive). Defaults start the safe
//  channel (disc) on and the breaking ones at depth 0.
// ============================================================

// ---- one-shot tile morph (motif cross-dissolve) ----------------
// A triggered animation (key 'o' / Controls "morph" button): each tile rolls a
// fresh TARGET motif and cross-dissolves to it -- arcs in the target but not the
// source GROW in along their path, source-only arcs RETRACT (see TileGeom morph +
// appendTruncated). At morphT==1 the targets COMMIT (mi:=miTo) and the morph stops.
// The layout (leaves) is never rebuilt -- only the per-tile motif index changes.
volatile boolean morphActive = false;   // a morph is currently playing / pinned
volatile float   morphT = 0;            // 0..1 raw progress (smoothstepped by morphMix)
float   morphDurationSec = 1.5;         // seconds for one morph
int     morphGen = 0;                   // increments per morph -> varies the target roll
float   morphSpread = 0;                // staggered morph: fraction of the timeline spent
                                        // staggering tile start/finish times (0 = all in sync)
boolean headlessMorph = false;          // TRUCHET_MORPH pins one frame (no advance/commit)
volatile boolean morphRequested = false; // Controls button -> start (uniform) on the viz thread
volatile boolean morphStaggerRequested = false; // Controls button -> start (staggered)

float morphMix() { float t = constrain(morphT, 0, 1); return t * t * (3 - 2 * t); }   // smoothstep
// Per-tile morph mix: with a stagger, remap the global phase through this tile's own
// window [morphOff, morphOff + (1-morphSpread)] so tiles start + finish at slightly
// different times. With no stagger this is just the global morphMix().
float morphLocalMix(Tile t) {
  if (morphSpread <= 0) return morphMix();
  float span = max(1e-4, 1 - morphSpread);
  float u = constrain((morphT - t.morphOff) / span, 0, 1);
  return u * u * (3 - 2 * u);
}

// ---- engine state ----------------------------------------------
volatile boolean animEnabled = false;   // continuous loop running?
float   animFrameRate = 30;             // target fps while animating
volatile float animSeconds = 0;         // animation clock (seconds)
boolean headlessAnimOverride = false;   // TRUCHET_ANIM_T/ANIM pin a deterministic frame
int     animSource = 0;                 // 0 = built-in LFOs, 1 = external (MIDI/env)
float   animRateHz = 0.25;              // master LFO rate (shared by all LFOs)

// ---- the registry (MIDI-ready seam) ----------------------------
// Each value is normalized to -1..+1; 0 = neutral (no visible effect).
class AnimState {
  volatile float bandWidthMod = 0;   // band/arc stroke width   (BREAKS connection)
  volatile float discMod      = 0;   // wing-disc size          (connection-safe)
  volatile float rotationMod  = 0;   // whole-tile rotation     (BREAKS connection)
  volatile float arcSweepMod  = 0;   // arc sweep grow/shrink   (BREAKS connection)
  volatile float arcRadiusMod = 0;   // arc radius grow/shrink  (BREAKS connection)
  volatile float colorMod     = 0;   // reserved (connection-safe); not yet rendered
  volatile float pulseSpeedMod = 0;  // light-pulse travel speed (overlay; see Pulse.pde)
  volatile float pulseWidthMod = 0;  // light-pulse trail length
  volatile float pulseGlowMod  = 0;  // light-pulse glow intensity
}
AnimState anim = new AnimState();

// The single sink an external source (a future MIDI handler) writes to from its
// own thread. v01 is a 0..1 knob value; mapped to the registry's -1..+1 (0.5 =
// neutral). Calling this is thread-safe (each field is an independent volatile).
void setAnimValue(String name, float v01) {
  float m = constrain(v01, 0, 1) * 2 - 1;
  if      (name.equals("bandWidthMod")) anim.bandWidthMod = m;
  else if (name.equals("discMod"))      anim.discMod      = m;
  else if (name.equals("rotationMod"))  anim.rotationMod  = m;
  else if (name.equals("arcSweepMod"))  anim.arcSweepMod  = m;
  else if (name.equals("arcRadiusMod")) anim.arcRadiusMod = m;
  else if (name.equals("colorMod"))     anim.colorMod     = m;
  else if (name.equals("pulseSpeedMod")) anim.pulseSpeedMod = m;
  else if (name.equals("pulseWidthMod")) anim.pulseWidthMod = m;
  else if (name.equals("pulseGlowMod"))  anim.pulseGlowMod  = m;
}

// ---- demo sources: one LFO per registry value ------------------
class Lfo {
  int   wave;     // 0 sine, 1 triangle, 2 saw, 3 square
  float rateHz;   // cycles per second
  float depth;    // 0..1 output amplitude
  float phase;    // 0..1 phase offset
  Lfo(int wave, float rateHz, float depth, float phase) {
    this.wave = wave; this.rateHz = rateHz; this.depth = depth; this.phase = phase;
  }
  float eval(float tSec) {                 // -> -1..+1 scaled by depth
    float ph = (tSec * rateHz + phase) % 1.0;
    if (ph < 0) ph += 1;
    float v;
    switch (wave) {
      case 1:  v = ph < 0.5 ? (4 * ph - 1) : (3 - 4 * ph);  break;   // triangle
      case 2:  v = 2 * ph - 1;                              break;   // saw
      case 3:  v = ph < 0.5 ? 1 : -1;                       break;   // square
      default: v = sin(ph * TWO_PI);                        break;   // sine
    }
    return depth * v;
  }
}
Lfo lfoBand, lfoDisc, lfoRot, lfoSweep, lfoRadius;

void initAnim() {
  // light-pulse defaults (px), resolution-scaled; env vars / Controls override.
  pulseSpeed = width * 0.16;
  pulseTrail = min(160, 0.12 * width);
  // sine LFOs at the master rate; safe channel (disc) on, breaking ones off.
  lfoBand   = new Lfo(0, animRateHz, 0.0, 0.00);
  lfoDisc   = new Lfo(0, animRateHz, 0.6, 0.00);
  lfoRot    = new Lfo(0, animRateHz, 0.0, 0.25);
  lfoSweep  = new Lfo(0, animRateHz, 0.0, 0.50);
  lfoRadius = new Lfo(0, animRateHz, 0.0, 0.75);
}

void driveAnimFromLFOs() {
  anim.bandWidthMod = lfoBand.eval(animSeconds);
  anim.discMod      = lfoDisc.eval(animSeconds);
  anim.rotationMod  = lfoRot.eval(animSeconds);
  anim.arcSweepMod  = lfoSweep.eval(animSeconds);
  anim.arcRadiusMod = lfoRadius.eval(animSeconds);
}

// ---- per-frame snapshot (read by the render passes, read-only) --
// Bounded base*mod factors; all = identity when the registry is neutral.
float animBandScale = 1, animDiscScale = 1, animArcSweep = 1, animArcRadius = 1, animRotOffset = 0;
// light-pulse frame globals (read by Pulse.pde; identity when neutral)
float pulseSpeedScale = 1, pulseTrailScale = 1, pulseGlowScale = 1;

void snapshotAnim() {
  animBandScale = 1 + 0.5 * anim.bandWidthMod;   // 0.5x .. 1.5x of side/3
  animDiscScale = 1 + 0.5 * anim.discMod;        // 0.5x .. 1.5x disc radius
  animArcSweep  = 1 + 0.4 * anim.arcSweepMod;    // 0.6x .. 1.4x arc sweep
  animArcRadius = 1 + 0.4 * anim.arcRadiusMod;   // 0.6x .. 1.4x arc radius
  animRotOffset = anim.rotationMod * PI;         // +/- half turn
  pulseSpeedScale = 1 + 0.7 * anim.pulseSpeedMod;  // 0.3x .. 1.7x travel speed
  pulseTrailScale = 1 + 0.6 * anim.pulseWidthMod;  // trail length
  pulseGlowScale  = 1 + 0.6 * anim.pulseGlowMod;   // glow intensity
}

// Called from draw() top. Advances the clock + drives the registry when active,
// or forces neutral when idle (so a non-animating frame == the static render).
void updateAnim() {
  if (animEnabled || headlessAnimOverride) {
    if (animEnabled && !headlessAnimOverride) animSeconds += 1.0 / animFrameRate;
    if (animSource == 0) driveAnimFromLFOs();   // source 1 holds external/env values
  } else {
    anim.bandWidthMod = anim.discMod = anim.rotationMod = 0;
    anim.arcSweepMod  = anim.arcRadiusMod = 0;
  }
  // one-shot morph: advance the phase, commit + stop at the end (headless pins it).
  if (morphActive && !headlessMorph) {
    morphT += (1.0 / animFrameRate) / max(0.05, morphDurationSec);
    if (morphT >= 1.0) commitMorph();
  }
  snapshotAnim();
}

// Trigger a morph: roll a fresh target motif per leaf and start the cross-dissolve.
// Called on the viz thread (keys 'o'/'O', or the request flags from Controls).
// spread = 0 -> all tiles morph in sync; spread > 0 -> per-tile start/finish offsets.
void beginMorph(float spread) {
  if (morphActive) return;
  morphSpread = constrain(spread, 0, 0.9);
  if (leaves == null || leaves.isEmpty()) { dirtyLayout = true; }   // build first, roll in rebuildLeaves
  morphActive = true; morphT = 0;
  if (leaves != null && !leaves.isEmpty()) rollMorphTargets();
  frameRate(animFrameRate);                 // so playback matches morphDurationSec
  loop();                                   // animate the morph (a static sketch is noLoop)
}
void startMorph()          { beginMorph(0); }      // uniform: all tiles in sync
void startMorphStaggered() { beginMorph(0.4); }    // staggered start/finish times

// Commit the targets and stop. Mutates only the per-tile motif index on existing
// leaves -- never sets dirtyLayout / rebuilds geometry (the layout is unchanged).
void commitMorph() {
  if (leaves != null) for (Tile t : leaves) { t.mi = t.miTo; t.mk = t.mkTo; }
  morphActive = false; morphT = 0; morphGen++;
  if (!animEnabled) noLoop();               // return to one-shot if we were static
}

// Roll a deterministic target motif for every leaf (no random() -> the steady-state
// RNG stream + layout are untouched, so morph-off is byte-identical and a pinned
// headless phase is reproducible). Keyed on the motif (twin-safe) under structural
// symmetry, on position otherwise (per-tile variety); straddlers get a symmetric roll.
void rollMorphTargets() {
  for (Tile t : leaves) {
    rollOneTarget(t);
    t.morphOff = (morphSpread > 0) ? morphSpread * morphHash01(t, 2) : 0;   // staggered start
  }
}
void rollOneTarget(Tile t) {
  if (t.trap) { t.miTo = pickWeightedR(TRAP_W, morphHash01(t, 0)); t.mkTo = 0; return; }
  boolean onV = (symmetryMode == 5 || symmetryMode == 7) && shapeMode != 3 && straddleV(t);
  boolean onH = (symmetryMode == 6 || symmetryMode == 7) && shapeMode != 3 && straddleH(t);
  if (t.straddle && (onV || onH)) { rollSymmetricTarget(t, onV, onH); return; }
  t.miTo = pickWeightedR(weightsFor(t.n), morphHash01(t, 0));
  t.mkTo = (int) floor(morphHash01(t, 1) * t.n) % t.n;
}
// Straddler: pick a target symmetric about every axis it straddles (mirror of
// pickSymmetricMotifMulti, hash-driven). Keeps the on-axis tile its own mirror
// throughout the morph, so the structural-symmetry seam stays clean.
void rollSymmetricTarget(Tile t, boolean onV, boolean onH) {
  int n = t.n;
  int[][][] alpha = connsFor(n);
  float[] w = weightsFor(n);
  int c0V = ((round((PI - 2 * t.rot) / (TWO_PI / n))) % n + n) % n;
  int c0H = ((round((-2 * t.rot) / (TWO_PI / n))) % n + n) % n;
  ArrayList<int[]> cand = new ArrayList<int[]>(); float total = 0;
  for (int mi = 0; mi < alpha.length; mi++)
    for (int mk = 0; mk < n; mk++) {
      if (onV && !selfMirrorMotif(alpha[mi], mk, c0V, n, max(1, anchorsPerSide))) continue;
      if (onH && !selfMirrorMotif(alpha[mi], mk, c0H, n, max(1, anchorsPerSide))) continue;
      cand.add(new int[]{ mi, mk }); total += w[mi];
    }
  if (cand.isEmpty() || total <= 0) { t.miTo = -1; t.mkTo = 0; return; }
  float r = morphHash01(t, 0) * total; int[] pick = cand.get(cand.size() - 1);
  for (int[] cm : cand) { r -= w[cm[0]]; if (r < 0) { pick = cm; break; } }
  t.miTo = pick[0]; t.mkTo = pick[1];
}
// A stable 0..1 hash for the target roll. Under structural symmetry (modes 4-7) it
// keys on the motif + depth so a twin and its source (same mi/mk/depth) roll the
// SAME target -> the twin renders the exact mirror of the source's morph. Otherwise
// it keys on position so neighbouring tiles morph independently.
float morphHash01(Tile t, int salt) {
  int h;
  if (symmetryMode >= 4 && shapeMode != 3) { h = t.mi; h = h * 31 + t.mk; h = h * 31 + t.depth; }
  else { h = Float.floatToIntBits(t.cx); h = h * 31 + Float.floatToIntBits(t.cy); h = h * 31 + t.depth; }
  h = h * 31 + morphGen; h = h * 31 + salt;
  h ^= (h >>> 16); h *= 0x7feb352d; h ^= (h >>> 15); h *= 0x846ca68b; h ^= (h >>> 16);
  return (h & 0x7fffffff) / 2147483647.0;
}
// pickWeighted with an externally supplied 0..1 value (vs random()) -> deterministic.
int pickWeightedR(float[] w, float r01) {
  float total = 0; for (float x : w) total += x;
  if (total <= 0) return -1;
  float r = r01 * total;
  for (int t = 0; t < w.length; t++) { r -= w[t]; if (r < 0) return t; }
  return w.length - 1;
}

// Start/stop the continuous loop. Static editing stays one-shot (noLoop+redraw).
void setAnimEnabled(boolean on) {
  animEnabled = on;
  if (on) { frameRate(animFrameRate); loop(); }
  else    { noLoop(); redraw(); }
}

void applyAnimRate(float hz) {
  animRateHz = hz;
  lfoBand.rateHz = lfoDisc.rateHz = lfoRot.rateHz = lfoSweep.rateHz = lfoRadius.rateHz = hz;
}
