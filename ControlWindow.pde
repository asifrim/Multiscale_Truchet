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
//  numeric params, check-toggles for the booleans, cycle buttons for the
//  enums, a palette selector with live swatches.
//
//  TABBED LAYOUT. Controls are grouped into switchable tabs (Tiles / Color /
//  Symmetry / Shadow & 3D / Animation / Rendering / Image). Each widget
//  carries a `tab` index; draw()/mousePressed() only show + hit-test the
//  active tab's widgets (tab == -1 means persistent — the bottom action bar
//  with New seed / Save / Load render, reachable from any tab). Because tabs
//  reuse the same vertical space, every tab lays out from `contentTop`.
//
//  Slider/toggle wiring is by NAMED REFERENCE (sGrid, tgShadow, …), not list
//  index, so reordering widgets across tabs can never misbind a control.
//
//  Notes on the built-in approach:
//    * size() must live in settings() for a PApplet subclass (the
//      preprocessor only relocates it for the main tab).
//    * This window runs on its own animation thread; reads of parent state
//      for display are best-effort, which is fine for a control panel.
// ============================================================

public class ControlWindow extends PApplet {
  Multiscale_Truchet parent;

  final int margin = 16;
  final int rowH   = 46;
  final int W      = 480;
  final int H      = 560;
  final int colX     = margin;                 // single-column content origin
  final int colX2    = margin + 224;           // second column (two-up toggles)
  final int contentW = W - 2 * margin;         // content width
  final int contentTop = 54;                   // first widget y in every tab
  final int labelGutter = 132;                 // slider label column width

  // ---- tabs ----
  final String[] tabNames = { "Tiles", "Color", "Sym", "Shadow", "Anim", "Render", "Image" };
  final int TAB_TILES = 0, TAB_COLOR = 1, TAB_SYM = 2, TAB_SHADOW = 3,
            TAB_ANIM = 4, TAB_RENDER = 5, TAB_IMAGE = 6;
  final int tabBarY = 10, tabBarH = 30;
  float tabW;
  int activeTab = TAB_TILES;

  // ---- widget collections (drawn/hit-tested filtered by tab) ----
  ArrayList<Slider> sliders = new ArrayList<Slider>();
  ArrayList<Toggle> toggles = new ArrayList<Toggle>();
  ArrayList<Button> buttons = new ArrayList<Button>();
  Slider active = null;

  // ---- named slider refs ----
  Slider sGrid, sDepth, sSubdiv;
  Slider sShadowAngle, sShadowSize, sShadowStrength, sVpx, sVpy, sExtrudeDepth, sExtrudeShade;
  Slider sAnimRate, sDiscDepth, sBandDepth, sRotDepth, sArcDepth;
  Slider sLineCount, sLineDuty, sLineSubdiv, sStripWidth;
  Slider sImgCols, sImgLib, sImgGamma;

  // ---- named toggle refs ----
  Toggle tgWinged, tgGrid, tgInvert, tgShadow, tgShadowGlobal, tgExtrude, tgAnim,
         tgLine, tgKumiko, tgImage, tgImgStretch, tgImgInvert, tgImgContain;

  // ---- named button refs ----
  Button bScheme, bSym, bExtrude, bPrev, bNext, bRot, bImgLoad;
  Button bSeed, bSave, bLoadRender;            // persistent action bar (tab == -1)
  // Tiles tab: segmented switches (custom-drawn pictogram/number buttons, NOT in
  // the `buttons` list -- drawn + hit-tested in the TAB_TILES branch).
  Button[] bShapes  = new Button[4];           // square / triangle / hexagon / trapezoid
  Button[] bAnchors = new Button[4];           // anchors per side 1..4
  int shapeRowY, anchorRowY;

  // section-label / swatch anchors
  int palLabelY, swatchY, swatchH, imgLabelY, symHelpY, animLabelY;
  int barY;

  ControlWindow(Multiscale_Truchet parent) { this.parent = parent; }

  public void settings() { size(W, H); }

