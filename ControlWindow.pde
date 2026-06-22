// ============================================================
//  ControlWindow.pde — the unified control panel (a second window).
//
//  Multi-window approach: this is its own PApplet, launched from the main
//  sketch's setup() with PApplet.runSketch(). It holds a reference to the
//  main sketch (`parent`); widgets write straight to the main sketch's
//  globals and call parent.redraw() (the visualization is noLoop(), so it
//  only repaints on demand).
//
//  THREE-ZONE 1080p LAYOUT (1920×1080):
//    * a VERTICAL TAB RAIL on the left (Tiles / Color / Sym / Shadow / Anim /
//      Render / Image) — a stack of buttons.
//    * a CONTROL COLUMN (middle) showing the active tab's widgets + the
//      persistent action bar (New seed / Save PNG / Load render…). Each widget
//      carries a `tab` index; draw()/mousePressed() only show + hit-test the
//      active tab's widgets (tab == -1 means persistent).
//    * a TILE PANE on the right (always visible): the shape + anchors/side
//      switches, the active tileset's selector, and the 16 tile slots each with
//      a weight slider + solo button. This used to be a separate "Tiles" window
//      (TileWindow.pde); it was folded in here so there is one control surface.
//
//  Widgets are drawn immediate-mode (no GUI library): sliders for the numeric
//  params, check-toggles for the booleans, cycle buttons for the enums, a
//  palette selector with live swatches. Slider/toggle wiring is by NAMED
//  REFERENCE (sGrid, tgShadow, …), not list index, so reordering widgets across
//  tabs can never misbind a control.
//
//  Notes on the built-in approach:
//    * size() must live in settings() for a PApplet subclass (the
//      preprocessor only relocates it for the main tab).
//    * This window runs on its own animation thread; reads of parent state
//      for display are best-effort, which is fine for a control panel.
//    * Tile weights are edited in place via parent.weightsFor(n)/TRAP_W (the
//      arrays pickWeighted() reads), exactly as the old Tiles window did; they
//      are NOT part of syncParent()/syncFromParent().
// ============================================================

public class ControlWindow extends PApplet {
  Multiscale_Truchet parent;

  // ---- window ----
  final int W = 1920, H = 1080;

  // ---- zone geometry ----
  final int railW       = 150;                 // left vertical tab rail
  final int controlColW = 470;                 // middle parameter column
  final int margin      = 16;
  final int colX        = railW + margin;       // 166 : control content origin
  final int contentW    = controlColW - 2 * margin;  // 438
  final int colX2       = colX + 224;           // second column (two-up toggles)
  final int labelGutter = 132;                  // slider label column width
  final int rowH        = 46;
  final int contentTop  = 88;                   // first widget y in every tab
  final int paneX0      = railW + controlColW + 20;  // 640 : tile pane left
  int paneRight;                                     // = W - margin, set in setup()
  int barY;

  // ---- tabs (vertical rail) ----
  final String[] tabNames = { "Tiles", "Color", "Sym", "Shadow", "Anim", "Render", "Image" };
  final int TAB_TILES = 0, TAB_COLOR = 1, TAB_SYM = 2, TAB_SHADOW = 3,
            TAB_ANIM = 4, TAB_RENDER = 5, TAB_IMAGE = 6;
  final int railTabTop = 96, railTabH = 54, railTabGap = 6;
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
  Slider sPulseSpeed, sPulseTrail, sPulseCount, sMorphDur;
  Slider sLineCount, sLineDuty, sLineSubdiv, sStripWidth;
  Slider sMetalBevel, sMetalLight;
  Slider sImgCols, sImgLib, sImgGamma;

  // ---- named toggle refs ----
  Toggle tgWinged, tgGrid, tgInvert, tgShadow, tgShadowGlobal, tgExtrude, tgAnim,
         tgLine, tgKumiko, tgMetal, tgImage, tgImgStretch, tgImgInvert, tgImgContain, tgPulse;

  // ---- named button refs ----
  Button bScheme, bExtrude, bPrev, bNext, bRot, bImgLoad, bMetalMat, bMetalStyle, bMorph, bMorphStagger;
  Button[] symBtns;                            // segmented switch, one per symmetry mode
  Button bSeed, bSave, bLoadRender;            // persistent action bar (tab == -1)

  // section-label / swatch anchors (control column)
  int palLabelY, swatchY, swatchH, imgLabelY, symHelpY, animLabelY;

  // ---- tile pane (the old TileWindow) ----
  // shape + anchors/side segmented switches now live in the pane header (custom-
  // drawn pictogram/number buttons, NOT in the `buttons` list).
  Button[] bShapes  = new Button[4];           // square / triangle / hexagon / trapezoid
  Button[] bAnchors = new Button[4];           // anchors per side 1..4
  int paneTitleY, tileShapeY, tileAnchorY, tileSelY, tileY0;

  final int   tileCols = 2;                    // 16 slots in a 2-column grid
  final int   tileRowH = 92;                   // generous rows (1080 has room)
  final int   tileSz   = 84;                   // large slot preview
  final float WMAX     = 8.0;                  // weight slider 0..WMAX
  final int   soloSz   = 20;
  int activeRow = -1;                          // tile weight slider being dragged

  // reload + reset buttons (pane header, top-right)
  final int reW = 140, reH = 26, reY = 36;
  final int rsW = 120, rsH = 26, rsY = 36;
  boolean reloadHot = false, resetHot = false;
  float reX() { return paneRight - reW; }
  float rsX() { return reX() - 12 - rsW; }

  // tileset selector (prev / label / next)
  final int navW = 32, selH = 28;
  boolean prevHot = false, nextHot = false;
  float prevX() { return paneX0; }
  float nextX() { return paneX0 + navW + 6; }
  boolean hitNav(float x) { return mouseX >= x && mouseX <= x + navW && mouseY >= tileSelY && mouseY <= tileSelY + selH; }

  // per-column tile-pane geometry: a cell is [preview][solo][slider track][value]
  float tileColW()       { return (paneRight - paneX0) / (float) tileCols; }
  float tileCellX(int c) { return paneX0 + c * tileColW(); }
  float tileCX(int c)    { return tileCellX(c) + tileSz / 2.0 + 12; }
  float soloX(int c)     { return tileCellX(c) + tileSz + 22; }
  float tileTrkX0(int c) { return soloX(c) + soloSz + 16; }
  float tileTrkX1(int c) { return tileCellX(c) + tileColW() - 56; }

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
    paneRight = W - margin;
    if (parent.panelTab >= 0) activeTab = constrain(parent.panelTab, 0, tabNames.length - 1);

