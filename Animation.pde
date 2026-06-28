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
// Per-multiscale-level morph duration (seconds): each depth level can morph at its
// own speed, so finer (deeper) levels of detail can morph faster than coarse ones.
// Indexed by tile depth (clamped); depth can run 0..maxDepth (maxDepth caps at 6).
final int MAX_MORPH_LV = 7;             // depth 0..6
float[] morphDurLevel = { 1.5, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5 };
float morphDurFor(int depth) { return max(0.05, morphDurLevel[constrain(depth, 0, MAX_MORPH_LV - 1)]); }
// Longest duration among the levels actually in play -- the one-shot timeline runs
// this long, and each level's progress is scaled up so it finishes in its own time.
float morphMaxDur() {
  float m = 0.05;
  for (int d = 0; d <= min(maxDepth, MAX_MORPH_LV - 1); d++) m = max(m, morphDurFor(d));
  return m;
}
int     morphGen = 0;                   // increments per morph -> varies the target roll
float   morphSpread = 0;                // staggered morph: fraction of the timeline spent
                                        // staggering tile start/finish times (0 = all in sync)
boolean headlessMorph = false;          // TRUCHET_MORPH pins one frame (no advance/commit)
volatile boolean morphRequested = false; // Controls button -> start (uniform) on the viz thread
volatile boolean morphStaggerRequested = false; // Controls button -> start (staggered)

// ---- continuous "morph" animation mode -------------------------------------
// Rather than one global one-shot, each tile independently rolls a per-frame
// chance of STARTING its own morph -- ignored while it is already morphing --
// then cross-dissolves to a fresh target with the selected easing. The result
// is a constantly shifting field. Per-tile state lives on the Tile (mphT phase,
// morphCount); the trigger + target rolls are hash-driven (morphTrigger /
// morphHash01 salted by morphFrame + morphCount), so a structural-symmetry twin
// fires on the same frame as its source and rolls the same target, staying
// mirror-exact. Both the one-shot (morphActive) and this mode engage the render
// path via morphRendering(); with neither on the render is byte-identical.
boolean morphMode = false;                  // continuous per-tile random morphing on?
float   morphProb = 0.5;                     // expected morph starts per tile per SECOND
volatile boolean morphModeChanged = false;   // Controls toggle -> apply on the viz thread
int     morphFrame = 0;                      // frame counter = deterministic trigger clock
int     headlessMorphFrames = 0;             // TRUCHET_MORPH_FRAMES: pre-roll N steps in a headless frame

// Does any morph engage the render path (so a tile with mi != miTo cross-dissolves)?
boolean morphRendering() { return morphActive || morphMode; }

float morphMix() { return applyMorphEasing(constrain(morphT, 0, 1)); }
// Per-tile morph mix. In continuous mode each tile carries its own phase (mphT).
// One-shot: the global morphT runs over morphMaxDur(); each tile's progress is
// scaled by morphMaxDur/level-duration so a finer (shorter-duration) level reaches
// mix 1 sooner and a coarse level finishes last (when all levels are equal the
// scale is 1 -> byte-identical to before). The stagger window still applies.
float morphLocalMix(Tile t) {
  if (morphMode) return applyMorphEasing(constrain(t.mphT, 0, 1));
  float scale = morphMaxDur() / morphDurFor(t.depth);     // >= 1; finer levels morph faster
  float base = morphT;
  if (morphSpread > 0) base = (morphT - t.morphOff) / max(1e-4, 1 - morphSpread);
  return applyMorphEasing(constrain(base * scale, 0, 1));
}

// One continuous-mode step (called from draw() after the layout is built/synced):
// advance every morphing tile, commit at phase 1, and roll the trigger for idle
// tiles. dt-normalized so playback speed is frame-rate independent. morphProb is a
// per-SECOND rate -> per-frame chance = morphProb / fps.
void updateMorphMode() {
  if (leaves == null || leaves.isEmpty()) return;
  morphFrame++;
  float perFrame  = 1.0 / animFrameRate;
  float pPerFrame = constrain(morphProb / animFrameRate, 0, 1);
  for (Tile t : leaves) {
    float dtNorm = perFrame / morphDurFor(t.depth);     // finer levels advance faster
    boolean morphing = (t.mi != t.miTo) || (t.mk != t.mkTo);
    if (morphing) {
      t.mphT += dtNorm;
      if (t.mphT >= 1.0) { t.mi = t.miTo; t.mk = t.mkTo; t.mphT = 0; }   // commit
    } else if (morphTrigger(t, pPerFrame)) {
      t.morphCount++;            // vary the next target roll (twin shares the count)
      rollOneTarget(t);          // sets miTo/mkTo (a roll == current motif is a no-op)
      t.mphT = 0;
    }
  }
}