  // ---- widget factory helpers (set tab + register) ----
  Slider addSlider(int tab, String label, int y, float lo, float hi, float value, boolean isInt) {
    Slider s = new Slider(label, colX, y, lo, hi, value, isInt);
    s.tab = tab; sliders.add(s); return s;
  }
  Toggle addToggle(int tab, String label, int x, int y, boolean value) {
    Toggle t = new Toggle(label, x, y, value); t.tab = tab; toggles.add(t); return t;
  }
  Button addButton(int tab, String label, int x, int y, int w, int h) {
    Button b = new Button(label, x, y, w, h); b.tab = tab; buttons.add(b); return b;
  }

  public void setup() {
    surface.setTitle("Truchet — Controls");
    tabW = (float)(W - 2 * margin) / tabNames.length;

    int y;

    // ===== TAB: Tiles =====
    y = contentTop;
    // shape + anchors are segmented switches: a label in the gutter, then 4 equal
    // buttons spanning the slider track region (so they line up with the sliders).
    int segX = colX + labelGutter;
    int segW = (contentW - labelGutter) / 4;
    shapeRowY = y;  y += 48;                            // shape pictogram buttons (h=40)
    anchorRowY = y; y += 50;                            // anchors number buttons (h=28) + gap before sliders
    for (int i = 0; i < 4; i++) bShapes[i]  = new Button("",      segX + i * segW, shapeRowY,  segW - 3, 40);
    for (int i = 0; i < 4; i++) bAnchors[i] = new Button(str(i+1), segX + i * segW, anchorRowY, segW - 3, 28);
    sGrid   = addSlider(TAB_TILES, "grid",        y, 2, 12, parent.gridN,         true);  y += rowH;
    sDepth  = addSlider(TAB_TILES, "max depth",   y, 1, 6,  parent.maxDepth,      true);  y += rowH;
    sSubdiv = addSlider(TAB_TILES, "subdiv prob", y, 0, 1,  parent.subdivideProb, false); y += rowH + 6;
    tgWinged= addToggle(TAB_TILES, "winged",       colX,  y, parent.winged);
    tgGrid  = addToggle(TAB_TILES, "grid overlay", colX2, y, parent.showGrid);

    // ===== TAB: Color =====
    y = contentTop;
    bScheme = addButton(TAB_COLOR, "scheme: duotone", colX, y, contentW, 30); y += 42;
    tgInvert= addToggle(TAB_COLOR, "invert per level", colX, y, parent.invertPerLevel); y += 42;
    palLabelY = y; y += 24;
    bPrev = addButton(TAB_COLOR, "<",      colX,      y, 30, 32);
    bNext = addButton(TAB_COLOR, ">",      colX + 34, y, 30, 32);
    bRot  = addButton(TAB_COLOR, "rotate", colX + 68, y, 60, 32);
    swatchY = y; swatchH = 32;

    // ===== TAB: Symmetry =====
    y = contentTop;
    bSym   = addButton(TAB_SYM, "symmetry: none", colX, y, contentW, 30); y += 44;
    symHelpY = y;

    // ===== TAB: Shadow & 3D =====
    y = contentTop;
    tgShadow       = addToggle(TAB_SHADOW, "drop shadow",   colX,  y, parent.dropShadow);
    tgShadowGlobal = addToggle(TAB_SHADOW, "global shadow", colX2, y, parent.shadowGlobal); y += 36;
    sShadowAngle    = addSlider(TAB_SHADOW, "shadow angle",    y, 0, 360, degrees(parent.shadowAngle), true);  y += rowH;
    sShadowSize     = addSlider(TAB_SHADOW, "shadow size",     y, 0, 1,   parent.shadowSize,     false); y += rowH;
    sShadowStrength = addSlider(TAB_SHADOW, "shadow strength", y, 0, 1,   parent.shadowStrength, false); y += rowH + 6;
    tgExtrude = addToggle(TAB_SHADOW, "extrude 3D", colX, y, parent.extrude3D); y += 34;
    bExtrude  = addButton(TAB_SHADOW, "extrude: oblique", colX, y, contentW, 30); y += 40;
    sVpx          = addSlider(TAB_SHADOW, "vp x",          y, 0,    1,   parent.vpX,          false); y += rowH;
    sVpy          = addSlider(TAB_SHADOW, "vp y",          y, -0.5, 1.5, parent.vpY,          false); y += rowH;
    sExtrudeDepth = addSlider(TAB_SHADOW, "extrude depth", y, 0,    1,   parent.extrudeDepth, false); y += rowH;
    sExtrudeShade = addSlider(TAB_SHADOW, "extrude shade", y, 0,    1,   parent.extrudeShade, false);

    // ===== TAB: Animation =====
    y = contentTop;
    tgAnim = addToggle(TAB_ANIM, "animate", colX, y, parent.animEnabled); y += 34;
    animLabelY = y; y += 22;
    // disc is connection-safe; band/rot/arc BREAK the seamless connection (labelled *).
    sAnimRate  = addSlider(TAB_ANIM, "anim rate",   y, 0, 2, parent.animRateHz,     false); y += rowH;
    sDiscDepth = addSlider(TAB_ANIM, "disc depth",  y, 0, 1, parent.lfoDisc.depth,  false); y += rowH;
    sBandDepth = addSlider(TAB_ANIM, "band depth*", y, 0, 1, parent.lfoBand.depth,  false); y += rowH;
    sRotDepth  = addSlider(TAB_ANIM, "rot depth*",  y, 0, 1, parent.lfoRot.depth,   false); y += rowH;
    sArcDepth  = addSlider(TAB_ANIM, "arc depth*",  y, 0, 1, parent.lfoSweep.depth, false);

    // ===== TAB: Rendering (line mode / kumiko) =====
    y = contentTop;
    tgLine = addToggle(TAB_RENDER, "line mode", colX, y, parent.lineMode); y += 34;
    sLineCount  = addSlider(TAB_RENDER, "line count",  y, 1, 24,  parent.lineCount,     true);  y += rowH;
    sLineDuty   = addSlider(TAB_RENDER, "line duty",   y, 0.1, 0.9, parent.lineDuty,    false); y += rowH;
    sLineSubdiv = addSlider(TAB_RENDER, "line subdiv", y, 0, 1,   parent.lineSubdivProb,false); y += rowH + 8;
    tgKumiko = addToggle(TAB_RENDER, "kumiko style", colX, y, parent.kumikoStyle); y += 34;
    sStripWidth = addSlider(TAB_RENDER, "strip width", y, 0.02, 0.33, parent.stripWidthFrac, false);

    // ===== TAB: Image (Truchet halftone) =====
    y = contentTop;
    imgLabelY = y; y += 24;
    tgImage      = addToggle(TAB_IMAGE, "image mode", colX,  y, parent.imageMode);
    tgImgStretch = addToggle(TAB_IMAGE, "stretch",    colX2, y, parent.imgStretch); y += 36;
    tgImgInvert  = addToggle(TAB_IMAGE, "invert map", colX,  y, parent.imgInvert);
    tgImgContain = addToggle(TAB_IMAGE, "contain",    colX2, y, parent.imgContain); y += 40;
    sImgCols  = addSlider(TAB_IMAGE, "img cols",  y, 8,  96,  parent.imgCols,  true);  y += rowH;
    sImgLib   = addSlider(TAB_IMAGE, "img lib",   y, 32, 512, parent.libSize,  true);  y += rowH;
    sImgGamma = addSlider(TAB_IMAGE, "img gamma", y, 0.2, 3.0, parent.imgGamma, false); y += rowH + 4;
    bImgLoad  = addButton(TAB_IMAGE, "Load image…", colX, y, contentW, 30);

    // ===== persistent action bar (tab == -1) =====
    barY = H - 44;
    bSeed       = addButton(-1, "New seed",    colX,       barY, 140, 34);
    bSave       = addButton(-1, "Save PNG",    colX + 150, barY, 140, 34);
    bLoadRender = addButton(-1, "Load render…",colX + 300, barY, contentW - 300, 34);
  }