    int y;

    // ===== TAB: Tiles (control column part — grid/depth/subdiv/winged; the shape +
    //       anchors switches live in the tile-pane header instead) =====
    y = contentTop;
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
    // A segmented switch: one cell per symmetry mode (selected one accented).
    y = contentTop;
    // Built directly (not via addButton) so they're drawn/hit-tested manually as
    // a segmented switch rather than by the generic plain-button loop.
    symBtns = new Button[parent.SYMMETRY_NAMES.length];
    for (int i = 0; i < symBtns.length; i++) {
      symBtns[i] = new Button(parent.SYMMETRY_NAMES[i], colX, y, contentW, 30);
      y += 34;
    }
    symHelpY = y + 8;

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
    tgAnim  = addToggle(TAB_ANIM, "animate", colX,  y, parent.animEnabled);
    tgPulse = addToggle(TAB_ANIM, "pulse",   colX2, y, parent.pulseEnabled); y += 34;
    animLabelY = y; y += 22;
    // disc is connection-safe; band/rot/arc BREAK the seamless connection (labelled *).
    sAnimRate  = addSlider(TAB_ANIM, "anim rate",   y, 0, 2, parent.animRateHz,     false); y += rowH;
    sDiscDepth = addSlider(TAB_ANIM, "disc depth",  y, 0, 1, parent.lfoDisc.depth,  false); y += rowH;
    sBandDepth = addSlider(TAB_ANIM, "band depth*", y, 0, 1, parent.lfoBand.depth,  false); y += rowH;
    sRotDepth  = addSlider(TAB_ANIM, "rot depth*",  y, 0, 1, parent.lfoRot.depth,   false); y += rowH;
    sArcDepth  = addSlider(TAB_ANIM, "arc depth*",  y, 0, 1, parent.lfoSweep.depth, false); y += rowH + 8;
    // light pulse (comet along the connection paths; see Pulse.pde)
    sPulseSpeed = addSlider(TAB_ANIM, "pulse speed", y, 0, 800, parent.pulseSpeed, false); y += rowH;
    sPulseTrail = addSlider(TAB_ANIM, "pulse trail", y, 0, 400, parent.pulseTrail, false); y += rowH;
    sPulseCount = addSlider(TAB_ANIM, "pulse count", y, 0, 30,  parent.pulseCount,  true); y += rowH + 8;
    bMorph       = addButton(TAB_ANIM, "morph tiles",     colX, y, contentW / 2 - 4, 30);
    bMorphStagger= addButton(TAB_ANIM, "morph staggered", colX + contentW / 2 + 4, y, contentW / 2 - 4, 30); y += 38;
    sMorphDur   = addSlider(TAB_ANIM, "morph dur", y, 0.2, 5, parent.morphDurationSec, false);

    // ===== TAB: Rendering (line mode / kumiko) =====
    y = contentTop;
    tgLine = addToggle(TAB_RENDER, "line mode", colX, y, parent.lineMode); y += 34;
    sLineCount  = addSlider(TAB_RENDER, "line count",  y, 1, 24,  parent.lineCount,     true);  y += rowH;
    sLineDuty   = addSlider(TAB_RENDER, "line duty",   y, 0.1, 0.9, parent.lineDuty,    false); y += rowH;
    sLineSubdiv = addSlider(TAB_RENDER, "line subdiv", y, 0, 1,   parent.lineSubdivProb,false); y += rowH + 8;
    tgKumiko = addToggle(TAB_RENDER, "kumiko style", colX, y, parent.kumikoStyle); y += 34;
    sStripWidth = addSlider(TAB_RENDER, "strip width", y, 0.02, 0.33, parent.stripWidthFrac, false); y += rowH + 10;
    tgMetal     = addToggle(TAB_RENDER, "metal", colX, y, parent.metalMode); y += 34;
    bMetalMat   = addButton(TAB_RENDER, "metal: gold", colX, y, contentW, 30); y += 38;
    bMetalStyle = addButton(TAB_RENDER, "bevel: round", colX, y, contentW, 30); y += 40;
    sMetalBevel = addSlider(TAB_RENDER, "bevel width", y, 2, 40, parent.metalBevelPx, true); y += rowH;
    sMetalLight = addSlider(TAB_RENDER, "metal light", y, 0, 360, parent.metalLightDeg, true);

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
    barY = H - 64;
    bSeed       = addButton(-1, "New seed",    colX,       barY, 140, 38);
    bSave       = addButton(-1, "Save PNG",    colX + 150, barY, 140, 38);
    bLoadRender = addButton(-1, "Load render…",colX + 300, barY, contentW - 300, 38);

