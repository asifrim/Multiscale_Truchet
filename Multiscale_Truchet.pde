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
float   gradCos, gradSin, gradMin, gradSpan;   // gradient axis + projection range
LinearGradientPaint gradPaint;  // Java2D paint matching the gradient (smooth schemes)

PaletteManager palettes;        // colour source (see Palettes.pde), set in setup()
ControlWindow  controls;        // parameter GUI window (see ControlWindow.pde), set in setup()
TileWindow     tilesWin;        // per-shape tile-weight editor (see TileWindow.pde), set in setup()
boolean saveRequested = false;  // set by the control window's Save button, handled in draw()
String  autosavePath  = null;   // TRUCHET_OUT env var: render once to this file, then exit

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
  smooth(8);
}

void setup() {
  palettes = new PaletteManager();   // built-in COLOURlovers snapshot
  initAnim();                        // animation engine (LFOs, registry) — see Animation.pde
  noLoop();

  // Headless one-shot render (for verifying changes from the command line —
  // never screenshot the window): environment variables select the output file
  // and optionally override parameters; the first fully drawn frame is saved
  // to TRUCHET_OUT and the sketch exits. Example:
  //   TRUCHET_OUT=/tmp/out.png TRUCHET_SHAPE=2 processing-java --sketch=... --run
  autosavePath = System.getenv("TRUCHET_OUT");
  String envShape  = System.getenv("TRUCHET_SHAPE");   // 0 square, 1 triangle, 2 hexagon, 3 trapezoid
  if (envShape != null)  shapeMode   = constrain(Integer.parseInt(envShape.trim()), 0, 3);
  String envScheme = System.getenv("TRUCHET_SCHEME");  // 0..4, see schemeName()
  if (envScheme != null) colorScheme = constrain(Integer.parseInt(envScheme.trim()), 0, 4);
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
  String envGrid   = System.getenv("TRUCHET_GRID");    // top-level cells per side
  if (envGrid != null)   gridN       = constrain(Integer.parseInt(envGrid.trim()), 2, 16);
  String envDepth  = System.getenv("TRUCHET_DEPTH");   // max subdivisions (0 = single scale)
  if (envDepth != null)  maxDepth    = constrain(Integer.parseInt(envDepth.trim()), 0, 6);
  String envSub    = System.getenv("TRUCHET_SUBDIV");  // subdivide probability (0..1; 1 = uniform fine)
  if (envSub != null)    subdivideProb = constrain(Float.parseFloat(envSub.trim()), 0, 1);
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

  // launch the GUIs as separate PApplet windows. Each holds a reference back
  // here, edits the globals above, and calls redraw() (the viz is noLoop()).
  controls = new ControlWindow(this);
  PApplet.runSketch(new String[]{"Controls"}, controls);
  tilesWin = new TileWindow(this);
  PApplet.runSketch(new String[]{"Tiles"}, tilesWin);
}

