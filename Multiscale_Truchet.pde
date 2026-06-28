// ============================================================
//  Multi-Scale Truchet Patterns
//  After Christopher Carlson's "Multi-Scale Truchet Patterns"
//  https://christophercarlson.com/portfolio/multi-scale-truchet-patterns/
//
//  Tile representation follows Oliver Steele's "Generalized Truchet
//  Tiles" (https://observablehq.com/@osteele/truchet-tile-generation):
//  a tile is a list of edge-pairs {i,j} meaning "connect the midpoint
//  of edge i to the midpoint of edge j". Adjacent edges -> a corner
//  arc; opposite edges -> a straight band. The "two points per side at
//  thirds / four arcs" generalization is Kerry Mitchell's "Generalizations
//  of Truchet Tiles" (Bridges 2020) -- see Literature/bridges2020-191.pdf.
//
//  THE CORE IDEA
//  -------------
//  Every tile is drawn in a unit square. Wherever a band crosses an
//  edge, the band occupies the central third (width = s/3), so its
//  black/white boundary meets that edge at the 1/3 and 2/3 points and
//  its centre at the edge midpoint.
//
//  WINGED TILES (Carlson's connection mechanism)
//  ---------------------------------------------
//  Connection is made structural -- independent of which motif each
//  neighbour picks -- by decorating every tile with "wings" (Steele's
//  winged rendering of Carlson's tiles):
//    * a BACKGROUND disc at each corner    (radius s/3), and
//    * a FOREGROUND disc at each edge midpoint (radius s/6),
//  drawn UNCLIPPED so they spill past the tile boundary into neighbours.
//  The fg disc guarantees a connection nub at the centre of every edge
//  even when no band reaches it; the bg disc keeps corners clean.
//
//  This is what makes scales meet: the midpoint of a coarse tile's edge
//  is exactly the shared corner of the two half-size tiles along it, so
//  the coarse fg edge-disc and the fine corner/edge discs land on the
//  same point. Tiles are drawn COARSE-FIRST so finer tiles (and their
//  wings) sit on top -- Carlson's "smaller tiles on top of larger".
//  Colours still invert per scale level for contrast.
//
//  Colours come from the active palette (see Palettes.pde). Five schemes:
//  duotone (palette's lightest/darkest, inverted per scale level); multi
//  (constant light ground, a different palette colour per scale level);
//  gradient (one random solid colour as ground; bands sample a random-direction
//  gradient of the other colours, one flat colour per tile); gradient-bg (a
//  smooth gradient of the other colours fills the canvas, with the one solid
//  colour as the ribbons); and gradient-smooth (the solid ground of gradient,
//  but the ribbons are painted with the smooth gradient continuously, not per
//  tile -- via a Java2D LinearGradientPaint; see Shapes.pde drawTileBands).
//
//  Shapes (see Shapes.pde): square (multi-scale quadtree), triangle
//  (multi-scale rep-tile), hexagon (multi-scale -- a hexagon is not a rep-tile,
//  so it subdivides into 6 equilateral triangles that then recurse), and
//  trapezoid (half-hexagon, rep-4 subdivision; long edge carries two ports).
//  Keys 4/3/6/t.
//
//  Controls:  SPACE = new pattern  |  4/3/6/t = square/triangle/hexagon/trapezoid
//             P/p = prev/next palette  |  R = rotate palette (duotone: 2 random
//             palette colours for fg/bg)  |  C = colour
//             scheme  |  M = symmetry (pixel mirror / rot 180 / tile mirror)
//             g = grid overlay  |  S = save PNG
// ============================================================

// Edges, clockwise:  0 = N (top), 1 = E (right), 2 = S (bottom), 3 = W (left)

// ---- parameters -------------------------------------------------
int     gridN         = 9;      // top-level cells per side
int     maxDepth      = 3;      // max recursive subdivisions
float   subdivideProb = 0.2;    // chance a cell splits into 4
int     seedVal       = 1;
boolean winged        = true;   // Carlson wings (structural connections)
boolean invertPerLevel= true;   // (duotone scheme) flip colours each scale level
boolean dropShadow    = false;  // bands + wing nubs cast a drop shadow
float   shadowAngle   = QUARTER_PI;  // direction the shadow falls (radians, screen coords)
float   shadowSize    = 0.4;    // shadow offset as a fraction of the band stroke width (side/3)
float   shadowStrength= 0.3;    // shadow darkness: 0 = invisible, 1 = black
boolean shadowGlobal  = false;  // false = per-level mask (finer bg occludes coarser shadow);
                                // true = one full-scene mask (coarse tiles cast across finer)
int     colorScheme   = 0;      // 0 = duotone, 1 = multi, 2 = gradient (see schemeName)
// Duotone (scheme 0) colours. By default the palette's luminance extremes
// (lightest = bg, darkest = fg). The palette "rotate" action instead picks two
// random palette colours, stored as indices (duoRandom = true); selecting another
// palette resets it. Indices (not colours) so the choice survives reproduce.
boolean duoRandom     = false;
int     duoBgIdx, duoFgIdx;
// Own RNG for the duotone rotate: Processing's random() is reseeded to seedVal
// every draw() (see the dirtyGradient block), so reusing it would pick the SAME
// pair on every press. This free-running stream advances each press instead.
java.util.Random duoRng;
int     symmetryMode  = 0;      // 0 = none, 1-3 = pixel mirrors (V/H/both), 4 = rot 180 (tile), 5-7 = tile mirrors (V/H/quad)
String[] SYMMETRY_NAMES = { "none", "vertical", "horizontal", "quad", "rot 180", "tile mir V", "tile mir H", "tile mir quad" };
boolean showGrid      = false;  // overlay the base (root) tile lattice on top of the render

// Line mode (parallel/concentric strokes): instead of one solid stroke of width
// side/3, each band is rendered as a bundle of thin lines at constant PERPENDICULAR
// offset from the centre-line (so straight bands -> parallel lines, arcs ->
// concentric arcs). Because Truchet centre-lines cross every edge perpendicular to
// it and meet C1 at the shared edge midpoint, equal-offset lines of abutting tiles
// land on the exact same points along the edge -> the line bundles flow across
// tiles (at one scale; cross-scale joins are bridged by the wing-nub rings). Pitch
// is a constant pixel spacing (derived from the depth-0 band so it's resolution-
// independent and scale-consistent); finer bands simply hold fewer lines.
boolean lineMode      = false;  // master toggle (off => byte-identical to solid bands)
int     lineCount     = 6;      // number of lines across a depth-0 band (sets the global pitch)
float   lineDuty      = 0.45;   // ink fraction of the pitch (line stroke weight = pitch * duty)
float   lineSubdivProb = 1.0;   // P(a stroke is subdivided into the line bundle) vs drawn full-thickness; 1 = all lines
float   bandWidth0    = 0;      // depth-0 band width (side/3 of a root tile); set in rebuildLeaves

// Kumiko (組子) lattice style: render bands as thin uniform mitered strips with no
// wing discs (the woodwork-lattice look), instead of thick side/3 Truchet bands.
// Pairs with the vertex (corner) connection ports the tile editor now exposes, so
// motifs like asanoha (corner -> opposite edge midpoint medians) read correctly.
// Render-only (no layout rebuild); off => byte-identical to the classic bands.
boolean kumikoStyle   = false;
float   stripWidthFrac = 0.10;  // strip width as a fraction of the tile side

// 3D extrusion (graffiti block depth): the foreground ribbons get solid sides
// extruded toward a vanishing point, viewed head-on. See draw()/drawExtrudeLevel.
boolean extrude3D     = false;  // master toggle
int     extrudeMode   = 0;      // 0 = oblique (parallel block), 1 = 1-point (converge to VP)
String[] EXTRUDE_NAMES = { "oblique", "1-point" };
float   vpX           = 0.5;    // vanishing point, normalised canvas coords (may be off-canvas)
float   vpY           = -0.2;   // default just above the top edge
float   extrudeDepth  = 0.5;    // depth as a fraction of each level's tile side
float   extrudeShade  = 0.55;   // side-wall darkness: 0 = ribbon colour, 1 = black

// Image mode (Truchet halftone): render an image as a mosaic of multi-scale
// Truchet patches chosen by brightness. See ImageMode.pde.
boolean imageMode     = false;  // master toggle (TRUCHET_IMG / Controls)
String  imagePath     = null;   // source image file
PImage  sourceImg     = null;   // loaded source (lazy, in drawImageMode)
int     imgCols       = 48;     // mosaic columns (rows derived from aspect); = gridN in image mode
int     libSize       = 256;    // number of candidate patches measured for the brightness library
float   imgGamma      = 1.0;    // gamma applied to sampled cell brightness (>1 darkens midtones)
boolean imgStretch    = true;   // map image brightness across the library's full achievable range
boolean imgInvert     = false;  // invert the brightness->patch mapping (dark image -> bright patch)
boolean imgContain    = true;   // true = fit whole image (pad with bright bg); false = cover/crop
boolean imgDirty      = true;   // rebuild the library + mosaic when image/params change
int[]   libSeed;                // per-patch RNG seed
float[] libSubdiv;              // per-patch subdivide probability (sweeps density -> brightness range)
float[] libBright;             // per-patch measured mean luminance (0..255), parallel to libSeed

// gradient scheme state (recomputed per draw; see setupGradient)
color   gradSolid;              // the one solid colour (tile background)
color[] gradStops;              // the other colours, forming the band gradient
float   gradCos, gradSin, gradMin, gradSpan;   // gradient axis + projection range (linear)
java.awt.Paint gradPaint;       // Java2D paint matching the gradient (smooth schemes)

// Radial transient: instead of the default unidirectional LINEAR gradient (project
// onto an axis), measure distance from a centre point so colour radiates outward in
// rings. Applies to the whole gradient family (schemes 2-6, including the animated
// wheel -> expanding/contracting rings). gradCx/gradCy are the centre in normalised
// canvas coords (0..1), adjustable live. The gradient parameter t in [0,1] is the
// shared seam between gradientColor() (per-point) and the Java2D paints.
boolean gradRadial = false;     // false = linear (default), true = radial
float   gradCx = 0.5, gradCy = 0.5;   // radial centre (normalised canvas coords)
// Radius so t spans 0 (centre) .. 1 (furthest canvas corner), covering the canvas.
float gradRadius() {
  float cx = gradCx * width, cy = gradCy * height, r = 1;
  float[] xs = { 0, width, 0, width }, ys = { 0, 0, height, height };
  for (int i = 0; i < 4; i++) r = max(r, dist(cx, cy, xs[i], ys[i]));
  return r;
}
// The gradient parameter t at a point: radial distance (normalised) or linear axis
// projection. Both gradientColor() and wheelColorAt() build their t from this, so a
// point's colour and the Java2D paint stay consistent.
float gradParam(float x, float y) {
  if (gradRadial) return dist(x, y, gradCx * width, gradCy * height) / gradRadius();
  return (x * gradCos + y * gradSin - gradMin) / gradSpan;
}

// gradient-wheel scheme (5): the WHOLE palette arranged as a cyclic 360 deg wheel
// (last stop wraps to the first, no seam), whose phase animates so the background
// gradient continuously transitions through the palette. wheelRate is the
// controllable rate (wheel turns per second); wheelPhase is the live 0..1 offset.
float   wheelRate  = 0.15;      // wheel rotations per second (Controls "wheel rate")
float   wheelPhase = 0;         // current animated phase in [0,1)
boolean headlessWheel = false;  // TRUCHET_WHEEL_PHASE pins the phase (no advance)
Color[] wheelCols;              // cyclic stop colours (c0..c(n-1), c0) for the Java2D paint
float[] wheelFr;                // matching even fractions [0 .. 1]
java.awt.Paint wheelFgPaint;    // per-frame foreground wheel paint (schemes 5/6); see fgPaint()
// Cached cyclic colour LUT for the radial wheel (RadialWheelPaint). Built once per
// setupGradient (depends only on the palette), NOT per draw primitive -- Java2D calls
// Paint.createContext once per fill/stroke, and the foreground draws thousands of them
// (each tile's bands + every wing nub/disc), so rebuilding the LUT each time was the
// real cost. Phase is applied as a continuous index offset, so one LUT serves every
// phase + both bg/fg. Power-of-two size -> the per-pixel index uses a mask.
final int WHEEL_LUT_N = 2048;
int[] wheelLUT;

// Schemes whose BACKGROUND is the smooth gradient (ribbons solid, bg polygon
// skipped, wing corner discs sample the gradient): gradient-bg (3) + the animated
// gradient-wheel (5). Schemes 4 + 6 paint the RIBBONS with the gradient instead.
boolean schemeBgGradient() { return colorScheme == 3 || colorScheme == 5; }
// Schemes whose FOREGROUND ribbons are painted with the animated cyclic wheel:
// gradient-wheel (5, ribbons ride a half-turn ahead of the bg wheel) + the
// fg-only gradient-wheel-fg (6, solid bg). Both share the per-frame wheelFgPaint.
boolean schemeWheelFg() { return colorScheme == 5 || colorScheme == 6; }

PaletteManager palettes;        // colour source (see Palettes.pde), set in setup()
ControlWindow  controls;        // unified GUI window (params + tile pane; see ControlWindow.pde), set in setup()
boolean saveRequested = false;  // set by the control window's Save button, handled in draw()
boolean reloadCatalogRequested = false;  // set by the Tiles panel's Reload button; re-reads tiles.json in draw()
String  autosavePath  = null;   // TRUCHET_OUT env var: render once to this file, then exit
String  panelOutPath  = null;   // TRUCHET_PANEL_OUT: dump the control panel's first frame, then exit
int     panelTab      = -1;     // TRUCHET_PANEL_TAB: open the panel on this tab (verification only)
boolean manifestLoaded = false; // a render manifest (TRUCHET_LOAD / Load render button) set the state
boolean controlsNeedSync = false; // ask ControlWindow to refresh its widgets from the globals

// ---- debug logging (TRUCHET_DEBUG / 'd' key) --------------------
// A thread-tagged action+phase log for tracing the intermittent NullPointerException.
// The three windows (viz, Controls, Tiles) each run their own thread and mutate the
// shared globals, so logging the THREAD + last action + render phase is what pins a
// cross-thread race. All fields are volatile: written/read across those threads.
volatile boolean debugLog = false;    // gate; near-zero cost when off (dbg early-returns)
long    debugStartMs = 0;             // millis() at startup, for relative timestamps
java.io.PrintWriter debugFile = null; // persistent sink (logs/debug-*.log), opened lazily
volatile String lastAction  = "(none)"; // last user action (set by logAction)
volatile String renderPhase = "(idle)"; // how far the current draw() got (cheap breadcrumb)

// Layout caching: the tile list + gradient are deterministic from seed/params, so
// they're rebuilt only when one of those changes (set dirty by the mutators) --
// not every animated frame. (Animation engine lives in Animation.pde.)
boolean dirtyLayout   = true;
boolean dirtyGradient = true;