  boolean shown(int tab) { return tab == activeTab || tab == -1; }

  public void draw() {
   try {
    if (parent.controlsNeedSync) { syncFromParent(); parent.controlsNeedSync = false; }
    background(38);
    textAlign(LEFT, CENTER);

    drawTabs();

    // dynamic button labels
    bScheme.label  = "scheme: "   + parent.schemeName(parent.colorScheme);
    bSym.label     = "symmetry: " + parent.SYMMETRY_NAMES[parent.symmetryMode];
    bExtrude.label = "extrude: "  + parent.EXTRUDE_NAMES[parent.extrudeMode];
    bImgLoad.label = (parent.imagePath == null)
      ? "Load image…" : "Image: " + imgBaseName(parent.imagePath);

    for (Slider s : sliders) if (shown(s.tab)) drawSlider(s);
    for (Toggle t : toggles) if (shown(t.tab)) drawToggle(t);
    for (Button b : buttons) if (shown(b.tab)) drawButton(b);

    // ---- per-tab decorations ----
    if (activeTab == TAB_TILES) {
      fill(205); textAlign(LEFT, CENTER);
      text("shape",        colX, shapeRowY + 20);
      text("anchors/side", colX, anchorRowY + 14);
      for (int i = 0; i < 4; i++) drawShapeButton(bShapes[i], i);
      for (int i = 0; i < 4; i++) drawSegButton(bAnchors[i], parent.anchorsPerSide == i + 1);
      textAlign(LEFT, CENTER);
    } else if (activeTab == TAB_COLOR) {
      fill(170); textAlign(LEFT, CENTER);
      text("Palette", colX, palLabelY);
      fill(235); textAlign(RIGHT, CENTER);
      text(parent.palettes.current().title, colX + contentW, palLabelY);
      textAlign(LEFT, CENTER);
      color[] cols = parent.palettes.current().colors;
      float sx0 = bRot.x + bRot.w + 10;
      float sw  = (colX + contentW - sx0) / cols.length;
      noStroke();
      for (int i = 0; i < cols.length; i++) {
        fill(cols[i]);
        rect(sx0 + i * sw, swatchY, sw - 2, swatchH);
      }
    } else if (activeTab == TAB_SYM) {
      fill(150); textAlign(LEFT, TOP); textSize(12);
      text("Cycles: none → mirror V/H/quad → rot 180 →\n"
         + "tile-mirror V/H/quad. Mirrors (1–3) are pixel\n"
         + "reflections; 4–7 are structural (seamless).",
           colX, symHelpY, contentW, 80);
      textSize(13); textAlign(LEFT, CENTER);
    } else if (activeTab == TAB_ANIM) {
      fill(150); textAlign(LEFT, CENTER);
      text("* breaks seamless connection (expressive)", colX, animLabelY);
    } else if (activeTab == TAB_IMAGE) {
      fill(170); textAlign(LEFT, CENTER);
      text("Truchet halftone of a source image", colX, imgLabelY);
    }

    // ---- action-bar separator ----
    stroke(70); strokeWeight(1);
    line(colX, barY - 12, colX + contentW, barY - 12);
    noStroke();
   } catch (Throwable e) { parent.dbgCrash(e); }   // attribute a Controls-thread crash
  }