    // ===== tile-pane header geometry =====
    paneTitleY   = 40;
    tileShapeY   = 70;
    tileAnchorY  = 122;
    tileSelY     = 170;
    tileY0       = 248;                          // first slot-row centre
    int segX = paneX0 + 110, segW = 80, segGap = 8;
    for (int i = 0; i < 4; i++) bShapes[i]  = new Button("",      segX + i * (segW + segGap), tileShapeY,  segW, 44);
    for (int i = 0; i < 4; i++) bAnchors[i] = new Button(str(i+1), segX + i * (segW + segGap), tileAnchorY, segW, 30);
  }

  boolean shown(int tab) { return tab == activeTab || tab == -1; }
  boolean inRect(float mx, float my, float x, float y, float w, float h) {
    return mx >= x && mx <= x + w && my >= y && my <= y + h;
  }

  public void draw() {
   try {
    if (parent.controlsNeedSync) { syncFromParent(); parent.controlsNeedSync = false; }
    background(32);

    // zone backgrounds (slightly elevated rail + pane vs the content column)
    noStroke();
    fill(44); rect(0, 0, railW, H);                          // rail
    fill(38); rect(paneX0 - 12, 0, W - (paneX0 - 12), H);     // tile pane

    drawRail();
    drawControlColumn();
    drawTilePane();

    // zone dividers
    stroke(62); strokeWeight(1);
    line(railW, 0, railW, H);
    line(paneX0 - 12, 0, paneX0 - 12, H);
    noStroke();

    // headless verification hook: dump the first fully-drawn panel frame and quit.
    if (parent.panelOutPath != null && frameCount >= 2) {
      save(parent.panelOutPath);
      parent.logAction("PANEL dump -> " + parent.panelOutPath);
      System.exit(0);
    }
   } catch (Throwable e) { parent.dbgCrash(e); }   // attribute a Controls-thread crash
  }

  // ---- left vertical tab rail ----
  void drawRail() {
    fill(236); textAlign(LEFT, CENTER); textSize(16);
    text("Truchet", 16, 38);
    fill(120, 180, 255); textSize(10);
    text("CONTROLS", 16, 58);

    textAlign(CENTER, CENTER); textSize(14);
    for (int i = 0; i < tabNames.length; i++) {
      int ty = railTabTop + i * (railTabH + railTabGap);
      boolean act = (i == activeTab);
      boolean hot = mouseX >= 10 && mouseX <= railW - 10 && mouseY >= ty && mouseY <= ty + railTabH;
      fill(act ? color(54, 84, 148) : (hot ? color(58) : color(50)));
      stroke(act ? color(120, 180, 255) : color(72)); strokeWeight(1);
      rect(10, ty, railW - 20, railTabH, 6);
      noStroke();
      if (act) { fill(120, 180, 255); rect(10, ty, 4, railTabH, 6); }   // accent bar
      fill(act ? 255 : 178);
      text(tabNames[i], railW / 2.0, ty + railTabH / 2.0);
    }
    textAlign(LEFT, CENTER); textSize(13);
  }

  // ---- middle control column (active tab's widgets) ----
  void drawControlColumn() {
    // column header
    fill(234); textAlign(LEFT, CENTER); textSize(17);
    text(tabNames[activeTab], colX, 46);
    stroke(62); strokeWeight(1); line(colX, 64, colX + contentW, 64); noStroke();
    textSize(13);

    // dynamic button labels
    bScheme.label  = "scheme: "   + parent.schemeName(parent.colorScheme);
    bExtrude.label = "extrude: "  + parent.EXTRUDE_NAMES[parent.extrudeMode];
    bImgLoad.label = (parent.imagePath == null)
      ? "Load image…" : "Image: " + imgBaseName(parent.imagePath);
    bMetalMat.label   = "metal: " + parent.metalMatName();
    bMetalStyle.label = "bevel: " + (parent.metalBevelStyle == 1 ? "flat-rim" : "round");

    for (Slider s : sliders) if (shown(s.tab)) drawSlider(s);
    for (Toggle t : toggles) if (shown(t.tab)) drawToggle(t);
    for (Button b : buttons) if (shown(b.tab)) drawButton(b);

    // ---- per-tab decorations ----
    if (activeTab == TAB_COLOR) {
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
      for (int i = 0; i < symBtns.length; i++)
        drawSegButton(symBtns[i], parent.symmetryMode == i);
      fill(150); textAlign(LEFT, TOP); textSize(12);
      text("none → mirror V/H/quad → rot 180 →\n"
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
    stroke(62); strokeWeight(1);
    line(colX, barY - 14, colX + contentW, barY - 14);
    noStroke();
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

  // A header button drawn from raw rect coords (reload / reset — not Button objects).
  void drawHdrButton(float x, float y, float w, float h, String s, boolean hot) {
    fill(hot ? color(82) : color(60)); stroke(110); strokeWeight(1);
    rect(x, y, w, h, 5); noStroke();
    fill(230); textAlign(CENTER, CENTER); textSize(12);
    text(s, x + w / 2.0, y + h / 2.0);
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
    drawShapePicto(b.x + b.w / 2, b.y + b.h / 2, 13, shape);
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

  // ============================================================
  //  TILE PANE (right) — the active shape's active tileset: 16 slots, each a
  //  preview + weight slider + solo button. Folded in from the old TileWindow.
  // ============================================================
  void drawTilePane() {
    boolean isTrap = parent.shapeMode == 3;
    int     n    = parent.SHAPE_N[parent.shapeMode];
    int[][][] arch = isTrap ? parent.TRAP_CONNS : parent.connsFor(n);
    float[] w    = isTrap ? parent.TRAP_W       : parent.weightsFor(n);

    // pane title
    textAlign(LEFT, CENTER);
    fill(236); textSize(17);
    text(parent.SHAPE_NAMES[parent.shapeMode] + " tiles (" + arch.length + ")", paneX0, paneTitleY);
    fill(150); textSize(11);
    text("drag a slider to set how often each tile is chosen", paneX0, paneTitleY + 20);

    // reload + reset buttons (top-right)
    drawHdrButton(reX(), reY, reW, reH, "Reload tiles.json", reloadHot);
    drawHdrButton(rsX(), rsY, rsW, rsH, "Reset weights", resetHot);

    // shape + anchors/side switches
    fill(205); textSize(12); textAlign(LEFT, CENTER);
    text("shape",   paneX0, tileShapeY + 22);
    text("anchors", paneX0, tileAnchorY + 15);
    for (int i = 0; i < 4; i++) drawShapeButton(bShapes[i], i);
    for (int i = 0; i < 4; i++) drawSegButton(bAnchors[i], parent.anchorsPerSide == i + 1);

    // tileset selector (current shape + k): prev / label / next
    int tsCount = parent.tilesetCount();
    boolean navOn = !isTrap && tsCount > 1;
    drawNav(prevX(), "<", prevHot, navOn);
    drawNav(nextX(), ">", nextHot, navOn);
    String lbl;
    if (isTrap)            lbl = "trapezoid — built-in (not a tileset)";
    else if (tsCount == 0) lbl = parent.SHAPE_NAMES[parent.shapeMode] + " k" + parent.anchorsPerSide
                                 + " — no tilesets (create one in the editor)";
    else                   lbl = parent.SHAPE_NAMES[parent.shapeMode] + " k" + parent.anchorsPerSide
                                 + "  ·  set " + parent.activeTilesetOrdinal() + " / " + tsCount;
    fill(isTrap || tsCount == 0 ? 150 : 220); textSize(12); textAlign(LEFT, CENTER);
    text(lbl, nextX() + navW + 14, tileSelY + selH / 2.0);

    // the 16 slots
    for (int i = 0; i < arch.length; i++) {
      int col = i % tileCols, row = i / tileCols;
      float cy = tileY0 + row * tileRowH;

      // slot card
      noStroke(); fill(i == activeRow ? color(54) : color(46));
      rect(tileCellX(col) + 2, cy - tileRowH / 2.0 + 4, tileColW() - 14, tileRowH - 8, 8);

      float cx = tileCX(col);
      if (isTrap) drawTrapArchetype(arch[i], cx, cy, tileSz);
      else        drawArchetype(arch[i], n, cx, cy, tileSz);

      // weight slider
      float x0 = tileTrkX0(col), x1 = tileTrkX1(col);
      stroke(95); strokeWeight(3);
      line(x0, cy, x1, cy);
      noStroke();
      float kx = lerp(x0, x1, constrain(w[i] / WMAX, 0, 1));
      fill(i == activeRow ? color(255, 200, 0) : color(120, 180, 255));
      ellipse(kx, cy, 14, 14);
      fill(180); textSize(11); textAlign(LEFT, CENTER);
      text(nf(w[i], 0, 1), x1 + 8, cy);

      // solo "s" button: set this tile's weight to 1, all others to 0
      float sx = soloX(col), sy = cy - soloSz / 2.0;
      boolean sHot = inRect(mouseX, mouseY, sx, sy, soloSz, soloSz);
      fill(sHot ? color(255, 200, 0) : color(70, 110, 160)); stroke(110); strokeWeight(1);
      rect(sx, sy, soloSz, soloSz, 4); noStroke();
      fill(sHot ? 30 : 230); textAlign(CENTER, CENTER); textSize(11);
      text("s", sx + soloSz / 2.0, cy);
      textAlign(LEFT, CENTER);
    }
  }

  // One prev/next nav button for the tileset selector (greyed when disabled).
  void drawNav(float x, String s, boolean hot, boolean enabled) {
    fill(enabled ? (hot ? color(82) : color(60)) : color(46));
    stroke(enabled ? 110 : 70); strokeWeight(1);
    rect(x, tileSelY, navW, selH, 5); noStroke();
    fill(enabled ? 230 : 110); textAlign(CENTER, CENTER); textSize(14);
    text(s, x + navW / 2.0, tileSelY + selH / 2.0 - 1);
    textAlign(LEFT, CENTER);
  }

  // Draw one archetype (its connection set) as a small tile preview, using a
  // fixed light/dark scheme so the SHAPE reads clearly regardless of palette.
  // Winged shapes (square/triangle, not whole hexagons) also draw their wings --
  // the bg-colour corner discs (r = side/3) and fg-colour edge-midpoint nubs
  // (r = side/6) -- so the preview matches the canvas tile.
  void drawArchetype(int[][] conns, int n, float ccx, float ccy, float sz) {
    int kk = max(1, parent.anchorsPerSide);          // anchor points per side
    boolean wholeHex = (n == 6 && kk == 1);
    boolean wings = !wholeHex;
    float R   = sz * (wings ? 0.40 : 0.46);
    float rot = (n == 4) ? QUARTER_PI : -HALF_PI;   // square axis-aligned; tri/hex point up
    float[] vx = new float[n], vy = new float[n];
    for (int k = 0; k < n; k++) {
      float a = rot + TWO_PI * k / n;
      vx[k] = ccx + R * cos(a);
      vy[k] = ccy + R * sin(a);
    }
    float side = dist(vx[0], vy[0], vx[1], vy[1]);
    // ports: E edge anchors (k per side), n apothem midpoints, the centre, then the
    // n vertices (corners -- the Kumiko lattice points).
    int E = n * kk;
    int pc = E + 2 * n + 1;
    float cx0 = 0, cy0 = 0;
    for (int e = 0; e < n; e++) { cx0 += vx[e]; cy0 += vy[e]; }
    cx0 /= n; cy0 /= n;
    float[] px = new float[pc], py = new float[pc];
    for (int e = 0; e < n; e++) {
      int e2 = (e + 1) % n;
      for (int s = 0; s < kk; s++) {
        float tt = (s + 0.5) / kk;
        px[e * kk + s] = vx[e] + tt * (vx[e2] - vx[e]);
        py[e * kk + s] = vy[e] + tt * (vy[e2] - vy[e]);
      }
      float emx = (vx[e] + vx[e2]) / 2, emy = (vy[e] + vy[e2]) / 2;
      px[E + e] = (cx0 + emx) / 2; py[E + e] = (cy0 + emy) / 2;       // apothem midpoint
    }
    px[E + n] = cx0; py[E + n] = cy0;                                  // centre
    for (int v = 0; v < n; v++) { px[E + n + 1 + v] = vx[v]; py[E + n + 1 + v] = vy[v]; }  // vertices
    float bandW = side / (3.0 * kk), fgR = side / (6.0 * kk), bgR = side / (3.0 * kk);

    // tile background
    noStroke();
    fill(230);
    beginShape();
    for (int k = 0; k < n; k++) vertex(vx[k], vy[k]);
    endShape(CLOSE);

    // background wings: discs at the kk sub-segment boundaries per edge (corners +
    // the points between adjacent anchors), r = side/(3k), unclipped.
    if (wings) {
      noStroke(); fill(230);
      float bgD = 2 * bgR;
      for (int e = 0; e < n; e++) {
        int e2 = (e + 1) % n;
        for (int s = 0; s < kk; s++) {
          float tb = (float) s / kk;
          ellipse(vx[e] + tb * (vx[e2] - vx[e]), vy[e] + tb * (vy[e2] - vy[e]), bgD, bgD);
        }
      }
    }

    // bands (same construction as Shapes.pde). Circuit motifs stroke thin (side/10k).
    stroke(35);
    strokeCap(wholeHex ? ROUND : SQUARE);
    noFill();
    float thinW = max(1, side / (10.0 * kk));
    float tcx = 0, tcy = 0;
    for (int k = 0; k < n; k++) { tcx += vx[k]; tcy += vy[k]; }
    tcx /= n; tcy /= n;
    for (int[] c : conns) {
      strokeWeight((parent.isInlineComp(c[0]) || parent.isPointGlyph(c[0])) ? thinW : bandW);
      drawArchConn(c, n, kk, tcx, tcy, vx, vy, px, py);
    }

    // solid points (CONN_DOT): filled discs of band width
    noStroke(); fill(35);
    for (int[] c : conns) if (c[0] == parent.CONN_DOT) ellipse(px[c[1]], py[c[1]], 2 * fgR, 2 * fgR);

    // foreground wings: a fg-colour nub at each EDGE port (r = side/(6k)).
    if (wings) {
      noStroke(); fill(35);
      float fgD = 2 * fgR;
      for (int p = 0; p < E; p++) ellipse(px[p], py[p], fgD, fgD);
    }

    // faint tile outline
    noFill();
    stroke(95);
    strokeWeight(1);
    beginShape();
    for (int k = 0; k < n; k++) vertex(vx[k], vy[k]);
    endShape(CLOSE);
  }

  // One connection of an archetype: k=1 edge pair (arc/line) or tagged hub/hump;
  // k>1 multi-anchor port pair (arc when equal-radius else bezier). Uses the main
  // sketch's geometry helpers (parent.lineIntersect/bez/inwardNormal).
  void drawArchConn(int[] c, int n, int kk, float tcx, float tcy,
                    float[] vx, float[] vy, float[] px, float[] py) {
    if (c[0] == parent.CONN_DOT) return;           // solid disc -- drawn in a separate fill pass
    if (c[0] == parent.CONN_CIRCLE) {              // a ring at a port
      float r = dist(vx[0], vy[0], vx[1], vy[1]) / (3.0 * kk);
      ellipse(px[c[1]], py[c[1]], 2 * r, 2 * r);
      return;
    }
    if (parent.isInlineComp(c[0])) {               // resistor / inductor / capacitor / stepped (ports c[1],c[2])
      float side = dist(vx[0], vy[0], vx[1], vy[1]);
      float[][] sd = parent.componentSD(c[0], side / (3.5 * kk));
      float ax = px[c[1]], ay = py[c[1]], bx = px[c[2]], by = py[c[2]];
      float dx = bx - ax, dy = by - ay, L = max(1e-6, dist(ax, ay, bx, by));
      float ux = dx / L, uy = dy / L, wx = -uy, wy = ux;
      boolean started = false;
      for (float[] p : sd) {
        float s = p[0] * L, d = p[1];
        if (!started) { beginShape(); started = true; }
        else if (p.length > 2 && p[2] == 1) { endShape(); beginShape(); }
        vertex(ax + ux * s + wx * d, ay + uy * s + wy * d);
      }
      if (started) endShape();
      return;
    }
    if (c[0] == parent.CONN_TERM) {                // small open ring at a port
      float r = dist(vx[0], vy[0], vx[1], vy[1]) / (6.0 * kk);
      ellipse(px[c[1]], py[c[1]], 2 * r, 2 * r);
      return;
    }
    if (c[0] == parent.CONN_GROUND || c[0] == parent.CONN_ARROW || c[0] == parent.CONN_CROSS) {
      drawArchGlyph(c[0], c[1], kk, tcx, tcy, vx, vy, px, py);
      return;
    }
    if (kk <= 1 && c.length >= 1 && c[0] == parent.CONN_HUB) {
      for (int s = 1; s < c.length; s++) line(tcx, tcy, px[c[s]], py[c[s]]);
      return;
    }
    if (kk <= 1 && c.length >= 3 && c[0] == parent.CONN_HUMP) {
      int i = c[1], j = c[2];
      float dx = px[j] - px[i], dy = py[j] - py[i];
      float dl = max(1e-6, dist(px[i], py[i], px[j], py[j]));
      float nx = dy / dl, ny = -dx / dl, bulge = dl * 0.30;
      beginShape();
      for (int q = 0; q <= 24; q++) {
        float t = q / 24.0, h = bulge * (1 - cos(TWO_PI * t)) / 2.0;
        vertex(px[i] + dx * t + nx * h, py[i] + dy * t + ny * h);
      }
      endShape();
      return;
    }
    int pa = c[0], pb = c[1];
    int E = n * kk;
    // straight line: explicitly flagged ([a,b,1]) or touching an interior port
    boolean straight = (c.length >= 3 && c[2] == 1) || pa >= E || pb >= E;
    if (straight) { line(px[pa], py[pa], px[pb], py[pb]); return; }
    int ea = pa / kk, eb = pb / kk;
    if (kk <= 1) { int d = min(abs(pa - pb), n - abs(pa - pb)); if (n % 2 == 0 && d == n / 2) { line(px[pa], py[pa], px[pb], py[pb]); return; } }
    int ea2 = (ea + 1) % n, eb2 = (eb + 1) % n;
    float[] cc = parent.nearlyParallel(vx[ea], vy[ea], vx[ea2], vy[ea2], vx[eb], vy[eb], vx[eb2], vy[eb2])
                 ? null : parent.lineIntersect(vx[ea], vy[ea], vx[ea2], vy[ea2], vx[eb], vy[eb], vx[eb2], vy[eb2]);
    if (cc != null) {
      float ra = dist(px[pa], py[pa], cc[0], cc[1]), rb = dist(px[pb], py[pb], cc[0], cc[1]);
      if (ra > 0.1 && abs(ra - rb) <= 1e-3 * max(ra, rb)) {
        float a0 = atan2(py[pa] - cc[1], px[pa] - cc[0]);
        float a1 = atan2(py[pb] - cc[1], px[pb] - cc[0]);
        float diff = a1 - a0;
        while (diff <= -PI) diff += TWO_PI;
        while (diff > PI)  diff -= TWO_PI;
        arc(cc[0], cc[1], 2 * ra, 2 * ra, diff >= 0 ? a0 : a0 + diff, diff >= 0 ? a0 + diff : a0);
        return;
      }
    }
    float[] na = parent.inwardNormal(vx[ea], vy[ea], vx[ea2], vy[ea2], px[pa], py[pa], tcx, tcy);
    float[] nb = parent.inwardNormal(vx[eb], vy[eb], vx[eb2], vy[eb2], px[pb], py[pb], tcx, tcy);
    float h = 0.42 * dist(px[pa], py[pa], px[pb], py[pb]);
    float c1x = px[pa] + na[0] * h, c1y = py[pa] + na[1] * h;
    float c2x = px[pb] + nb[0] * h, c2y = py[pb] + nb[1] * h;
    beginShape();
    int seg = max(10, ceil(dist(px[pa], py[pa], px[pb], py[pb]) / 4.0));
    for (int q = 0; q <= seg; q++) {
      float u = (float) q / seg;
      vertex(parent.bez(px[pa], c1x, c2x, px[pb], u), parent.bez(py[pa], c1y, c2y, py[pb], u));
    }
    endShape();
  }

  // A point glyph (ground / arrow / cross) stroked at a port, oriented inward
  // (port -> centroid; defaults to screen-up at the centre port). Mirrors the
  // engine's emitGlyph (Shapes.pde). Stroke state is set by the caller.
  void drawArchGlyph(int code, int port, int kk, float tcx, float tcy,
                     float[] vx, float[] vy, float[] px, float[] py) {
    float g = dist(vx[0], vy[0], vx[1], vy[1]) / (6.0 * kk);
    float ox = px[port], oy = py[port];
    float ux = tcx - ox, uy = tcy - oy, L = sqrt(ux * ux + uy * uy);
    if (L < 1e-3) { ux = 0; uy = -1; } else { ux /= L; uy /= L; }
    float wx = -uy, wy = ux;
    if (code == parent.CONN_GROUND) {
      gseg(ox, oy, ux, uy, wx, wy, 0, 0,          1.4*g, 0);
      gseg(ox, oy, ux, uy, wx, wy, 1.4*g, -1.4*g, 1.4*g, 1.4*g);
      gseg(ox, oy, ux, uy, wx, wy, 2.0*g, -0.9*g, 2.0*g, 0.9*g);
      gseg(ox, oy, ux, uy, wx, wy, 2.6*g, -0.45*g,2.6*g, 0.45*g);
    } else if (code == parent.CONN_ARROW) {
      gseg(ox, oy, ux, uy, wx, wy, 0, 0, 1.7*g, 0);
      beginShape();
      gv(ox, oy, ux, uy, wx, wy, 0.9*g, -g);
      gv(ox, oy, ux, uy, wx, wy, 1.7*g, 0);
      gv(ox, oy, ux, uy, wx, wy, 0.9*g, g);
      endShape();
    } else if (code == parent.CONN_CROSS) {
      gseg(ox, oy, ux, uy, wx, wy, -g, 0, g, 0);
      gseg(ox, oy, ux, uy, wx, wy, 0, -g, 0, g);
    }
  }
  void gseg(float ox, float oy, float ux, float uy, float wx, float wy,
            float s0, float t0, float s1, float t1) {
    line(ox + ux*s0 + wx*t0, oy + uy*s0 + wy*t0, ox + ux*s1 + wx*t1, oy + uy*s1 + wy*t1);
  }
  void gv(float ox, float oy, float ux, float uy, float wx, float wy, float s, float t) {
    vertex(ox + ux*s + wx*t, oy + uy*s + wy*t);
  }

  // Draw one trapezoid archetype: the canonical half-hexagon (see Shapes.pde),
  // its bands sampled from parent.trapArcSpec, plus the foreground port nubs so
  // the unmatched-port caps read. Canonical y is up, so y is flipped here.
  void drawTrapArchetype(int[][] conns, float ccx, float ccy, float sz) {
    float H = parent.TRAP_H;
    float scale = sz / 2.4;                          // canonical width 2 fits in sz
    // tile background
    noStroke(); fill(230);
    beginShape();
    for (float[] v : parent.TRAP_V) vertex(ccx + (v[0] - 1) * scale, ccy - (v[1] - H / 2) * scale);
    endShape(CLOSE);

    // background wings: a bg-colour disc at each corner (the 4 vertices + the long
    // edge's mid "virtual corner" = TRAP_CORN), r = scale/3, unclipped.
    noStroke(); fill(230);
    float bgD = 2 * scale / 3.0;
    for (float[] cv : parent.TRAP_CORN) ellipse(ccx + (cv[0] - 1) * scale, ccy - (cv[1] - H / 2) * scale, bgD, bgD);

    // bands (centre-lines stroked at width scale/3, sampled from the arc specs)
    stroke(35); strokeWeight(scale / 3.0); strokeCap(SQUARE); noFill();
    for (int[] c : conns) {
      float[] sp = parent.trapArcSpec(c[0], c[1]);
      float r = sp[2], a0 = radians(sp[3]), a1 = radians(sp[4]);
      int seg = max(8, (int) (r * scale * abs(a1 - a0) / 3.0));
      beginShape();
      for (int k = 0; k <= seg; k++) {
        float ph = a0 + (a1 - a0) * k / seg;
        float zx = sp[0] + r * cos(ph), zy = sp[1] + r * sin(ph);
        vertex(ccx + (zx - 1) * scale, ccy - (zy - H / 2) * scale);
      }
      endShape();
    }

    // foreground port nubs (radius scale/6)
    noStroke(); fill(35);
    float d = scale / 3.0;
    for (float[] p : parent.TRAP_PORT) ellipse(ccx + (p[0] - 1) * scale, ccy - (p[1] - H / 2) * scale, d, d);

    // faint tile outline
    noFill(); stroke(95); strokeWeight(1);
    beginShape();
    for (float[] v : parent.TRAP_V) vertex(ccx + (v[0] - 1) * scale, ccy - (v[1] - H / 2) * scale);
    endShape(CLOSE);
  }

  // ---- interaction ----
  public void mousePressed() {
    // vertical tab rail
    int tb = tabAt(mouseX, mouseY);
    if (tb >= 0) { activeTab = tb; active = null; return; }

    // control-column sliders (active tab)
    for (Slider s : sliders) {
      if (shown(s.tab) && hitSlider(s)) { active = s; setSliderFromMouse(s); return; }
    }

    // persistent action bar
    if (bSeed.hit(mouseX, mouseY)) { parent.seedVal = (int) random(1, 99999); parent.logAction("CTRL seed -> " + parent.seedVal); parent.dirtyLayout = true; parent.dirtyGradient = true; parent.imgDirty = true; parent.redraw(); return; }
    if (bSave.hit(mouseX, mouseY)) { parent.logAction("CTRL save"); parent.saveRequested = true; parent.redraw(); return; }
    if (bLoadRender.hit(mouseX, mouseY)) { parent.logAction("CTRL load-render dialog"); selectInput("Load render manifest (.json)", "manifestChosen", null, parent); return; }

    // control-column per-tab widgets
    switch (activeTab) {
      case TAB_TILES:
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
        for (int i = 0; i < symBtns.length; i++) {
          if (symBtns[i].hit(mouseX, mouseY)) { parent.symmetryMode = i; parent.logAction("CTRL sym -> " + parent.SYMMETRY_NAMES[i]); parent.dirtyLayout = true; parent.redraw(); return; }
        }
        break;
      case TAB_SHADOW:
        if (tgShadow.hit(mouseX, mouseY))       { tgShadow.value = !tgShadow.value; parent.logAction("CTRL shadow -> " + tgShadow.value); syncParent(); return; }
        if (tgShadowGlobal.hit(mouseX, mouseY)) { tgShadowGlobal.value = !tgShadowGlobal.value; parent.logAction("CTRL shadowGlobal -> " + tgShadowGlobal.value); syncParent(); return; }
        if (tgExtrude.hit(mouseX, mouseY))      { tgExtrude.value = !tgExtrude.value; parent.logAction("CTRL extrude -> " + tgExtrude.value); syncParent(); return; }
        if (bExtrude.hit(mouseX, mouseY))       { parent.extrudeMode = (parent.extrudeMode + 1) % parent.EXTRUDE_NAMES.length; parent.logAction("CTRL extrudeMode -> " + parent.EXTRUDE_NAMES[parent.extrudeMode]); parent.redraw(); return; }
        break;
      case TAB_ANIM:
        if (tgAnim.hit(mouseX, mouseY)) { tgAnim.value = !tgAnim.value; parent.logAction("CTRL anim -> " + tgAnim.value); parent.setAnimEnabled(tgAnim.value); return; }
        if (tgPulse.hit(mouseX, mouseY)) {
          tgPulse.value = !tgPulse.value; parent.pulseEnabled = tgPulse.value;
          parent.logAction("CTRL pulse -> " + tgPulse.value);
          if (tgPulse.value) { parent.dirtyPaths = true; tgAnim.value = true; parent.setAnimEnabled(true); }
          parent.redraw();
          return;
        }
        if (bMorph.hit(mouseX, mouseY)) {     // trigger a one-shot morph (runs on viz thread)
          parent.logAction("CTRL morph");
          parent.morphRequested = true; parent.redraw();
          return;
        }
        if (bMorphStagger.hit(mouseX, mouseY)) {   // staggered morph (tiles finish at different times)
          parent.logAction("CTRL morph staggered");
          parent.morphStaggerRequested = true; parent.redraw();
          return;
        }
        break;
      case TAB_RENDER:
        if (tgLine.hit(mouseX, mouseY))   { tgLine.value = !tgLine.value; parent.logAction("CTRL line -> " + tgLine.value); parent.lineMode = tgLine.value; parent.redraw(); return; }
        if (tgKumiko.hit(mouseX, mouseY)) { tgKumiko.value = !tgKumiko.value; parent.logAction("CTRL kumiko -> " + tgKumiko.value); parent.kumikoStyle = tgKumiko.value; parent.redraw(); return; }
        if (tgMetal.hit(mouseX, mouseY)) { tgMetal.value = !tgMetal.value; parent.logAction("CTRL metal -> " + tgMetal.value); parent.metalMode = tgMetal.value; if (parent.imageMode) parent.imgDirty = true; parent.redraw(); return; }
        if (bMetalMat.hit(mouseX, mouseY)) {
          parent.ensureMetalMats();
          parent.metalMaterial = (parent.metalMaterial + 1) % parent.metalMats.length;
          parent.logAction("CTRL metalMat -> " + parent.metalMatName());
          if (parent.imageMode) parent.imgDirty = true;
          parent.redraw(); return;
        }
        if (bMetalStyle.hit(mouseX, mouseY)) {
          parent.metalBevelStyle = (parent.metalBevelStyle + 1) % 2;
          parent.logAction("CTRL metalStyle -> " + parent.metalBevelStyle);
          if (parent.imageMode) parent.imgDirty = true;
          parent.redraw(); return;
        }
        break;
      case TAB_IMAGE:
        if (tgImage.hit(mouseX, mouseY))      { tgImage.value = !tgImage.value; parent.logAction("CTRL imageMode -> " + tgImage.value); parent.imageMode = tgImage.value; parent.imgDirty = true; parent.redraw(); return; }
        if (tgImgStretch.hit(mouseX, mouseY)) { tgImgStretch.value = !tgImgStretch.value; parent.logAction("CTRL imgStretch -> " + tgImgStretch.value); parent.imgStretch = tgImgStretch.value; parent.imgDirty = true; parent.redraw(); return; }
        if (tgImgInvert.hit(mouseX, mouseY))  { tgImgInvert.value = !tgImgInvert.value; parent.logAction("CTRL imgInvert -> " + tgImgInvert.value); parent.imgInvert = tgImgInvert.value; parent.imgDirty = true; parent.redraw(); return; }
        if (tgImgContain.hit(mouseX, mouseY)) { tgImgContain.value = !tgImgContain.value; parent.logAction("CTRL imgContain -> " + tgImgContain.value); parent.imgContain = tgImgContain.value; parent.imgDirty = true; parent.redraw(); return; }
        if (bImgLoad.hit(mouseX, mouseY))     { parent.logAction("CTRL load-image dialog"); selectInput("Select an image", "imageChosen", null, parent); return; }
        break;
    }

    // tile pane (always visible)
    tilePanePressed();
  }

  // Hit-test the right-hand tile pane. Returns true if it consumed the click.
  boolean tilePanePressed() {
    // shape switches
    for (int i = 0; i < 4; i++) if (bShapes[i].hit(mouseX, mouseY)) {
      if (parent.shapeMode != i) { parent.shapeMode = i; parent.logAction("TILE shape -> " + parent.SHAPE_NAMES[i]); parent.dirtyLayout = true; parent.imgDirty = true; parent.redraw(); }
      return true;
    }
    // anchors/side switches
    for (int i = 0; i < 4; i++) if (bAnchors[i].hit(mouseX, mouseY)) {
      int k = i + 1;
      if (parent.anchorsPerSide != k) { parent.anchorsPerSide = k; parent.logAction("TILE anchors -> " + k); parent.dirtyLayout = true; parent.redraw(); }
      return true;
    }
    // reload-catalog: re-read tiles.json on the viz thread (via a flag, like Save)
    if (inRect(mouseX, mouseY, reX(), reY, reW, reH)) {
      parent.logAction("TILE reload-catalog"); parent.reloadCatalogRequested = true; parent.redraw(); return true;
    }
    // reset-weights: zero every weight in the active set
    if (inRect(mouseX, mouseY, rsX(), rsY, rsW, rsH)) { resetWeights(); return true; }
    // tileset prev/next (current shape + k)
    if (parent.shapeMode != 3 && parent.tilesetCount() > 1) {
      if (hitNav(prevX())) { parent.setActiveTileset(-1); parent.redraw(); return true; }
      if (hitNav(nextX())) { parent.setActiveTileset(+1); parent.redraw(); return true; }
    }
    int count = (parent.shapeMode == 3 ? parent.TRAP_CONNS
                                       : parent.connsFor(parent.SHAPE_N[parent.shapeMode])).length;
    // solo buttons (checked before sliders -- the "s" button overlaps the slider's
    // left hit margin): set this tile's weight to 1, all others to 0.
    for (int i = 0; i < count; i++) {
      int col = i % tileCols, row = i / tileCols;
      float cy = tileY0 + row * tileRowH, sx = soloX(col), sy = cy - soloSz / 2.0;
      if (inRect(mouseX, mouseY, sx, sy, soloSz, soloSz)) { soloTile(i); return true; }
    }
    // weight sliders
    for (int i = 0; i < count; i++) {
      int col = i % tileCols, row = i / tileCols;
      float cy = tileY0 + row * tileRowH;
      if (abs(mouseY - cy) < tileRowH / 2 - 2 && mouseX > tileTrkX0(col) - 14 && mouseX < tileTrkX1(col) + 30) {
        activeRow = i; setWeight(i); return true;
      }
    }
    return false;
  }

  // map a rail click -> tab index (vertical hit-test)
  int tabAt(int mx, int my) {
    if (mx < 0 || mx > railW) return -1;
    for (int i = 0; i < tabNames.length; i++) {
      int ty = railTabTop + i * (railTabH + railTabGap);
      if (my >= ty && my <= ty + railTabH) return i;
    }
    return -1;
  }

  public void mouseDragged() {
    if (active != null) setSliderFromMouse(active);
    else if (activeRow >= 0) setWeight(activeRow);
  }
  public void mouseReleased() { active = null; activeRow = -1; }

  public void mouseMoved() {
    for (Button b : buttons) b.hot = shown(b.tab) && b.hit(mouseX, mouseY);
    reloadHot = inRect(mouseX, mouseY, reX(), reY, reW, reH);
    resetHot  = inRect(mouseX, mouseY, rsX(), rsY, rsW, rsH);
    prevHot   = hitNav(prevX());
    nextHot   = hitNav(nextX());
  }

  void setSliderFromMouse(Slider s) {
    float t = constrain((mouseX - trkX0(s)) / (trkX1(s) - trkX0(s)), 0, 1);
    float v = lerp(s.lo, s.hi, t);
    s.value = s.isInt ? round(v) : v;
    parent.logAction("CTRL slider " + s.label + " = " + (s.isInt ? str((int) s.value) : nf(s.value, 0, 3)));
    syncParent();
  }

  // ---- tile-weight editing (the arrays pickWeighted draws from) ----
  // The active weight array (the one pickWeighted draws from + the panel displays).
  float[] activeWeights() {
    return (parent.shapeMode == 3) ? parent.TRAP_W
                                   : parent.weightsFor(parent.SHAPE_N[parent.shapeMode]);
  }
  // Zero every weight in the active set (blank slate; pickWeighted then renders blank).
  void resetWeights() {
    float[] w = activeWeights();
    for (int i = 0; i < w.length; i++) w[i] = 0;
    parent.logAction("TILE reset weights -> 0");
    parent.dirtyLayout = true;
    parent.redraw();
  }
  // Solo: this tile's weight to 1, all others to 0 (it becomes the only one chosen).
  void soloTile(int i) {
    float[] w = activeWeights();
    for (int j = 0; j < w.length; j++) w[j] = (j == i) ? 1.0 : 0.0;
    parent.logAction("TILE solo " + i);
    parent.dirtyLayout = true;
    parent.redraw();
  }
  void setWeight(int i) {
    int col = i % tileCols;
    float t = constrain((mouseX - tileTrkX0(col)) / (tileTrkX1(col) - tileTrkX0(col)), 0, 1);
    float[] w = activeWeights();
    w[i] = t * WMAX;
    parent.logAction("TILE weight[" + i + "] = " + nf(w[i], 0, 2));
    parent.dirtyLayout = true;   // weights drive the motif roll in collectTile -> rebuild
    parent.redraw();
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
    parent.pulseSpeed     = sPulseSpeed.value;            // light-pulse params (no layout rebuild)
    parent.pulseTrail     = sPulseTrail.value;
    parent.pulseCount     = (int) sPulseCount.value;
    parent.morphDurationSec = sMorphDur.value;
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
    if (parent.imageMode && (tgMetal.value != parent.metalMode
        || sMetalBevel.value != parent.metalBevelPx || sMetalLight.value != parent.metalLightDeg))
      parent.imgDirty = true;                            // metal changes patch brightness
    parent.metalMode    = tgMetal.value;
    parent.metalBevelPx = sMetalBevel.value;
    parent.metalLightDeg = sMetalLight.value;
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
    sMorphDur.value   = parent.morphDurationSec;
    sMetalBevel.value = parent.metalBevelPx;
    sMetalLight.value = parent.metalLightDeg;
    sImgCols.value  = parent.imgCols;
    sImgLib.value   = parent.libSize;
    sImgGamma.value = parent.imgGamma;
    tgKumiko.value       = parent.kumikoStyle;
    tgMetal.value        = parent.metalMode;
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