// ---- tile alphabet ----------------------------------------------
// The n=4 instance of Steele's sideConnectionSets: every non-crossing
// way to pair the four edges (gaps/unpaired edges allowed). Each base
// tile gets a random quarter-turn when placed.
//   conns: list of {i,j} edge pairs.  TILE_W: relative weights.
// Edges: 0 = N (top), 1 = E (right), 2 = S (bottom), 3 = W (left).
//
// Two connections are NOT plain edge pairs (the 4-edge matching alphabet is
// otherwise complete -- the 5 entries above exhaust it). They are tagged by a
// type code in the FIRST slot (>= CONN_TAG, outside any edge index) and dispatched
// in TileGeom.appendBandsOffset (see Shapes.pde):
//   { CONN_HUB,  e0, e1, e2, ... } -- a junction: straight spokes from the tile
//       centre to each listed edge midpoint (a 3-spoke hub = a T/Y; 2 = a band,
//       4 = the CrossCross +). Spokes enter each edge perpendicular at the central
//       third, so it stays seamless and multi-scale-safe.
//   { CONN_HUMP, i, j }            -- an opposite-edge connection drawn as a hump/
//       arch (raised cosine) instead of a straight band: enters i and j horizontal
//       (perpendicular) at the central third, bulges toward the perpendicular side.
final int CONN_TAG    = 100;   // first-slot values >= this are tagged primitives
final int CONN_HUMP   = 100;   // { CONN_HUMP, i, j }       opposite-edge arch
final int CONN_HUB    = 101;   // { CONN_HUB, e0, e1, ... } centre-spoke junction
final int CONN_CIRCLE = 102;   // { CONN_CIRCLE, port }     a ring centred at the port
final int CONN_DOT     = 103;  // { CONN_DOT, port }        a solid disc (band width) at the port
// Circuit-inspired motifs. INLINE COMPONENTS join two ports like a wire with a
// component in the middle (straight leads + a motif); they are decorative (no
// thirds-invariant guarantee, like adjacent-edge straight bands). POINT GLYPHS
// stamp a single port and auto-orient toward the tile centre. All are stroked
// polylines (or a ring), so they flow through every render pass via
// appendMotifConn -- solid, drop shadow, 3D extrude, and line-mode offset.
final int CONN_RES    = 104;   // { CONN_RES, a, b }    resistor (zigzag) between two ports
final int CONN_IND    = 105;   // { CONN_IND, a, b }    inductor (coils) between two ports
final int CONN_CAP    = 106;   // { CONN_CAP, a, b }    capacitor (gap + plates) between two ports
final int CONN_STEP   = 107;   // { CONN_STEP, a, b }   stepped (square wave) between two ports
final int CONN_GROUND = 108;   // { CONN_GROUND, port } ground glyph (stem + 3 bars) at a port
final int CONN_ARROW  = 109;   // { CONN_ARROW, port }  inward arrowhead glyph at a port
final int CONN_TERM   = 110;   // { CONN_TERM, port }   open-circle terminal glyph at a port
final int CONN_CROSS  = 111;   // { CONN_CROSS, port }  plus/cross glyph at a port
// True for the inline two-port components (decorative wire+component motifs).
boolean isInlineComp(int code) { return code == CONN_RES || code == CONN_IND || code == CONN_CAP || code == CONN_STEP; }
// True for the single-port glyphs that auto-orient toward the tile centre.
boolean isPointGlyph(int code) { return code == CONN_GROUND || code == CONN_ARROW || code == CONN_TERM || code == CONN_CROSS; }
int[][][] TILE_CONNS = {
  {                      },          // blank (solid)
  { {0, 1}               },          // single corner arc (N-E)
  { {0, 2}               },          // single straight band (N-S)
  { {0, 1}, {2, 3}       },          // two diagonal arcs  (N-E + S-W)
  { {0, 2}, {1, 3}       },          // two crossing bands (N-S + E-W)
  { {CONN_HUB, 0, 2, 1}  },          // T / Y junction (N-S bar + E spoke)
  { {CONN_HUMP, 3, 1}    },          // arch / hump (W-E, bulging toward N)
};
float[] TILE_W = { 0.4, 1.0, 1.0, 6.0, 2.0, 1.5, 1.5 };

// ---- shared tile catalog: named 16-tile TILESETS (tiles.json) ---
// A TILESET is exactly TILESET_SIZE (16) tile slots that share one shape (n sides)
// and one anchors-per-side (k). Blank slots are an empty conns[] with weight 0. The
// catalog (tiles.json) holds any number of tilesets; per (shape, k) there may be
// several, and the user selects which one is active (Tiles panel / TRUCHET_TILESET).
//
// The hardcoded square alphabet above (TILE_CONNS/TILE_W) and TRI_*/HEX_* in
// Shapes.pde are the built-in DEFAULTS, used only to SEED a fresh tiles.json (one
// k = 1 tileset per shape). At runtime, rendering routes through the active tileset
// via connsFor()/weightsFor(); the standalone editor (TileEditor/TileEditor.pde)
// authors tilesets into the same file. If tiles.json is missing it is seeded; if it
// is an old (v1) flat catalog it is backed up and replaced with a fresh v2 seed.
// The trapezoid (port-based, bespoke arc specs) is intentionally NOT catalogued.
//
// A connection inside a tile is a JSON array of ints: a plain {i,j} edge/port pair,
// OR a tagged primitive {CONN_HUB,...}/{CONN_HUMP,i,j}/{CONN_CIRCLE,p}/{CONN_DOT,p}
// -- any length is preserved. k must be uniform across a tiling to connect, so it is
// a global render parameter (anchorsPerSide), not per-tile.
String tilesJsonPath()   { return sketchPath("tiles.json"); }
String tilesBackupPath() { return sketchPath("tiles.v1.backup.json"); }

final int TILESET_SIZE = 16;                         // a tileset is exactly 16 slots (4x4)
int anchorsPerSide = 1;                              // global k; TRUCHET_ANCHORS / Controls

// One tileset: 16 slots (conns + weight) for one (sides n, anchors k).
class Tileset {
  int sides, anchors;
  int[][][] conns;                                   // length TILESET_SIZE; conns[i] = motif i
  float[]   weights;                                 // length TILESET_SIZE
  Tileset(int sides, int anchors) {
    this.sides = sides; this.anchors = anchors;
    conns   = new int[TILESET_SIZE][][];
    weights = new float[TILESET_SIZE];
    for (int i = 0; i < TILESET_SIZE; i++) { conns[i] = new int[0][]; weights[i] = 0; }
  }
}

HashMap<String,ArrayList<Tileset>> tilesetsByNK   = new HashMap<String,ArrayList<Tileset>>(); // key "n_k"
HashMap<String,Integer>            activeTilesetIdx = new HashMap<String,Integer>();           // key "n_k" -> active index
final int[][][] BLANK_CONNS = { { } };               // fallback when no tileset exists for (n,k) yet
final float[]   BLANK_W     = { 1 };

String nkKey(int n, int k) { return n + "_" + k; }
int curN() { return shapeMode == 1 ? 3 : (shapeMode == 2 ? 6 : 4); }  // current shape's polygon n (trapezoid -> 4)
boolean shapeUsesTilesets() { return shapeMode != 3; }                // trapezoid is bespoke (TRAP_*)

ArrayList<Tileset> tilesetsFor(int n, int k) { return tilesetsByNK.get(nkKey(n, k)); }
int activeIdxFor(int n, int k) { Integer v = activeTilesetIdx.get(nkKey(n, k)); return v == null ? 0 : v; }

// The active tileset for shape n at the current k, or null if that (n,k) has none.
Tileset activeTilesetFor(int n) {
  ArrayList<Tileset> list = tilesetsFor(n, anchorsPerSide);
  if (list == null || list.isEmpty()) return null;
  return list.get(constrain(activeIdxFor(n, anchorsPerSide), 0, list.size() - 1));
}

// Tileset count / 1-based active ordinal for the CURRENT (shape, k) -- drives the Tiles-panel label.
int tilesetCount() {
  if (!shapeUsesTilesets()) return 0;
  ArrayList<Tileset> list = tilesetsFor(curN(), anchorsPerSide);
  return list == null ? 0 : list.size();
}
int activeTilesetOrdinal() {
  int c = tilesetCount();
  return c == 0 ? 0 : constrain(activeIdxFor(curN(), anchorsPerSide), 0, c - 1) + 1;
}
// Step the active tileset for the current (shape, k); wraps. Sets dirtyLayout.
void setActiveTileset(int dir) {
  int c = tilesetCount();
  if (c == 0) return;
  String key = nkKey(curN(), anchorsPerSide);
  int idx = (activeIdxFor(curN(), anchorsPerSide) + dir + c) % c;
  activeTilesetIdx.put(key, idx);
  logAction("TILESET active -> " + (idx + 1) + "/" + c);
  dirtyLayout = true;
}

// Load the shared tiles.json. Missing -> seed a fresh v2 default. Old (v1) flat
// catalog -> back it up and replace with a fresh seed (start fresh, do not migrate).
// Always applyCatalog() so the runtime tilesetsByNK map is populated.
void loadTileCatalog() {
  File f = new File(tilesJsonPath());
  if (!f.exists()) {                                 // seed the shared file from built-in defaults
    JSONObject fresh = defaultCatalogJson();
    saveJSONObject(fresh, tilesJsonPath());
    applyCatalog(fresh);
    return;
  }
  JSONObject cat = loadJSONObject(tilesJsonPath());
  if (cat == null) { applyCatalog(defaultCatalogJson()); return; }   // unreadable -> in-memory default
  if (cat.getInt("version", 1) < 2 || !cat.hasKey("tilesets")) {     // old flat format -> back up + reseed
    saveJSONObject(cat, tilesBackupPath());
    println("backed up old tiles.json -> " + tilesBackupPath());
    JSONObject fresh = defaultCatalogJson();
    saveJSONObject(fresh, tilesJsonPath());
    applyCatalog(fresh);
    return;
  }
  applyCatalog(cat);
}

// Overwrite the in-memory tilesets from a catalog object (v2 tiles.json schema).
// Used by loadTileCatalog() (the shared file) and loadManifest() (the catalog
// embedded in a render manifest). A v1 (flat) catalog is converted on the fly so
// old manifests still reproduce. connsFor()/weightsFor() and the Tiles panel read
// the tilesets by reference, so the change propagates everywhere.
void applyCatalog(JSONObject cat) {
  tilesetsByNK.clear();
  JSONObject v2 = cat.hasKey("tilesets") ? cat : v1ToV2(cat);
  JSONArray sets = v2.getJSONArray("tilesets");
  for (int i = 0; i < sets.size(); i++) {
    Tileset ts = jsonToTileset(sets.getJSONObject(i));
    String key = nkKey(ts.sides, ts.anchors);
    if (!tilesetsByNK.containsKey(key)) tilesetsByNK.put(key, new ArrayList<Tileset>());
    tilesetsByNK.get(key).add(ts);
  }
  if (cat.hasKey("trapezoid")) {                     // weights only; conns are hardcoded (TRAP_CONNS)
    float[] tw = jsonToWeights(cat.getJSONArray("trapezoid"));
    if (tw.length == TRAP_W.length) TRAP_W = tw;
  }
  for (String key : tilesetsByNK.keySet()) {         // clamp any now-stale active selection
    int c = tilesetsByNK.get(key).size();
    Integer idx = activeTilesetIdx.get(key);
    if (idx != null && idx >= c) activeTilesetIdx.put(key, 0);
  }
}

// One tileset JSON object -> a Tileset (always padded/truncated to TILESET_SIZE slots).
Tileset jsonToTileset(JSONObject o) {
  int sides   = o.getInt("sides", 4);
  int anchors = max(1, o.getInt("anchors", 1));
  Tileset ts  = new Tileset(sides, anchors);
  JSONArray tiles = o.hasKey("tiles") ? o.getJSONArray("tiles") : new JSONArray();
  int n = min(TILESET_SIZE, tiles.size());
  for (int i = 0; i < n; i++) {
    JSONObject m  = tiles.getJSONObject(i);
    JSONArray  cs = m.hasKey("conns") ? m.getJSONArray("conns") : new JSONArray();
    int[][] conns = new int[cs.size()][];
    for (int c = 0; c < cs.size(); c++) {
      JSONArray pair = cs.getJSONArray(c);
      int[] arr = new int[pair.size()];
      for (int t = 0; t < pair.size(); t++) arr[t] = pair.getInt(t);
      conns[c] = arr;
    }
    ts.conns[i]   = conns;
    ts.weights[i] = m.getFloat("weight", 0);
  }
  return ts;
}

// A Tileset -> its JSON object (shape/sides/anchors + 16 {conns, weight} tiles).
JSONObject tilesetToJson(Tileset ts) {
  JSONObject o = new JSONObject();
  o.setString("shape", shapeKeyFor(ts.sides));
  o.setInt("sides",   ts.sides);
  o.setInt("anchors", ts.anchors);
  JSONArray tiles = new JSONArray();
  for (int i = 0; i < TILESET_SIZE; i++) {
    JSONObject m  = new JSONObject();
    JSONArray  cs = new JSONArray();
    int[][] conns = (i < ts.conns.length && ts.conns[i] != null) ? ts.conns[i] : new int[0][];
    for (int c = 0; c < conns.length; c++) {
      JSONArray pair = new JSONArray();
      for (int t = 0; t < conns[c].length; t++) pair.setInt(t, conns[c][t]);
      cs.setJSONArray(c, pair);
    }
    m.setJSONArray("conns", cs);
    m.setFloat("weight", i < ts.weights.length ? ts.weights[i] : 0);
    tiles.setJSONObject(i, m);
  }
  o.setJSONArray("tiles", tiles);
  return o;
}

String shapeKeyFor(int sides) { return sides == 3 ? "triangle" : (sides == 6 ? "hexagon" : "square"); }

// Fresh v2 catalog: one k = 1 tileset per shape, seeded from the built-in alphabets
// and padded to 16 slots. Other (shape, k) combos start empty (authored in the editor).
JSONObject defaultCatalogJson() {
  JSONObject cat = new JSONObject();
  cat.setInt("version", 2);
  JSONArray sets = new JSONArray();
  sets.setJSONObject(sets.size(), seedTilesetJson("square",   4, TILE_CONNS, TILE_W));
  sets.setJSONObject(sets.size(), seedTilesetJson("triangle", 3, TRI_CONNS,  TRI_W));
  sets.setJSONObject(sets.size(), seedTilesetJson("hexagon",  6, HEX_CONNS,  HEX_W));
  cat.setJSONArray("tilesets", sets);
  return cat;
}

// Build a 16-slot tileset JSON from a built-in alphabet (extra slots blank, weight 0).
JSONObject seedTilesetJson(String shape, int n, int[][][] conns, float[] w) {
  JSONObject o = new JSONObject();
  o.setString("shape", shape);
  o.setInt("sides", n);
  o.setInt("anchors", 1);
  JSONArray tiles = new JSONArray();
  for (int i = 0; i < TILESET_SIZE; i++) {
    JSONObject m  = new JSONObject();
    JSONArray  cs = new JSONArray();
    if (i < conns.length) {
      for (int c = 0; c < conns[i].length; c++) {
        JSONArray pair = new JSONArray();
        for (int t = 0; t < conns[i][c].length; t++) pair.setInt(t, conns[i][c][t]);
        cs.setJSONArray(c, pair);
      }
    }
    m.setJSONArray("conns", cs);
    m.setFloat("weight", (i < conns.length) ? (i < w.length ? w[i] : 1.0) : 0);
    tiles.setJSONObject(i, m);
  }
  o.setJSONArray("tiles", tiles);
  return o;
}

// Reflects the CURRENT in-memory state: every tileset (all shapes, all k) plus the
// trapezoid weights. Embedded in a render manifest so reproduction does not depend on
// tiles.json staying put.
JSONObject currentCatalogJson() {
  JSONObject cat = new JSONObject();
  cat.setInt("version", 2);
  JSONArray sets = new JSONArray();
  for (String key : tilesetsByNK.keySet())
    for (Tileset ts : tilesetsByNK.get(key))
      sets.setJSONObject(sets.size(), tilesetToJson(ts));
  cat.setJSONArray("tilesets", sets);
  cat.setJSONArray("trapezoid", connsToJson(TRAP_CONNS, TRAP_W, 4));
  return cat;
}

// Convert an old (v1) flat catalog -> v2 tilesets (best-effort, for old manifests).
// Each (shape, k) group is split into 16-tile tilesets, padding the last with blanks.
JSONObject v1ToV2(JSONObject v1) {
  JSONObject out = new JSONObject();
  out.setInt("version", 2);
  JSONArray sets = new JSONArray();
  addV1Shape(sets, v1, "square",   4);
  addV1Shape(sets, v1, "triangle", 3);
  addV1Shape(sets, v1, "hexagon",  6);
  out.setJSONArray("tilesets", sets);
  return out;
}
void addV1Shape(JSONArray sets, JSONObject v1, String key, int n) {
  if (!v1.hasKey(key)) return;
  JSONArray a = v1.getJSONArray(key);
  HashMap<Integer,ArrayList<JSONObject>> byK = new HashMap<Integer,ArrayList<JSONObject>>();
  for (int i = 0; i < a.size(); i++) {
    JSONObject m = a.getJSONObject(i);
    int k = max(1, m.getInt("anchors", 1));
    if (!byK.containsKey(k)) byK.put(k, new ArrayList<JSONObject>());
    byK.get(k).add(m);
  }
  for (Integer k : byK.keySet()) {
    ArrayList<JSONObject> motifs = byK.get(k);
    for (int start = 0; start < motifs.size(); start += TILESET_SIZE) {
      JSONObject ts = new JSONObject();
      ts.setString("shape", key);
      ts.setInt("sides", n);
      ts.setInt("anchors", k);
      JSONArray tiles = new JSONArray();
      for (int s = 0; s < TILESET_SIZE; s++) {
        int src = start + s;
        JSONObject tile = new JSONObject();
        if (src < motifs.size()) {
          tile.setJSONArray("conns", motifs.get(src).getJSONArray("conns"));
          tile.setFloat("weight", motifs.get(src).getFloat("weight", 1.0));
        } else {
          tile.setJSONArray("conns", new JSONArray());
          tile.setFloat("weight", 0);
        }
        tiles.setJSONObject(s, tile);
      }
      ts.setJSONArray("tiles", tiles);
      sets.setJSONObject(sets.size(), ts);
    }
  }
}