  void drawTabs() {
    textAlign(CENTER, CENTER); textSize(12);
    for (int i = 0; i < tabNames.length; i++) {
      float x = margin + i * tabW;
      boolean act = (i == activeTab);
      fill(act ? color(70) : color(48));
      stroke(act ? color(120, 180, 255) : color(80)); strokeWeight(1);
      rect(x, tabBarY, tabW - 2, tabBarH, 4);
      noStroke();
      fill(act ? 255 : 170);
      text(tabNames[i], x + tabW / 2, tabBarY + tabBarH / 2);
    }
    textAlign(LEFT, CENTER); textSize(13);
  }

  // last path component, for the load button label.
  String imgBaseName(String p) {
    int i = max(p.lastIndexOf('/'), p.lastIndexOf('\\'));
    return i >= 0 ? p.substring(i + 1) : p;
  }

  // ---- widget rendering ----
  float trkX0(Slider s) { return s.colX + labelGutter; }
  float trkX1(Slider s) { return s.colX + contentW; }

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

  // Segmented-switch cell background: accent when selected, lighten on hover.
  void segCell(Button b, boolean active) {
    boolean hot = b.hit(mouseX, mouseY);
    fill(active ? color(50, 90, 160) : (hot ? color(82) : color(60)));
    stroke(active ? color(120, 180, 255) : color(110)); strokeWeight(1);
    rect(b.x, b.y, b.w, b.h, 5);
    noStroke();
  }