void draw() {
  // 0. animation: advance the clock + refresh the modulator snapshot the render
  //    reads (identity when animation is off, so a static frame is unchanged).
  updateAnim();

  // gradient + layout are deterministic from seed/params -> rebuild only when a
  // mutator marked them dirty, not every animated frame.
  if (dirtyGradient) {
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
    drawImageMode();
  } else {
    if (colorScheme == 3) drawGradientBackground();   // smooth gradient fills the canvas
    else background(canvasBgColor());

    // 1. build the leaf tiling (cached; see rebuildLeaves).
    if (dirtyLayout) { rebuildLeaves(); dirtyLayout = false; }

    // 2. draw the tiling coarse-first (see renderTiling).
    renderTiling();

    // 3. mirror symmetry (modes 1-3): reflect the rendered pixels about
    //    grid-aligned axes. (Mode 4, rot 180, is tile-level -- see step 1.)
    applySymmetry();

    // 3b. optional: overlay the base (root) tile lattice on top of everything.
    if (showGrid) drawGridOverlay();
  }

  // 4. honour a save request from the control window (run here, on the
  // viz thread, so the saved frame is the fully drawn one).
  if (saveRequested) {
    saveTiling();
    saveRequested = false;
  }

  // 5. headless mode (TRUCHET_OUT): save the rendered frame and quit. Also echo the
  // parameter-stamped name + reproduce command for this frame (handy for scripting
  // and for confirming the GUI's filename scheme).
  if (autosavePath != null) {
    save(autosavePath);
    println("name: " + saveBaseName());
    println("reproduce: " + reproduceCmd(saveBaseName()));
    exit();
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
  hexBatch = new Path2D.Float();
  hexSolidBatch = new Path2D.Float();
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
  if (lineMode && colorScheme != 3) {
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
    default: return "gradient-smooth";
  }
}

// Tile background colour.
color tileBg(Tile t) {
  Palette p = palettes.current();
  if (colorScheme == 2 || colorScheme == 4) return gradSolid;   // gradient ribbons: solid ground
  if (colorScheme == 3) return gradientColor(t.cx, t.cy);       // gradient-bg: blend wing corner discs
  if (colorScheme == 1) return p.lightest();                    // multi: constant light ground
  boolean inv = invertPerLevel && (t.depth % 2 == 1);           // duotone: extremes, or 2 random (rotate)
  color a = duoRandom ? p.get(duoBgIdx) : p.lightest();         // bg slot when not inverted
  color b = duoRandom ? p.get(duoFgIdx) : p.darkest();          // fg slot when not inverted
  return inv ? b : a;
}

// Foreground (band/wing) colour. (In gradient-smooth the bands are painted via
// the Java2D gradient instead -- see gradientStroke()/drawTileBands in Shapes.pde.)
color tileFg(Tile t) {
  Palette p = palettes.current();
  if (colorScheme == 2 || colorScheme == 4) return gradientColor(t.cx, t.cy);  // gradient ribbons
  if (colorScheme == 3) return gradSolid;                       // gradient-bg: solid ribbons
  if (colorScheme == 1) return ribbonColor(p, t.depth);         // multi: a palette colour per level
  boolean inv = invertPerLevel && (t.depth % 2 == 1);           // duotone: extremes, or 2 random (rotate)
  color a = duoRandom ? p.get(duoBgIdx) : p.lightest();         // bg slot when not inverted
  color b = duoRandom ? p.get(duoFgIdx) : p.darkest();          // fg slot when not inverted
  return inv ? a : b;
}

// Canvas clear colour (shows in overscan / tiny gaps). Matches the depth-0 bg.
color canvasBgColor() {
  if (colorScheme == 2 || colorScheme == 4) return gradSolid;
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

// ---- saving (parameter-stamped) ---------------------------------
// Save the current frame to a filename that encodes the displayed parameters +
// seed, and print the exact headless command that reproduces it -- so a saved
// PNG can later be re-rendered at higher resolution (bump TRUCHET_SCALE) with the
// identical composition. Called on the viz thread (Save button via saveRequested,
// or the S key) so the grabbed frame is fully drawn.
void saveTiling() {
  String base = saveBaseName();
  saveFrame(base + ".png");                 // written to the sketch folder
  println("saved " + base + ".png");
  println("reproduce at higher resolution (raise/lower TRUCHET_SCALE for the size):");
  println("  " + reproduceCmd(base));
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
    return s;
  }
  s = "truchet_" + SHAPE_NAMES[shapeMode] + "_" + schemeName(colorScheme)
    + "_seed" + seedVal + "_g" + gridN + "_d" + maxDepth
    + "_sub" + round(subdivideProb * 100) + "_pal" + palettes.current;
  if (symmetryMode != 0) s += "_sym" + symmetryMode;
  if (!winged)           s += "_nowing";
  if (!dropShadow)       s += "_noshadow";
  else if (shadowGlobal) s += "_gshadow";
  if (!invertPerLevel)   s += "_noinv";
  if (extrude3D)         s += "_ext" + extrudeMode;
  if (lineMode)          s += "_line" + lineCount;
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
    + " TRUCHET_PALETTE=" + palettes.current
    + " TRUCHET_INVERT=" + (invertPerLevel ? 1 : 0)
    + " TRUCHET_LINE=" + (lineMode ? 1 : 0)
    + " TRUCHET_LINE_COUNT=" + lineCount
    + " TRUCHET_LINE_DUTY=" + nf(lineDuty, 1, 2)
    + " TRUCHET_LINE_SUBDIV=" + nf(lineSubdivProb, 1, 2)
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
  cmd += " TRUCHET_OUT=" + base + "_hires.png"
    + " processing-java --sketch=" + sketchPath("") + " --run";
  return cmd;
}

// ---- interaction ------------------------------------------------
void keyPressed() {
  if (key == ' ') {
    seedVal = int(random(1, 99999));
    dirtyLayout = true; dirtyGradient = true;
    redraw();
  } else if (key == 's' || key == 'S') {
    saveTiling();
  } else if (key == 'a' || key == 'A') {   // toggle animation
    setAnimEnabled(!animEnabled);
    println("animation: " + animEnabled);
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
    colorScheme = (colorScheme + 1) % 5;
    println("colour scheme: " + schemeName(colorScheme));
    dirtyGradient = true;
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
  }
}

void setShape(int mode) {
  shapeMode = mode;
  println("shape: " + SHAPE_NAMES[shapeMode]);
  dirtyLayout = true;
  redraw();
}