// JSON array of motifs -> the int[][][] alphabet (each conn is a variable-length int[]).
int[][][] jsonToConns(JSONArray shape) {
  int[][][] out = new int[shape.size()][][];
  for (int i = 0; i < shape.size(); i++) {
    JSONArray cs = shape.getJSONObject(i).getJSONArray("conns");
    int[][] conns = new int[cs.size()][];
    for (int k = 0; k < cs.size(); k++) {
      JSONArray c = cs.getJSONArray(k);
      int[] pair = new int[c.size()];
      for (int t = 0; t < c.size(); t++) pair[t] = c.getInt(t);
      conns[k] = pair;
    }
    out[i] = conns;
  }
  return out;
}

float[] jsonToWeights(JSONArray shape) {
  float[] w = new float[shape.size()];
  for (int i = 0; i < shape.size(); i++) w[i] = shape.getJSONObject(i).getFloat("weight", 1.0);
  return w;
}

JSONArray connsToJson(int[][][] conns, float[] w, int sides) {
  JSONArray arr = new JSONArray();
  for (int i = 0; i < conns.length; i++) {
    JSONObject m  = new JSONObject();
    JSONArray  cs = new JSONArray();
    for (int k = 0; k < conns[i].length; k++) {
      JSONArray c = new JSONArray();
      for (int t = 0; t < conns[i][k].length; t++) c.setInt(t, conns[i][k][t]);
      cs.setJSONArray(k, c);
    }
    m.setJSONArray("conns", cs);
    m.setFloat("weight", (i < w.length) ? w[i] : 1.0);
    m.setInt("sides", sides);
    m.setInt("anchors", 1);
    arr.setJSONObject(i, m);
  }
  return arr;
}

// ---- leaves (the Tile polygon is defined in Shapes.pde) --------
ArrayList<Tile> leaves;

// ---- setup / draw ----------------------------------------------
// Canvas size lives in settings() (Processing requires size()/smooth() there
// when driven by variables). Defaults to 1920x1080; the whole tiling is
// resolution-independent (every length derives from width/height), so a larger
// canvas yields the SAME composition at higher resolution -- ideal for a
// print/wallpaper export. Override for a high-res render via env vars:
//   TRUCHET_W / TRUCHET_H  -- explicit canvas pixels, or
//   TRUCHET_SCALE          -- multiply the 1920x1080 default (e.g. 2 -> 4K, 4 -> 8K).
// This also enlarges the interactive window (window == canvas in Processing), so
// for a "small window, big PNG" export use the headless path (TRUCHET_OUT), which
// opens no window at all. Big sizes cost memory: the shadow/extrude layers are
// width*height*4 bytes each (~133 MB apiece at 8K).
void settings() {
  int w = 1920, h = 1080;
  String envW = System.getenv("TRUCHET_W");
  if (envW != null) w = max(16, Integer.parseInt(envW.trim()));
  String envH = System.getenv("TRUCHET_H");
  if (envH != null) h = max(16, Integer.parseInt(envH.trim()));
  String envScale = System.getenv("TRUCHET_SCALE");
  if (envScale != null) {
    float s = max(0.05, Float.parseFloat(envScale.trim()));
    w = round(w * s); h = round(h * s);
  }
  size(w, h);
  // Antialiasing level. Defaults to 8 (byte-identical to before); TRUCHET_SMOOTH lets
  // a live animation trade AA quality for fill rate (e.g. 2/4 while animating, 8 for a
  // print/export). smooth() must live in settings() and can't change after setup.
  int sm = 8;
  String envSm = System.getenv("TRUCHET_SMOOTH");
  if (envSm != null) { try { sm = Integer.parseInt(envSm.trim()); } catch (NumberFormatException e) { } }
  if (sm <= 1) noSmooth(); else smooth(sm);
}

void setup() {
  debugStartMs = millis();           // base for relative debug timestamps
  if ("1".equals(System.getenv("TRUCHET_DEBUG"))) enableDebug(true);  // log everything from startup
  palettes = new PaletteManager();   // built-in COLOURlovers snapshot
  initAnim();                        // animation engine (LFOs, registry) — see Animation.pde
  loadTileCatalog();                 // shared tiles.json -> overwrites the square/tri/hex alphabets (seeds the file if absent)
  noLoop();

  // Headless one-shot render (for verifying changes from the command line —
  // never screenshot the window): environment variables select the output file
  // and optionally override parameters; the first fully drawn frame is saved
  // to TRUCHET_OUT and the sketch exits. Example:
  //   TRUCHET_OUT=/tmp/out.png TRUCHET_SHAPE=2 processing-java --sketch=... --run
  autosavePath = System.getenv("TRUCHET_OUT");
  // TRUCHET_PANEL_OUT: headless verification of the control panel itself -- launch the
  // panel (the viz also opens), dump its first fully-drawn frame to this path, and quit
  // (the dump + System.exit live in ControlWindow.draw()). Mirrors TILEEDITOR_OUT, since
  // the project rule is to make the sketch render its own image, never screenshot a window.
  panelOutPath = System.getenv("TRUCHET_PANEL_OUT");
  String envPanelTab = System.getenv("TRUCHET_PANEL_TAB"); // open the panel on this tab (0..6), for verification
  if (envPanelTab != null) panelTab = Integer.parseInt(envPanelTab.trim());
  // TRUCHET_LOAD: restore a full render manifest as the baseline state (the complete,
  // reproducible recipe -- globals + tile catalog + palette). Parsed first so any
  // explicit TRUCHET_* override below still wins (e.g. load a frame, bump TRUCHET_SCALE).
  String envLoad = System.getenv("TRUCHET_LOAD");
  if (envLoad != null) loadManifest(envLoad.trim());
  String envShape  = System.getenv("TRUCHET_SHAPE");   // 0 square, 1 triangle, 2 hexagon, 3 trapezoid
  if (envShape != null)  shapeMode   = constrain(Integer.parseInt(envShape.trim()), 0, 3);
  String envScheme = System.getenv("TRUCHET_SCHEME");  // 0..6, see schemeName()
  if (envScheme != null) colorScheme = constrain(Integer.parseInt(envScheme.trim()), 0, 6);
  String envWRate = System.getenv("TRUCHET_WHEEL_RATE");  // gradient-wheel turns per second
  if (envWRate != null) wheelRate = Float.parseFloat(envWRate.trim());
  String envWPh = System.getenv("TRUCHET_WHEEL_PHASE");   // pin the wheel phase 0..1 (headless, no advance)
  if (envWPh != null) { wheelPhase = Float.parseFloat(envWPh.trim()); wheelPhase -= floor(wheelPhase); headlessWheel = true; }
  String envGRad = System.getenv("TRUCHET_GRAD_RADIAL");  // 0/1: radial vs linear gradient transient
  if (envGRad != null && !envGRad.trim().equals("0")) gradRadial = true;
  String envGCx = System.getenv("TRUCHET_GRAD_CX");       // radial centre x (normalised 0..1)
  if (envGCx != null) gradCx = Float.parseFloat(envGCx.trim());
  String envGCy = System.getenv("TRUCHET_GRAD_CY");       // radial centre y (normalised 0..1)
  if (envGCy != null) gradCy = Float.parseFloat(envGCy.trim());
  // A headless render is a single frame: freeze the wheel so the saved phase (env,
  // manifest, or default 0) is exactly what renders -- so a manifest reproduces
  // byte-identically instead of advancing one step before the save.
  if (autosavePath != null) headlessWheel = true;
  String envSeed   = System.getenv("TRUCHET_SEED");
  if (envSeed != null)   seedVal     = Integer.parseInt(envSeed.trim());
  String envPal    = System.getenv("TRUCHET_PALETTE"); // palette index (wraps; see loadDefaults)
  if (envPal != null)    palettes.setCurrent(Integer.parseInt(envPal.trim()));
  String envDuo    = System.getenv("TRUCHET_DUO");     // "bgIdx,fgIdx": duotone fg/bg as two palette colours (= rotate)
  if (envDuo != null) {
    String[] ix = split(envDuo.trim(), ',');
    if (ix.length == 2) {
      duoBgIdx = Integer.parseInt(ix[0].trim());
      duoFgIdx = Integer.parseInt(ix[1].trim());
      duoRandom = true;
    }
  }
  String envSym    = System.getenv("TRUCHET_SYM");     // 0..4, see SYMMETRY_NAMES
  if (envSym != null)    symmetryMode = constrain(Integer.parseInt(envSym.trim()), 0, SYMMETRY_NAMES.length - 1);
  String envSG     = System.getenv("TRUCHET_SHOWGRID");  // 0/1: overlay the base tile grid
  if (envSG != null)     showGrid    = !envSG.trim().equals("0");
  String envShadow = System.getenv("TRUCHET_SHADOW");  // 0/1: drop shadow off/on
  if (envShadow != null) dropShadow  = !envShadow.trim().equals("0");
  String envShStr  = System.getenv("TRUCHET_SHADOW_STR");  // shadow darkness 0..1
  if (envShStr != null)  shadowStrength = constrain(Float.parseFloat(envShStr.trim()), 0, 1);
  String envShGl   = System.getenv("TRUCHET_SHADOW_GLOBAL");  // 0/1: per-level vs full-scene mask
  if (envShGl != null)   shadowGlobal = !envShGl.trim().equals("0");
  String envShSz   = System.getenv("TRUCHET_SHADOW_SIZE");  // shadow offset (fraction of stroke)
  if (envShSz != null)   shadowSize = Float.parseFloat(envShSz.trim());
  String envShAng  = System.getenv("TRUCHET_SHADOW_ANGLE"); // shadow direction (degrees)
  if (envShAng != null)  shadowAngle = radians(Float.parseFloat(envShAng.trim()));
  String envWing   = System.getenv("TRUCHET_WINGED");  // 0/1: Carlson wings (structural connections)
  if (envWing != null)   winged      = !envWing.trim().equals("0");
  String envInv    = System.getenv("TRUCHET_INVERT");  // 0/1: duotone colour inversion per level
  if (envInv != null)    invertPerLevel = !envInv.trim().equals("0");
  String envLine   = System.getenv("TRUCHET_LINE");        // 0/1: parallel-stroke (line) mode
  if (envLine != null)   lineMode    = !envLine.trim().equals("0");
  String envLineN  = System.getenv("TRUCHET_LINE_COUNT");  // lines across a depth-0 band
  if (envLineN != null)  lineCount   = constrain(Integer.parseInt(envLineN.trim()), 1, 40);
  String envLineD  = System.getenv("TRUCHET_LINE_DUTY");   // ink fraction of the pitch (0..1)
  if (envLineD != null)  lineDuty    = constrain(Float.parseFloat(envLineD.trim()), 0.05, 0.95);
  String envLineS  = System.getenv("TRUCHET_LINE_SUBDIV"); // P(stroke subdivided into lines) vs full thickness
  if (envLineS != null)  lineSubdivProb = constrain(Float.parseFloat(envLineS.trim()), 0.0, 1.0);
  String envKum    = System.getenv("TRUCHET_KUMIKO");      // 0/1: thin mitered Kumiko-lattice strips
  if (envKum != null)    kumikoStyle = !envKum.trim().equals("0");
  String envStrip  = System.getenv("TRUCHET_STRIP");       // Kumiko strip width (fraction of side)
  if (envStrip != null)  stripWidthFrac = constrain(Float.parseFloat(envStrip.trim()), 0.01, 0.33);
  String envMet    = System.getenv("TRUCHET_METAL");       // 0/1: SDF metallic shading
  if (envMet != null)    metalMode   = !envMet.trim().equals("0");
  String envMetMat = System.getenv("TRUCHET_METAL_MAT");   // material index or name
  if (envMetMat != null) metalMaterial = parseMetalMat(envMetMat.trim());
  String envMetBev = System.getenv("TRUCHET_METAL_BEVEL"); // bevel/rim width (px at 1080p)
  if (envMetBev != null) metalBevelPx = constrain(Float.parseFloat(envMetBev.trim()), 1, 60);
  String envMetSty = System.getenv("TRUCHET_METAL_STYLE"); // 0 round-bevel, 1 flat-rim
  if (envMetSty != null) metalBevelStyle = constrain(Integer.parseInt(envMetSty.trim()), 0, 1);
  String envMetLit = System.getenv("TRUCHET_METAL_LIGHT"); // light azimuth (degrees)
  if (envMetLit != null) metalLightDeg = Float.parseFloat(envMetLit.trim());
  String envGrid   = System.getenv("TRUCHET_GRID");    // top-level cells per side
  if (envGrid != null)   gridN       = constrain(Integer.parseInt(envGrid.trim()), 2, 16);
  String envDepth  = System.getenv("TRUCHET_DEPTH");   // max subdivisions (0 = single scale)
  if (envDepth != null)  maxDepth    = constrain(Integer.parseInt(envDepth.trim()), 0, 6);
  String envSub    = System.getenv("TRUCHET_SUBDIV");  // subdivide probability (0..1; 1 = uniform fine)
  if (envSub != null)    subdivideProb = constrain(Float.parseFloat(envSub.trim()), 0, 1);
  String envAnch   = System.getenv("TRUCHET_ANCHORS"); // anchor points per side (k); 1 = classic
  if (envAnch != null)   anchorsPerSide = constrain(Integer.parseInt(envAnch.trim()), 1, 4);
  String envTset   = System.getenv("TRUCHET_TILESET"); // active tileset index for the current (shape, k)
  if (envTset != null)   activeTilesetIdx.put(nkKey(curN(), anchorsPerSide), max(0, Integer.parseInt(envTset.trim())));
  String envEx     = System.getenv("TRUCHET_EXTRUDE");      // 0/1: 3D extrusion off/on
  if (envEx != null)     extrude3D   = !envEx.trim().equals("0");
  String envExMode = System.getenv("TRUCHET_EXTRUDE_MODE"); // 0 oblique, 1 one-point
  if (envExMode != null) extrudeMode = constrain(Integer.parseInt(envExMode.trim()), 0, EXTRUDE_NAMES.length - 1);
  String envVpx    = System.getenv("TRUCHET_VPX");          // vanishing point x (normalised)
  if (envVpx != null)    vpX         = Float.parseFloat(envVpx.trim());
  String envVpy    = System.getenv("TRUCHET_VPY");          // vanishing point y (normalised)
  if (envVpy != null)    vpY         = Float.parseFloat(envVpy.trim());
  String envExD    = System.getenv("TRUCHET_EXTRUDE_DEPTH"); // depth (fraction of tile side)
  if (envExD != null)    extrudeDepth = Float.parseFloat(envExD.trim());
  String envExS    = System.getenv("TRUCHET_EXTRUDE_SHADE"); // side darkness 0..1
  if (envExS != null)    extrudeShade = constrain(Float.parseFloat(envExS.trim()), 0, 1);
  // --- animation (headless verification of motion) ---
  String envARate  = System.getenv("TRUCHET_ANIM_RATE");   // master LFO rate (Hz)
  if (envARate != null)  applyAnimRate(Float.parseFloat(envARate.trim()));
  String envADep   = System.getenv("TRUCHET_ANIM_DEPTH");  // set ALL LFO depths (show motion)
  if (envADep != null) {
    float dep = constrain(Float.parseFloat(envADep.trim()), 0, 1);
    lfoBand.depth = lfoDisc.depth = lfoRot.depth = lfoSweep.depth = lfoRadius.depth = dep;
  }
  String envAT     = System.getenv("TRUCHET_ANIM_T");      // LFO-driven frame at this time (s)
  if (envAT != null) { animSeconds = Float.parseFloat(envAT.trim()); headlessAnimOverride = true; animEnabled = true; animSource = 0; }
  String envA      = System.getenv("TRUCHET_ANIM");        // fixed registry values "name=v01,..."
  if (envA != null) {                                       // deterministic, bypasses LFOs
    headlessAnimOverride = true; animSource = 1;
    for (String pair : envA.trim().split(",")) {
      String[] kv = pair.split("=");
      if (kv.length == 2) setAnimValue(kv[0].trim(), Float.parseFloat(kv[1].trim()));
    }
  }
  // --- light pulse (comet flowing along the connection paths; see Pulse.pde) ---
  String envPulse = System.getenv("TRUCHET_PULSE");        // 0/1 enable
  if (envPulse != null && !envPulse.trim().equals("0")) { pulseEnabled = true; headlessPulse = true; }
  String envPSpd = System.getenv("TRUCHET_PULSE_SPEED");   // px/sec
  if (envPSpd != null) pulseSpeed = Float.parseFloat(envPSpd.trim());
  String envPTr  = System.getenv("TRUCHET_PULSE_TRAIL");   // comet trail length (px)
  if (envPTr != null) pulseTrail = Float.parseFloat(envPTr.trim());
  String envPCnt = System.getenv("TRUCHET_PULSE_COUNT");   // 0 = all paths, else N longest
  if (envPCnt != null) pulseCount = max(0, Integer.parseInt(envPCnt.trim()));
  String envPCol = System.getenv("TRUCHET_PULSE_COLOR");   // 0 palette-bright / 1 white / 2 complementary
  if (envPCol != null) pulseColorMode = constrain(Integer.parseInt(envPCol.trim()), 0, 2);

  // --- one-shot tile morph (headless: pin a single mid-morph frame) ---
  String envMorph = System.getenv("TRUCHET_MORPH");        // 0/1 enable
  if (envMorph != null && !envMorph.trim().equals("0")) { morphActive = true; headlessMorph = true; }
  String envMDur = System.getenv("TRUCHET_MORPH_DUR");     // seconds; sets EVERY level
  if (envMDur != null) { float v = max(0.05, Float.parseFloat(envMDur.trim())); for (int i = 0; i < MAX_MORPH_LV; i++) morphDurLevel[i] = v; }
  String envMDL = System.getenv("TRUCHET_MORPH_DUR_LEVELS"); // per-level: "1.5,1.0,0.6,..." (depth 0..)
  if (envMDL != null) {
    String[] parts = split(envMDL.trim(), ',');
    for (int i = 0; i < parts.length && i < MAX_MORPH_LV; i++)
      if (parts[i].trim().length() > 0) morphDurLevel[i] = max(0.05, Float.parseFloat(parts[i].trim()));
  }
  String envMT = System.getenv("TRUCHET_MORPH_T");         // pin the morph phase 0..1
  if (envMT != null) { morphT = constrain(Float.parseFloat(envMT.trim()), 0, 1); morphActive = true; headlessMorph = true; }
  String envMGen = System.getenv("TRUCHET_MORPH_GEN");     // which target roll (default 0)
  if (envMGen != null) morphGen = Integer.parseInt(envMGen.trim());
  String envMSpr = System.getenv("TRUCHET_MORPH_SPREAD");  // 0 in-sync, >0 staggered start/finish
  if (envMSpr != null) morphSpread = constrain(Float.parseFloat(envMSpr.trim()), 0, 0.9);
  String envMEase = System.getenv("TRUCHET_MORPH_EASE");   // easing index OR name (see MORPH_EASE_NAMES)
  if (envMEase != null) morphEasing = parseMorphEase(envMEase.trim());
  String envMCap = System.getenv("TRUCHET_MORPH_CAP");     // band-cap style index OR name (see MORPH_CAP_NAMES)
  if (envMCap != null) morphCap = parseMorphCap(envMCap.trim());
  String envMMode = System.getenv("TRUCHET_MORPH_MODE");   // continuous per-tile random morphing (0/1)
  if (envMMode != null && !envMMode.trim().equals("0")) morphMode = true;
  String envMProb = System.getenv("TRUCHET_MORPH_PROB");   // expected morph starts per tile per second
  if (envMProb != null) morphProb = max(0, Float.parseFloat(envMProb.trim()));
  String envMFr = System.getenv("TRUCHET_MORPH_FRAMES");   // headless: pre-roll N morph-mode steps before saving
  if (envMFr != null) headlessMorphFrames = max(0, Integer.parseInt(envMFr.trim()));

  // --- image mode (Truchet halftone of a source image) ---
  String envImg = System.getenv("TRUCHET_IMG");          // path -> enable image mode
  if (envImg != null && envImg.trim().length() > 0) { imagePath = envImg.trim(); imageMode = true; }
  String envImgCols = System.getenv("TRUCHET_IMG_COLS"); // mosaic columns
  if (envImgCols != null) imgCols = max(1, Integer.parseInt(envImgCols.trim()));
  String envImgLib  = System.getenv("TRUCHET_IMG_LIB");  // brightness-library size
  if (envImgLib != null)  libSize = max(2, Integer.parseInt(envImgLib.trim()));
  String envImgGam  = System.getenv("TRUCHET_IMG_GAMMA");
  if (envImgGam != null)  imgGamma = max(0.01, Float.parseFloat(envImgGam.trim()));
  String envImgStr  = System.getenv("TRUCHET_IMG_STRETCH"); // 0/1: histogram-stretch to library range
  if (envImgStr != null)  imgStretch = !envImgStr.trim().equals("0");
  String envImgInv  = System.getenv("TRUCHET_IMG_INVERT");  // 0/1: invert brightness mapping
  if (envImgInv != null)  imgInvert = !envImgInv.trim().equals("0");
  String envImgFit  = System.getenv("TRUCHET_IMG_CONTAIN"); // 0 = cover/crop, 1 = contain (fit whole)
  if (envImgFit != null)  imgContain = !envImgFit.trim().equals("0");

  if (autosavePath != null) {
    saveRequested = false;             // headless writes only TRUCHET_OUT
    return;                            // no GUI windows in headless mode
  }

  // The interactive app opens with the active tileset's authored weights (selecting a
  // curated 16-tile set is the point), so there is no blank-slate reset here. Tweak the
  // mix live with the Tiles-panel sliders, or switch tilesets with its selector.

  // launch the GUIs as separate PApplet windows. Each holds a reference back
  // here, edits the globals above, and calls redraw() (the viz is noLoop()).
  controls = new ControlWindow(this);
  PApplet.runSketch(new String[]{"Controls"}, controls);
}

