// ============================================================
//  ControlWindow.pde — a second window with parameter controls.
//
//  Multi-window approach: this is its own PApplet, launched from the main
//  sketch's setup() with PApplet.runSketch(). It holds a reference to the
//  main sketch (`parent`); widgets write straight to the main sketch's
//  globals and call parent.redraw() (the visualization is noLoop(), so it
//  only repaints on demand).
//
//  Widgets are drawn immediate-mode (no GUI library): sliders for the
//  numeric params, check-toggles for the booleans, a duotone/multi scheme
//  switch, a palette selector with live swatches, and New seed / Save.
//
//  Notes on the built-in approach:
//    * size() must live in settings() for a PApplet subclass (the
//      preprocessor only relocates it for the main tab).
//    * This window runs on its own animation thread; reads of parent state
//      for display are best-effort, which is fine for a control panel.
// ============================================================

public class ControlWindow extends PApplet {
  Multiscale_Truchet parent;

  final int margin = 18;
  final int rowH   = 50;
  float trackX0, trackX1;

  ArrayList<Slider> sliders = new ArrayList<Slider>();
  Toggle tgWinged, tgInvert;
  Button bShape, bScheme, bSym, bPrev, bNext, bRot, bSeed, bSave;
  Slider active = null;

  int palLabelY, swatchY, swatchH;

  ControlWindow(Multiscale_Truchet parent) { this.parent = parent; }

  public void settings() { size(340, 510); }

  public void setup() {
    surface.setTitle("Truchet — Controls");
    trackX0 = 150;
    trackX1 = width - margin;

    int y = 56;
    sliders.add(new Slider("grid",        y, 2, 12, parent.gridN,         true));  y += rowH;
    sliders.add(new Slider("max depth",   y, 1, 6,  parent.maxDepth,      true));  y += rowH;
    sliders.add(new Slider("subdiv prob", y, 0, 1,  parent.subdivideProb, false)); y += rowH + 4;

    tgWinged = new Toggle("winged",       margin,       y, parent.winged);
    tgInvert = new Toggle("invert/level", margin + 160, y, parent.invertPerLevel);
    y += 40;

    bShape = new Button("shape: square", margin, y, width - 2 * margin, 30);
    y += 40;

    bScheme = new Button("scheme: duotone", margin, y, width - 2 * margin, 30);
    y += 40;

    bSym = new Button("symmetry: none", margin, y, width - 2 * margin, 30);
    y += 44;

    palLabelY = y; y += 26;
    bPrev = new Button("<",      margin,      y, 30, 32);
    bNext = new Button(">",      margin + 34, y, 30, 32);
    bRot  = new Button("rotate", margin + 68, y, 60, 32);
    swatchY = y; swatchH = 32;
    y += 32 + 26;

    bSeed = new Button("New seed", margin,       y, 150, 36);
    bSave = new Button("Save PNG", margin + 162, y, width - margin - (margin + 162), 36);
  }

  public void draw() {
    background(38);
    textAlign(LEFT, CENTER);

    fill(235); textSize(16);
    text("Truchet parameters", margin, 28);
    textSize(13);

    for (Slider s : sliders) drawSlider(s);
    drawToggle(tgWinged);
    drawToggle(tgInvert);

    bShape.label = "shape: " + parent.SHAPE_NAMES[parent.shapeMode];
    drawButton(bShape);

    bScheme.label = "scheme: " + parent.schemeName(parent.colorScheme);
    drawButton(bScheme);

    bSym.label = "symmetry: " + parent.SYMMETRY_NAMES[parent.symmetryMode];
    drawButton(bSym);

    // palette name + swatches
    fill(170); textAlign(LEFT, CENTER);
    text("Palette", margin, palLabelY);
    fill(235);  textAlign(RIGHT, CENTER);
    text(parent.palettes.current().title, width - margin, palLabelY);
    textAlign(LEFT, CENTER);
    drawButton(bPrev);
    drawButton(bNext);
    drawButton(bRot);
    color[] cols = parent.palettes.current().colors;
    float sx0 = bRot.x + bRot.w + 10;
    float sw  = (width - margin - sx0) / cols.length;
    noStroke();
    for (int i = 0; i < cols.length; i++) {
      fill(cols[i]);
      rect(sx0 + i * sw, swatchY, sw - 2, swatchH);
    }

    drawButton(bSeed);
    drawButton(bSave);
  }

  // ---- widget rendering ----
  void drawSlider(Slider s) {
    fill(205); textAlign(LEFT, CENTER);
    text(s.label, margin, s.y);
    stroke(90); strokeWeight(3);
    line(trackX0, s.y, trackX1, s.y);
    noStroke();
    fill(150);
    text(s.isInt ? str((int) s.value) : nf(s.value, 0, 2), margin, s.y + 17);
    fill(s == active ? color(255, 200, 0) : color(120, 180, 255));
    ellipse(knobX(s), s.y, 16, 16);
  }

