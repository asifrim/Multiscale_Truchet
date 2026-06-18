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
  final int rowH   = 46;
  final int gap    = 24;                          // gap between the two columns
  final int W      = 680;                          // window width (double the old 340)
  final int colW   = (W - 2 * margin - gap) / 2;   // content width of one column
  final int colLX  = margin;                       // left column origin x
  final int colRX  = margin + colW + gap;          // right column origin x

  ArrayList<Slider> sliders = new ArrayList<Slider>();
  Toggle tgWinged, tgInvert, tgShadow, tgShadowGlobal, tgExtrude, tgAnim, tgGrid, tgLine;
  int lineLabelY;
  Toggle tgImage, tgImgStretch, tgImgInvert, tgImgContain;
  Button bShape, bScheme, bSym, bExtrude, bPrev, bNext, bRot, bSeed, bSave, bImgLoad;
  Slider active = null;
  int imgLabelY;

  int palLabelY, swatchY, swatchH;

  ControlWindow(Multiscale_Truchet parent) { this.parent = parent; }

  public void settings() { size(W, 904); }

  public void setup() {
    surface.setTitle("Truchet — Controls");

    // The sliders ArrayList order is read by index in syncParent(), so the
    // sliders MUST be added in this order: 0-9 (left column), then 10-17 (right
    // column), then 18-19 (line mode, appended at the very end of setup). Layout
    // x/y differs per column but does not affect the indices.

    // ===== LEFT COLUMN: geometry, shadow, 3D extrusion =====
    int y = 56;
    sliders.add(new Slider("grid",        colLX, y, 2, 12, parent.gridN,         true));  y += rowH;  // 0
    sliders.add(new Slider("max depth",   colLX, y, 1, 6,  parent.maxDepth,      true));  y += rowH;  // 1
    sliders.add(new Slider("subdiv prob", colLX, y, 0, 1,  parent.subdivideProb, false)); y += rowH;  // 2
    sliders.add(new Slider("shadow angle", colLX, y, 0, 360, degrees(parent.shadowAngle), true)); y += rowH;  // 3
    sliders.add(new Slider("shadow size", colLX, y, 0, 1,  parent.shadowSize,    false)); y += rowH;  // 4
    sliders.add(new Slider("shadow strength", colLX, y, 0, 1, parent.shadowStrength, false)); y += rowH;  // 5
    sliders.add(new Slider("vp x",          colLX, y, 0,    1,   parent.vpX,          false)); y += rowH;  // 6
    sliders.add(new Slider("vp y",          colLX, y, -0.5, 1.5, parent.vpY,          false)); y += rowH;  // 7
    sliders.add(new Slider("extrude depth", colLX, y, 0,    1,   parent.extrudeDepth, false)); y += rowH;  // 8
    sliders.add(new Slider("extrude shade", colLX, y, 0,    1,   parent.extrudeShade, false)); y += rowH + 4;  // 9

    tgWinged = new Toggle("winged",       colLX,       y, parent.winged);
    tgInvert = new Toggle("invert/level", colLX + 155, y, parent.invertPerLevel);
    y += 38;
    tgShadow       = new Toggle("drop shadow",   colLX,       y, parent.dropShadow);
    tgShadowGlobal = new Toggle("global shadow", colLX + 155, y, parent.shadowGlobal);
    y += 38;
    tgExtrude = new Toggle("extrude 3D", colLX,       y, parent.extrude3D);
    tgAnim    = new Toggle("animate",    colLX + 155, y, parent.animEnabled);
    y += 38;
    tgGrid    = new Toggle("grid overlay", colLX,     y, parent.showGrid);
    y += 42;

    bShape   = new Button("shape: square",    colLX, y, colW, 30); y += 38;
    bScheme  = new Button("scheme: duotone",  colLX, y, colW, 30); y += 38;
    bSym     = new Button("symmetry: none",   colLX, y, colW, 30); y += 38;
    bExtrude = new Button("extrude: oblique", colLX, y, colW, 30);

    // ===== RIGHT COLUMN: animation, image mode, palette, actions =====
    int yr = 56;
    // animation: master rate + per-target depth (disc is connection-safe; band/
    // rot/arc BREAK the seamless connection -- labelled, default depth 0).
    sliders.add(new Slider("anim rate",  colRX, yr, 0, 2, parent.animRateHz,     false)); yr += rowH;  // 10
    sliders.add(new Slider("disc depth", colRX, yr, 0, 1, parent.lfoDisc.depth,  false)); yr += rowH;  // 11
    sliders.add(new Slider("band depth*", colRX, yr, 0, 1, parent.lfoBand.depth, false)); yr += rowH;  // 12
    sliders.add(new Slider("rot depth*",  colRX, yr, 0, 1, parent.lfoRot.depth,  false)); yr += rowH;  // 13
    sliders.add(new Slider("arc depth*",  colRX, yr, 0, 1, parent.lfoSweep.depth, false)); yr += rowH + 8;  // 14

    // image mode (Truchet halftone of a source image)
    imgLabelY = yr; yr += 24;
    sliders.add(new Slider("img cols",  colRX, yr, 8,  96,  parent.imgCols,  true));  yr += rowH;  // 15
    sliders.add(new Slider("img lib",   colRX, yr, 32, 512, parent.libSize,  true));  yr += rowH;  // 16
    sliders.add(new Slider("img gamma", colRX, yr, 0.2, 3.0, parent.imgGamma, false)); yr += rowH + 2;  // 17
    tgImage      = new Toggle("image mode",  colRX,       yr, parent.imageMode);
    tgImgStretch = new Toggle("stretch",     colRX + 155, yr, parent.imgStretch); yr += 36;
    tgImgInvert  = new Toggle("invert map",  colRX,       yr, parent.imgInvert);
    tgImgContain = new Toggle("contain",     colRX + 155, yr, parent.imgContain); yr += 38;
    bImgLoad = new Button("Load image…", colRX, yr, colW, 30); yr += 50;

    palLabelY = yr; yr += 24;
    bPrev = new Button("<",      colRX,      yr, 30, 32);
    bNext = new Button(">",      colRX + 34, yr, 30, 32);
    bRot  = new Button("rotate", colRX + 68, yr, 60, 32);
    swatchY = yr; swatchH = 32;
    yr += 32 + 22;

    bSeed = new Button("New seed", colRX,       yr, 150, 36);
    bSave = new Button("Save PNG", colRX + 162, yr, colW - 162, 36);
    yr += 52;

    // ===== line mode (parallel/concentric strokes) =====
    // Appended LAST, so these are sliders 18-20 -- the 0-17 indices above stay put.
    lineLabelY = yr; yr += 30;
    tgLine = new Toggle("line mode", colRX, lineLabelY, parent.lineMode);
    sliders.add(new Slider("line count", colRX, yr, 1, 24, parent.lineCount, true)); yr += rowH;  // 18
    sliders.add(new Slider("line duty",  colRX, yr, 0.1, 0.9, parent.lineDuty, false)); yr += rowH; // 19
    // P(stroke subdivided into lines) vs drawn full-thickness; 1 = all lines (plain line mode)
    sliders.add(new Slider("line subdiv", colRX, yr, 0, 1, parent.lineSubdivProb, false));         // 20
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
    drawToggle(tgShadow);
    drawToggle(tgShadowGlobal);
    drawToggle(tgExtrude);
    drawToggle(tgAnim);
    drawToggle(tgGrid);
    drawToggle(tgLine);

    bShape.label = "shape: " + parent.SHAPE_NAMES[parent.shapeMode];
    drawButton(bShape);

    bScheme.label = "scheme: " + parent.schemeName(parent.colorScheme);
    drawButton(bScheme);

    bSym.label = "symmetry: " + parent.SYMMETRY_NAMES[parent.symmetryMode];
    drawButton(bSym);

    bExtrude.label = "extrude: " + parent.EXTRUDE_NAMES[parent.extrudeMode];
    drawButton(bExtrude);

    // palette name + swatches
    fill(170); textAlign(LEFT, CENTER);
    text("Palette", colRX, palLabelY);
    fill(235);  textAlign(RIGHT, CENTER);
    text(parent.palettes.current().title, colRX + colW, palLabelY);
    textAlign(LEFT, CENTER);
    drawButton(bPrev);
    drawButton(bNext);
    drawButton(bRot);
    color[] cols = parent.palettes.current().colors;
    float sx0 = bRot.x + bRot.w + 10;
    float sw  = (colRX + colW - sx0) / cols.length;
    noStroke();
    for (int i = 0; i < cols.length; i++) {
      fill(cols[i]);
      rect(sx0 + i * sw, swatchY, sw - 2, swatchH);
    }

    drawButton(bSeed);
    drawButton(bSave);

    // image-mode section
    fill(170); textAlign(LEFT, CENTER);
    text("Image mode (Truchet halftone)", colRX, imgLabelY);
    drawToggle(tgImage);
    drawToggle(tgImgStretch);
    drawToggle(tgImgInvert);
    drawToggle(tgImgContain);
    bImgLoad.label = (parent.imagePath == null)
      ? "Load image…"
      : "Image: " + imgBaseName(parent.imagePath);
    drawButton(bImgLoad);
  }

  // last path component, for the load button label.
  String imgBaseName(String p) {
    int i = max(p.lastIndexOf('/'), p.lastIndexOf('\\'));
    return i >= 0 ? p.substring(i + 1) : p;
  }

  // ---- widget rendering ----
  // Each slider's track runs within its own column, from a fixed label gutter to
  // the column's right edge.
  float trkX0(Slider s) { return s.colX + 118; }
  float trkX1(Slider s) { return s.colX + colW; }

  void drawSlider(Slider s) {
    fill(205); textAlign(LEFT, CENTER);
    text(s.label, s.colX, s.y);
    stroke(90); strokeWeight(3);
    line(trkX0(s), s.y, trkX1(s), s.y);
    noStroke();
    fill(150);
    text(s.isInt ? str((int) s.value) : nf(s.value, 0, 2), s.colX, s.y + 16);
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
    return lerp(trkX0(s), trkX1(s), constrain(t, 0, 1));
  }

  // ---- interaction ----
  public void mousePressed() {
    for (Slider s : sliders) {
      if (abs(mouseY - s.y) < 16 && mouseX > trkX0(s) - 16 && mouseX < trkX1(s) + 16) {
        active = s; setSliderFromMouse(s); return;
      }
    }
    if (tgWinged.hit(mouseX, mouseY)) { tgWinged.value = !tgWinged.value; syncParent(); return; }
    if (tgInvert.hit(mouseX, mouseY)) { tgInvert.value = !tgInvert.value; syncParent(); return; }
    if (tgShadow.hit(mouseX, mouseY)) { tgShadow.value = !tgShadow.value; syncParent(); return; }
    if (tgShadowGlobal.hit(mouseX, mouseY)) { tgShadowGlobal.value = !tgShadowGlobal.value; syncParent(); return; }
    if (tgExtrude.hit(mouseX, mouseY)) { tgExtrude.value = !tgExtrude.value; syncParent(); return; }
    if (tgAnim.hit(mouseX, mouseY))  { tgAnim.value = !tgAnim.value; parent.setAnimEnabled(tgAnim.value); return; }
    if (tgGrid.hit(mouseX, mouseY))  { tgGrid.value = !tgGrid.value; parent.showGrid = tgGrid.value; parent.redraw(); return; }
    if (tgLine.hit(mouseX, mouseY))  { tgLine.value = !tgLine.value; parent.lineMode = tgLine.value; parent.redraw(); return; }
    if (bShape.hit(mouseX, mouseY))  { parent.shapeMode = (parent.shapeMode + 1) % 4; parent.dirtyLayout = true; parent.imgDirty = true; parent.redraw(); return; }
    if (bScheme.hit(mouseX, mouseY)) { parent.colorScheme = (parent.colorScheme + 1) % 5; parent.dirtyGradient = true; parent.imgDirty = true; parent.redraw(); return; }
    if (bSym.hit(mouseX, mouseY))    { parent.symmetryMode = (parent.symmetryMode + 1) % parent.SYMMETRY_NAMES.length; parent.dirtyLayout = true; parent.redraw(); return; }
    if (bExtrude.hit(mouseX, mouseY)) { parent.extrudeMode = (parent.extrudeMode + 1) % parent.EXTRUDE_NAMES.length; parent.redraw(); return; }
    if (bPrev.hit(mouseX, mouseY))   { parent.palettes.prev(); parent.duoRandom = false; parent.dirtyGradient = true; parent.imgDirty = true; parent.redraw(); return; }
    if (bNext.hit(mouseX, mouseY))   { parent.palettes.next(); parent.duoRandom = false; parent.dirtyGradient = true; parent.imgDirty = true; parent.redraw(); return; }
    if (bRot.hit(mouseX, mouseY))    { parent.rotatePalette(); parent.redraw(); return; }
    if (bSeed.hit(mouseX, mouseY))   { parent.seedVal = (int) random(1, 99999); parent.dirtyLayout = true; parent.dirtyGradient = true; parent.imgDirty = true; parent.redraw(); return; }
    if (bSave.hit(mouseX, mouseY))   { parent.saveRequested = true; parent.redraw(); return; }
    if (tgImage.hit(mouseX, mouseY))      { tgImage.value = !tgImage.value; parent.imageMode = tgImage.value; parent.imgDirty = true; parent.redraw(); return; }
    if (tgImgStretch.hit(mouseX, mouseY)) { tgImgStretch.value = !tgImgStretch.value; parent.imgStretch = tgImgStretch.value; parent.imgDirty = true; parent.redraw(); return; }
    if (tgImgInvert.hit(mouseX, mouseY))  { tgImgInvert.value = !tgImgInvert.value; parent.imgInvert = tgImgInvert.value; parent.imgDirty = true; parent.redraw(); return; }
    if (tgImgContain.hit(mouseX, mouseY)) { tgImgContain.value = !tgImgContain.value; parent.imgContain = tgImgContain.value; parent.imgDirty = true; parent.redraw(); return; }
    if (bImgLoad.hit(mouseX, mouseY))     { selectInput("Select an image", "imageChosen", null, parent); return; }
  }

  public void mouseDragged() { if (active != null) setSliderFromMouse(active); }
  public void mouseReleased() { active = null; }

  public void mouseMoved() {
    bShape.hot  = bShape.hit(mouseX, mouseY);
    bScheme.hot = bScheme.hit(mouseX, mouseY);
    bSym.hot    = bSym.hit(mouseX, mouseY);
    bExtrude.hot = bExtrude.hit(mouseX, mouseY);
    bPrev.hot   = bPrev.hit(mouseX, mouseY);
    bNext.hot   = bNext.hit(mouseX, mouseY);
    bRot.hot    = bRot.hit(mouseX, mouseY);
    bSeed.hot   = bSeed.hit(mouseX, mouseY);
    bSave.hot   = bSave.hit(mouseX, mouseY);
    bImgLoad.hot = bImgLoad.hit(mouseX, mouseY);
  }

  void setSliderFromMouse(Slider s) {
    float t = constrain((mouseX - trkX0(s)) / (trkX1(s) - trkX0(s)), 0, 1);
    float v = lerp(s.lo, s.hi, t);
    s.value = s.isInt ? round(v) : v;
    syncParent();
  }

  // Push every control value to the main sketch and repaint it.
  void syncParent() {
    int   ng = (int) sliders.get(0).value;
    int   nd = (int) sliders.get(1).value;
    float ns = sliders.get(2).value;
    if (ng != parent.gridN || nd != parent.maxDepth || ns != parent.subdivideProb)
      parent.dirtyLayout = true;          // only these sliders change the tile layout
    // image-mode sliders (appended after the animation block)
    int   ic = (int) sliders.get(15).value;
    int   il = (int) sliders.get(16).value;
    float ig = sliders.get(17).value;
    // anything that changes a patch's appearance or the mapping invalidates the
    // brightness library / mosaic -> rebuild on next draw.
    if (nd != parent.maxDepth || ns != parent.subdivideProb
        || tgWinged.value != parent.winged || tgInvert.value != parent.invertPerLevel
        || ic != parent.imgCols || il != parent.libSize || ig != parent.imgGamma)
      parent.imgDirty = true;
    parent.imgCols  = ic;
    parent.libSize  = il;
    parent.imgGamma = ig;
    parent.gridN          = ng;
    parent.maxDepth       = nd;
    parent.subdivideProb  = ns;
    parent.shadowAngle    = radians(sliders.get(3).value);
    parent.shadowSize     = sliders.get(4).value;
    parent.shadowStrength = sliders.get(5).value;
    parent.vpX            = sliders.get(6).value;
    parent.vpY            = sliders.get(7).value;
    parent.extrudeDepth   = sliders.get(8).value;
    parent.extrudeShade   = sliders.get(9).value;
    parent.applyAnimRate(sliders.get(10).value);          // master LFO rate
    parent.lfoDisc.depth  = sliders.get(11).value;        // connection-safe
    parent.lfoBand.depth  = sliders.get(12).value;        // * breaks connection
    parent.lfoRot.depth   = sliders.get(13).value;        // *
    parent.lfoSweep.depth = sliders.get(14).value;        // * (arc drives sweep + radius)
    parent.lfoRadius.depth = sliders.get(14).value;
    parent.winged         = tgWinged.value;
    parent.invertPerLevel = tgInvert.value;
    parent.dropShadow     = tgShadow.value;
    parent.shadowGlobal   = tgShadowGlobal.value;
    parent.extrude3D      = tgExtrude.value;
    parent.lineCount      = (int) sliders.get(18).value;
    parent.lineDuty       = sliders.get(19).value;
    parent.lineSubdivProb = sliders.get(20).value;
    parent.redraw();
  }
}

// ---- plain widget data holders ---------------------------------
class Slider {
  String label; int colX, y; float lo, hi, value; boolean isInt;
  Slider(String label, int colX, int y, float lo, float hi, float value, boolean isInt) {
    this.label = label; this.colX = colX; this.y = y; this.lo = lo; this.hi = hi;
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