void draw() {
 try {
  // 0. animation: advance the clock + refresh the modulator snapshot the render
  //    reads (identity when animation is off, so a static frame is unchanged).
  phase("updateAnim");
  geomStamp++;            // invalidate the per-frame TileGeom cache (see geomFor)
  updateAnim();

  // Tiles panel "Reload" button: re-read tiles.json on the viz thread (so the
  // catalog arrays are not swapped mid-render). loadTileCatalog reassigns the
  // alphabet/weight globals in place, so connsFor/weightsFor and the panels pick
  // up the new sets by reference; rebuild the tiling to apply them.
  if (reloadCatalogRequested) {
    phase("reloadCatalog");
    loadTileCatalog();
    reloadCatalogRequested = false;
    dirtyLayout = true;
  }

  // Controls "morph" button -> start the one-shot morph on the viz thread (so the
  // leaves' target motifs aren't rolled cross-thread mid-render).
  if (morphRequested) { morphRequested = false; logAction("morph start"); startMorph(); }
  if (morphStaggerRequested) { morphStaggerRequested = false; logAction("morph start (staggered)"); startMorphStaggered(); }

  // Controls "morph mode" toggle -> apply on the viz thread (it touches leaves +
  // the loop state). Done before rebuildLeaves so engaging it can request a build.
  if (morphModeChanged) { morphModeChanged = false; logAction("morph mode -> " + morphMode); applyMorphModeChange(); }

  // gradient + layout are deterministic from seed/params -> rebuild only when a
  // mutator marked them dirty, not every animated frame.
  if (dirtyGradient) {
    phase("setupGradient");
    randomSeed(seedVal);
    setupGradient();              // pick the gradient scheme's colours (uses random)
    dirtyGradient = false;
  }
  // Defensive: clear any polygon clip a previous frame may have left set (see
  // pushPolyClip in Shapes.pde) before we clear and redraw the canvas.
  ((PGraphicsJava2D) g).g2.setClip(null);

  // Geometrically pure stroking. Java2D defaults to STROKE_NORMALIZE, which snaps
  // thin strokes to the pixel grid -- on long thin curved strokes (line mode's
  // concentric arcs) that snapping wobbles the path and reads as jagged. PURE
  // stroking keeps the curve faithful so it antialiases smoothly.
  ((PGraphicsJava2D) g).g2.setRenderingHint(
    RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);

  // IMAGE MODE (TRUCHET_IMG / Controls): render the active image as a mosaic of
  // multi-scale Truchet patches chosen by brightness. Self-contained -- it clears
  // the canvas, builds its own leaves and draws them (see ImageMode.pde) -- so it
  // replaces the normal background + build + render + symmetry block below.
  if (imageMode) {
    phase("imageMode");
    drawImageMode();
  } else {
    phase("background");
    if (schemeBgGradient()) drawGradientBackground();   // smooth gradient fills the canvas (3 + wheel 5)
    else background(canvasBgColor());

    // 1. build the leaf tiling (cached; see rebuildLeaves).
    if (dirtyLayout) { phase("rebuildLeaves"); rebuildLeaves(); dirtyLayout = false; }

    // 1b. light-pulse path graph (cached; rebuilt with the layout, or when the
    //     pulse is toggled on at runtime). See Pulse.pde.
    if (dirtyPaths) { phase("rebuildPulsePaths"); rebuildPulsePaths(); dirtyPaths = false; }

    // 1c. continuous morph mode: advance per-tile cross-dissolves + roll new
    //     triggers, on the now-built/synced leaves (before they render). Headless
    //     can pre-roll N steps (TRUCHET_MORPH_FRAMES) for a deterministic frame.
    if (morphMode) {
      phase("updateMorphMode");
      int steps = max(1, headlessMorphFrames);
      for (int i = 0; i < steps; i++) updateMorphMode();
      headlessMorphFrames = 0;     // pre-roll only once
    }

    // 2. draw the tiling coarse-first (see renderTiling).
    phase("renderTiling");
    renderTiling();

    // 2b. light-pulse overlay: comets flowing along the connection paths. Drawn
    //     BEFORE applySymmetry so the pixel mirrors reflect the pulses too.
    phase("drawPulses");
    drawPulses();

    // 3. mirror symmetry (modes 1-3): reflect the rendered pixels about
    //    grid-aligned axes. (Mode 4, rot 180, is tile-level -- see step 1.)
    phase("applySymmetry");
    applySymmetry();

    // 3b. optional: overlay the base (root) tile lattice on top of everything.
    if (showGrid) { phase("gridOverlay"); drawGridOverlay(); }
  }

  // 4. honour a save request from the control window (run here, on the
  // viz thread, so the saved frame is the fully drawn one).
  if (saveRequested) {
    phase("saveTiling");
    saveTiling();
    saveRequested = false;
  }

  // 5. headless mode (TRUCHET_OUT): save the rendered frame and quit. Also echo the
  // parameter-stamped name + reproduce command for this frame (handy for scripting
  // and for confirming the GUI's filename scheme).
  if (autosavePath != null) {
    phase("autosave");
    save(autosavePath);
    saveManifest(autosavePath);          // sidecar JSON beside the PNG (TRUCHET_LOAD reproduces it)
    println("name: " + saveBaseName());
    println("reproduce: " + reproduceCmd(saveBaseName()));
    exit();
  }
  // Authoritative loop control: keep looping while any mode animates (LFO / morph /
  // gradient-wheel), else settle to static. Placed here so a Controls-thread change
  // (e.g. selecting the wheel scheme, or moving its rate slider) lands the correct
  // loop state on the viz thread. Skipped in headless (no window / loop).
  if (autosavePath == null && panelOutPath == null) refreshLoopState();

  phase("(idle)");
 } catch (Throwable e) {
  // The primary crash catch (viz thread). Dump thread + last action + phase + state
  // + stack trace to console and the log file, then stop the loop (see dbgCrash).
  dbgCrash(e);
 }
}

// Draw the global `leaves` coarse-first so finer tiles + wings land on top. Each
// depth level renders in three passes -- all backgrounds, then ONE unioned shadow
// layer, then all foregrounds (see Shapes.pde) -- so every shadow falls across
// every same-level background yet stays beneath every same-level band, keeping a
// single consistent light direction. Whole hexagons (all depth 0) accumulate
// their bands and are stroked once, as a single antialiased shape -- no seams
// between their overlapping bands. Factored out of draw() so image mode can reuse
// it for both the calibration rounds and the final mosaic.
void renderTiling() {
  refreshWheelFgPaint();        // per-frame foreground wheel paint (schemes 5/6); else null
  hexBatch = new Path2D.Float();
  hexSolidBatch = new Path2D.Float();
  hexBatchUsed = false;
  if (metalMode) {
    // METAL: synthesise normals for the whole ink region via an SDF and shade it as
    // metal, composited over the paper canvas. Replaces the normal foreground passes
    // (it needs the whole figure at once for the distance field). See Metal.pde.
    drawMetalTiling();
    return;
  }
  if (extrude3D) {
    // 3D EXTRUSION: lay down ALL backgrounds first (so a finer tile's background
    // can never chop a coarser ribbon's wall), then the optional drop shadow on
    // that flat plane, then per level coarse-first build+composite the extruded
    // side walls and draw the top faces on top -- finer tiles' walls/tops land
    // over coarser ones (Carlson's "smaller on top"). See drawExtrudeLevel.
    for (int d = 0; d <= maxDepth; d++)
      for (Tile lf : leaves)
        if (lf.depth == d) drawTileBackground(lf, tileBg(lf));
    if (dropShadow) {
      Graphics2D sg = beginShadowLayer();
      for (Tile lf : leaves) addTileShadow(sg, lf);
      compositeShadowLayer(sg);
    }
    for (int d = 0; d <= maxDepth; d++) {
      drawExtrudeLevel(d);
      drawForegroundLevel(d);
    }
  } else if (dropShadow && shadowGlobal) {
    // GLOBAL shadow: one full-scene mask. Lay down ALL backgrounds (coarse-first),
    // composite every caster's shadow once, then ALL foregrounds. Coarse tiles
    // cast across finer regions because the mask lands after the finer backgrounds.
    for (int d = 0; d <= maxDepth; d++)
      for (Tile lf : leaves)
        if (lf.depth == d) drawTileBackground(lf, tileBg(lf));
    Graphics2D sg = beginShadowLayer();
    for (Tile lf : leaves) addTileShadow(sg, lf);
    compositeShadowLayer(sg);
    for (int d = 0; d <= maxDepth; d++) drawForegroundLevel(d);
  } else {
    // PER-LEVEL shadow (default): each depth renders bg -> shadow -> fg, so a
    // finer level's backgrounds occlude the coarser level's shadow beneath it.
    for (int d = 0; d <= maxDepth; d++) {
      for (Tile lf : leaves)
        if (lf.depth == d) drawTileBackground(lf, tileBg(lf));
      if (dropShadow) {
        Graphics2D sg = null;                       // lazy: skip empty levels
        for (Tile lf : leaves)
          if (lf.depth == d) {
            if (sg == null) sg = beginShadowLayer();
            addTileShadow(sg, lf);
          }
        if (sg != null) compositeShadowLayer(sg);
      }
      drawForegroundLevel(d);
    }
  }
}

// Draw all foreground (bands + wings) of one depth level, then flush the depth-0
// whole-hexagon batch. In line mode (except the smooth gradient-bg scheme, whose
// background must show through) bands render as OPAQUE ribbons via three
// level-wide passes:
//   1. wing rings        -- the little target/spiral circles at the ports;
//   2. opaque ribbon base (background colour, the full side/3 band) drawn OVER the
//      rings -- where a band runs through a port it hides that port's ring, so two
//      arcs joining no longer show the circle and crossing/overlapping bands cover
//      cleanly instead of letting the lines underneath show through. At a port the
//      band does NOT continue across (an unmatched / cross-scale join) the ring's
//      outer half survives -> the arc curls smoothly into the spiral;
//   3. the foreground line bundle, drawn LAST across ALL tiles so the hatching
//      stays continuous where neighbouring tiles meet.
// Solid mode and scheme 3 keep the original single per-tile path.
void drawForegroundLevel(int d) {
  if (lineMode && !schemeBgGradient()) {
    for (Tile lf : leaves) if (lf.depth == d) drawTileLineRings(lf, tileFg(lf));
    for (Tile lf : leaves) if (lf.depth == d) drawTileRibbonBase(lf, tileBg(lf));
    for (Tile lf : leaves) if (lf.depth == d) drawTileLineBundle(lf, tileFg(lf));
  } else {
    for (Tile lf : leaves) if (lf.depth == d) drawTileForeground(lf, tileFg(lf));
  }
  if (d == 0 && hexBatchUsed) strokeHexBatch();
}