  // One shape-switch cell: cell background + a centred shape pictogram.
  void drawShapeButton(Button b, int shape) {
    boolean active = (parent.shapeMode == shape);
    segCell(b, active);
    stroke(active ? color(255) : color(190)); strokeWeight(active ? 2 : 1.5); noFill();
    drawShapePicto(b.x + b.w / 2, b.y + b.h / 2, 12, shape);
    noStroke();
  }

  // One number-switch cell (anchors/side): cell background + its label.
  void drawSegButton(Button b, boolean active) {
    segCell(b, active);
    fill(active ? 255 : 200); textAlign(CENTER, CENTER);
    text(b.label, b.x + b.w / 2, b.y + b.h / 2);
    textAlign(LEFT, CENTER);
  }

  // Outline pictogram of each tile shape (0 square, 1 triangle, 2 hexagon,
  // 3 trapezoid = half-hexagon), centred at (cx,cy) with nominal radius r.
  void drawShapePicto(float cx, float cy, float r, int shape) {
    if (shape == 0) {                       // square (axis-aligned)
      float s = r * 0.85;
      beginShape();
      vertex(cx - s, cy - s); vertex(cx + s, cy - s);
      vertex(cx + s, cy + s); vertex(cx - s, cy + s);
      endShape(CLOSE);
    } else if (shape == 1) {                // triangle, point up
      float h = r * 1.05;
      beginShape();
      vertex(cx, cy - h); vertex(cx + r, cy + h * 0.72); vertex(cx - r, cy + h * 0.72);
      endShape(CLOSE);
    } else if (shape == 2) {                // hexagon
      beginShape();
      for (int i = 0; i < 6; i++) { float a = i * TWO_PI / 6; vertex(cx + r * cos(a), cy + r * sin(a)); }
      endShape(CLOSE);
    } else {                                // trapezoid (half hexagon)
      float h = r * 0.62;
      beginShape();
      vertex(cx - r, cy + h); vertex(cx + r, cy + h);
      vertex(cx + r * 0.5, cy - h); vertex(cx - r * 0.5, cy - h);
      endShape(CLOSE);
    }
  }

  float knobX(Slider s) {
    float t = (s.value - s.lo) / (s.hi - s.lo);
    return lerp(trkX0(s), trkX1(s), constrain(t, 0, 1));
  }

  boolean hitSlider(Slider s) {
    return abs(mouseY - s.y) < 16 && mouseX > trkX0(s) - 16 && mouseX < trkX1(s) + 16;
  }