// Deterministic per-frame morph trigger. Keyed twin-shared under structural
// symmetry (motif + depth, like morphHash01) so a twin and its source fire on the
// SAME frame; on position otherwise. morphFrame supplies the time variation.
boolean morphTrigger(Tile t, float pPerFrame) {
  if (pPerFrame <= 0) return false;
  int h;
  if (symmetryMode >= 4 && shapeMode != 3) { h = t.mi; h = h * 31 + t.mk; h = h * 31 + t.depth; }
  else { h = Float.floatToIntBits(t.cx); h = h * 31 + Float.floatToIntBits(t.cy); h = h * 31 + t.depth; }
  h = h * 31 + morphFrame; h = h * 31 + 0x51ed5a17;     // trigger salt (distinct stream)
  return (hashMix(h) & 0x7fffffff) / 2147483647.0 < pPerFrame;
}

// Settle every leaf to "not morphing" (target := current). New leaves default
// miTo/mkTo to 0, which would differ from a non-zero motif and read as an instant
// morph; this is run when continuous mode engages (and after a layout rebuild
// while it is on) so tiles start from a clean, idle state.
void syncMorphIdle() {
  if (leaves == null) return;
  for (Tile t : leaves) { t.miTo = t.mi; t.mkTo = t.mk; t.mphT = 0; }
}

// Apply a Controls toggle of continuous morph mode on the viz thread (it mutates
// leaves + the loop state). Engaging it keeps the sketch looping; disengaging it
// commits any in-flight morphs and returns to one-shot if nothing else animates.
void applyMorphModeChange() {
  if (morphMode) {
    if (leaves == null || leaves.isEmpty()) dirtyLayout = true;   // build, then syncMorphIdle in rebuildLeaves
    else syncMorphIdle();
    frameRate(animFrameRate);
    loop();
  } else {
    if (leaves != null) for (Tile t : leaves) { t.mi = t.miTo; t.mk = t.mkTo; t.mphT = 0; }
    if (!anyAnimRunning()) noLoop();
  }
}

// ---- easing functions (https://github.com/ai/easings.net) ----------------
// The morph eases its raw 0..1 progress through the selected curve. Index 0 is
// the original smoothstep, so a default morph is byte-identical to before; index
// 1 is linear; 2.. are the easings.net families (In/Out/InOut of each).
int morphEasing = 0;   // index into MORPH_EASE_NAMES (Controls "ease" button, TRUCHET_MORPH_EASE)
final String[] MORPH_EASE_NAMES = {
  "smoothstep", "linear",
  "inSine",    "outSine",    "inOutSine",
  "inQuad",    "outQuad",    "inOutQuad",
  "inCubic",   "outCubic",   "inOutCubic",
  "inQuart",   "outQuart",   "inOutQuart",
  "inQuint",   "outQuint",   "inOutQuint",
  "inExpo",    "outExpo",    "inOutExpo",
  "inCirc",    "outCirc",    "inOutCirc",
  "inBack",    "outBack",    "inOutBack",
  "inElastic", "outElastic", "inOutElastic",
  "inBounce",  "outBounce",  "inOutBounce"
};

// Parse TRUCHET_MORPH_EASE: an index (0..N-1) or a case-insensitive name match.
int parseMorphEase(String s) {
  if (s == null || s.length() == 0) return morphEasing;
  try { return constrain(Integer.parseInt(s), 0, MORPH_EASE_NAMES.length - 1); }
  catch (NumberFormatException e) { }
  for (int i = 0; i < MORPH_EASE_NAMES.length; i++)
    if (MORPH_EASE_NAMES[i].equalsIgnoreCase(s)) return i;
  return morphEasing;
}

// ---- morph band cap style -------------------------------------------------
// During a one-shot morph a band end is truncated to its reveal fraction, so a
// growing/retracting end sits in the tile INTERIOR (not at a tile edge). The
// classic flush band cap (CAP_BUTT for square/triangle/trapezoid) reads as an
// abrupt straight cut there; morphCap rounds/squares those interior ends. Only
// applied while a morph is active (off => byte-identical), and the tile clip
// still flattens any band that genuinely ends at an edge, so the seamless
// edge invariant is untouched. Index 0 = butt (default, the original look).
int morphCap = 0;   // index into MORPH_CAP_NAMES (Controls "cap" button, TRUCHET_MORPH_CAP)
final String[] MORPH_CAP_NAMES = { "butt", "round", "square" };
final int[]    MORPH_CAP_AWT   = {
  java.awt.BasicStroke.CAP_BUTT, java.awt.BasicStroke.CAP_ROUND, java.awt.BasicStroke.CAP_SQUARE
};