// Overlay the base (root-level) tile lattice on top of the finished render -- a
// visual aid for reading the grid the tiling subdivides from. Independent of the
// drawn leaves (and of the symmetry filtering applied to them): it re-derives the
// full-canvas root tessellation from buildRoots() and strokes each tile's
// outline, so it covers the whole canvas in every symmetry mode. Drawn in a thin
// translucent line whose weight scales with the canvas so it stays ~1px at any
// export resolution. Not shown in image mode (that mosaic uses its own cell grid).
void drawGridOverlay() {
  ((PGraphicsJava2D) g).g2.setClip(null);    // clear any leftover tile clip
  pushStyle();
  noFill();
  stroke(255, 0, 80, 200);                   // contrasting pink-red, reads on light or dark
  strokeWeight(max(1.0, width / 1600.0));
  strokeJoin(MITER);
  for (Tile t : buildRoots()) {
    TileGeom gm = new TileGeom(t);            // gm.vx/vy = this root's polygon outline
    beginShape();
    for (int k = 0; k < gm.vx.length; k++) vertex(gm.vx[k], gm.vy[k]);
    endShape(CLOSE);
  }
  popStyle();
}

// Build the leaf tiling for the active shape + seed into the global `leaves`.
// Deterministic from seedVal/gridN/maxDepth/subdivideProb/shapeMode/symmetryMode,
// so it's cached across animated frames and only re-run when one of those changes.
// The tile-level symmetries are structural: rot 180 (mode 4) generates only the
// rows above the rotation centre and adds a half-turn twin per leaf; tile mirrors
// (modes 5-7) generate the fundamental domain (half or quadrant) plus the on-axis
// straddlers (mirror-aware) and add a flipped/rotated twin per leaf to fill the
// rest (see collectSym/addSymTwins).
// Constant line pitch (px) for line mode: the depth-0 band split into lineCount
// lines, applied at every scale (so the hatching reads at one density). Falls back
// to a sane default before the first layout build. lineStroke() is the per-line
// stroke weight (a fraction of the pitch, leaving paper between lines).
float linePitch()  { return (bandWidth0 > 0 ? bandWidth0 : 18) / max(1, lineCount); }
float lineStroke() { return max(0.5, linePitch() * constrain(lineDuty, 0.05, 0.95)); }
// Perpendicular offsets of the lines filling a band of width w, centred on the
// centre-line (symmetric, spaced by the global pitch). max(1,...) => >=1 line.
float[] lineOffsets(float w) {
  int nL = max(1, round(w / linePitch()));
  float[] off = new float[nL];
  for (int i = 0; i < nL; i++) off[i] = (i - (nL - 1) / 2.0) * linePitch();
  return off;
}
// Width the line-mode parallel-line bundle spreads across, centred on the band
// centre-line: the set strip width (stripWidthFrac * side), clamped to the band
// so lines never spill past the band region (and the opaque ribbon base). The
// pitch stays constant (lineCount-driven), so density reads uniform across scales
// and the wing rings stay phase-aligned -- only the spread tracks the strip width.
float lineBundleW(TileGeom gm) {
  return min(stripWidthFrac * gm.side, gm.bandW) * animBandScale;
}

void rebuildLeaves() {
  randomSeed(seedVal);             // reseed so motif rolls match the seed exactly
  // depth-0 band width (side/3 of a root tile) -> the line-mode pitch reference.
  ArrayList<Tile> roots0 = buildRoots();
  bandWidth0 = roots0.isEmpty() ? 0 : new TileGeom(roots0.get(0)).side / 3.0;
  leaves = new ArrayList<Tile>();
  // The structural (tile-level) symmetry modes 4-7 rely on grid-specific
  // rotation centres / mirror lines defined only for square/triangle/hexagon, so
  // the trapezoid ignores them (collects normally); the post-render pixel mirror
  // modes 1-3 still apply to it in applySymmetry().
  boolean rot180 = (symmetryMode == 4) && shapeMode != 3;
  boolean vMir   = (symmetryMode == 5 || symmetryMode == 7) && shapeMode != 3;
  boolean hMir   = (symmetryMode == 6 || symmetryMode == 7) && shapeMode != 3;
  float rotYc = rot180 ? rotCentreY() : 0;
  for (Tile t : roots0) {
    if (rot180 && t.cy >= rotYc) continue;     // half-turn twins fill the rest
    if (vMir || hMir) { collectSym(t, vMir, hMir); continue; }
    collectTile(t);
  }
  if (rot180)        addRotatedTwins();
  if (vMir || hMir)  addSymTwins(vMir, hMir);
  if (morphMode)          syncMorphIdle();      // continuous mode: every fresh tile starts idle
  else if (morphActive)   rollMorphTargets();   // one-shot: a mid-morph rebuild re-rolls targets
  dirtyPaths = true;     // the light-pulse path graph derives from `leaves`
}

// Recursively subdivide a tile (per its shape) or record it as a leaf.
void collectTile(Tile t) {
  if (canSubdivide(t) && random(1) < subdivideProb) {
    for (Tile c : children(t)) collectTile(c);
  } else {
    // fix the motif at collection time so a rot-180 twin can reuse it verbatim.
    // The trapezoid is not rotationally symmetric, so it carries no motif spin
    // (mk = 0) and draws from its own alphabet (TRAP_CONNS/TRAP_W).
    t.mi = pickWeighted(t.trap ? TRAP_W : weightsFor(t.n));
    t.mk = t.trap ? 0 : int(random(t.n));
    leaves.add(t);
  }
}

// ---- symmetry (mirroring) ----------------------------------------
// Post-render mirroring: reflect the drawn pattern about an axis that lies on
// a mirror line of the active grid, so the seam follows tile geometry. Pixel
// mirroring makes the join seamless by construction: at the axis the reflected
// copy equals the original, so any band crossing it continues into its mirror
// image (the 1/3-2/3 crossing points are symmetric about the axis).

// Spacing of the grid's vertical mirror lines. All three shapes share
// L = width/gridN (for hexagons, hexW == width/gridN): squares mirror on grid
// lines; triangles on vertex + edge-midpoint columns (L/2); hexagons on
// centre + shared-edge columns (hexW/2).
float symPitchX() {
  float L = (float) width / gridN;
  return shapeMode == 0 ? L : L / 2.0;
}

// Spacing of the grid's horizontal mirror lines: square grid lines; triangle
// row lines; hexagon row-centre lines (vSpacing) -- all L or L*sqrt(3)/2.
float symPitchY() {
  float L = (float) width / gridN;
  return shapeMode == 0 ? L : L * sqrt(3) / 2.0;
}

// First mirror line at or beyond the canvas centre, so the source strip
// between the axis and the near border reflects exactly onto the far border.
int symAxis(float centre, float pitch) {
  return round(ceil(centre / pitch - 1e-4) * pitch);
}

void applySymmetry() {
  if (symmetryMode == 0) return;
  if (symmetryMode == 1 || symmetryMode == 3) {       // vertical axis: left -> right
    int ax = symAxis(width / 2.0, symPitchX());
    int sw = width - ax;
    if (sw > 0 && ax - sw >= 0) {
      PImage strip = get(ax - sw, 0, sw, height);
      pushMatrix();
      translate(2 * ax, 0);                           // screen x = 2*ax - drawn x
      scale(-1, 1);
      image(strip, ax - sw, 0);
      popMatrix();
    }
  }
  if (symmetryMode == 2 || symmetryMode == 3) {       // horizontal axis: top -> bottom
    int ay = symAxis(height / 2.0, symPitchY());
    int sh = height - ay;
    if (sh > 0 && ay - sh >= 0) {
      PImage strip = get(0, ay - sh, width, sh);
      pushMatrix();
      translate(0, 2 * ay);
      scale(1, -1);
      image(strip, 0, ay - sh);
      popMatrix();
    }
  }
}

// ---- rot-180 symmetry (tile level) -------------------------------
// 180-degree rotation is structural, not pixel-copied: a half-turn of a tile
// is just rot + PI with the SAME motif (no edge relabelling -- unlike a mirror
// image, which is why the mirror modes stay pixel-based). draw() generates
// only the roots above the rotation centre; addRotatedTwins() then adds a
// half-turn twin of every leaf. Everything draws in one normal pass, so wings
// spill across the join in both directions, coarse-first layering holds, the
// drop shadow keeps a single light direction, and the gradient schemes stay
// continuous -- there is no pixel seam at all.
//
// The centre must be a 2-fold rotation centre of the grid so the twins land
// exactly back on the grid. Squares/triangles use (width/2, the grid/row line
// at or past height/2): the twins of cell rows 0..k-1 are exactly rows
// k..2k-1, an exact cover with no overlap. A hexagon row line cannot work that
// way (rows would map onto themselves), so hexagons rotate about a slanted-
// edge midpoint -- x on the odd hexW/4 column, y on the half-row line -- which
// maps row r to row 2rs+1-r and swaps the stagger parity correctly; rs is
// chosen so the twins of rows 0..rs cover every row visible below.

float rotCentreX() {
  if (shapeMode != 2) return width / 2.0;               // a multiple of L/2 for both
  return width / 2.0 + (float) width / gridN / 4.0;     // hexagon: slant-edge midpoint column
}

float rotCentreY() {
  if (shapeMode != 2) {
    float py = symPitchY();                             // square grid line / triangle row line
    return py * ceil(height / (2.0 * py) - 1e-4);
  }
  float R0 = (float) width / (gridN * sqrt(3));         // matches hexagonRoots()
  float vSp = 1.5 * R0;
  int last = ceil((height + R0) / vSp) - 1;             // lowest hex row visible on canvas
  int rs   = ceil((last - 1) / 2.0);                    // keep rows 0..rs; twins are rows rs+1..2rs+1
  return (rs + 0.5) * vSp;                              // slant-edge midpoint line
}

// Append a half-turn twin of every collected leaf (same motif, rot + PI).
void addRotatedTwins() {
  float xc = rotCentreX(), yc = rotCentreY();
  int n0 = leaves.size();
  for (int i = 0; i < n0; i++) {
    Tile t = leaves.get(i);
    Tile twin = new Tile(2 * xc - t.cx, 2 * yc - t.cy, t.R, t.rot + PI, t.n, t.depth);
    twin.mi = t.mi;
    twin.mk = t.mk;
    leaves.add(twin);
  }
}

// ---- tile-level mirror symmetry (modes 5-7) -----------------------
// Structural mirrors, the tile-level siblings of the pixel mirror modes: like
// rot 180 they render in one normal pass (wings spill both ways, shadows keep
// one light direction, gradients stay continuous), but each reflected half is
// the exact REFLECTION of the fundamental one, motif for motif. A mirrored
// motif is drawn by reversing the tile's vertex winding (Tile.flip, see
// TileGeom in Shapes.pde), so no per-shape edge-relabelling tables are needed.
// Modes: 5 = vertical axis only, 6 = horizontal only, 7 = quad (both -> the
// Klein 4-group {identity, V, H, 180-rotation}).
//
// Tile-level twinning needs NO global grid mirror line: the reflected half is
// self-consistent by construction, so only the SEAM along the axis must be
// clean -- i.e. the axis may pass along tile edges/vertices (tiles lie fully on
// one side) or through tile CENTRES ("straddlers", which map to themselves and
// must look symmetric alone), but never cut a tile body off-centre. The chosen
// axes satisfy this for every shape:
//   * vertical x = width/2 -- a mirror column of all three grids (the grid
//     divides width exactly): squares straddle it for odd gridN, triangles one
//     per strip, hexes every other row.
//   * horizontal y = mirrorAxisY() -- snapped to the nearest grid mirror line
//     to mid-canvas (height is NOT divided evenly, so it sits slightly
//     off-centre): square cell/boundary line (s0/2 spacing), triangle strip
//     boundary (row-line spacing; the up-triangle bases there tile edge-to-edge
//     and their flipped twins share those exact edges -> no straddlers), or
//     hexagon row-centre line (a straddler row; its fan-triangle children split
//     into 2 straddlers + 2 mirror pairs).
// collectSym() walks the fundamental domain straddler-aware; addSymTwins()
// fills the rest; straddler leaves get a motif symmetric about the relevant
// axis/axes (pickSymmetricMotifMulti).

float mirrorAxisX() { return width / 2.0; }

// Nearest grid horizontal mirror line to mid-canvas (see header). Square cell
// lines are s0/2 apart (both boundaries and centres mirror); triangle strip
// boundaries are rowH apart; hexagon row centres are vSpacing apart.
float mirrorAxisY() {
  float L = (float) width / gridN;
  float u;
  if (shapeMode == 0)      u = L / 2.0;             // square: s0/2 lines
  else if (shapeMode == 1) u = L * sqrt(3) / 2.0;   // triangle: rowH strip boundaries
  else                     u = 1.5 * (float) width / (gridN * sqrt(3));  // hexagon: row centres
  return round((height / 2.0) / u) * u;
}

boolean straddleV(Tile t) { return abs(t.cx - mirrorAxisX()) < 1e-3 * t.R; }
boolean straddleH(Tile t) { return abs(t.cy - mirrorAxisY()) < 1e-3 * t.R; }

// Collect a tile under the active mirror axes. A tile strictly on the far side
// of an axis is dropped (a twin will cover it); a tile centred on an axis is a
// straddler (recurse mirror-aware, or emit a leaf with an axis-symmetric
// motif); anything else lies wholly in the fundamental domain and collects
// normally (its children stay inside it, since the axis never cuts a body
// off-centre).
void collectSym(Tile t, boolean vMir, boolean hMir) {
  float ax = mirrorAxisX(), ay = mirrorAxisY(), tol = 1e-3 * t.R;
  if (vMir && t.cx > ax + tol) return;            // right half: V-twins cover it
  if (hMir && t.cy > ay + tol) return;            // bottom half: H-twins cover it
  boolean onV = vMir && straddleV(t);
  boolean onH = hMir && straddleH(t);
  if (!onV && !onH) { collectTile(t); return; }   // interior of the fundamental domain
  if (canSubdivide(t) && random(1) < subdivideProb) {
    for (Tile c : children(t)) collectSym(c, vMir, hMir);
  } else {
    pickSymmetricMotifMulti(t, onV, onH);
    t.straddle = true;          // on a symmetry axis -> morph target must stay symmetric
    leaves.add(t);
  }
}

// Add the symmetry-orbit twins of every fundamental leaf. The orbit (minus the
// identity) is up to three images; an axis the tile straddles fixes it, so that
// reflection is skipped (and the diagonal 180-rotation collapses onto the
// remaining single reflection). V/H reflections reverse winding (flip); the
// 180-rotation is two reflections, so it does not.
void addSymTwins(boolean vMir, boolean hMir) {
  float ax = mirrorAxisX(), ay = mirrorAxisY();
  int n0 = leaves.size();
  for (int i = 0; i < n0; i++) {
    Tile t = leaves.get(i);
    boolean onV = vMir && straddleV(t);
    boolean onH = hMir && straddleH(t);
    if (vMir && !onV)            addTwin(2 * ax - t.cx, t.cy, PI - t.rot, true, t);
    if (hMir && !onH)            addTwin(t.cx, 2 * ay - t.cy, -t.rot, true, t);
    if (vMir && hMir && !onV && !onH)
                                 addTwin(2 * ax - t.cx, 2 * ay - t.cy, t.rot + PI, false, t);
  }
}

void addTwin(float cx, float cy, float rot, boolean flip, Tile src) {
  Tile tw = new Tile(cx, cy, src.R, rot, src.n, src.depth);
  tw.mi = src.mi;
  tw.mk = src.mk;
  tw.flip = flip;
  leaves.add(tw);
}