  void drawToggle(Toggle t) {
    stroke(120); strokeWeight(2); noFill();
    rect(t.x, t.y - 9, 18, 18, 3);
    noStroke();
    if (t.value) { fill(120, 180, 255); rect(t.x + 4, t.y - 5, 10, 10, 2); }
    fill(210); textAlign(LEFT, CENTER);
    text(t.label, t.x + 26, t.y);
  }

  void drawButton(Button b) {
    fill(b.hot ? color(82) : color(60));
    stroke(110); strokeWeight(1);
    rect(b.x, b.y, b.w, b.h, 5);
    noStroke();
    fill(230); textAlign(CENTER, CENTER);
    text(b.label, b.x + b.w / 2, b.y + b.h / 2);
    textAlign(LEFT, CENTER);
  }

  float knobX(Slider s) {
    float t = (s.value - s.lo) / (s.hi - s.lo);
    return lerp(trackX0, trackX1, constrain(t, 0, 1));
  }

  // ---- interaction ----
  public void mousePressed() {
    for (Slider s : sliders) {
      if (abs(mouseY - s.y) < 16 && mouseX > trackX0 - 16 && mouseX < trackX1 + 16) {
        active = s; setSliderFromMouse(s); return;
      }
    }
    if (tgWinged.hit(mouseX, mouseY)) { tgWinged.value = !tgWinged.value; syncParent(); return; }
    if (tgInvert.hit(mouseX, mouseY)) { tgInvert.value = !tgInvert.value; syncParent(); return; }
    if (bShape.hit(mouseX, mouseY))  { parent.shapeMode = (parent.shapeMode + 1) % 3; parent.redraw(); return; }
    if (bScheme.hit(mouseX, mouseY)) { parent.colorScheme = (parent.colorScheme + 1) % 5; parent.redraw(); return; }
    if (bSym.hit(mouseX, mouseY))    { parent.symmetryMode = (parent.symmetryMode + 1) % 4; parent.redraw(); return; }
    if (bPrev.hit(mouseX, mouseY))   { parent.palettes.prev(); parent.redraw(); return; }
    if (bNext.hit(mouseX, mouseY))   { parent.palettes.next(); parent.redraw(); return; }
    if (bRot.hit(mouseX, mouseY))    { parent.palettes.current().rotate(); parent.redraw(); return; }
    if (bSeed.hit(mouseX, mouseY))   { parent.seedVal = (int) random(1, 99999); parent.redraw(); return; }
    if (bSave.hit(mouseX, mouseY))   { parent.saveRequested = true; parent.redraw(); return; }
  }

  public void mouseDragged() { if (active != null) setSliderFromMouse(active); }
  public void mouseReleased() { active = null; }

  public void mouseMoved() {
    bShape.hot  = bShape.hit(mouseX, mouseY);
    bScheme.hot = bScheme.hit(mouseX, mouseY);
    bSym.hot    = bSym.hit(mouseX, mouseY);
    bPrev.hot   = bPrev.hit(mouseX, mouseY);
    bNext.hot   = bNext.hit(mouseX, mouseY);
    bRot.hot    = bRot.hit(mouseX, mouseY);
    bSeed.hot   = bSeed.hit(mouseX, mouseY);
    bSave.hot   = bSave.hit(mouseX, mouseY);
  }

  void setSliderFromMouse(Slider s) {
    float t = constrain((mouseX - trackX0) / (trackX1 - trackX0), 0, 1);
    float v = lerp(s.lo, s.hi, t);
    s.value = s.isInt ? round(v) : v;
    syncParent();
  }

  // Push every control value to the main sketch and repaint it.
  void syncParent() {
    parent.gridN          = (int) sliders.get(0).value;
    parent.maxDepth       = (int) sliders.get(1).value;
    parent.subdivideProb  = sliders.get(2).value;
    parent.winged         = tgWinged.value;
    parent.invertPerLevel = tgInvert.value;
    parent.redraw();
  }
}

// ---- plain widget data holders ---------------------------------
class Slider {
  String label; int y; float lo, hi, value; boolean isInt;
  Slider(String label, int y, float lo, float hi, float value, boolean isInt) {
    this.label = label; this.y = y; this.lo = lo; this.hi = hi;
    this.value = value; this.isInt = isInt;
  }
}

class Toggle {
  String label; int x, y; boolean value;
  Toggle(String label, int x, int y, boolean value) {
    this.label = label; this.x = x; this.y = y; this.value = value;
  }
  boolean hit(int mx, int my) { return mx >= x && mx <= x + 140 && my >= y - 12 && my <= y + 12; }
}

class Button {
  String label; int x, y, w, h; boolean hot = false;
  Button(String label, int x, int y, int w, int h) {
    this.label = label; this.x = x; this.y = y; this.w = w; this.h = h;
  }
  boolean hit(int mx, int my) { return mx >= x && mx <= x + w && my >= y && my <= y + h; }
}
