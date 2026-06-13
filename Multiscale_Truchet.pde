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
//  so it subdivides into 6 equilateral triangles that then recurse). Keys 4/3/6.
//
//  Controls:  SPACE = new pattern  |  4/3/6 = square/triangle/hexagon
//             P/p = prev/next palette  |  R = rotate palette  |  C = colour
//             scheme  |  M = symmetry (pixel mirror / rot 180 / tile mirror)  |  S = save PNG
// ============================================================

// Edges, clockwise:  0 = N (top), 1 = E (right), 2 = S (bottom), 3 = W (left)

// ---- parameters -------------------------------------------------
int     gridN         = 6;      // top-level cells per side
int     maxDepth      = 4;      // max recursive subdivisions
float   subdivideProb = 0.55;   // chance a cell splits into 4
int     seedVal       = 1;
boolean winged        = true;   // Carlson wings (structural connections)
boolean invertPerLevel= true;   // (duotone scheme) flip colours each scale level
boolean dropShadow    = true;   // bands + wing nubs cast a drop shadow
float   shadowAngle   = QUARTER_PI;  // direction the shadow falls (radians, screen coords)
float   shadowSize    = 0.4;    // shadow offset as a fraction of the band stroke width (side/3)
float   shadowStrength= 0.3;    // shadow darkness: 0 = invisible, 1 = black
boolean shadowGlobal  = false;  // false = per-level mask (finer bg occludes coarser shadow);
                                // true = one full-scene mask (coarse tiles cast across finer)
int     colorScheme   = 0;      // 0 = duotone, 1 = multi, 2 = gradient (see schemeName)
int     symmetryMode  = 0;      // 0 = none, 1-3 = pixel mirrors (V/H/both), 4 = rot 180 (tile), 5-7 = tile mirrors (V/H/quad)
String[] SYMMETRY_NAMES = { "none", "vertical", "horizontal", "quad", "rot 180", "tile mir V", "tile mir H", "tile mir quad" };

// 3D extrusion (graffiti block depth): the foreground ribbons get solid sides
// extruded toward a vanishing point, viewed head-on. See draw()/drawExtrudeLevel.
boolean extrude3D     = false;  // master toggle
int     extrudeMode   = 0;      // 0 = oblique (parallel block), 1 = 1-point (converge to VP)
String[] EXTRUDE_NAMES = { "oblique", "1-point" };
float   vpX           = 0.5;    // vanishing point, normalised canvas coords (may be off-canvas)
float   vpY           = -0.2;   // default just above the top edge
float   extrudeDepth  = 0.5;    // depth as a fraction of each level's tile side
float   extrudeShade  = 0.55;   // side-wall darkness: 0 = ribbon colour, 1 = black

// gradient scheme state (recomputed per draw; see setupGradient)
color   gradSolid;              // the one solid colour (tile background)
color[] gradStops;              // the other colours, forming the band gradient
float   gradCos, gradSin, gradMin, gradSpan;   // gradient axis + projection range
LinearGradientPaint gradPaint;  // Java2D paint matching the gradient (smooth schemes)

PaletteManager palettes;        // colour source (see Palettes.pde), set in setup()
ControlWindow  controls;        // parameter GUI window (see ControlWindow.pde), set in setup()
TileWindow     tilesWin;        // per-shape tile-weight editor (see TileWindow.pde), set in setup()
boolean saveRequested = false;  // set by the control window's Save button, handled in draw()
String  autosavePath  = null;   // TRUCHET_OUT env var: render once to this file, then exit

// ---- tile alphabet ----------------------------------------------
// The n=4 instance of Steele's sideConnectionSets: every non-crossing
// way to pair the four edges (gaps/unpaired edges allowed). Each base
// tile gets a random quarter-turn when placed.
//   conns: list of {i,j} edge pairs.  TILE_W: relative weights.
int[][][] TILE_CONNS = {
  {                      },   // blank (solid)
  { {0, 1}               },   // single corner arc (N-E)
  { {0, 2}               },   // single straight band (N-S)
  { {0, 1}, {2, 3}       },   // two diagonal arcs  (N-E + S-W)
  { {0, 2}, {1, 3}       },   // two crossing bands (N-S + E-W)
};
float[] TILE_W = { 0.4, 1.0, 1.0, 6.0, 2.0 };

// ---- leaves (the Tile polygon is defined in Shapes.pde) --------
ArrayList<Tile> leaves;