// Constrained motif roll for a straddler: keep only (motif, rotation) pairs
// symmetric about every axis the tile straddles. A reflection maps the tile's
// edge e -> c0 - 1 - e; c0 differs per axis -- vertical reflection (theta ->
// PI - theta) gives c0 = (PI - 2*rot)/(TWO_PI/n), horizontal (theta -> -theta)
// gives c0 = -2*rot/(TWO_PI/n) -- each an integer because a straddler's
// footprint is self-symmetric about that axis. Each qualifying pair keeps its
// natural weight w[mi], so this is the normal roll conditioned on symmetry.
// Every alphabet has qualifying entries (blank for square/triangle; e.g. the
// trefoil and asterisk for hexagons); should weights leave none, fall back to
// motif 0.
void pickSymmetricMotifMulti(Tile t, boolean onV, boolean onH) {
  int n = t.n;
  int[][][] alpha = connsFor(n);
  float[] w = weightsFor(n);
  int c0V = ((round((PI - 2 * t.rot) / (TWO_PI / n))) % n + n) % n;
  int c0H = ((round((-2 * t.rot) / (TWO_PI / n))) % n + n) % n;
  ArrayList<int[]> cand = new ArrayList<int[]>();
  float total = 0;
  for (int mi = 0; mi < alpha.length; mi++)
    for (int mk = 0; mk < n; mk++) {
      if (onV && !selfMirrorMotif(alpha[mi], mk, c0V, n, max(1, anchorsPerSide))) continue;
      if (onH && !selfMirrorMotif(alpha[mi], mk, c0H, n, max(1, anchorsPerSide))) continue;
      cand.add(new int[]{ mi, mk });
      total += w[mi];
    }
  if (cand.isEmpty() || total <= 0) { t.mi = -1; t.mk = 0; return; }   // none qualify -> blank
  float r = random(total);
  int[] pick = cand.get(cand.size() - 1);
  for (int[] cm : cand) {
    r -= w[cm[0]];
    if (r < 0) { pick = cm; break; }
  }
  t.mi = pick[0];
  t.mk = pick[1];
}

// Does the motif (connection set rotated by mk) map onto itself under the axis
// reflection? Works over PORTS (k anchors per side; k=1 = the classic single
// midpoint, identical to before). The reflection maps a port (edge e, slot s) to
// (edge c0-1-e, slot k-1-s): the edge reflects by e -> c0-1-e and, because a
// reflection reverses the anchor order along an edge, the slot reverses too. A
// rotation by mk steps maps (e,s) -> (e+mk, s) (slot preserved). Tagged primitives
// (hub/hump, first slot >= CONN_TAG; k=1 only) never qualify -- a straddler then
// falls back to a plain symmetric motif.
boolean selfMirrorMotif(int[][] conns, int mk, int c0, int n, int k) {
  int vbase = n * k + n + 1;             // vertex (corner) ports start here
  for (int[] c : conns) {
    if (c[0] >= CONN_TAG) return false;                 // tagged prims (hub/hump/circle/dot)
    if (c[0] >= vbase || c[1] >= vbase) return false;   // vertex-port (Kumiko) motifs: rotPort/
                                                        // reflPort don't map corners -> skip straddlers
  }
  int P = n * k + n + 1;                 // edge anchors + apothem mids + centre
  boolean[][] has = new boolean[P][P];
  for (int[] c : conns) {
    int i = rotPort(c[0], mk, n, k), j = rotPort(c[1], mk, n, k);
    has[i][j] = has[j][i] = true;
  }
  for (int[] c : conns) {
    int i = reflPort(rotPort(c[0], mk, n, k), c0, n, k);
    int j = reflPort(rotPort(c[1], mk, n, k), c0, n, k);
    if (!has[i][j]) return false;
  }
  return true;
}

// Port transforms used by the straddler self-symmetry test. Edge port p encodes
// (edge e = p/k, slot s = p%k). rotPort spins by mk edge-steps (slot kept);
// reflPort reflects across the edge origin c0 (slot reversed: s -> k-1-s).
// Interior ports: an apothem midpoint (n*k + e) follows its edge e; the centre
// (n*k + n) is fixed by every rotation/reflection.
int rotPort(int p, int mk, int n, int k) {
  int E = n * k;
  if (p < E)     { int e = p / k, s = p % k; return ((e + mk) % n) * k + s; }
  if (p < E + n) return E + (p - E + mk) % n;
  return p;
}
int reflPort(int p, int c0, int n, int k) {
  int E = n * k;
  if (p < E)     { int e = p / k, s = p % k; return (((c0 - 1 - e) % n + n) % n) * k + (k - 1 - s); }
  if (p < E + n) return E + ((c0 - 1 - (p - E)) % n + n) % n;
  return p;
}

// ---- colour from the active palette -----------------------------
// The palette "rotate" control (R key / Controls button). Scheme-aware: in
// duotone it assigns two random palette colours to fg/bg (rotating the colour
// order is invisible there, since the extremes are luminance-picked); every other
// scheme cycles the colour order, which DOES change order-sensitive mappings.
void rotatePalette() {
  if (colorScheme == 0) rotateDuotone();
  else                  palettes.current().rotate();
  dirtyGradient = true;
  imgDirty = true;
}

// Pick two random palette colours for the duotone fg/bg, with a minimum
// luminance gap (so the pair always reads as a clear fg vs bg) and different from
// the current pair (so every press visibly changes). bg = the lighter colour, fg
// = the darker (per-level inversion still swaps them). Uses its own RNG (duoRng).
void rotateDuotone() {
  Palette p = palettes.current();
  int n = p.size();
  if (n < 2) { duoRandom = false; return; }
  if (duoRng == null) duoRng = new java.util.Random();
  // palette luminance range -> a gap that is always achievable (the extremes meet it)
  float lo = 1e9, hi = -1e9;
  for (int k = 0; k < n; k++) { float l = p.lum(p.get(k)); lo = min(lo, l); hi = max(hi, l); }
  float minGap = 0.4 * (hi - lo);
  int curA = duoRandom ? min(duoBgIdx, duoFgIdx) : -1;
  int curB = duoRandom ? max(duoBgIdx, duoFgIdx) : -1;
  int chA = 0, chB = 1; float bestGap = -1;
  for (int t = 0; t < 64; t++) {
    int i = duoRng.nextInt(n);
    int j = duoRng.nextInt(n - 1); if (j >= i) j++;     // distinct from i
    int a = min(i, j), b = max(i, j);
    if (a == curA && b == curB) continue;                // same pair as now -> keep trying
    float gap = abs(p.lum(p.get(a)) - p.lum(p.get(b)));
    if (gap > bestGap) { bestGap = gap; chA = a; chB = b; }   // track best as a fallback
    if (gap >= minGap) break;                            // good enough -> take it
  }
  boolean aLighter = p.lum(p.get(chA)) >= p.lum(p.get(chB));
  duoBgIdx = aLighter ? chA : chB;
  duoFgIdx = aLighter ? chB : chA;
  duoRandom = true;
}

String schemeName(int s) {
  switch (s) {
    case 0:  return "duotone";
    case 1:  return "multi";
    case 2:  return "gradient";
    case 3:  return "gradient-bg";
    case 4:  return "gradient-smooth";
    case 5:  return "gradient-wheel";
    default: return "gradient-wheel-fg";
  }
}

// Tile background colour.
color tileBg(Tile t) {
  Palette p = palettes.current();
  if (colorScheme == 2 || colorScheme == 4 || colorScheme == 6) return gradSolid;  // solid ground (incl. wheel-fg)
  if (schemeBgGradient()) return gradientColor(t.cx, t.cy);     // gradient-bg / wheel: blend wing corner discs
  if (colorScheme == 1) return p.lightest();                    // multi: constant light ground
  boolean inv = invertPerLevel && (t.depth % 2 == 1);           // duotone: extremes, or 2 random (rotate)
  color a = duoRandom ? p.get(duoBgIdx) : p.lightest();         // bg slot when not inverted
  color b = duoRandom ? p.get(duoFgIdx) : p.darkest();          // fg slot when not inverted
  return inv ? b : a;
}

// Foreground (band/wing) colour. In the gradient-smooth + wheel-fg/wheel schemes
// (4/5/6) the bands are painted via a Java2D gradient instead (gradientStroke()/
// fgPaint()), so this value is only a per-tile fallback for those.
color tileFg(Tile t) {
  Palette p = palettes.current();
  if (colorScheme == 2 || colorScheme == 4) return gradientColor(t.cx, t.cy);  // gradient ribbons (flat fallback)
  if (colorScheme == 5) return wheelColorAt(t.cx, t.cy, 0.5);    // wheel ribbons ride +0.5 (fallback)
  if (colorScheme == 6) return wheelColorAt(t.cx, t.cy, 0);      // wheel-fg ribbons ride the wheel (fallback)
  if (colorScheme == 3) return gradSolid;                       // gradient-bg: solid ribbons
  if (colorScheme == 1) return ribbonColor(p, t.depth);         // multi: a palette colour per level
  boolean inv = invertPerLevel && (t.depth % 2 == 1);           // duotone: extremes, or 2 random (rotate)
  color a = duoRandom ? p.get(duoBgIdx) : p.lightest();         // bg slot when not inverted
  color b = duoRandom ? p.get(duoFgIdx) : p.darkest();          // fg slot when not inverted
  return inv ? a : b;
}

// Canvas clear colour (shows in overscan / tiny gaps). Matches the depth-0 bg.
color canvasBgColor() {
  if (colorScheme == 2 || colorScheme == 4 || colorScheme == 6) return gradSolid;  // solid ground (incl. wheel-fg)
  if (colorScheme == 0 && duoRandom)        return palettes.current().get(duoBgIdx);
  return palettes.current().lightest();
}

// Gradient schemes (2 and 3): one palette colour (chosen at random) is the solid
// element; the other colours form a gradient, in a random direction. In scheme 2
// the bands sample that gradient and the ground is solid; in scheme 3 the
// background IS the (smooth) gradient and the bands are solid. Recomputed each
// draw -- a new seed (or palette rotation) gives a new pairing. Uses random(),
// so draw() re-seeds afterwards.
void setupGradient() {
  if (colorScheme < 2) return;   // schemes 2..6 are the gradient family
  if (colorScheme >= 5) { setupWheel(); return; }   // 5 + 6 share the cyclic wheel
  Palette p = palettes.current();
  int n = p.size();
  int solidIdx = int(random(n));
  gradSolid = p.get(solidIdx);
  ArrayList<Integer> stops = new ArrayList<Integer>();   // the other colours, in palette order
  for (int i = 0; i < n; i++) if (i != solidIdx) stops.add(p.get(i));
  if (stops.isEmpty()) stops.add(gradSolid);
  gradStops = new color[stops.size()];
  for (int i = 0; i < stops.size(); i++) gradStops[i] = stops.get(i);
  float a = random(TWO_PI);                              // random gradient axis
  gradCos = cos(a); gradSin = sin(a);
  float lo = 1e9, hi = -1e9;                             // project the 4 corners onto the axis
  float[] xs = { 0, width, 0, width }, ys = { 0, 0, height, height };
  for (int i = 0; i < 4; i++) {
    float pr = xs[i] * gradCos + ys[i] * gradSin;
    lo = min(lo, pr); hi = max(hi, pr);
  }
  gradMin = lo; gradSpan = max(1, hi - lo);

  // Build a matching Java2D paint for the smooth schemes (3, 4): linear along the
  // axis, or radial about the centre -- placed so its fraction equals gradParam().
  gradPaint = buildGradPaint();
}