  // ---- interaction ----
  public void mousePressed() {
    // tab bar
    int tb = tabAt(mouseX, mouseY);
    if (tb >= 0) { activeTab = tb; active = null; return; }

    // sliders on the active tab
    for (Slider s : sliders) {
      if (shown(s.tab) && hitSlider(s)) { active = s; setSliderFromMouse(s); return; }
    }

    // persistent action bar
    if (bSeed.hit(mouseX, mouseY)) { parent.seedVal = (int) random(1, 99999); parent.logAction("CTRL seed -> " + parent.seedVal); parent.dirtyLayout = true; parent.dirtyGradient = true; parent.imgDirty = true; parent.redraw(); return; }
    if (bSave.hit(mouseX, mouseY)) { parent.logAction("CTRL save"); parent.saveRequested = true; parent.redraw(); return; }
    if (bLoadRender.hit(mouseX, mouseY)) { parent.logAction("CTRL load-render dialog"); selectInput("Load render manifest (.json)", "manifestChosen", null, parent); return; }

    // per-tab widgets
    switch (activeTab) {
      case TAB_TILES:
        for (int i = 0; i < 4; i++) if (bShapes[i].hit(mouseX, mouseY)) {
          if (parent.shapeMode != i) { parent.shapeMode = i; parent.logAction("CTRL shape -> " + parent.SHAPE_NAMES[i]); parent.dirtyLayout = true; parent.imgDirty = true; parent.redraw(); }
          return;
        }
        for (int i = 0; i < 4; i++) if (bAnchors[i].hit(mouseX, mouseY)) {
          int k = i + 1;
          if (parent.anchorsPerSide != k) { parent.anchorsPerSide = k; parent.logAction("CTRL anchors -> " + k); parent.dirtyLayout = true; parent.redraw(); }
          return;
        }
        if (tgWinged.hit(mouseX, mouseY)) { tgWinged.value = !tgWinged.value; parent.logAction("CTRL winged -> " + tgWinged.value); syncParent(); return; }
        if (tgGrid.hit(mouseX, mouseY))   { tgGrid.value = !tgGrid.value; parent.logAction("CTRL grid -> " + tgGrid.value); parent.showGrid = tgGrid.value; parent.redraw(); return; }
        break;
      case TAB_COLOR:
        if (tgInvert.hit(mouseX, mouseY)) { tgInvert.value = !tgInvert.value; parent.logAction("CTRL invert -> " + tgInvert.value); syncParent(); return; }
        if (bScheme.hit(mouseX, mouseY))  { parent.colorScheme = (parent.colorScheme + 1) % 5; parent.logAction("CTRL scheme -> " + parent.schemeName(parent.colorScheme)); parent.dirtyGradient = true; parent.imgDirty = true; parent.redraw(); return; }
        if (bPrev.hit(mouseX, mouseY))    { parent.palettes.prev(); parent.duoRandom = false; parent.logAction("CTRL palette prev"); parent.dirtyGradient = true; parent.imgDirty = true; parent.redraw(); return; }
        if (bNext.hit(mouseX, mouseY))    { parent.palettes.next(); parent.duoRandom = false; parent.logAction("CTRL palette next"); parent.dirtyGradient = true; parent.imgDirty = true; parent.redraw(); return; }
        if (bRot.hit(mouseX, mouseY))     { parent.logAction("CTRL rotate"); parent.rotatePalette(); parent.redraw(); return; }
        break;
      case TAB_SYM:
        if (bSym.hit(mouseX, mouseY)) { parent.symmetryMode = (parent.symmetryMode + 1) % parent.SYMMETRY_NAMES.length; parent.logAction("CTRL sym -> " + parent.SYMMETRY_NAMES[parent.symmetryMode]); parent.dirtyLayout = true; parent.redraw(); return; }
        break;
      case TAB_SHADOW:
        if (tgShadow.hit(mouseX, mouseY))       { tgShadow.value = !tgShadow.value; parent.logAction("CTRL shadow -> " + tgShadow.value); syncParent(); return; }
        if (tgShadowGlobal.hit(mouseX, mouseY)) { tgShadowGlobal.value = !tgShadowGlobal.value; parent.logAction("CTRL shadowGlobal -> " + tgShadowGlobal.value); syncParent(); return; }
        if (tgExtrude.hit(mouseX, mouseY))      { tgExtrude.value = !tgExtrude.value; parent.logAction("CTRL extrude -> " + tgExtrude.value); syncParent(); return; }
        if (bExtrude.hit(mouseX, mouseY))       { parent.extrudeMode = (parent.extrudeMode + 1) % parent.EXTRUDE_NAMES.length; parent.logAction("CTRL extrudeMode -> " + parent.EXTRUDE_NAMES[parent.extrudeMode]); parent.redraw(); return; }
        break;
      case TAB_ANIM:
        if (tgAnim.hit(mouseX, mouseY)) { tgAnim.value = !tgAnim.value; parent.logAction("CTRL anim -> " + tgAnim.value); parent.setAnimEnabled(tgAnim.value); return; }
        break;
      case TAB_RENDER:
        if (tgLine.hit(mouseX, mouseY))   { tgLine.value = !tgLine.value; parent.logAction("CTRL line -> " + tgLine.value); parent.lineMode = tgLine.value; parent.redraw(); return; }
        if (tgKumiko.hit(mouseX, mouseY)) { tgKumiko.value = !tgKumiko.value; parent.logAction("CTRL kumiko -> " + tgKumiko.value); parent.kumikoStyle = tgKumiko.value; parent.redraw(); return; }
        break;
      case TAB_IMAGE:
        if (tgImage.hit(mouseX, mouseY))      { tgImage.value = !tgImage.value; parent.logAction("CTRL imageMode -> " + tgImage.value); parent.imageMode = tgImage.value; parent.imgDirty = true; parent.redraw(); return; }
        if (tgImgStretch.hit(mouseX, mouseY)) { tgImgStretch.value = !tgImgStretch.value; parent.logAction("CTRL imgStretch -> " + tgImgStretch.value); parent.imgStretch = tgImgStretch.value; parent.imgDirty = true; parent.redraw(); return; }
        if (tgImgInvert.hit(mouseX, mouseY))  { tgImgInvert.value = !tgImgInvert.value; parent.logAction("CTRL imgInvert -> " + tgImgInvert.value); parent.imgInvert = tgImgInvert.value; parent.imgDirty = true; parent.redraw(); return; }
        if (tgImgContain.hit(mouseX, mouseY)) { tgImgContain.value = !tgImgContain.value; parent.logAction("CTRL imgContain -> " + tgImgContain.value); parent.imgContain = tgImgContain.value; parent.imgDirty = true; parent.redraw(); return; }
        if (bImgLoad.hit(mouseX, mouseY))     { parent.logAction("CTRL load-image dialog"); selectInput("Select an image", "imageChosen", null, parent); return; }
        break;
    }
  }