// ---- setup / draw ----------------------------------------------
void setup() {
  size(1920, 1080);
  smooth(8);
  palettes = new PaletteManager();   // built-in COLOURlovers snapshot
  noLoop();

  // Headless one-shot render (for verifying changes from the command line —
  // never screenshot the window): environment variables select the output file
  // and optionally override parameters; the first fully drawn frame is saved
  // to TRUCHET_OUT and the sketch exits. Example:
  //   TRUCHET_OUT=/tmp/out.png TRUCHET_SHAPE=2 processing-java --sketch=... --run
  autosavePath = System.getenv("TRUCHET_OUT");
  String envShape  = System.getenv("TRUCHET_SHAPE");   // 0 square, 1 triangle, 2 hexagon
  if (envShape != null)  shapeMode   = constrain(Integer.parseInt(envShape.trim()), 0, 2);
  String envScheme = System.getenv("TRUCHET_SCHEME");  // 0..4, see schemeName()
  if (envScheme != null) colorScheme = constrain(Integer.parseInt(envScheme.trim()), 0, 4);
  String envSeed   = System.getenv("TRUCHET_SEED");
  if (envSeed != null)   seedVal     = Integer.parseInt(envSeed.trim());
  String envSym    = System.getenv("TRUCHET_SYM");     // 0..4, see SYMMETRY_NAMES
  if (envSym != null)    symmetryMode = constrain(Integer.parseInt(envSym.trim()), 0, SYMMETRY_NAMES.length - 1);
  String envShadow = System.getenv("TRUCHET_SHADOW");  // 0/1: drop shadow off/on
  if (envShadow != null) dropShadow  = !envShadow.trim().equals("0");
  String envShStr  = System.getenv("TRUCHET_SHADOW_STR");  // shadow darkness 0..1
  if (envShStr != null)  shadowStrength = constrain(Float.parseFloat(envShStr.trim()), 0, 1);
  String envShGl   = System.getenv("TRUCHET_SHADOW_GLOBAL");  // 0/1: per-level vs full-scene mask
  if (envShGl != null)   shadowGlobal = !envShGl.trim().equals("0");
  String envShSz   = System.getenv("TRUCHET_SHADOW_SIZE");  // shadow offset (fraction of stroke)
  if (envShSz != null)   shadowSize = Float.parseFloat(envShSz.trim());
  String envInv    = System.getenv("TRUCHET_INVERT");  // 0/1: duotone colour inversion per level
  if (envInv != null)    invertPerLevel = !envInv.trim().equals("0");
  String envGrid   = System.getenv("TRUCHET_GRID");    // top-level cells per side
  if (envGrid != null)   gridN       = constrain(Integer.parseInt(envGrid.trim()), 2, 16);
  String envDepth  = System.getenv("TRUCHET_DEPTH");   // max subdivisions (0 = single scale)
  if (envDepth != null)  maxDepth    = constrain(Integer.parseInt(envDepth.trim()), 0, 6);
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
  if (autosavePath != null) {
    saveRequested = false;             // headless writes only TRUCHET_OUT
    return;                            // no GUI windows in headless mode
  }

  // launch the GUIs as separate PApplet windows. Each holds a reference back
  // here, edits the globals above, and calls redraw() (the viz is noLoop()).
  controls = new ControlWindow(this);
  PApplet.runSketch(new String[]{"Controls"}, controls);
  tilesWin = new TileWindow(this);
  PApplet.runSketch(new String[]{"Tiles"}, tilesWin);
}

