// ============================================================
//  TileEditor.pde — a standalone Processing sketch for visually
//  authoring Truchet tile types (connection sets) for the main
//  Multiscale_Truchet visualizer.
//
//  Pick a shape (square / triangle / hexagon) and the number of ANCHOR
//  POINTS PER SIDE (k = 1..4); the side then carries k ports at (s+0.5)/k.
//  Click one port then a second to CONNECT them — a band appears live
//  with the exact renderer geometry (a perpendicular arc when the two
//  anchors are equidistant from the edge-line intersection, else a cubic
//  bezier with inward-normal tangents; matches Shapes.pde appendPortConn /
//  appendConn). A port may carry more than one connection. Right-click a
//  port to remove a connection. Set a weight, then Save.
//
//  Tiles are organised into TILESETS: a tileset is exactly 16 slots that
//  share a shape and a k. Pick a shape + k, then create / select a tileset
//  ("New set", "< Set"/"Set >") and click a slot in the 4x4 grid to edit it;
//  Save writes the buffer into that slot, Clear blanks it.
//
//  Editor and visualizer share ONE catalog: tiles.json in the parent folder
//  (v2 schema: { version:2, tilesets:[ {shape, sides, anchors, tiles:[16]} ] }).
//  The main sketch loads it at startup and renders the ACTIVE tileset for its
//  (shape, k), so: author here at some k, set the visualizer's anchors/side to
//  k, pick the same tileset, and hit "Reload tiles.json". k must be uniform
//  across a tiling to connect, so it is a global render parameter. This is a
//  SEPARATE sketch, so the geometry helpers (lineIntersect/bez/inwardNormal)
//  are duplicated.
//
//  Scope: square/triangle/hexagon. The trapezoid is port-based with
//  bespoke arc specs and is not edited here (and is always k=1).
//
//  Run:  processing-java --sketch=/mnt/e/Multiscale_Truchet/TileEditor --run
// ============================================================

import java.io.File;

// Tagged-primitive codes (mirror the main sketch). The click UI only creates
// plain {i,j} pairs, but loaded motifs may contain these, so the preview and
// edge-usage tests recognise them.
final int CONN_HUMP   = 100;   // { CONN_HUMP, i, j }       opposite-edge arch
final int CONN_HUB    = 101;   // { CONN_HUB, e0, e1, ... } centre-spoke junction
final int CONN_CIRCLE = 102;   // { CONN_CIRCLE, port }     a ring centred at the port
final int CONN_DOT     = 103;  // { CONN_DOT, port }        a solid disc (band width) at the port
// Circuit-inspired primitives (mirror Shapes.pde). Inline components join two ports
// (leads + a motif); point glyphs stamp one port, oriented inward. All stroked.
final int CONN_RES    = 104;   // { CONN_RES, a, b }    resistor (zigzag)
final int CONN_IND    = 105;   // { CONN_IND, a, b }    inductor (coils)
final int CONN_CAP    = 106;   // { CONN_CAP, a, b }    capacitor (gap + plates)
final int CONN_STEP   = 107;   // { CONN_STEP, a, b }   stepped (square wave)
final int CONN_GROUND = 108;   // { CONN_GROUND, port } ground glyph
final int CONN_ARROW  = 109;   // { CONN_ARROW, port }  inward arrowhead
final int CONN_TERM   = 110;   // { CONN_TERM, port }   open-circle terminal
final int CONN_CROSS  = 111;   // { CONN_CROSS, port }  plus / cross
boolean isInlineComp(int code) { return code >= CONN_RES && code <= CONN_STEP; }
boolean isPointGlyph(int code) { return code >= CONN_GROUND && code <= CONN_CROSS; }

// The editor's active TOOL. Connection tools (<= TOOL_STEP) act on a two-click pair;
// stamp tools (>= TOOL_RING) drop a single-port glyph on one click.
final int TOOL_ARC=0, TOOL_LINE=1, TOOL_RES=2, TOOL_IND=3, TOOL_CAP=4, TOOL_STEP=5;
final int TOOL_RING=6, TOOL_DOT=7, TOOL_GROUND=8, TOOL_ARROW=9, TOOL_TERM=10, TOOL_CROSS=11;
boolean isConnTool(int t)  { return t <= TOOL_STEP; }
boolean isStampTool(int t) { return t >= TOOL_RING; }
// Connection-tool -> inline-component code (RES/IND/CAP/STEP); -1 for ARC/LINE (plain pair).
int connToolCode(int t) {
  switch (t) { case TOOL_RES: return CONN_RES; case TOOL_IND: return CONN_IND;
               case TOOL_CAP: return CONN_CAP; case TOOL_STEP: return CONN_STEP; }
  return -1;
}
// Stamp-tool -> single-port glyph code.
int stampToolCode(int t) {
  switch (t) { case TOOL_RING: return CONN_CIRCLE; case TOOL_DOT: return CONN_DOT;
               case TOOL_GROUND: return CONN_GROUND; case TOOL_ARROW: return CONN_ARROW;
               case TOOL_TERM: return CONN_TERM; case TOOL_CROSS: return CONN_CROSS; }
  return -1;
}
String toolName(int t) {
  String[] nm = { "Arc","Line","Res","Ind","Cap","Step","Ring","Dot","Gnd","Arrow","Term","Cross" };
  return (t >= 0 && t < nm.length) ? nm[t] : "?";
}

final String[] SHAPE_KEYS  = { "square", "triangle", "hexagon" };
final int[]    SHAPE_N      = { 4, 3, 6 };
final float    WMAX         = 8.0;
final int      TILESET_SIZE = 16;        // a tileset is exactly 16 slots (4x4)

int shapeMode = 0;                       // 0 square / 1 triangle / 2 hexagon
int   anchorsK = 1;                       // anchor points per side (k); ports = sides*k
ArrayList<int[]> conns = new ArrayList<int[]>();   // work buffer: the current slot's connection set
int   pendingPort = -1;                  // first port of a pair-in-progress
float weight = 3.0;                       // the current slot's weight
int   tsIndex = 0;                        // which tileset (among the current shape+k list) is active
int   editSlot = 0;                       // which slot (0..15) of the active tileset is being edited
boolean showWings = true;                // draw Carlson wings (square/triangle only; hexagons never)
boolean kumikoStyle = false;             // preview as thin mitered Kumiko strips (no wings) -- matches the main sketch
final float stripWidthFrac = 0.10;       // Kumiko strip width as a fraction of side (matches the main sketch default)
int   tool = TOOL_ARC;                   // active palette tool (connection or stamp)
int   portE = 0;                         // count of edge ports (interior ports are >= portE)
String status = "";

JSONObject catalog;                      // { version:2, tilesets:[ {shape, sides, anchors, tiles:[16]} ] }

