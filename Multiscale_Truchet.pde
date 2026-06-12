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
//  tile -- via a Java2D LinearGradientPaint; see Shapes.pde drawConnG2).
//
//  Shapes (see Shapes.pde): square (multi-scale quadtree), triangle
//  (multi-scale rep-tile), hexagon (multi-scale -- a hexagon is not a rep-tile,
//  so it subdivides into 6 equilateral triangles that then recurse). Keys 4/3/6.
//
//  Controls:  SPACE = new pattern  |  4/3/6 = square/triangle/hexagon
//             P/p = prev/next palette  |  R = rotate palette  |  C = colour
//             scheme  |  S = save PNG
// ============================================================

// Edges, clockwise:  0 = N (top), 1 = E (right), 2 = S (bottom), 3 = W (left)

// ---- parameters -------------------------------------------------
int     gridN         = 6;      // top-level cells per side
int     maxDepth      = 4;      // max recursive subdivisions
float   subdivideProb = 0.55;   // chance a cell splits into 4
int     seedVal       = 1;
boolean winged        = true;   // Carlson wings (structural connections)
boolean invertPerLevel= true;   // (duotone scheme) flip colours each scale level
int     colorScheme   = 0;      // 0 = duotone, 1 = multi, 2 = gradient (see schemeName)

// gradient scheme state (recomputed per draw; see setupGradient)
color   gradSolid;              // the one solid colour (tile background)
color[] gradStops;              // the other colours, forming the band gradient
float   gradCos, gradSin, gradMin, gradSpan;   // gradient axis + projection range
LinearGradientPaint gradPaint;  // Java2D paint matching the gradient (smooth schemes)

PaletteManager palettes;        // colour source (see Palettes.pde), set in setup()
ControlWindow  controls;        // secondary GUI window (see ControlWindow.pde), set in setup()
boolean saveRequested = false;  // set by the control window's Save button, handled in draw()

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

  // launch the parameter GUI as its own window (separate PApplet); see
  // ControlWindow.pde. It edits the globals above and calls redraw().
  controls = new ControlWindow(this);
  PApplet.runSketch(new String[]{"Controls"}, controls);
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
  leaves = new ArrayList<Tile>();
  for (Tile t : buildRoots()) collectTile(t);

  // 2. draw coarse-first so finer tiles + wings land on top
  for (int d = 0; d <= maxDepth; d++)
    for (Tile lf : leaves)
      if (lf.depth == d) drawPolyTile(lf, tileFg(lf), tileBg(lf));

  // 3. honour a save request from the control window (run here, on the
  // viz thread, so the saved frame is the fully drawn one).
  if (saveRequested) {
    saveFrame("truchet-####.png");
    saveRequested = false;
  }
}

// Recursively subdivide a tile (per its shape) or record it as a leaf.
void collectTile(Tile t) {
  if (canSubdivide(t) && random(1) < subdivideProb) {
    for (Tile c : children(t)) collectTile(c);
  } else {
    leaves.add(t);
  }
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
// the Java2D gradient instead -- see gradientStroke()/drawConnG2 in Shapes.pde.)
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