void draw() {
  randomSeed(seedVal);
  setupGradient();                // pick the gradient scheme's colours (may use random)
  randomSeed(seedVal);            // reset so the tile layout is the same across schemes
  // Defensive: clear any polygon clip a previous frame may have left set (see
  // pushPolyClip in Shapes.pde) before we clear and redraw the canvas.
  ((PGraphicsJava2D) g).g2.setClip(null);
  if (colorScheme == 3) drawGradientBackground();   // smooth gradient fills the canvas
  else background(canvasBgColor());

  // 1. build the top-level tiling for the active shape, then subdivide
  //    (square + triangle) collecting leaf tiles. (See Shapes.pde.)
  //    The tile-level symmetries are structural: rot 180 (mode 4) generates
  //    only the rows above the rotation centre and adds a half-turn twin per
  //    leaf; tile mirrors (modes 5-7) generate the fundamental domain (half or
  //    quadrant) plus the on-axis straddlers (mirror-aware) and add a flipped/
  //    rotated twin per leaf to fill the rest (see collectSym/addSymTwins).
  leaves = new ArrayList<Tile>();
  boolean rot180 = (symmetryMode == 4);
  boolean vMir   = (symmetryMode == 5 || symmetryMode == 7);
  boolean hMir   = (symmetryMode == 6 || symmetryMode == 7);
  float rotYc = rot180 ? rotCentreY() : 0;
  for (Tile t : buildRoots()) {
    if (rot180 && t.cy >= rotYc) continue;     // half-turn twins fill the rest
    if (vMir || hMir) { collectSym(t, vMir, hMir); continue; }
    collectTile(t);
  }
  if (rot180)        addRotatedTwins();
  if (vMir || hMir)  addSymTwins(vMir, hMir);

  // 2. draw coarse-first so finer tiles + wings land on top. Each depth level
  //    renders in three passes -- all backgrounds, then ONE unioned shadow
  //    layer, then all foregrounds (see Shapes.pde) -- so every shadow falls
  //    across every same-level background yet stays beneath every same-level
  //    band, keeping a single consistent light direction. Whole hexagons (all
  //    depth 0) accumulate their bands and are stroked once, as a single
  //    antialiased shape -- no seams between their overlapping bands.
  hexBatch = new Path2D.Float();
  hexBatchUsed = false;
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
      for (Tile lf : leaves)
        if (lf.depth == d) drawTileForeground(lf, tileFg(lf));
      if (d == 0 && hexBatchUsed) strokeHexBatch();
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
    for (int d = 0; d <= maxDepth; d++) {
      for (Tile lf : leaves)
        if (lf.depth == d) drawTileForeground(lf, tileFg(lf));
      if (d == 0 && hexBatchUsed) strokeHexBatch();
    }
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
      for (Tile lf : leaves)
        if (lf.depth == d) drawTileForeground(lf, tileFg(lf));
      if (d == 0 && hexBatchUsed) strokeHexBatch();
    }
  }

  // 3. mirror symmetry (modes 1-3): reflect the rendered pixels about
  //    grid-aligned axes. (Mode 4, rot 180, is tile-level -- see step 1.)
  applySymmetry();

  // 4. honour a save request from the control window (run here, on the
  // viz thread, so the saved frame is the fully drawn one).
  if (saveRequested) {
    saveFrame("truchet-####.png");
    saveRequested = false;
  }

  // 5. headless mode (TRUCHET_OUT): save the rendered frame and quit.
  if (autosavePath != null) {
    save(autosavePath);
    exit();
  }
}

// Recursively subdivide a tile (per its shape) or record it as a leaf.
void collectTile(Tile t) {
  if (canSubdivide(t) && random(1) < subdivideProb) {
    for (Tile c : children(t)) collectTile(c);
  } else {
    t.mi = pickWeighted(weightsFor(t.n));   // fix the motif at collection time so
    t.mk = int(random(t.n));                // a rot-180 twin can reuse it verbatim
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
      if (onV && !selfMirrorMotif(alpha[mi], mk, c0V, n)) continue;
      if (onH && !selfMirrorMotif(alpha[mi], mk, c0H, n)) continue;
      cand.add(new int[]{ mi, mk });
      total += w[mi];
    }
  if (cand.isEmpty() || total <= 0) { t.mi = 0; t.mk = 0; return; }
  float r = random(total);
  int[] pick = cand.get(cand.size() - 1);
  for (int[] cm : cand) {
    r -= w[cm[0]];
    if (r < 0) { pick = cm; break; }
  }
  t.mi = pick[0];
  t.mk = pick[1];
}

// Does the motif (connection set rotated by mk) map onto itself under the
// edge reflection e -> c0 - 1 - e?
boolean selfMirrorMotif(int[][] conns, int mk, int c0, int n) {
  boolean[][] has = new boolean[n][n];
  for (int[] c : conns) {
    int i = (c[0] + mk) % n, j = (c[1] + mk) % n;
    has[i][j] = has[j][i] = true;
  }
  for (int[] c : conns) {
    int i = ((c0 - 1 - c[0] - mk) % n + n) % n;
    int j = ((c0 - 1 - c[1] - mk) % n + n) % n;
    if (!has[i][j]) return false;
  }
  return true;
}

// ---- colour from the active palette -----------------------------
String schemeName(int s) {
  switch (s) {
    case 0:  return "duotone";
    case 1:  return "multi";
    case 2:  return "gradient";
    case 3:  return "gradient-bg";
    default: return "gradient-smooth";
  }
}

// Tile background colour.
color tileBg(Tile t) {
  Palette p = palettes.current();
  if (colorScheme == 2 || colorScheme == 4) return gradSolid;   // gradient ribbons: solid ground
  if (colorScheme == 3) return gradientColor(t.cx, t.cy);       // gradient-bg: blend wing corner discs
  if (colorScheme == 1) return p.lightest();                    // multi: constant light ground
  boolean inv = invertPerLevel && (t.depth % 2 == 1);           // duotone: palette extremes
  return inv ? p.darkest() : p.lightest();
}