  int tabAt(int mx, int my) {
    if (my < tabBarY || my > tabBarY + tabBarH) return -1;
    if (mx < margin || mx > W - margin) return -1;
    int i = (int) ((mx - margin) / tabW);
    return constrain(i, 0, tabNames.length - 1);
  }

  public void mouseDragged() { if (active != null) setSliderFromMouse(active); }
  public void mouseReleased() { active = null; }

  public void mouseMoved() {
    for (Button b : buttons) b.hot = shown(b.tab) && b.hit(mouseX, mouseY);
  }

  void setSliderFromMouse(Slider s) {
    float t = constrain((mouseX - trkX0(s)) / (trkX1(s) - trkX0(s)), 0, 1);
    float v = lerp(s.lo, s.hi, t);
    s.value = s.isInt ? round(v) : v;
    parent.logAction("CTRL slider " + s.label + " = " + (s.isInt ? str((int) s.value) : nf(s.value, 0, 3)));
    syncParent();
  }

  // Push every control value to the main sketch and repaint it.
  void syncParent() {
    int   ng = (int) sGrid.value;
    int   nd = (int) sDepth.value;
    float ns = sSubdiv.value;
    if (ng != parent.gridN || nd != parent.maxDepth || ns != parent.subdivideProb)
      parent.dirtyLayout = true;          // these sliders change the tile layout
    // image-mode sliders
    int   ic = (int) sImgCols.value;
    int   il = (int) sImgLib.value;
    float ig = sImgGamma.value;
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
    parent.shadowAngle    = radians(sShadowAngle.value);
    parent.shadowSize     = sShadowSize.value;
    parent.shadowStrength = sShadowStrength.value;
    parent.vpX            = sVpx.value;
    parent.vpY            = sVpy.value;
    parent.extrudeDepth   = sExtrudeDepth.value;
    parent.extrudeShade   = sExtrudeShade.value;
    parent.applyAnimRate(sAnimRate.value);                // master LFO rate
    parent.lfoDisc.depth  = sDiscDepth.value;             // connection-safe
    parent.lfoBand.depth  = sBandDepth.value;             // * breaks connection
    parent.lfoRot.depth   = sRotDepth.value;              // *
    parent.lfoSweep.depth = sArcDepth.value;              // * (arc drives sweep + radius)
    parent.lfoRadius.depth = sArcDepth.value;
    parent.winged         = tgWinged.value;
    parent.invertPerLevel = tgInvert.value;
    parent.dropShadow     = tgShadow.value;
    parent.shadowGlobal   = tgShadowGlobal.value;
    parent.extrude3D      = tgExtrude.value;
    parent.lineCount      = (int) sLineCount.value;
    parent.lineDuty       = sLineDuty.value;
    parent.lineSubdivProb = sLineSubdiv.value;
    parent.kumikoStyle    = tgKumiko.value;
    parent.stripWidthFrac = sStripWidth.value;
    parent.redraw();
  }