// headless verification (never screenshot the window): TILEEDITOR_OUT=path saves
// the first fully-drawn frame and exits; TILEEDITOR_SHAPE/TILEEDITOR_ANCHORS/
// TILEEDITOR_TILESET/TILEEDITOR_SLOT/TILEEDITOR_CONNS preload state (CONNS =
// "a-b,a-b,..." port pairs); TILEEDITOR_SAVE=1 writes the buffer into the slot.
String headlessOut = null;

// preview geometry (recomputed each frame; cached for hit-testing)
int   n;                                 // polygon sides
int   P;                                 // ports = n (k=1) or n*k
float pcx, pcy, pSz, pSide;
float[] vx, vy;                          // polygon vertices (edge lines)
float[] portX, portY;                    // the P clickable port positions

// layout
final int previewCX = 250, previewCY = 300, previewSz = 300;
final int trackX0 = 120, trackX1 = 440, weightY = 500;
final int colCX = 720, colSz = 74, colY0 = 96, colDY = 96;   // rotations column (far right)
Button[] shapeBtns, actionBtns, anchorBtns;
Button wingsBtn, kumikoBtn;
Button[] toolBtns;                       // pictogram tool palette (right of the preview)
int[]    toolCodes;                      // parallel: which TOOL_* each palette button selects
boolean draggingWeight = false;
// tool palette layout (two groups: Connect / Stamp), right of the preview
final int palX0 = 452, palBW = 74, palBH = 46, palGX = 80, palGY = 52;
final int palConnY = 116, palStampY = 320;

// the active tileset's 16-slot grid (4x4) at the bottom: each cell's {cx, cy, sz, slot}
// 2 rows of 8, full panel width (column spacing derived from `width` in drawSlotGrid).
final int slotY0 = 706, slotSz = 90, slotGapY = 124, slotMargin = 14, slotCols = 8;
ArrayList<float[]> slotRects = new ArrayList<float[]>();

// ---------------------------------------------------------------
void settings() { size(810, 1000); }

void setup() {
  surface.setTitle("Truchet — Tile Editor");
  textFont(createFont("SansSerif", 13));
  loadCatalog();

  headlessOut = System.getenv("TILEEDITOR_OUT");
  String envShape = System.getenv("TILEEDITOR_SHAPE");          // 0 square / 1 triangle / 2 hexagon
  if (envShape != null) shapeMode = constrain(Integer.parseInt(envShape.trim()), 0, 2);
  String envK = System.getenv("TILEEDITOR_ANCHORS");            // anchor points per side (1..4)
  if (envK != null) anchorsK = constrain(Integer.parseInt(envK.trim()), 1, 4);
  String envWings = System.getenv("TILEEDITOR_WINGS");          // 0/1 = wings off/on
  if (envWings != null) showWings = !envWings.trim().equals("0");
  String envKum = System.getenv("TILEEDITOR_KUMIKO");           // 0/1 = thin mitered Kumiko-strip preview
  if (envKum != null) kumikoStyle = !envKum.trim().equals("0");
  n = SHAPE_N[shapeMode];

  String envTs = System.getenv("TILEEDITOR_TILESET");          // active tileset among (shape, k)
  if (envTs != null) tsIndex = max(0, Integer.parseInt(envTs.trim()));
  String envSlot = System.getenv("TILEEDITOR_SLOT");           // slot index 0..15
  if (envSlot != null) editSlot = constrain(Integer.parseInt(envSlot.trim()), 0, TILESET_SIZE - 1);
  clampTsIndex();

  boolean preloaded = false;
  String envConns = System.getenv("TILEEDITOR_CONNS");          // "a-b,a-b-1,..." (a-b-1 = straight)
  if (envConns != null) {
    for (String p : split(envConns.trim(), ',')) {
      String[] ij = split(p.trim(), '-');
      if (ij.length == 2) conns.add(new int[]{ Integer.parseInt(ij[0].trim()), Integer.parseInt(ij[1].trim()) });
      else if (ij.length == 3) conns.add(new int[]{ Integer.parseInt(ij[0].trim()), Integer.parseInt(ij[1].trim()), Integer.parseInt(ij[2].trim()) });
    }
    preloaded = true;
  }
  if (!preloaded) loadSlot(editSlot);    // show the chosen slot's content (no-op if (shape,k) has no tileset)

  shapeBtns = new Button[] {
    new Button("Square",   18,  50, 100, 30),
    new Button("Triangle", 128, 50, 100, 30),
    new Button("Hexagon",  238, 50, 100, 30),
  };
  wingsBtn  = new Button("Wings",  366, 50, 70, 30);
  kumikoBtn = new Button("Kumiko", 444, 50, 78, 30);   // preview as thin mitered Kumiko strips
  // anchors-per-side selector (k = 1..4)
  anchorBtns = new Button[4];
  for (int i = 0; i < 4; i++) anchorBtns[i] = new Button(str(i + 1), 168 + i * 40, 88, 34, 26);
  // pictogram tool palette: 6 connection tools (Connect group) + 6 stamp tools
  // (Stamp group), each a 2-col x 3-row block to the right of the preview.
  int[] order = { TOOL_ARC, TOOL_LINE, TOOL_RES, TOOL_IND, TOOL_CAP, TOOL_STEP,
                  TOOL_RING, TOOL_DOT, TOOL_GROUND, TOOL_ARROW, TOOL_TERM, TOOL_CROSS };
  toolBtns  = new Button[order.length];
  toolCodes = order;
  for (int i = 0; i < order.length; i++) {
    boolean stamp = (i >= 6);
    int gi  = stamp ? i - 6 : i;                       // index within the group
    int col = gi % 2, row = gi / 2;
    int gy0 = stamp ? palStampY : palConnY;
    toolBtns[i] = new Button("", palX0 + col * palGX, gy0 + row * palGY, palBW, palBH);
  }

  if (System.getenv("TILEEDITOR_SAVE") != null) {            // headless save round-trip
    ArrayList<int[]> buf = new ArrayList<int[]>(conns);      // preserve buffer (newTileset reloads a blank slot)
    ensureTileset();
    conns = buf;
    saveEntry();
    exit();
  }

  actionBtns = new Button[] {
    new Button("< Set",   18,  545, 78, 30),     // tileset nav (within the current shape + k)
    new Button("Set >",   100, 545, 78, 30),
    new Button("New set", 250, 545, 96, 30),
    new Button("Del set", 350, 545, 96, 30),
    new Button("Save",    18,  583, 110, 32),    // write the buffer into the current slot
    new Button("Clear",   134, 583, 110, 32),    // blank the current slot
  };
}