// Foreground (band/wing) colour. (In gradient-smooth the bands are painted via
// the Java2D gradient instead -- see gradientStroke()/drawTileBands in Shapes.pde.)
color tileFg(Tile t) {
  Palette p = palettes.current();
  if (colorScheme == 2 || colorScheme == 4) return gradientColor(t.cx, t.cy);  // gradient ribbons
  if (colorScheme == 3) return gradSolid;                       // gradient-bg: solid ribbons
  if (colorScheme == 1) return ribbonColor(p, t.depth);         // multi: a palette colour per level
  boolean inv = invertPerLevel && (t.depth % 2 == 1);           // duotone: palette extremes
  return inv ? p.lightest() : p.darkest();
}

// Canvas clear colour (shows in overscan / tiny gaps).
color canvasBgColor() {
  return (colorScheme == 2 || colorScheme == 4) ? gradSolid : palettes.current().lightest();
}

// Gradient schemes (2 and 3): one palette colour (chosen at random) is the solid
// element; the other colours form a gradient, in a random direction. In scheme 2
// the bands sample that gradient and the ground is solid; in scheme 3 the
// background IS the (smooth) gradient and the bands are solid. Recomputed each
// draw -- a new seed (or palette rotation) gives a new pairing. Uses random(),
// so draw() re-seeds afterwards.
void setupGradient() {
  if (colorScheme < 2) return;   // schemes 2, 3, 4 are the gradient family
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

  // Build a matching Java2D paint for the smooth schemes (3, 4). The paint's
  // start/end points are placed so its fraction equals gradientColor()'s t.
  gradPaint = null;
  if (gradStops.length >= 2) {
    float sx = gradMin * gradCos,                sy = gradMin * gradSin;
    float ex = (gradMin + gradSpan) * gradCos,   ey = (gradMin + gradSpan) * gradSin;
    if (dist(sx, sy, ex, ey) > 1e-3) {
      float[] fr = new float[gradStops.length];
      Color[] cols = new Color[gradStops.length];
      for (int i = 0; i < gradStops.length; i++) {
        fr[i] = i / (float) (gradStops.length - 1);
        int c = gradStops[i];
        cols[i] = new Color((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF);
      }
      gradPaint = new LinearGradientPaint(new Point2D.Float(sx, sy),
                                          new Point2D.Float(ex, ey), fr, cols);
    }
  }
}

// Interpolate the gradient stops at parameter t in [0,1].
color gradAt(float t) {
  if (gradStops == null || gradStops.length == 0) return color(0);
  if (gradStops.length == 1) return gradStops[0];
  float seg = constrain(t, 0, 1) * (gradStops.length - 1);
  int i = min(int(seg), gradStops.length - 2);
  return lerpColor(gradStops[i], gradStops[i + 1], seg - i);
}

// Sample the gradient at a point (project onto the gradient axis, normalise).
color gradientColor(float x, float y) {
  return gradAt((x * gradCos + y * gradSin - gradMin) / gradSpan);
}

// Paint the whole canvas with the smooth gradient (scheme 3 background), using
// the Java2D LinearGradientPaint so it is continuous (not stepped).
void drawGradientBackground() {
  if (gradPaint == null) {                   // <2 distinct stops: fall back to flat
    background(gradStops != null && gradStops.length > 0 ? gradStops[0] : color(0));
    return;
  }
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  g2.setPaint(gradPaint);
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

// ---- interaction ------------------------------------------------
void keyPressed() {
  if (key == ' ') {
    seedVal = int(random(1, 99999));
    redraw();
  } else if (key == 's' || key == 'S') {
    saveFrame("truchet-####.png");
  } else if (key == 'p') {                 // next palette
    palettes.next();
    println("palette: " + palettes.current());
    redraw();
  } else if (key == 'P') {                 // previous palette
    palettes.prev();
    println("palette: " + palettes.current());
    redraw();
  } else if (key == 'c' || key == 'C') {   // cycle colour scheme
    colorScheme = (colorScheme + 1) % 5;
    println("colour scheme: " + schemeName(colorScheme));
    redraw();
  } else if (key == 'r' || key == 'R') {   // rotate the palette's colours
    palettes.current().rotate();
    redraw();
  } else if (key == 'm' || key == 'M') {   // cycle symmetry (mirrors, then rot 180)
    symmetryMode = (symmetryMode + 1) % SYMMETRY_NAMES.length;
    println("symmetry: " + SYMMETRY_NAMES[symmetryMode]);
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
  }
}

void setShape(int mode) {
  shapeMode = mode;
  println("shape: " + SHAPE_NAMES[shapeMode]);
  redraw();
}
