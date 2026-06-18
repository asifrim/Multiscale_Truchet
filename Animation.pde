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

void snapshotAnim() {
  animBandScale = 1 + 0.5 * anim.bandWidthMod;   // 0.5x .. 1.5x of side/3
  animDiscScale = 1 + 0.5 * anim.discMod;        // 0.5x .. 1.5x disc radius
  animArcSweep  = 1 + 0.4 * anim.arcSweepMod;    // 0.6x .. 1.4x arc sweep
  animArcRadius = 1 + 0.4 * anim.arcRadiusMod;   // 0.6x .. 1.4x arc radius
  animRotOffset = anim.rotationMod * PI;         // +/- half turn
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
  snapshotAnim();
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