// ---------------------------------------------------------------
void draw() {
  background(34);
  n = SHAPE_N[shapeMode];

  P = (anchorsK <= 1) ? n : n * anchorsK;

  // header
  fill(235); textAlign(LEFT, BASELINE); textSize(16);
  text("Tile Editor — click two anchor points to connect them", 18, 30);

  // shape buttons + wings toggle
  for (int i = 0; i < shapeBtns.length; i++) shapeBtns[i].draw(i == shapeMode);
  wingsBtn.draw(showWings);
  kumikoBtn.draw(kumikoStyle);

  // anchors-per-side selector
  fill(205); textAlign(LEFT, CENTER); textSize(13);
  text("anchors/side", 18, 101);
  for (int i = 0; i < anchorBtns.length; i++) anchorBtns[i].draw(anchorsK == i + 1);

  // tool palette (Connect = two-click pairs, Stamp = single-click glyphs)
  fill(205); textAlign(LEFT, BASELINE); textSize(12);
  text("connect (2 clicks)", palX0, palConnY - 6);
  text("stamp (1 click)",    palX0, palStampY - 6);
  for (int i = 0; i < toolBtns.length; i++) drawToolButton(toolBtns[i], toolCodes[i]);

  // preview + clickable edges
  drawPreview(previewCX, previewCY, previewSz);

  // rotations column (all phases the placer can roll)
  drawRotationsColumn();

  // weight slider
  fill(205); textAlign(LEFT, CENTER); textSize(13);
  text("weight", 18, weightY);
  stroke(90); strokeWeight(3); line(trackX0, weightY, trackX1, weightY);
  noStroke();
  float kx = lerp(trackX0, trackX1, constrain(weight / WMAX, 0, 1));
  fill(draggingWeight ? color(255, 200, 0) : color(120, 180, 255));
  ellipse(kx, weightY, 16, 16);
  fill(170); textAlign(LEFT, CENTER);
  text(nf(weight, 0, 1), trackX1 + 12, weightY);

  // action buttons
  for (Button b : actionBtns) b.draw(false);

  // status: tileset + slot + ports
  int tsCount = currentTilesets().size();
  String tsLbl = (tsCount == 0) ? "no tileset (click 'New set')" : ("set " + (tsIndex + 1) + " / " + tsCount);
  fill(150); textAlign(LEFT, CENTER); textSize(12);
  text(SHAPE_KEYS[shapeMode] + " k=" + anchorsK + " (" + P + " ports)  ·  " + tsLbl
       + "  ·  slot " + (editSlot + 1) + "/16" + connsLabel(), 18, 628);
  fill(110);
  text("pick a tool • Connect tools: click two points • Stamp tools: click one • "
       + "green = centre/apothem • amber = corners • right-click a point to remove", 18, 648);
  if (status.length() > 0) { fill(120, 200, 140); text(status, 18, 668); }
  fill(90); textAlign(LEFT, CENTER); textSize(11);
  text("shared catalog: " + tilesPath(), 18, 686);

  drawSlotGrid();

  if (headlessOut != null && frameCount >= 2) { save(headlessOut); exit(); }
}

// The active tileset's 16 slots (4x4) as clickable thumbnails. Click one to edit it;
// the slot being edited is boxed; blank slots show an empty cell.
void drawSlotGrid() {
  slotRects.clear();
  JSONObject ts = currentTileset();
  fill(205); textAlign(LEFT, BASELINE); textSize(13);
  String hdr = (ts == null) ? "tiles — no tileset for " + SHAPE_KEYS[shapeMode] + " k=" + anchorsK + " (click 'New set')"
                            : "tiles — " + SHAPE_KEYS[shapeMode] + " k=" + anchorsK + " · set " + (tsIndex + 1);
  text(hdr, slotMargin, slotY0 - 8);
  textAlign(LEFT, CENTER);
  if (ts == null) return;
  JSONArray tiles = ts.getJSONArray("tiles");
  for (int i = 0; i < TILESET_SIZE; i++) {
    int col = i % slotCols, row = i / slotCols;
    float colW = (width - 2.0 * slotMargin) / slotCols;     // span the full panel width
    float cx = slotMargin + colW * (col + 0.5);
    float cy = slotY0 + 18 + slotSz / 2.0 + row * slotGapY;
    noFill(); stroke(i == editSlot ? color(255, 200, 0) : color(70)); strokeWeight(i == editSlot ? 2 : 1);
    rect(cx - slotSz / 2.0 - 3, cy - slotSz / 2.0 - 3, slotSz + 6, slotSz + 6, 4);
    noStroke();
    ArrayList<int[]> cs = connsOfTile(tiles, i);
    if (!cs.isEmpty()) renderTile(cs, cx, cy, slotSz, 0, false);
    fill(150); textSize(9); textAlign(CENTER, CENTER);
    text((i + 1) + (cs.isEmpty() ? "" : "  w" + nf(tiles.getJSONObject(i).getFloat("weight", 0), 0, 1)),
         cx, cy + slotSz / 2.0 + 9);
    slotRects.add(new float[]{ cx, cy, slotSz, i });
  }
  textAlign(LEFT, BASELINE);
}

// Parse tiles[i].conns into the editor's connection form.
ArrayList<int[]> connsOfTile(JSONArray tiles, int i) {
  ArrayList<int[]> out = new ArrayList<int[]>();
  if (i < 0 || i >= tiles.size()) return out;
  JSONArray a = tiles.getJSONObject(i).getJSONArray("conns");
  if (a == null) return out;
  for (int q = 0; q < a.size(); q++) {
    JSONArray jc = a.getJSONArray(q);
    int[] c = new int[jc.size()];
    for (int t = 0; t < jc.size(); t++) c[t] = jc.getInt(t);
    out.add(c);
  }
  return out;
}

String connsLabel() {
  if (conns.isEmpty()) return "  conns: (blank)";
  StringBuilder sb = new StringBuilder("  conns: ");
  for (int i = 0; i < conns.size(); i++) {
    int[] c = conns.get(i);
    sb.append("{");
    for (int t = 0; t < c.length; t++) { if (t > 0) sb.append(","); sb.append(c[t]); }
    sb.append("}");
    if (i < conns.size() - 1) sb.append(" ");
  }
  return sb.toString();
}

// ---- preview ---------------------------------------------------
// The large interactive tile (rotSteps = 0, clickable edges) plus, on the right,
// a column of small thumbnails of every rotation — a placed tile gets a random
// mk·(2π/n) turn, so rotating the polygon by k·(2π/n) shows each phase.
void drawPreview(float ccx, float ccy, float sz) {
  renderTile(conns, ccx, ccy, sz, 0, true);
}

void drawRotationsColumn() {
  fill(205); textAlign(CENTER, BASELINE); textSize(13);
  text("rotations (" + n + ")", colCX, colY0 - 36);
  textAlign(LEFT, BASELINE);
  for (int k = 0; k < n; k++) {
    float cy = colY0 + k * colDY;
    renderTile(conns, colCX, cy, colSz, k, false);
    fill(120); textAlign(CENTER, CENTER); textSize(10);
    text("×" + k, colCX, cy + colSz * 0.5 + 8);
    textAlign(LEFT, BASELINE);
  }
}