  // Inverse of syncParent: pull every slider/toggle value back from the main sketch's
  // globals. Needed after a manifest load mutates those globals behind the panel's
  // back -- otherwise the widgets show stale values and the next slider drag (which
  // calls syncParent) would push the stale set back. Buttons/swatches read parent
  // state live in draw(), so they need no resync. Animation sliders + tgAnim are
  // runtime state (not in a manifest), so they are left untouched.
  void syncFromParent() {
    sGrid.value    = parent.gridN;
    sDepth.value   = parent.maxDepth;
    sSubdiv.value  = parent.subdivideProb;
    sShadowAngle.value    = degrees(parent.shadowAngle);
    sShadowSize.value     = parent.shadowSize;
    sShadowStrength.value = parent.shadowStrength;
    sVpx.value         = parent.vpX;
    sVpy.value         = parent.vpY;
    sExtrudeDepth.value = parent.extrudeDepth;
    sExtrudeShade.value = parent.extrudeShade;
    sLineCount.value  = parent.lineCount;
    sLineDuty.value   = parent.lineDuty;
    sLineSubdiv.value = parent.lineSubdivProb;
    sStripWidth.value = parent.stripWidthFrac;
    sImgCols.value  = parent.imgCols;
    sImgLib.value   = parent.libSize;
    sImgGamma.value = parent.imgGamma;
    tgKumiko.value       = parent.kumikoStyle;
    tgWinged.value       = parent.winged;
    tgInvert.value       = parent.invertPerLevel;
    tgShadow.value       = parent.dropShadow;
    tgShadowGlobal.value = parent.shadowGlobal;
    tgExtrude.value      = parent.extrude3D;
    tgGrid.value         = parent.showGrid;
    tgLine.value         = parent.lineMode;
    tgImage.value        = parent.imageMode;
    tgImgStretch.value   = parent.imgStretch;
    tgImgInvert.value    = parent.imgInvert;
    tgImgContain.value   = parent.imgContain;
  }
}

// ---- plain widget data holders ---------------------------------
class Slider {
  String label; int colX, y; float lo, hi, value; boolean isInt; int tab = -1;
  Slider(String label, int colX, int y, float lo, float hi, float value, boolean isInt) {
    this.label = label; this.colX = colX; this.y = y; this.lo = lo; this.hi = hi;
    this.value = value; this.isInt = isInt;
  }
}

class Toggle {
  String label; int x, y; boolean value; int tab = -1;
  Toggle(String label, int x, int y, boolean value) {
    this.label = label; this.x = x; this.y = y; this.value = value;
  }
  boolean hit(int mx, int my) { return mx >= x && mx <= x + 140 && my >= y - 12 && my <= y + 12; }
}

class Button {
  String label; int x, y, w, h; boolean hot = false; int tab = -1;
  Button(String label, int x, int y, int w, int h) {
    this.label = label; this.x = x; this.y = y; this.w = w; this.h = h;
  }
  boolean hit(int mx, int my) { return mx >= x && mx <= x + w && my >= y && my <= y + h; }
}