// Parse TRUCHET_MORPH_CAP: an index (0..N-1) or a case-insensitive name match.
int parseMorphCap(String s) {
  if (s == null || s.length() == 0) return morphCap;
  try { return constrain(Integer.parseInt(s), 0, MORPH_CAP_NAMES.length - 1); }
  catch (NumberFormatException e) { }
  for (int i = 0; i < MORPH_CAP_NAMES.length; i++)
    if (MORPH_CAP_NAMES[i].equalsIgnoreCase(s)) return i;
  return morphCap;
}

// easeOutBounce, shared by the three bounce variants (easings.net).
float easeOutBounce(float x) {
  final float n1 = 7.5625, d1 = 2.75;
  if (x < 1 / d1)        return n1 * x * x;
  else if (x < 2 / d1) { x -= 1.5  / d1; return n1 * x * x + 0.75; }
  else if (x < 2.5/ d1){ x -= 2.25 / d1; return n1 * x * x + 0.9375; }
  else                 { x -= 2.625/ d1; return n1 * x * x + 0.984375; }
}

// Map raw progress x (0..1) through the curve selected by morphEasing. Formulas
// are the verbatim easings.net definitions.
float applyMorphEasing(float x) {
  final float c1 = 1.70158, c2 = c1 * 1.525, c3 = c1 + 1;
  final float c4 = TWO_PI / 3, c5 = TWO_PI / 4.5;
  switch (morphEasing) {
    case 0:  return x * x * (3 - 2 * x);                                            // smoothstep (default)
    case 1:  return x;                                                              // linear
    case 2:  return 1 - cos((x * PI) / 2);                                          // inSine
    case 3:  return sin((x * PI) / 2);                                              // outSine
    case 4:  return -(cos(PI * x) - 1) / 2;                                         // inOutSine
    case 5:  return x * x;                                                          // inQuad
    case 6:  return 1 - (1 - x) * (1 - x);                                          // outQuad
    case 7:  return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2;               // inOutQuad
    case 8:  return x * x * x;                                                      // inCubic
    case 9:  return 1 - pow(1 - x, 3);                                             // outCubic
    case 10: return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2;           // inOutCubic
    case 11: return x * x * x * x;                                                  // inQuart
    case 12: return 1 - pow(1 - x, 4);                                             // outQuart
    case 13: return x < 0.5 ? 8 * x * x * x * x : 1 - pow(-2 * x + 2, 4) / 2;       // inOutQuart
    case 14: return x * x * x * x * x;                                              // inQuint
    case 15: return 1 - pow(1 - x, 5);                                             // outQuint
    case 16: return x < 0.5 ? 16 * x * x * x * x * x : 1 - pow(-2 * x + 2, 5) / 2;  // inOutQuint
    case 17: return x == 0 ? 0 : pow(2, 10 * x - 10);                               // inExpo
    case 18: return x == 1 ? 1 : 1 - pow(2, -10 * x);                              // outExpo
    case 19: return x == 0 ? 0 : x == 1 ? 1                                         // inOutExpo
               : x < 0.5 ? pow(2, 20 * x - 10) / 2 : (2 - pow(2, -20 * x + 10)) / 2;
    case 20: return 1 - sqrt(1 - pow(x, 2));                                        // inCirc
    case 21: return sqrt(1 - pow(x - 1, 2));                                        // outCirc
    case 22: return x < 0.5 ? (1 - sqrt(1 - pow(2 * x, 2))) / 2                      // inOutCirc
                            : (sqrt(1 - pow(-2 * x + 2, 2)) + 1) / 2;
    case 23: return c3 * x * x * x - c1 * x * x;                                    // inBack
    case 24: return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2);                    // outBack
    case 25: return x < 0.5                                                         // inOutBack
               ? (pow(2 * x, 2) * ((c2 + 1) * 2 * x - c2)) / 2
               : (pow(2 * x - 2, 2) * ((c2 + 1) * (2 * x - 2) + c2) + 2) / 2;
    case 26: return x == 0 ? 0 : x == 1 ? 1                                         // inElastic
               : -pow(2, 10 * x - 10) * sin((10 * x - 10.75) * c4);
    case 27: return x == 0 ? 0 : x == 1 ? 1                                         // outElastic
               : pow(2, -10 * x) * sin((10 * x - 0.75) * c4) + 1;
    case 28: return x == 0 ? 0 : x == 1 ? 1                                         // inOutElastic
               : x < 0.5 ? -(pow(2, 20 * x - 10) * sin((20 * x - 11.125) * c5)) / 2
                         :  (pow(2, -20 * x + 10) * sin((20 * x - 11.125) * c5)) / 2 + 1;
    case 29: return 1 - easeOutBounce(1 - x);                                       // inBounce
    case 30: return easeOutBounce(x);                                              // outBounce
    case 31: return x < 0.5 ? (1 - easeOutBounce(1 - 2 * x)) / 2                     // inOutBounce
                            : (1 + easeOutBounce(2 * x - 1)) / 2;
    default: return x * x * (3 - 2 * x);
  }
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
  // one-shot morph: advance the global phase over the SLOWEST level's duration, so
  // every level has finished (finer ones earlier, see morphLocalMix) by morphT==1;
  // commit + stop there (headless pins it).
  if (morphActive && !headlessMorph) {
    morphT += (1.0 / animFrameRate) / morphMaxDur();
    if (morphT >= 1.0) commitMorph();
  }
  // gradient-wheel schemes (5/6): advance the wheel phase (turns per second).
  // Headless pins it via TRUCHET_WHEEL_PHASE so a single frame is deterministic.
  if (colorScheme >= 5 && !headlessWheel) {
    wheelPhase += wheelRate * (1.0 / animFrameRate);
    wheelPhase -= floor(wheelPhase);
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
  if (!anyAnimRunning()) noLoop();           // return to one-shot if nothing else animates
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
  if (t.trap) { t.miTo = pickWeightedR(TRAP_W, morphHash01(t, morphSalt(t, 0))); t.mkTo = 0; return; }
  boolean onV = (symmetryMode == 5 || symmetryMode == 7) && shapeMode != 3 && straddleV(t);
  boolean onH = (symmetryMode == 6 || symmetryMode == 7) && shapeMode != 3 && straddleH(t);
  if (t.straddle && (onV || onH)) { rollSymmetricTarget(t, onV, onH); return; }
  t.miTo = pickWeightedR(weightsFor(t.n), morphHash01(t, morphSalt(t, 0)));
  t.mkTo = (int) floor(morphHash01(t, morphSalt(t, 1)) * t.n) % t.n;
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
  float r = morphHash01(t, morphSalt(t, 0)) * total; int[] pick = cand.get(cand.size() - 1);
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
  return (hashMix(h) & 0x7fffffff) / 2147483647.0;
}
// Final integer avalanche (splitmix-style), shared by the morph hashes.
int hashMix(int h) {
  h ^= (h >>> 16); h *= 0x7feb352d; h ^= (h >>> 15); h *= 0x846ca68b; h ^= (h >>> 16);
  return h;
}
// Salt stride per continuous-mode morph: morphCount*STRIDE + base keeps each
// successive roll on a fresh stream, and -- because the one-shot path never
// increments morphCount (always 0) -- collapses to the original base salt there,
// so one-shot target rolls stay byte-identical.
final int MORPH_SALT_STRIDE = 8;
int morphSalt(Tile t, int base) { return t.morphCount * MORPH_SALT_STRIDE + base; }
// pickWeighted with an externally supplied 0..1 value (vs random()) -> deterministic.
int pickWeightedR(float[] w, float r01) {
  float total = 0; for (float x : w) total += x;
  if (total <= 0) return -1;
  float r = r01 * total;
  for (int t = 0; t < w.length; t++) { r -= w[t]; if (r < 0) return t; }
  return w.length - 1;
}

// Is any continuous animation active (so the sketch must keep looping)? Covers the
// LFO animation, one-shot + continuous morph, and the gradient-wheel scheme.
boolean anyAnimRunning() {
  return animEnabled || morphActive || morphMode || (colorScheme >= 5 && wheelRate != 0);
}

// Authoritative loop control: loop while anything animates, else go static. Called
// at the end of draw() so a Controls-thread change (scheme, wheel rate) settles on
// the right loop state on the viz thread without cross-thread loop()/noLoop().
void refreshLoopState() {
  if (anyAnimRunning()) { frameRate(animFrameRate); loop(); }
  else                    noLoop();
}

// Start/stop the continuous loop. Static editing stays one-shot (noLoop+redraw).
void setAnimEnabled(boolean on) {
  animEnabled = on;
  if (on) { frameRate(animFrameRate); loop(); }
  else if (anyAnimRunning()) { redraw(); }   // another mode (morph / wheel) still needs the loop
  else    { noLoop(); redraw(); }
}

void applyAnimRate(float hz) {
  animRateHz = hz;
  lfoBand.rateHz = lfoDisc.rateHz = lfoRot.rateHz = lfoSweep.rateHz = lfoRadius.rateHz = hz;
}