// Render one tile (its connection set) at a rotation of rotSteps·(2π/n). When
// interactive, the geometry is cached for hit-testing and clickable edge markers
// are drawn. Mirrors TileWindow.drawArchetype.
void renderTile(ArrayList<int[]> cs, float ccx, float ccy, float sz, int rotSteps, boolean interactive) {
  int k = max(1, anchorsK);
  boolean wholeHex = (n == 6 && k == 1);
  boolean wings = !wholeHex && showWings && !kumikoStyle;   // Kumiko = bare strips, no wing discs
  float R   = sz * ((n != 6 || k > 1) ? 0.40 : 0.46);
  float rot = ((n == 4) ? QUARTER_PI : -HALF_PI) + rotSteps * TWO_PI / n;
  float[] lvx = new float[n], lvy = new float[n];
  for (int e = 0; e < n; e++) {
    float a = rot + TWO_PI * e / n;
    lvx[e] = ccx + R * cos(a);
    lvy[e] = ccy + R * sin(a);
  }
  float side = dist(lvx[0], lvy[0], lvx[1], lvy[1]);
  float tcx = 0, tcy = 0;
  for (int e = 0; e < n; e++) { tcx += lvx[e]; tcy += lvy[e]; }
  tcx /= n; tcy /= n;
  // ports: E edge anchors (k per side), then n apothem midpoints (centre->edge
  // midpoint, halfway), then the centre. The interior ports (apothem/centre) are
  // connection endpoints only -- they get no wing nub.
  int E = n * k;
  int pc = E + 2 * n + 1;             // edge anchors + apothem mids + centre + n vertices
  float[] lpx = new float[pc], lpy = new float[pc];
  for (int e = 0; e < n; e++) {
    int e2 = (e + 1) % n;
    for (int s = 0; s < k; s++) {
      float tt = (s + 0.5) / k;
      lpx[e * k + s] = lvx[e] + tt * (lvx[e2] - lvx[e]);
      lpy[e * k + s] = lvy[e] + tt * (lvy[e2] - lvy[e]);
    }
    float emx = (lvx[e] + lvx[e2]) / 2, emy = (lvy[e] + lvy[e2]) / 2;   // edge midpoint
    lpx[E + e] = (tcx + emx) / 2; lpy[E + e] = (tcy + emy) / 2;          // apothem midpoint
  }
  lpx[E + n] = tcx; lpy[E + n] = tcy;                                    // centre
  for (int v = 0; v < n; v++) { lpx[E + n + 1 + v] = lvx[v]; lpy[E + n + 1 + v] = lvy[v]; }  // vertices (Kumiko)
  portE = E;
  float bandW = side / (3.0 * k), fgR = side / (6.0 * k), bgR = side / (3.0 * k);

  // tile background
  noStroke(); fill(230);
  beginShape(); for (int e = 0; e < n; e++) vertex(lvx[e], lvy[e]); endShape(CLOSE);

  // background wings: discs at the k sub-segment boundaries per edge (s/k, i.e. the
  // corners plus the points BETWEEN adjacent anchors), r = side/(3k)
  if (wings) {
    float bgD = 2 * bgR;
    for (int e = 0; e < n; e++) {
      int e2 = (e + 1) % n;
      for (int s = 0; s < k; s++) {
        float tb = (float) s / k;
        ellipse(lvx[e] + tb * (lvx[e2] - lvx[e]), lvy[e] + tb * (lvy[e2] - lvy[e]), bgD, bgD);
      }
    }
  }

  // bands -- Kumiko: thin uniform strips with a square cap + mitered join; else the side/3 band.
  // Circuit motifs are fine linework, stroked thin (side/10k) regardless (matches the engine).
  stroke(35); noFill();
  float mainW = kumikoStyle ? max(1, stripWidthFrac * side) : bandW;
  float thinW = max(1, side / (10.0 * k));
  if (kumikoStyle) { strokeCap(SQUARE); strokeJoin(MITER); }
  else             { strokeCap(wholeHex ? ROUND : SQUARE); }
  for (int[] c : cs) {
    strokeWeight((isInlineComp(c[0]) || isPointGlyph(c[0])) ? thinW : mainW);
    drawConn(c, tcx, tcy, lvx, lvy, lpx, lpy, k);
  }

  // solid points (CONN_DOT): filled discs of band width at any port
  noStroke(); fill(35);
  float dotD = 2 * fgR;
  for (int[] c : cs) if (c[0] == CONN_DOT) ellipse(lpx[c[1]], lpy[c[1]], dotD, dotD);

  // foreground wings (port nubs, r = side/(6k)) -- EDGE ports only
  if (wings) {
    noStroke(); fill(35);
    float fgD = 2 * fgR;
    for (int p = 0; p < E; p++) ellipse(lpx[p], lpy[p], fgD, fgD);
  }

  // faint outline
  noFill(); stroke(95); strokeWeight(1);
  beginShape(); for (int e = 0; e < n; e++) vertex(lvx[e], lvy[e]); endShape(CLOSE);

  if (interactive) {
    pcx = ccx; pcy = ccy; pSz = sz; pSide = side;
    vx = lvx; vy = lvy; portX = lpx; portY = lpy;
    // clickable port markers + indices (interior ports = apothem mids + centre
    // shown with a green tint so they read apart from the edge anchors)
    float md = constrain(13.0 / sqrt(k), 7, 14);
    textAlign(CENTER, CENTER); textSize(k > 2 ? 9 : 11);
    for (int p = 0; p < pc; p++) {
      noStroke();
      if (p == pendingPort)      fill(255, 200, 0);
      else if (portUsed(p))      fill(120, 180, 255);
      else if (p > E + n)        fill(235, 150, 60);    // vertex (corner) -- Kumiko lattice point
      else if (p >= E)           fill(120, 200, 140);   // interior (apothem / centre)
      else                       fill(150);
      ellipse(lpx[p], lpy[p], md, md);
      fill(20);
      text(p, lpx[p], lpy[p] - 0.5);
    }
    textAlign(LEFT, BASELINE);
  }
}