// A non-cyclic Java2D paint over gradStops (schemes 3/4): LinearGradientPaint along
// the axis, or RadialGradientPaint about the centre. Its fraction at a point matches
// gradParam(): linear t = projection, radial t = distance/radius. null if < 2 stops.
java.awt.Paint buildGradPaint() {
  if (gradStops == null || gradStops.length < 2) return null;
  float[] fr = new float[gradStops.length];
  Color[] cols = new Color[gradStops.length];
  for (int i = 0; i < gradStops.length; i++) {
    fr[i] = i / (float) (gradStops.length - 1);
    int c = gradStops[i];
    cols[i] = new Color((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF);
  }
  if (gradRadial) {
    return new java.awt.RadialGradientPaint(new Point2D.Float(gradCx * width, gradCy * height),
                                            gradRadius(), fr, cols);   // NO_CYCLE -> clamp
  }
  float sx = gradMin * gradCos,                sy = gradMin * gradSin;
  float ex = (gradMin + gradSpan) * gradCos,   ey = (gradMin + gradSpan) * gradSin;
  if (dist(sx, sy, ex, ey) < 1e-3) return null;
  return new LinearGradientPaint(new Point2D.Float(sx, sy), new Point2D.Float(ex, ey), fr, cols);
}

// ---- gradient-wheel scheme (5): a cyclic, animated palette wheel -------------
// The whole palette is laid round a 360 deg wheel (the last stop wraps back to
// the first, so there is no seam) projected across the canvas; wheelPhase shifts
// it continuously. gradStops holds the wheel colours; gradSolid is a constant
// high-contrast ribbon colour. The axis + projection reuse the same gradMin/
// gradSpan machinery, so gradientColor() and the Java2D paint stay in lockstep.
void setupWheel() {
  Palette p = palettes.current();
  int n = p.size();
  gradStops = new color[max(1, n)];
  for (int i = 0; i < n; i++) gradStops[i] = p.get(i);
  // A constant ribbon colour that contrasts the colourful wheel: pick the palette
  // extreme furthest in luminance from the palette's mean (darkest or lightest).
  float mean = 0; for (int i = 0; i < n; i++) mean += p.lum(p.get(i));
  mean = (n > 0) ? mean / n : 0;
  gradSolid = (mean >= 128) ? p.darkest() : p.lightest();
  float a = random(TWO_PI);                              // random wheel axis
  gradCos = cos(a); gradSin = sin(a);
  float lo = 1e9, hi = -1e9;
  float[] xs = { 0, width, 0, width }, ys = { 0, 0, height, height };
  for (int i = 0; i < 4; i++) {
    float pr = xs[i] * gradCos + ys[i] * gradSin;
    lo = min(lo, pr); hi = max(hi, pr);
  }
  gradMin = lo; gradSpan = max(1, hi - lo);
  gradPaint = null;                                      // scheme 5 uses wheelPaint(), not gradPaint
  // Cyclic Java2D stop arrays: colours c0..c(n-1) then c0 again at fraction 1, so
  // a CycleMethod.REPEAT paint wraps seamlessly. Built once; the phase is applied
  // at draw time by translating the paint (wheelPaint), not by rebuilding here.
  int m = max(2, gradStops.length + 1);
  wheelCols = new Color[m]; wheelFr = new float[m];
  for (int i = 0; i < m; i++) {
    int c = gradStops[i % gradStops.length];
    wheelCols[i] = new Color((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF);
    wheelFr[i]   = i / (float) (m - 1);
  }
  // Cached colour LUT for the radial wheel paint (cyclic linear interpolation =
  // exactly gradWheelAt). Built here once, reused by every RadialWheelPaint context.
  int nw = gradStops.length;
  wheelLUT = new int[WHEEL_LUT_N];
  for (int i = 0; i < WHEEL_LUT_N; i++) {
    float seg = (i / (float) WHEEL_LUT_N) * nw;
    int ai = (int) seg % nw, bi = (ai + 1) % nw;
    float f = seg - (int) seg;
    int ca = gradStops[ai], cb = gradStops[bi];
    int r = (int) (((ca >> 16) & 0xFF) * (1 - f) + ((cb >> 16) & 0xFF) * f + 0.5);
    int g = (int) (((ca >>  8) & 0xFF) * (1 - f) + ((cb >>  8) & 0xFF) * f + 0.5);
    int bl= (int) ((ca & 0xFF)         * (1 - f) + (cb & 0xFF)         * f + 0.5);
    wheelLUT[i] = (r << 16) | (g << 8) | bl;
  }
}

// Build the cyclic wheel paint at phase (wheelPhase + extraPhase), matching
// wheelColorAt() with the same extra. extraPhase = 0 for the background wheel; the
// foreground rides +0.5 (scheme 5).
//   LINEAR -- shift a fixed-stop LinearGradientPaint's start point back by ph*gradSpan
//     (a geometric slide of a fixed colour LUT -> perfectly smooth).
//   RADIAL -- an additive radial phase is NOT any geometric transform of a radial
//     gradient, so RadialGradientPaint would have to rebuild its ~256-cell colour LUT
//     every frame (cell boundaries jump as the phase shifts -> a temporal wobble).
//     Instead use RadialWheelPaint, a custom Paint that computes each pixel's colour
//     directly from the wheel (no LUT) -> the rings move as smoothly as the linear
//     wheel, at ~the same per-pixel cost (RadialGradientPaint already measures the
//     per-pixel distance; only its LUT lookup is replaced by an exact interpolation).
java.awt.Paint wheelPaint(float extraPhase) {
  if (wheelCols == null || wheelCols.length < 2) return null;
  float ph = wheelPhase + extraPhase;
  if (gradRadial)
    return new RadialWheelPaint(gradCx * width, gradCy * height, gradRadius(), ph, wheelLUT);
  float startProj = gradMin - ph * gradSpan;
  float sx = startProj * gradCos,                sy = startProj * gradSin;
  float ex = (startProj + gradSpan) * gradCos,   ey = (startProj + gradSpan) * gradSin;
  if (dist(sx, sy, ex, ey) < 1e-3) return null;
  return new LinearGradientPaint(new Point2D.Float(sx, sy), new Point2D.Float(ex, ey),
                                 wheelFr, wheelCols,
                                 java.awt.MultipleGradientPaint.CycleMethod.REPEAT);
}

// Rebuild the per-frame foreground wheel paint (called once at the top of
// renderTiling). Scheme 5 ribbons ride a half-turn ahead of the bg wheel so they
// always contrast it; scheme 6 has no bg wheel, so they ride it directly.
void refreshWheelFgPaint() {
  wheelFgPaint = schemeWheelFg() ? wheelPaint(colorScheme == 5 ? 0.5 : 0.0) : null;
}

// The Java2D paint for foreground bands/nubs when gradientStroke() is true:
// scheme 4 = the static linear gradient (gradPaint); schemes 5/6 = the animated
// cyclic wheel (the cached wheelFgPaint).
java.awt.Paint fgPaint() { return schemeWheelFg() ? wheelFgPaint : gradPaint; }

// Interpolate the gradient stops at parameter t in [0,1].
color gradAt(float t) {
  if (gradStops == null || gradStops.length == 0) return color(0);
  if (gradStops.length == 1) return gradStops[0];
  float seg = constrain(t, 0, 1) * (gradStops.length - 1);
  int i = min(int(seg), gradStops.length - 2);
  return lerpColor(gradStops[i], gradStops[i + 1], seg - i);
}

// Cyclic sample of the wheel at parameter u (wraps mod 1; stop n == stop 0).
color gradWheelAt(float u) {
  if (gradStops == null || gradStops.length == 0) return color(0);
  int n = gradStops.length;
  if (n == 1) return gradStops[0];
  u = u - floor(u);                    // wrap to [0,1)
  float seg = u * n;                   // n cyclic segments
  int i = int(seg) % n;
  int j = (i + 1) % n;
  return lerpColor(gradStops[i], gradStops[j], seg - floor(seg));
}

// Cyclic wheel colour at a point, offset by (wheelPhase + extra).
color wheelColorAt(float x, float y, float extra) {
  return gradWheelAt(gradParam(x, y) + wheelPhase + extra);
}

// Sample the gradient at a point. gradParam() gives t (linear axis projection or
// radial distance). Wheel schemes (5/6) sample the cyclic wheel at the animated
// phase; others clamp linearly. (Background discs read offset 0; fg adds its own.)
color gradientColor(float x, float y) {
  if (colorScheme >= 5) return wheelColorAt(x, y, 0);
  return gradAt(gradParam(x, y));
}

// Paint the whole canvas with the smooth gradient background (schemes 3 + 5),
// using a Java2D LinearGradientPaint so it is continuous (not stepped). Scheme 5
// uses the phase-shifted cyclic wheel paint; scheme 3 uses the static gradPaint.
void drawGradientBackground() {
  java.awt.Paint paint = (colorScheme == 5) ? wheelPaint(0) : gradPaint;
  if (paint == null) {                       // <2 distinct stops: fall back to flat
    background(gradStops != null && gradStops.length > 0 ? gradStops[0] : color(0));
    return;
  }
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  g2.setPaint(paint);
  g2.fill(new Rectangle2D.Float(0, 0, width, height));
}

// Multi-colour scheme: cycle the palette's non-background colours by scale
// level, darkest first so the coarsest (most visible) tiles get the boldest
// ribbon against the light ground.
color ribbonColor(Palette p, int depth) {
  color bg = p.lightest();
  ArrayList<Integer> pool = new ArrayList<Integer>();
  for (int i = 0; i < p.size(); i++) {
    color c = p.get(i);
    if (c != bg) pool.add(c);
  }
  if (pool.size() == 0) return p.darkest();
  for (int a = 0; a < pool.size(); a++)               // sort ascending by luminance
    for (int b = a + 1; b < pool.size(); b++)
      if (p.lum(pool.get(b)) < p.lum(pool.get(a))) {
        Integer t = pool.get(a); pool.set(a, pool.get(b)); pool.set(b, t);
      }
  return pool.get(depth % pool.size());
}

// ---- saving (parameter-stamped) ---------------------------------
// Save the current frame to a filename that encodes the displayed parameters +
// seed, and print the exact headless command that reproduces it -- so a saved
// PNG can later be re-rendered at higher resolution (bump TRUCHET_SCALE) with the
// identical composition. Called on the viz thread (Save button via saveRequested,
// or the S key) so the grabbed frame is fully drawn.
void saveTiling() {
  String base = saveBaseName();
  String path = renderDir() + base + ".png";
  saveFrame(path);                          // Processing creates hires/ if absent
  saveManifest(path);                       // sidecar JSON: the complete reproducible recipe
  println("saved " + path);
  println("reproduce at higher resolution (raise/lower TRUCHET_SCALE for the size):");
  println("  " + reproduceCmd(base));
}

// Saved renders go in a single flat hires/ folder (gitignored) to keep the sketch
// root uncluttered; the parameter-stamped filename is the index. Relative to the
// sketch folder. (TRUCHET_OUT headless renders still honour their explicit path.)
String renderDir() {
  return "hires/";
}

// Compact, human-readable parameter summary for the filename. Captures the knobs
// that define the composition; the full recipe (every knob) is in reproduceCmd().
String saveBaseName() {
  String s;
  if (imageMode) {
    s = "truchet_halftone_" + schemeName(colorScheme)
      + "_cols" + imgCols + "_pal" + palettes.current;
    if (imagePath != null) {
      String b = new java.io.File(imagePath).getName();
      int dot = b.lastIndexOf('.');
      if (dot > 0) b = b.substring(0, dot);
      s += "_" + b.replaceAll("[^A-Za-z0-9._-]", "");
    }
    return s + appearanceTokens();
  }
  s = "truchet_" + SHAPE_NAMES[shapeMode] + "_" + schemeName(colorScheme)
    + "_seed" + seedVal + "_g" + gridN + "_d" + maxDepth
    + "_sub" + round(subdivideProb * 100) + "_pal" + palettes.current;
  if (symmetryMode != 0) s += "_sym" + symmetryMode;
  return s + appearanceTokens();
}

// Appearance/colour tokens shared by both render modes. Each is emitted ONLY when
// it deviates from its setup() default, so a default render keeps a short name yet
// any tweak a headless re-render would otherwise miss is captured -- making the
// filename a faithful spec, not just an index. (reproduceCmd() lists every
// parameter unconditionally; this is the subset that differs from default.)
// Continuous values are encoded as integer percent / degrees, e.g. line duty 0.40
// -> "d40", line subdiv 0.80 -> "s80", shadow 0.3/0.4/45deg -> "sh30-40-45".
String appearanceTokens() {
  String s = "";
  if (anchorsPerSide != 1) s += "_k" + anchorsPerSide;              // multi-anchor tile alphabet
  if (duoRandom)         s += "_duo" + duoBgIdx + "-" + duoFgIdx;   // R-key random fg/bg (duotone)
  if (!winged)           s += "_nowing";
  if (!dropShadow)       s += "_noshadow";
  else {
    if (shadowGlobal)    s += "_gshadow";
    if (round(shadowStrength * 100) != 30 || round(shadowSize * 100) != 40
        || round(degrees(shadowAngle)) != 45)
      s += "_sh" + round(shadowStrength * 100) + "-" + round(shadowSize * 100)
         + "-" + round(degrees(shadowAngle));
  }
  if (!invertPerLevel)   s += "_noinv";
  if (extrude3D) {
    s += "_ext" + extrudeMode;
    if (round(vpX * 100) != 50 || round(vpY * 100) != -20
        || round(extrudeDepth * 100) != 50 || round(extrudeShade * 100) != 55)
      s += "_vp" + round(vpX * 100) + "_" + round(vpY * 100)
         + "_ed" + round(extrudeDepth * 100) + "_es" + round(extrudeShade * 100);
  }
  if (lineMode) {
    s += "_line" + lineCount;                                      // lineCount is always shown
    if (round(lineDuty * 100) != 45)        s += "d" + round(lineDuty * 100);
    if (round(lineSubdivProb * 100) != 100) s += "s" + round(lineSubdivProb * 100);
  }
  if (kumikoStyle) {
    s += "_kumiko";
    if (round(stripWidthFrac * 100) != 10) s += round(stripWidthFrac * 100);   // strip width %
  }
  if (colorScheme >= 5)                                            // gradient-wheel rate + phase
    s += "_wheel" + round(wheelRate * 100) + "p" + round(wheelPhase * 100);
  if (colorScheme >= 2 && gradRadial)                              // radial transient + centre
    s += "_radial" + round(gradCx * 100) + "-" + round(gradCy * 100);
  if (metalMode) {
    s += "_metal-" + metalMatName() + (metalBevelStyle == 1 ? "-rim" : "");    // material always shown
    if (round(metalBevelPx) != 10)  s += "b" + round(metalBevelPx);
    if (round(metalLightDeg) != 118) s += "l" + round(metalLightDeg);
  }
  if (morphActive) s += "_morph" + round(morphT * 100) + "g" + morphGen          // mid-morph frame
                      + (morphSpread > 0 ? "s" + round(morphSpread * 100) : "")   // staggered
                      + (morphEasing != 0 ? "-" + MORPH_EASE_NAMES[morphEasing] : "");  // easing
  return s;
}

// The full headless command that reproduces this frame. Defaults TRUCHET_SCALE=2
// (a 4K render); change it for other sizes. Output goes to <base>_hires.png so it
// doesn't clobber the GUI save. Includes every render-affecting parameter (each
// has a matching env override parsed in setup()).
String reproduceCmd(String base) {
  String cmd = "TRUCHET_SCALE=2"
    + " TRUCHET_SHAPE="  + shapeMode
    + " TRUCHET_SCHEME=" + colorScheme
    + (colorScheme >= 5 ? " TRUCHET_WHEEL_RATE=" + nf(wheelRate, 1, 3) + " TRUCHET_WHEEL_PHASE=" + nf(wheelPhase, 1, 3) : "")
    + (colorScheme >= 2 ? " TRUCHET_GRAD_RADIAL=" + (gradRadial ? 1 : 0) + " TRUCHET_GRAD_CX=" + nf(gradCx, 1, 3) + " TRUCHET_GRAD_CY=" + nf(gradCy, 1, 3) : "")
    + " TRUCHET_PALETTE=" + palettes.current
    + " TRUCHET_ANCHORS=" + anchorsPerSide
    + " TRUCHET_TILESET=" + activeIdxFor(curN(), anchorsPerSide)
    + " TRUCHET_INVERT=" + (invertPerLevel ? 1 : 0)
    + " TRUCHET_LINE=" + (lineMode ? 1 : 0)
    + " TRUCHET_LINE_COUNT=" + lineCount
    + " TRUCHET_LINE_DUTY=" + nf(lineDuty, 1, 2)
    + " TRUCHET_LINE_SUBDIV=" + nf(lineSubdivProb, 1, 2)
    + " TRUCHET_KUMIKO=" + (kumikoStyle ? 1 : 0)
    + " TRUCHET_STRIP=" + nf(stripWidthFrac, 1, 2)
    + " TRUCHET_METAL=" + (metalMode ? 1 : 0)
    + " TRUCHET_METAL_MAT=" + metalMaterial
    + " TRUCHET_METAL_BEVEL=" + round(metalBevelPx)
    + " TRUCHET_METAL_STYLE=" + metalBevelStyle
    + " TRUCHET_METAL_LIGHT=" + nf(metalLightDeg, 1, 1)
    + (duoRandom ? " TRUCHET_DUO=" + duoBgIdx + "," + duoFgIdx : "");
  if (imageMode && imagePath != null) {
    cmd += " TRUCHET_IMG=" + imagePath
      + " TRUCHET_IMG_COLS=" + imgCols
      + " TRUCHET_IMG_LIB=" + libSize
      + " TRUCHET_IMG_GAMMA=" + nf(imgGamma, 1, 2)
      + " TRUCHET_IMG_STRETCH=" + (imgStretch ? 1 : 0)
      + " TRUCHET_IMG_INVERT=" + (imgInvert ? 1 : 0)
      + " TRUCHET_IMG_CONTAIN=" + (imgContain ? 1 : 0)
      + " TRUCHET_DEPTH=" + maxDepth
      + " TRUCHET_SUBDIV=" + nf(subdivideProb, 1, 2)
      + " TRUCHET_WINGED=" + (winged ? 1 : 0);
  } else {
    cmd += " TRUCHET_SEED="  + seedVal
      + " TRUCHET_GRID="   + gridN
      + " TRUCHET_DEPTH="  + maxDepth
      + " TRUCHET_SUBDIV=" + nf(subdivideProb, 1, 2)
      + " TRUCHET_SYM="    + symmetryMode
      + " TRUCHET_WINGED=" + (winged ? 1 : 0)
      + " TRUCHET_SHADOW=" + (dropShadow ? 1 : 0)
      + " TRUCHET_SHADOW_STR="    + nf(shadowStrength, 1, 2)
      + " TRUCHET_SHADOW_SIZE="   + nf(shadowSize, 1, 2)
      + " TRUCHET_SHADOW_ANGLE="  + nf(degrees(shadowAngle), 1, 1)
      + " TRUCHET_SHADOW_GLOBAL=" + (shadowGlobal ? 1 : 0);
    if (extrude3D) {
      cmd += " TRUCHET_EXTRUDE=1"
        + " TRUCHET_EXTRUDE_MODE="  + extrudeMode
        + " TRUCHET_VPX=" + nf(vpX, 1, 3)
        + " TRUCHET_VPY=" + nf(vpY, 1, 3)
        + " TRUCHET_EXTRUDE_DEPTH=" + nf(extrudeDepth, 1, 2)
        + " TRUCHET_EXTRUDE_SHADE=" + nf(extrudeShade, 1, 2);
    }
  }
  if (morphActive)      // a mid-morph frame: pin the phase + which target roll + stagger
    cmd += " TRUCHET_MORPH=1 TRUCHET_MORPH_T=" + nf(morphT, 1, 3) + " TRUCHET_MORPH_GEN=" + morphGen
         + " TRUCHET_MORPH_SPREAD=" + nf(morphSpread, 1, 2)
         + " TRUCHET_MORPH_EASE=" + morphEasing
         + " TRUCHET_MORPH_CAP=" + morphCap;
  cmd += " TRUCHET_OUT=" + renderDir() + base + "_hires.png"
    + " processing-java --sketch=" + sketchPath("") + " --run";
  return cmd;
}

// ---- render manifest (the complete, reproducible recipe) --------
// The filename is a lossy human index and reproduceCmd() is env-only; both omit the
// three pieces of implicit state that bit us before -- tile weights, anchors-per-side,
// and palette rotation. A manifest is the authoritative recipe: every render global
// PLUS the exact tile catalog (alphabets + weights) and palette colour order, written
// as a JSON sidecar beside each saved PNG. loadManifest() restores it all, so the
// composition reproduces regardless of later tiles.json edits -- at any resolution
// (TRUCHET_SCALE/W/H stay env-only, since they are output size, not composition).
JSONObject renderManifest() {
  JSONObject root = new JSONObject();
  root.setInt("version", 1);
  root.setString("name", saveBaseName());

  JSONObject r = new JSONObject();
  r.setInt("shape", shapeMode);          r.setInt("scheme", colorScheme);
  r.setFloat("wheelRate", wheelRate);    r.setFloat("wheelPhase", wheelPhase);
  r.setBoolean("gradRadial", gradRadial); r.setFloat("gradCx", gradCx); r.setFloat("gradCy", gradCy);
  r.setInt("seed", seedVal);             r.setInt("grid", gridN);
  r.setInt("depth", maxDepth);           r.setFloat("subdiv", subdivideProb);
  r.setInt("sym", symmetryMode);         r.setInt("anchors", anchorsPerSide);
  r.setBoolean("winged", winged);        r.setBoolean("invert", invertPerLevel);
  r.setBoolean("showGrid", showGrid);
  r.setBoolean("duoRandom", duoRandom);  r.setInt("duoBgIdx", duoBgIdx);  r.setInt("duoFgIdx", duoFgIdx);
  r.setBoolean("shadow", dropShadow);    r.setFloat("shadowStr", shadowStrength);
  r.setFloat("shadowSize", shadowSize);  r.setFloat("shadowAngle", degrees(shadowAngle));
  r.setBoolean("shadowGlobal", shadowGlobal);
  r.setBoolean("line", lineMode);        r.setInt("lineCount", lineCount);
  r.setFloat("lineDuty", lineDuty);      r.setFloat("lineSubdiv", lineSubdivProb);
  r.setBoolean("kumiko", kumikoStyle);   r.setFloat("stripWidth", stripWidthFrac);
  r.setBoolean("metal", metalMode);      r.setInt("metalMat", metalMaterial);
  r.setInt("metalStyle", metalBevelStyle); r.setFloat("metalBevel", metalBevelPx);
  r.setFloat("metalLight", metalLightDeg);
  r.setBoolean("extrude", extrude3D);    r.setInt("extrudeMode", extrudeMode);
  r.setFloat("vpX", vpX);                r.setFloat("vpY", vpY);
  r.setFloat("extrudeDepth", extrudeDepth); r.setFloat("extrudeShade", extrudeShade);
  r.setBoolean("morph", morphActive);    r.setFloat("morphT", morphT);   r.setInt("morphGen", morphGen);
  r.setFloat("morphSpread", morphSpread); r.setInt("morphEasing", morphEasing);
  r.setInt("morphCap", morphCap);
  r.setBoolean("imageMode", imageMode);
  if (imagePath != null) r.setString("img", imagePath);
  r.setInt("imgCols", imgCols);          r.setInt("imgLib", libSize);
  r.setFloat("imgGamma", imgGamma);      r.setBoolean("imgStretch", imgStretch);
  r.setBoolean("imgInvert", imgInvert);  r.setBoolean("imgContain", imgContain);
  root.setJSONObject("render", r);

  JSONObject pal = new JSONObject();                 // index + exact colour order (captures rotation)
  pal.setInt("index", palettes.current);
  Palette p = palettes.current();
  JSONArray cols = new JSONArray();
  for (int i = 0; i < p.size(); i++) cols.setInt(i, p.get(i));
  pal.setJSONArray("colors", cols);
  root.setJSONObject("palette", pal);

  root.setJSONObject("catalog", currentCatalogJson());

  JSONObject act = new JSONObject();                 // which tileset is active per (n,k)
  for (String key : activeTilesetIdx.keySet()) act.setInt(key, activeTilesetIdx.get(key));
  root.setJSONObject("activeTilesets", act);
  return root;
}

// Sidecar path for a PNG (foo.png -> foo.json), and the writer.
String manifestPathFor(String pngPath) {
  int dot = pngPath.lastIndexOf('.');
  return (dot > 0 ? pngPath.substring(0, dot) : pngPath) + ".json";
}
void saveManifest(String pngPath) {
  String jp = manifestPathFor(pngPath);
  saveJSONObject(renderManifest(), jp);
  println("manifest " + jp);
}

// Inverse of renderManifest: restore every global, the palette colour order, and the
// full tile catalog. Returns true on success. Called from setup() (TRUCHET_LOAD, as a
// baseline the per-env overrides then refine) and the Controls "Load render…" button.
boolean loadManifest(String path) {
  JSONObject root = loadJSONObject(path);
  if (root == null) { println("manifest not found / unreadable: " + path); return false; }
  JSONObject r = root.getJSONObject("render");
  if (r != null) {
    shapeMode      = r.getInt("shape", shapeMode);
    colorScheme    = r.getInt("scheme", colorScheme);
    wheelRate      = r.getFloat("wheelRate", wheelRate);
    gradRadial     = r.getBoolean("gradRadial", gradRadial);
    gradCx         = r.getFloat("gradCx", gradCx);
    gradCy         = r.getFloat("gradCy", gradCy);
    wheelPhase     = r.getFloat("wheelPhase", wheelPhase);
    seedVal        = r.getInt("seed", seedVal);
    gridN          = r.getInt("grid", gridN);
    maxDepth       = r.getInt("depth", maxDepth);
    subdivideProb  = r.getFloat("subdiv", subdivideProb);
    symmetryMode   = r.getInt("sym", symmetryMode);
    anchorsPerSide = r.getInt("anchors", anchorsPerSide);
    winged         = r.getBoolean("winged", winged);
    invertPerLevel = r.getBoolean("invert", invertPerLevel);
    showGrid       = r.getBoolean("showGrid", showGrid);
    duoRandom      = r.getBoolean("duoRandom", duoRandom);
    duoBgIdx       = r.getInt("duoBgIdx", duoBgIdx);
    duoFgIdx       = r.getInt("duoFgIdx", duoFgIdx);
    dropShadow     = r.getBoolean("shadow", dropShadow);
    shadowStrength = r.getFloat("shadowStr", shadowStrength);
    shadowSize     = r.getFloat("shadowSize", shadowSize);
    shadowAngle    = radians(r.getFloat("shadowAngle", degrees(shadowAngle)));
    shadowGlobal   = r.getBoolean("shadowGlobal", shadowGlobal);
    lineMode       = r.getBoolean("line", lineMode);
    lineCount      = r.getInt("lineCount", lineCount);
    lineDuty       = r.getFloat("lineDuty", lineDuty);
    lineSubdivProb = r.getFloat("lineSubdiv", lineSubdivProb);
    kumikoStyle    = r.getBoolean("kumiko", kumikoStyle);
    stripWidthFrac = r.getFloat("stripWidth", stripWidthFrac);
    metalMode      = r.getBoolean("metal", metalMode);
    metalMaterial  = r.getInt("metalMat", metalMaterial);
    metalBevelStyle = r.getInt("metalStyle", metalBevelStyle);
    metalBevelPx   = r.getFloat("metalBevel", metalBevelPx);
    metalLightDeg  = r.getFloat("metalLight", metalLightDeg);
    extrude3D      = r.getBoolean("extrude", extrude3D);
    extrudeMode    = r.getInt("extrudeMode", extrudeMode);
    vpX            = r.getFloat("vpX", vpX);
    vpY            = r.getFloat("vpY", vpY);
    extrudeDepth   = r.getFloat("extrudeDepth", extrudeDepth);
    extrudeShade   = r.getFloat("extrudeShade", extrudeShade);
    morphActive    = r.getBoolean("morph", morphActive);
    morphT         = r.getFloat("morphT", morphT);
    morphGen       = r.getInt("morphGen", morphGen);
    morphSpread    = r.getFloat("morphSpread", morphSpread);
    morphEasing    = r.getInt("morphEasing", morphEasing);
    morphCap       = r.getInt("morphCap", morphCap);
    if (morphActive) headlessMorph = true;    // a loaded morph frame is a pinned phase
    imageMode      = r.getBoolean("imageMode", imageMode);
    if (r.hasKey("img")) imagePath = r.getString("img");
    imgCols        = r.getInt("imgCols", imgCols);
    libSize        = r.getInt("imgLib", libSize);
    imgGamma       = r.getFloat("imgGamma", imgGamma);
    imgStretch     = r.getBoolean("imgStretch", imgStretch);
    imgInvert      = r.getBoolean("imgInvert", imgInvert);
    imgContain     = r.getBoolean("imgContain", imgContain);
  }
  if (root.hasKey("palette")) {
    JSONObject pal = root.getJSONObject("palette");
    palettes.setCurrent(pal.getInt("index", palettes.current));
    if (pal.hasKey("colors")) {
      JSONArray cols = pal.getJSONArray("colors");
      Palette p = palettes.current();
      if (cols.size() == p.size())
        for (int i = 0; i < cols.size(); i++) p.colors[i] = cols.getInt(i);
    }
  }
  if (root.hasKey("catalog")) applyCatalog(root.getJSONObject("catalog"));
  if (root.hasKey("activeTilesets")) {               // restore which tileset is active per (n,k)
    JSONObject act = root.getJSONObject("activeTilesets");
    for (Object ko : act.keys()) activeTilesetIdx.put((String) ko, act.getInt((String) ko));
  }
  manifestLoaded = true;
  return true;
}

// Controls "Load render…" callback: restore a full manifest and re-render.
void manifestChosen(File selection) {
  if (selection == null) return;                     // user cancelled
  logAction("LOAD render " + selection.getAbsolutePath());  // prime race suspect: reassigns the catalog
  if (!loadManifest(selection.getAbsolutePath())) return;
  sourceImg = null;                                  // force reload if the manifest is image mode
  dirtyLayout = true; dirtyGradient = true; imgDirty = true;
  controlsNeedSync = true;                            // refresh the Controls widgets next frame
  redraw();
}

// ---- debug logging helpers --------------------------------------
// dbg: emit one categorized, thread-tagged, timestamped line to the console and the
// persistent log file. Early-returns when debug is off so call sites cost ~nothing.
void dbg(String cat, String msg) {
  if (!debugLog) return;
  String line = String.format("[+%.1fs][%s] %s: %s",
    (millis() - debugStartMs) / 1000.0, Thread.currentThread().getName(), cat, msg);
  println(line);
  writeDebugLine(line);
}

// logAction: record a user action so a later crash dump can quote the last one.
void logAction(String msg) {
  lastAction = msg;
  dbg("ACTION", msg);
}

// phase: set the render-phase breadcrumb (always; cheap, read by dbgCrash). Emits a
// PHASE log line only when animation is OFF -- under continuous playback the per-frame
// phases would flood the log, but a crash still reports the breadcrumb either way.
void phase(String p) {
  renderPhase = p;
  if (debugLog && !animEnabled) dbg("PHASE", p);
}

// writeDebugLine: append to the log file (opening it on first use). Guarded so logging
// can never itself throw and mask the bug we're chasing.
void writeDebugLine(String line) {
  try {
    if (debugFile == null) openDebugFile();
    if (debugFile != null) { debugFile.println(line); debugFile.flush(); }
  } catch (Throwable t) { /* never let logging crash the sketch */ }
}

void openDebugFile() {
  try {
    java.io.File dir = new java.io.File(sketchPath("logs"));
    if (!dir.exists()) dir.mkdirs();
    // millis()-based name (wall-clock formatting is avoided here); append mode keeps
    // one file across repeated 'd' toggles within a session.
    java.io.File f = new java.io.File(dir, "debug-" + (System.currentTimeMillis()) + ".log");
    debugFile = new java.io.PrintWriter(new java.io.FileWriter(f, true), true);
  } catch (Throwable t) {
    println("debug: could not open log file: " + t);
    debugFile = null;
  }
}

// enableDebug: flip the gate and announce the transition (forced through, so the line
// appears even when turning logging off).
void enableDebug(boolean on) {
  boolean was = debugLog;
  debugLog = true;                 // force the announcement line to be emitted...
  dbg("DEBUG", (on ? "ON" : "OFF") + " (was " + was + ")");
  debugLog = on;                   // ...then settle to the requested state
}

// dbgCrash: the whole point. On any exception in a draw loop, dump the offending
// thread, the last user action, the render phase reached, a compact state line, and
// the full stack trace -- to both console and the log file -- then stop the loop so a
// recurring crash doesn't flood. A crash is always recorded, even if 'd' was never on.
void dbgCrash(Throwable e) {
  boolean was = debugLog;
  debugLog = true;
  String state = "scheme=" + schemeName(colorScheme) + " shape=" + SHAPE_NAMES[shapeMode]
    + " k=" + anchorsPerSide + " sym=" + SYMMETRY_NAMES[symmetryMode]
    + " image=" + imageMode + " line=" + lineMode + " extrude=" + extrude3D + " seed=" + seedVal;
  dbg("CRASH", "!!! " + e.getClass().getName() + (e.getMessage() != null ? ": " + e.getMessage() : ""));
  dbg("CRASH", "thread=" + Thread.currentThread().getName() + "  lastAction=" + lastAction);
  dbg("CRASH", "phase=" + renderPhase + "  " + state);
  e.printStackTrace();                                    // console
  try {                                                   // and the log file
    if (debugFile == null) openDebugFile();
    if (debugFile != null) { e.printStackTrace(debugFile); debugFile.flush(); }
  } catch (Throwable t) { /* ignore */ }
  debugLog = was;
  noLoop();   // halt the loop; the static frame + log are preserved for inspection
}

// ---- interaction ------------------------------------------------
void keyPressed() {
  logAction("KEY '" + (key == ' ' ? "SPACE" : key) + "'");
  if (key == ' ') {
    seedVal = int(random(1, 99999));
    dirtyLayout = true; dirtyGradient = true;
    redraw();
  } else if (key == 's' || key == 'S') {
    saveTiling();
  } else if (key == 'a' || key == 'A') {   // toggle animation
    setAnimEnabled(!animEnabled);
    println("animation: " + animEnabled);
  } else if (key == 'o') {                 // one-shot tile morph to a fresh motif set
    startMorph();
    println("morph");
  } else if (key == 'O') {                 // staggered morph (tiles finish at different times)
    startMorphStaggered();
    println("morph (staggered)");
  } else if (key == 'p') {                 // next palette
    palettes.next();
    duoRandom = false;                     // new palette -> back to duotone extremes
    println("palette: " + palettes.current());
    dirtyGradient = true;
    redraw();
  } else if (key == 'P') {                 // previous palette
    palettes.prev();
    duoRandom = false;
    println("palette: " + palettes.current());
    dirtyGradient = true;
    redraw();
  } else if (key == 'c' || key == 'C') {   // cycle colour scheme
    colorScheme = (colorScheme + 1) % 7;
    println("colour scheme: " + schemeName(colorScheme));
    dirtyGradient = true;
    refreshLoopState();                    // gradient-wheel (5) animates -> ensure the loop runs
    redraw();
  } else if (key == 'r' || key == 'R') {   // rotate: 2 random duotone colours, else cycle order
    rotatePalette();
    redraw();
  } else if (key == 'm' || key == 'M') {   // cycle symmetry (mirrors, then rot 180)
    symmetryMode = (symmetryMode + 1) % SYMMETRY_NAMES.length;
    println("symmetry: " + SYMMETRY_NAMES[symmetryMode]);
    dirtyLayout = true;
    redraw();
  } else if (key == 'e') {                 // toggle 3D extrusion
    extrude3D = !extrude3D;
    println("extrude 3D: " + extrude3D);
    redraw();
  } else if (key == 'E') {                 // cycle extrusion mode
    extrudeMode = (extrudeMode + 1) % EXTRUDE_NAMES.length;
    println("extrude mode: " + EXTRUDE_NAMES[extrudeMode]);
    redraw();
  } else if (key == '4') {                 // square
    setShape(0);
  } else if (key == '3') {                 // triangle
    setShape(1);
  } else if (key == '6') {                 // hexagon
    setShape(2);
  } else if (key == 't' || key == 'T') {   // trapezoid (half-hexagon)
    setShape(3);
  } else if (key == 'g' || key == 'G') {   // toggle base-grid overlay
    showGrid = !showGrid;
    println("grid overlay: " + showGrid);
    redraw();
  } else if (key == 'l' || key == 'L') {   // toggle parallel-stroke (line) mode
    lineMode = !lineMode;
    println("line mode: " + lineMode);
    redraw();
  } else if (key == 'k' || key == 'K') {   // toggle Kumiko thin-strip lattice style
    kumikoStyle = !kumikoStyle;
    println("kumiko style: " + kumikoStyle);
    redraw();
  } else if (key == 'd' || key == 'D') {   // toggle debug action/crash logging
    enableDebug(!debugLog);
  }
}

void setShape(int mode) {
  shapeMode = mode;
  println("shape: " + SHAPE_NAMES[shapeMode]);
  dirtyLayout = true;
  redraw();
}