// one connection. k=1: a plain edge pair (arc/line) or a tagged hub/hump primitive.
// k>1: a multi-anchor PORT pair -- a perpendicular circular arc when the two anchors
// are equidistant from the edge-line intersection, else a cubic bezier with tangents
// along the inward edge normals (matches Shapes.pde appendPortConn).
void drawConn(int[] c, float tcx, float tcy, float[] vx, float[] vy, float[] px, float[] py, int k) {
  if (c[0] == CONN_DOT) return;                   // solid disc -- drawn in a separate fill pass
  if (c[0] == CONN_CIRCLE) {                      // a ring at a port
    float r = dist(vx[0], vy[0], vx[1], vy[1]) / (3.0 * k);
    ellipse(px[c[1]], py[c[1]], 2 * r, 2 * r);   // noFill + band stroke already set -> ring
    return;
  }
  if (isInlineComp(c[0])) {                       // resistor / inductor / capacitor / stepped
    float side = dist(vx[0], vy[0], vx[1], vy[1]);
    drawComponent(c[0], px[c[1]], py[c[1]], px[c[2]], py[c[2]], side / (3.5 * k));
    return;
  }
  if (c[0] == CONN_TERM) {                        // small open ring at a port
    float r = dist(vx[0], vy[0], vx[1], vy[1]) / (6.0 * k);
    ellipse(px[c[1]], py[c[1]], 2 * r, 2 * r);
    return;
  }
  if (c[0] == CONN_GROUND || c[0] == CONN_ARROW || c[0] == CONN_CROSS) {
    drawGlyph(c[0], c[1], tcx, tcy, vx, vy, px, py, k);
    return;
  }
  if (k <= 1 && c.length >= 1 && c[0] == CONN_HUB) {
    for (int s = 1; s < c.length; s++) line(tcx, tcy, px[c[s]], py[c[s]]);
    return;
  }
  if (k <= 1 && c.length >= 3 && c[0] == CONN_HUMP) {
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
  int E = n * k;
  // straight line: explicitly flagged ([a,b,1]) or touching an interior port
  boolean straight = (c.length >= 3 && c[2] == 1) || pa >= E || pb >= E;
  if (straight) { line(px[pa], py[pa], px[pb], py[pb]); return; }
  int ea = pa / k, eb = pb / k;
  int ea2 = (ea + 1) % n, eb2 = (eb + 1) % n;
  // opposite edges, single anchor -> straight band (k=1 only; matches engine)
  if (k <= 1) { int d = min(abs(pa - pb), n - abs(pa - pb)); if (n % 2 == 0 && d == n / 2) { line(px[pa], py[pa], px[pb], py[pb]); return; } }
  float[] cc = nearlyParallel(vx[ea], vy[ea], vx[ea2], vy[ea2], vx[eb], vy[eb], vx[eb2], vy[eb2])
               ? null : lineIntersect(vx[ea], vy[ea], vx[ea2], vy[ea2], vx[eb], vy[eb], vx[eb2], vy[eb2]);
  if (cc != null) {
    float ra = dist(px[pa], py[pa], cc[0], cc[1]), rb = dist(px[pb], py[pb], cc[0], cc[1]);
    if (ra > 0.1 && abs(ra - rb) <= 1e-3 * max(ra, rb)) {           // equal radii -> arc
      float a0 = atan2(py[pa] - cc[1], px[pa] - cc[0]);
      float a1 = atan2(py[pb] - cc[1], px[pb] - cc[0]);
      float diff = a1 - a0;
      while (diff <= -PI) diff += TWO_PI;
      while (diff > PI)  diff -= TWO_PI;
      arc(cc[0], cc[1], 2 * ra, 2 * ra, diff >= 0 ? a0 : a0 + diff, diff >= 0 ? a0 + diff : a0);
      return;
    }
  }
  // cubic bezier with inward-normal tangents
  float[] na = inwardNormal(vx[ea], vy[ea], vx[ea2], vy[ea2], px[pa], py[pa], tcx, tcy);
  float[] nb = inwardNormal(vx[eb], vy[eb], vx[eb2], vy[eb2], px[pb], py[pb], tcx, tcy);
  float h = 0.42 * dist(px[pa], py[pa], px[pb], py[pb]);
  float c1x = px[pa] + na[0] * h, c1y = py[pa] + na[1] * h;
  float c2x = px[pb] + nb[0] * h, c2y = py[pb] + nb[1] * h;
  noFill();
  beginShape();
  int seg = max(10, ceil(dist(px[pa], py[pa], px[pb], py[pb]) / 4.0));
  for (int q = 0; q <= seg; q++) {
    float u = (float) q / seg;
    vertex(bez(px[pa], c1x, c2x, px[pb], u), bez(py[pa], c1y, c2y, py[pb], u));
  }
  endShape();
}

// ---- circuit-inspired primitives (mirror Shapes.pde appendComponent/emitGlyph) ----
// Inline component A->B: leads + a motif, amplitude `amp`. Stroke state set by caller.
void drawComponent(int code, float ax, float ay, float bx, float by, float amp) {
  float[][] sd = componentSD(code, amp);
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
}
float[][] componentSD(int code, float a) {
  if (code == CONN_RES)  return new float[][]{ {0,0},{0.30,0},{0.35,a},{0.45,-a},{0.55,a},{0.65,-a},{0.70,0},{1,0} };
  if (code == CONN_STEP) return new float[][]{ {0,0},{0.2,0},{0.2,a},{0.4,a},{0.4,0},{0.6,0},{0.6,a},{0.8,a},{0.8,0},{1,0} };
  if (code == CONN_CAP)  return new float[][]{ {0,0},{0.44,0}, {0.44,-a,1},{0.44,a}, {0.56,-a,1},{0.56,a}, {0.56,0,1},{1,0} };
  ArrayList<float[]> pts = new ArrayList<float[]>();           // CONN_IND: leads + 3 same-side bumps
  pts.add(new float[]{0,0}); pts.add(new float[]{0.25,0});
  int nb = 3; float s0 = 0.25, w = 0.5 / nb;
  for (int b = 0; b < nb; b++)
    for (int q = 1; q <= 8; q++) { float t = q / 8.0; pts.add(new float[]{ s0 + w * (b + t), a * sin(PI * t) }); }
  pts.add(new float[]{1,0});
  return pts.toArray(new float[0][]);
}
// Point glyph at a port, oriented inward (port -> centroid). Stroke state set by caller.
void drawGlyph(int code, int port, float tcx, float tcy, float[] vx, float[] vy, float[] px, float[] py, int k) {
  float g = dist(vx[0], vy[0], vx[1], vy[1]) / (6.0 * k);
  float ox = px[port], oy = py[port];
  float ux = tcx - ox, uy = tcy - oy, L = sqrt(ux * ux + uy * uy);
  if (L < 1e-3) { ux = 0; uy = -1; } else { ux /= L; uy /= L; }
  float wx = -uy, wy = ux;
  if (code == CONN_GROUND) {
    gseg(ox, oy, ux, uy, wx, wy, 0, 0,          1.4*g, 0);
    gseg(ox, oy, ux, uy, wx, wy, 1.4*g, -1.4*g, 1.4*g, 1.4*g);
    gseg(ox, oy, ux, uy, wx, wy, 2.0*g, -0.9*g, 2.0*g, 0.9*g);
    gseg(ox, oy, ux, uy, wx, wy, 2.6*g, -0.45*g,2.6*g, 0.45*g);
  } else if (code == CONN_ARROW) {
    gseg(ox, oy, ux, uy, wx, wy, 0, 0, 1.7*g, 0);
    beginShape();
    gv(ox, oy, ux, uy, wx, wy, 0.9*g, -g);
    gv(ox, oy, ux, uy, wx, wy, 1.7*g, 0);
    gv(ox, oy, ux, uy, wx, wy, 0.9*g, g);
    endShape();
  } else if (code == CONN_CROSS) {
    gseg(ox, oy, ux, uy, wx, wy, -g, 0, g, 0);
    gseg(ox, oy, ux, uy, wx, wy, 0, -g, 0, g);
  }
}
void gseg(float ox, float oy, float ux, float uy, float wx, float wy, float s0, float t0, float s1, float t1) {
  line(ox + ux*s0 + wx*t0, oy + uy*s0 + wy*t0, ox + ux*s1 + wx*t1, oy + uy*s1 + wy*t1);
}
void gv(float ox, float oy, float ux, float uy, float wx, float wy, float s, float t) {
  vertex(ox + ux*s + wx*t, oy + uy*s + wy*t);
}

// ---- tool palette rendering ------------------------------------
void drawToolButton(Button b, int t) {
  boolean on = (tool == t);
  fill(on ? color(70, 110, 160) : color(60));
  stroke(110); strokeWeight(1);
  rect(b.x, b.y, b.w, b.h, 5);
  noStroke();
  drawToolIcon(t, b.x + b.w / 2.0, b.y + 15, 10);
  fill(on ? 255 : 205); textAlign(CENTER, CENTER); textSize(10);
  text(toolName(t), b.x + b.w / 2.0, b.y + b.h - 11);
  textAlign(LEFT, BASELINE);
}
// A small representative icon for each tool, centred at (cx,cy), nominal radius r.
void drawToolIcon(int t, float cx, float cy, float r) {
  stroke(on(t) ? 255 : 225); strokeWeight(2); noFill();
  if (t == TOOL_ARC)        arc(cx - r, cy + r, 4 * r, 4 * r, -HALF_PI, 0);
  else if (t == TOOL_LINE)  line(cx - r, cy, cx + r, cy);
  else if (t == TOOL_RES)   { beginShape(); vertex(cx-r,cy); vertex(cx-r*0.6,cy); vertex(cx-r*0.4,cy-r); vertex(cx-r*0.1,cy+r); vertex(cx+r*0.2,cy-r); vertex(cx+r*0.5,cy+r); vertex(cx+r*0.6,cy); vertex(cx+r,cy); endShape(); }
  else if (t == TOOL_IND)   { for (int i = 0; i < 3; i++) { float bx = cx - r + (i + 0.5) * (2*r/3.0); arc(bx, cy, 2*r/3.0, 2*r/3.0, PI, TWO_PI); } }
  else if (t == TOOL_CAP)   { line(cx-r,cy,cx-r*0.25,cy); line(cx+r*0.25,cy,cx+r,cy); line(cx-r*0.25,cy-r*0.9,cx-r*0.25,cy+r*0.9); line(cx+r*0.25,cy-r*0.9,cx+r*0.25,cy+r*0.9); }
  else if (t == TOOL_STEP)  { beginShape(); vertex(cx-r,cy); vertex(cx-r*0.5,cy); vertex(cx-r*0.5,cy-r); vertex(cx,cy-r); vertex(cx,cy); vertex(cx+r*0.5,cy); vertex(cx+r*0.5,cy-r); vertex(cx+r,cy-r); endShape(); }
  else if (t == TOOL_RING)  ellipse(cx, cy, 1.8*r, 1.8*r);
  else if (t == TOOL_DOT)   { noStroke(); fill(on(t) ? 255 : 225); ellipse(cx, cy, 1.4*r, 1.4*r); }
  else if (t == TOOL_GROUND){ line(cx,cy-r,cx,cy-r*0.15); line(cx-r,cy-r*0.15,cx+r,cy-r*0.15); line(cx-r*0.6,cy+r*0.3,cx+r*0.6,cy+r*0.3); line(cx-r*0.25,cy+r*0.7,cx+r*0.25,cy+r*0.7); }
  else if (t == TOOL_ARROW) { line(cx,cy-r,cx,cy+r*0.35); beginShape(); vertex(cx-r*0.6,cy); vertex(cx,cy+r*0.7); vertex(cx+r*0.6,cy); endShape(); }
  else if (t == TOOL_TERM)  ellipse(cx, cy, 1.1*r, 1.1*r);
  else if (t == TOOL_CROSS) { line(cx-r,cy,cx+r,cy); line(cx,cy-r,cx,cy+r); }
  noStroke();
}
boolean on(int t) { return tool == t; }

float bez(float p0, float p1, float p2, float p3, float u) {
  float v = 1 - u;
  return v*v*v*p0 + 3*v*v*u*p1 + 3*v*u*u*p2 + u*u*u*p3;
}
boolean nearlyParallel(float ax, float ay, float bx, float by, float cx, float cy, float dx2, float dy2) {
  float ux = bx - ax, uy = by - ay, vx2 = dx2 - cx, vy2 = dy2 - cy;
  float lu = sqrt(ux*ux + uy*uy), lv = sqrt(vx2*vx2 + vy2*vy2);
  if (lu < 1e-6 || lv < 1e-6) return true;
  return abs(ux*vy2 - uy*vx2) / (lu*lv) < 1e-3;
}
float[] inwardNormal(float ax, float ay, float bx, float by, float pxx, float pyy, float cx, float cy) {
  float dx = bx - ax, dy = by - ay, dl = max(1e-6, sqrt(dx*dx + dy*dy));
  float nx = -dy / dl, ny = dx / dl;
  if (nx * (cx - pxx) + ny * (cy - pyy) < 0) { nx = -nx; ny = -ny; }
  return new float[]{ nx, ny };
}

// ---- port-usage helpers ----------------------------------------
boolean connUsesPort(int[] c, int p) {
  if (c[0] == CONN_CIRCLE || c[0] == CONN_DOT || isPointGlyph(c[0])) return c[1] == p;
  if (isInlineComp(c[0]))                 return c.length >= 3 && (c[1] == p || c[2] == p);
  if (anchorsK <= 1 && c[0] == CONN_HUMP) return c.length >= 3 && (c[1] == p || c[2] == p);
  if (anchorsK <= 1 && c[0] == CONN_HUB)  { for (int s = 1; s < c.length; s++) if (c[s] == p) return true; return false; }
  return c[0] == p || c[1] == p;     // plain pair; a 3rd element is the straight flag, not a port
}
boolean portUsed(int p) { for (int[] c : conns) if (connUsesPort(c, p)) return true; return false; }

// ---- interaction -----------------------------------------------
void mousePressed() {
  status = "";
  // shape buttons
  for (int i = 0; i < shapeBtns.length; i++) {
    if (shapeBtns[i].hit(mouseX, mouseY)) { setShape(i); return; }
  }
  if (wingsBtn.hit(mouseX, mouseY))  { showWings = !showWings; redraw(); return; }
  if (kumikoBtn.hit(mouseX, mouseY)) { kumikoStyle = !kumikoStyle; redraw(); return; }
  for (int i = 0; i < anchorBtns.length; i++) {
    if (anchorBtns[i].hit(mouseX, mouseY)) { setAnchors(i + 1); return; }
  }
  // tool palette: pick the active tool
  for (int i = 0; i < toolBtns.length; i++) {
    if (toolBtns[i].hit(mouseX, mouseY)) { tool = toolCodes[i]; pendingPort = -1; redraw(); return; }
  }
  // weight slider
  if (abs(mouseY - weightY) < 16 && mouseX > trackX0 - 16 && mouseX < trackX1 + 16) {
    draggingWeight = true; setWeightFromMouse(); return;
  }
  // action buttons
  for (Button b : actionBtns) {
    if (b.hit(mouseX, mouseY)) { doAction(b.label); return; }
  }
  // slot grid: click a cell to edit that slot
  for (float[] g : slotRects) {
    if (abs(mouseX - g[0]) < g[2] / 2 + 4 && abs(mouseY - g[1]) < g[2] / 2 + 4) { selectSlot((int) g[3]); return; }
  }
  // port click: right = remove; stamp tool = place/remove a glyph; connection tool = connect
  int e = nearestPort(mouseX, mouseY);
  if (e >= 0) {
    if (mouseButton == RIGHT)   removeConnAt(e);
    else if (isStampTool(tool)) toggleStamp(stampToolCode(tool), e);
    else                        clickPort(e);
  }
}

// Circle/Point modes: a click on a port toggles a [tag, port] element there.
void toggleStamp(int tag, int p) {
  for (int i = conns.size() - 1; i >= 0; i--) {
    int[] c = conns.get(i);
    if (c[0] == tag && c[1] == p) { conns.remove(i); redraw(); return; }
  }
  conns.add(new int[]{ tag, p });
  redraw();
}

void mouseDragged() { if (draggingWeight) setWeightFromMouse(); }
void mouseReleased() { draggingWeight = false; }

void setWeightFromMouse() {
  weight = constrain((mouseX - trackX0) / float(trackX1 - trackX0), 0, 1) * WMAX;
  redraw();
}

int nearestPort(int qx, int qy) {
  if (portX == null) return -1;
  int best = -1; float bestD = constrain(0.45 * pSide / max(1, anchorsK) + 10, 12, 0.45 * pSide);
  for (int p = 0; p < portX.length; p++) {
    float d = dist(qx, qy, portX[p], portY[p]);
    if (d < bestD) { bestD = d; best = p; }
  }
  return best;
}

void clickPort(int e) {
  // a port may carry more than one connection, so connecting never auto-removes
  if (pendingPort == -1)      pendingPort = e;          // first port of a pair
  else if (pendingPort == e)  pendingPort = -1;         // click same port -> cancel
  else {                                                // complete the pair
    int comp = connToolCode(tool);                      // RES/IND/CAP/STEP, or -1 for ARC/LINE
    if (comp >= 0) {
      conns.add(new int[]{ comp, pendingPort, e });     // inline component
    } else {
      boolean straight = (tool == TOOL_LINE) || pendingPort >= portE || e >= portE;  // interior -> always straight
      conns.add(straight ? new int[]{ pendingPort, e, 1 } : new int[]{ pendingPort, e });
    }
    pendingPort = -1;
  }
  redraw();
}

// right-click: remove the most-recently-added connection touching this port
void removeConnAt(int e) {
  for (int i = conns.size() - 1; i >= 0; i--) {
    if (connUsesPort(conns.get(i), e)) { conns.remove(i); pendingPort = -1; redraw(); return; }
  }
  pendingPort = -1;
  redraw();
}

void setShape(int s)   { shapeMode = s; n = SHAPE_N[s]; onComboChanged(); }
void setAnchors(int k)  { anchorsK = k; onComboChanged(); }   // ports change -> reselect

// Shape or k changed: snap to the first tileset / first slot of the new (shape, k).
void onComboChanged() {
  tsIndex = 0; editSlot = 0; pendingPort = -1;
  clampTsIndex();
  loadSlot(editSlot);
  status = "";
  redraw();
}

void doAction(String label) {
  if (label.equals("Save"))         saveEntry();
  else if (label.equals("Clear"))   clearSlot();
  else if (label.equals("New set")) newTileset();
  else if (label.equals("Del set")) deleteTileset();
  else if (label.equals("< Set"))   browseTileset(-1);
  else if (label.equals("Set >"))   browseTileset(+1);
}

// Make slot `s` the edit target and load its content into the work buffer.
void selectSlot(int s) {
  editSlot = constrain(s, 0, TILESET_SIZE - 1);
  loadSlot(editSlot);
  status = "editing slot " + (editSlot + 1);
  redraw();
}

// Step the active tileset within the current (shape, k); wraps.
void browseTileset(int dir) {
  int count = currentTilesets().size();
  if (count == 0) { status = "no tilesets for " + SHAPE_KEYS[shapeMode] + " k=" + anchorsK + " (click 'New set')"; redraw(); return; }
  tsIndex = (tsIndex + dir + count) % count;
  editSlot = 0;
  loadSlot(editSlot);
  status = "tileset " + (tsIndex + 1) + " / " + count;
  redraw();
}

// ---- catalog I/O (v2 tilesets) ---------------------------------
String tilesPath() {
  return new File(new File(sketchPath("")).getParentFile(), "tiles.json").getAbsolutePath();
}
String tilesBackupPath() {
  return new File(new File(sketchPath("")).getParentFile(), "tiles.v1.backup.json").getAbsolutePath();
}

// Load the shared catalog. v2 -> use it. Old (v1) flat file -> back it up and start
// fresh with an empty v2 (matches the visualizer's "start fresh" policy; the
// visualizer reseeds the default tilesets, the editor leaves it empty until you save).
void loadCatalog() {
  JSONObject loaded = new File(tilesPath()).exists() ? loadJSONObject(tilesPath()) : null;
  if (loaded != null && loaded.getInt("version", 1) >= 2 && loaded.hasKey("tilesets")) {
    catalog = loaded;
  } else {
    if (loaded != null) {                            // old flat format -> back up
      saveJSONObject(loaded, tilesBackupPath());
      println("backed up old tiles.json -> " + tilesBackupPath());
    }
    catalog = new JSONObject();
    catalog.setInt("version", 2);
    catalog.setJSONArray("tilesets", new JSONArray());
  }
}

JSONArray tilesetsArr() {
  if (!catalog.hasKey("tilesets")) catalog.setJSONArray("tilesets", new JSONArray());
  return catalog.getJSONArray("tilesets");
}

// Raw indices of the tilesets matching the current (shape, k).
ArrayList<Integer> currentTilesets() {
  ArrayList<Integer> out = new ArrayList<Integer>();
  JSONArray sets = tilesetsArr();
  for (int i = 0; i < sets.size(); i++) {
    JSONObject ts = sets.getJSONObject(i);
    if (ts.getInt("sides", 4) == n && max(1, ts.getInt("anchors", 1)) == anchorsK) out.add(i);
  }
  return out;
}

// The active tileset JSON object for the current (shape, k), or null if none.
JSONObject currentTileset() {
  ArrayList<Integer> list = currentTilesets();
  if (list.isEmpty()) return null;
  return tilesetsArr().getJSONObject(list.get(constrain(tsIndex, 0, list.size() - 1)));
}

void clampTsIndex() {
  int c = currentTilesets().size();
  tsIndex = (c == 0) ? 0 : constrain(tsIndex, 0, c - 1);
}

// Load a slot's connections + weight into the work buffer (or clear it if blank / no tileset).
void loadSlot(int slot) {
  conns.clear();
  pendingPort = -1;
  weight = 3.0;
  JSONObject ts = currentTileset();
  if (ts == null) return;
  JSONArray tiles = ts.getJSONArray("tiles");
  if (slot < 0 || slot >= tiles.size()) return;
  JSONObject tile = tiles.getJSONObject(slot);
  JSONArray a = tile.getJSONArray("conns");
  if (a != null) for (int i = 0; i < a.size(); i++) {
    JSONArray jc = a.getJSONArray(i);
    int[] c = new int[jc.size()];
    for (int t = 0; t < jc.size(); t++) c[t] = jc.getInt(t);
    conns.add(c);
  }
  weight = tile.getFloat("weight", 0);
}

// The current work buffer -> a {conns, weight} tile object.
JSONObject tileJsonFromBuffer() {
  JSONObject m = new JSONObject();
  JSONArray a = new JSONArray();
  for (int i = 0; i < conns.size(); i++) {
    int[] c = conns.get(i);
    JSONArray jc = new JSONArray();
    for (int t = 0; t < c.length; t++) jc.setInt(t, c[t]);
    a.setJSONArray(i, jc);
  }
  m.setJSONArray("conns", a);
  m.setFloat("weight", weight);
  return m;
}

JSONObject blankTileJson() {
  JSONObject m = new JSONObject();
  m.setJSONArray("conns", new JSONArray());
  m.setFloat("weight", 0);
  return m;
}

// A fresh 16-slot tileset for the current (shape, k), all slots blank.
JSONObject newTilesetJson() {
  JSONObject ts = new JSONObject();
  ts.setString("shape", SHAPE_KEYS[shapeMode]);
  ts.setInt("sides", n);
  ts.setInt("anchors", anchorsK);
  JSONArray tiles = new JSONArray();
  for (int i = 0; i < TILESET_SIZE; i++) tiles.setJSONObject(i, blankTileJson());
  ts.setJSONArray("tiles", tiles);
  return ts;
}

// Create a new tileset for the current (shape, k) and make it active.
void newTileset() {
  JSONArray sets = tilesetsArr();
  sets.setJSONObject(sets.size(), newTilesetJson());
  saveJSONObject(catalog, tilesPath());
  tsIndex = currentTilesets().size() - 1;
  editSlot = 0;
  loadSlot(editSlot);
  status = "new tileset " + (tsIndex + 1) + " (" + SHAPE_KEYS[shapeMode] + " k=" + anchorsK + ")";
  redraw();
}

// Ensure a current tileset exists (headless save helper).
void ensureTileset() { if (currentTileset() == null) newTileset(); }

void deleteTileset() {
  ArrayList<Integer> list = currentTilesets();
  if (list.isEmpty()) { status = "no tileset to delete"; redraw(); return; }
  tilesetsArr().remove(list.get(constrain(tsIndex, 0, list.size() - 1)));
  saveJSONObject(catalog, tilesPath());
  clampTsIndex();
  editSlot = 0;
  loadSlot(editSlot);
  status = "deleted tileset";
  redraw();
}

// Write the work buffer (conns + weight) into the active tileset's current slot.
void saveEntry() {
  JSONObject ts = currentTileset();
  if (ts == null) { status = "no tileset — click 'New set' first"; redraw(); return; }
  ts.getJSONArray("tiles").setJSONObject(editSlot, tileJsonFromBuffer());
  saveJSONObject(catalog, tilesPath());
  status = "saved slot " + (editSlot + 1) + " of set " + (tsIndex + 1)
           + " — in the visualizer set anchors=" + anchorsK + " & Reload tiles.json";
  redraw();
}

// Blank the active tileset's current slot.
void clearSlot() {
  JSONObject ts = currentTileset();
  if (ts == null) { status = "no tileset"; redraw(); return; }
  ts.getJSONArray("tiles").setJSONObject(editSlot, blankTileJson());
  saveJSONObject(catalog, tilesPath());
  conns.clear(); pendingPort = -1; weight = 3.0;
  status = "cleared slot " + (editSlot + 1);
  redraw();
}

// ---- geometry (duplicated from Shapes.pde lineIntersect) -------
float[] lineIntersect(float x1, float y1, float x2, float y2,
                      float x3, float y3, float x4, float y4) {
  float den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
  if (abs(den) < 1e-6) return null;
  float pre = x1 * y2 - y1 * x2, post = x3 * y4 - y3 * x4;
  float px = (pre * (x3 - x4) - (x1 - x2) * post) / den;
  float py = (pre * (y3 - y4) - (y1 - y2) * post) / den;
  return new float[]{ px, py };
}

// ---- a minimal button ------------------------------------------
class Button {
  String label; int x, y, w, h;
  Button(String label, int x, int y, int w, int h) { this.label = label; this.x = x; this.y = y; this.w = w; this.h = h; }
  boolean hit(int mx, int my) { return mx >= x && mx <= x + w && my >= y && my <= y + h; }
  void draw(boolean on) {
    fill(on ? color(70, 110, 160) : color(60));
    stroke(110); strokeWeight(1);
    rect(x, y, w, h, 5);
    noStroke();
    fill(on ? 255 : 225); textAlign(CENTER, CENTER); textSize(13);
    text(label, x + w / 2, y + h / 2);
    textAlign(LEFT, BASELINE);
  }
}
