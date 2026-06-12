// ============================================================
//  Shapes.pde — generalized n-gon Truchet tiles + per-shape layouts
//
//  Generalizes the square sketch to triangles (n=3) and hexagons (n=6)
//  using Oliver Steele's construction: a connection between edge i and
//  edge j is a circular arc whose centre is the intersection of the two
//  edge lines (radius = distance from an edge midpoint to that centre);
//  diametrically opposite edges (even n) connect with a straight band.
//  Band width is sideLength/3, so boundaries cross each edge at its
//  central third -- the same invariant as the square.
//
//  MULTI-SCALE per shape:
//    SQUARE   (n=4): quadtree -- 4 half-size squares.
//    TRIANGLE (n=3): rep-tile -- 3 same-orientation corner triangles plus
//                    1 flipped centre triangle (the medial triangle).
//    HEXAGON  (n=6): a hexagon is NOT a rep-tile, so it subdivides into 6
//                    equilateral triangles (fanning from the centre) that then
//                    recurse as triangles -- whole hexagons stay the coarse scale.
//
//  Tiles are stored as (centre, circumradius R, base rotation rot, n).
//  A random motif rotation is applied by adding k*(2*PI/n) to rot, which
//  keeps the polygon's footprint identical (so it still tiles) while
//  relabelling its edges.
// ============================================================

import processing.awt.PGraphicsJava2D;     // for polygon clipping + gradient paint via Graphics2D
import java.awt.Graphics2D;
import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.LinearGradientPaint;
import java.awt.geom.Path2D;
import java.awt.geom.Point2D;
import java.awt.geom.Ellipse2D;
import java.awt.geom.Rectangle2D;

int shapeMode = 0;                         // 0 = square, 1 = triangle, 2 = hexagon
String[] SHAPE_NAMES = { "square", "triangle", "hexagon" };
int[]    SHAPE_N     = { 4, 3, 6 };

// Whole-hexagon band batching (see drawPolyTile / strokeHexBatch). Hexagons are
// all depth 0 and (except the per-tile mode 2) share one colour, so their bands
// are accumulated into ONE path and stroked once -- a single antialiased shape
// with no 1px seams where overlapping bands of separate tiles would otherwise meet.
Path2D.Float hexBatch;
boolean hexBatchUsed;
color   hexBatchFg;
float   hexBatchSide;

// ---- a polygon tile --------------------------------------------
class Tile {
  float cx, cy, R, rot;
  int n, depth;
  Tile(float cx, float cy, float R, float rot, int n, int depth) {
    this.cx = cx; this.cy = cy; this.R = R; this.rot = rot;
    this.n = n; this.depth = depth;
  }
}

// ---- per-shape tile alphabets ----------------------------------
// Triangle: every edge pair is adjacent, so a tile carries at most one arc.
int[][][] TRI_CONNS = { { }, { {0, 1} } };
float[]   TRI_W     = { 0.5, 3.0 };

// Hexagon (whole-tile motif): every tile is FULLY CONNECTED (each of the 6
// edges is paired) -- no gap edges means bands flow continuously into
// neighbours, giving clean loops. Adjacent edges {i,i+1} -> small arc;
// distance-2 {i,i+2} -> a wide sweeping arc; opposite {i,i+3} -> straight
// band. (Motifs are clipped to the tile, so wide arcs are safe.) Random
// rotation covers the phases.
int[][][] HEX_CONNS = {
  { {0, 1}, {2, 3}, {4, 5} },   // three small arcs (trefoil)
  { {0, 1}, {3, 4}, {2, 5} },   // two arcs + one band
  { {0, 2}, {3, 5}, {1, 4} },   // two sweeping arcs + one band
  { {0, 1}, {2, 4}, {3, 5} },   // one arc + two crossing sweeps
  { {0, 3}, {1, 4}, {2, 5} },   // three bands (asterisk hub)
};
float[] HEX_W = { 2.5, 2.0, 2.0, 1.5, 1.0 };

int[][][] connsFor(int n)   { return n == 3 ? TRI_CONNS : (n == 6 ? HEX_CONNS : TILE_CONNS); }
float[]   weightsFor(int n) { return n == 3 ? TRI_W     : (n == 6 ? HEX_W     : TILE_W); }

// ---- building the top-level tiling -----------------------------
ArrayList<Tile> buildRoots() {
  int n = SHAPE_N[shapeMode];
  if (n == 3) return triangleRoots();
  if (n == 6) return hexagonRoots();
  return squareRoots();
}

ArrayList<Tile> squareRoots() {
  ArrayList<Tile> roots = new ArrayList<Tile>();
  float s0 = (float) width / gridN;
  float R0 = s0 * sqrt(2) / 2.0;
  int cols = gridN;
  int rows = ceil(height / s0);
  for (int gy = 0; gy < rows; gy++)
    for (int gx = 0; gx < cols; gx++)
      roots.add(new Tile((gx + 0.5) * s0, (gy + 0.5) * s0, R0, QUARTER_PI, 4, 0));
  return roots;
}

ArrayList<Tile> triangleRoots() {
  ArrayList<Tile> roots = new ArrayList<Tile>();
  float L = (float) width / gridN;          // triangle side
  float rowH = L * sqrt(3) / 2.0;
  int rows = ceil(height / rowH) + 1;
  int cols = gridN + 2;
  for (int r = 0; r < rows; r++) {
    float ytop = r * rowH, ybot = (r + 1) * rowH;
    for (int k = -1; k < cols; k++) {
      // upward triangle (base on bottom)
      roots.add(triFromVerts(k * L, ybot, (k + 1) * L, ybot, (k + 0.5) * L, ytop));
      // downward triangle (base on top)
      roots.add(triFromVerts((k + 0.5) * L, ytop, (k + 1.5) * L, ytop, (k + 1) * L, ybot));
    }
  }
  return roots;
}

// An equilateral triangle from its 3 vertices -> (centroid, R, rot).
Tile triFromVerts(float ax, float ay, float bx, float by, float cx, float cy) {
  float gx = (ax + bx + cx) / 3.0, gy = (ay + by + cy) / 3.0;
  float R = dist(gx, gy, ax, ay);
  float rot = atan2(ay - gy, ax - gx);      // place vertex 0 at A
  return new Tile(gx, gy, R, rot, 3, 0);
}

ArrayList<Tile> hexagonRoots() {
  ArrayList<Tile> roots = new ArrayList<Tile>();
  float R0 = (float) width / (gridN * sqrt(3));   // pointy-top circumradius
  float hexW = sqrt(3) * R0;                       // flat-to-flat width
  float vSpacing = 1.5 * R0;
  int rows = ceil(height / vSpacing) + 2;
  int cols = gridN + 2;
  for (int r = 0; r < rows; r++)
    for (int q = -1; q < cols; q++) {
      float cx = q * hexW + (r % 2) * (hexW / 2.0);
      float cy = r * vSpacing;
      roots.add(new Tile(cx, cy, R0, -HALF_PI, 6, 0));   // vertex pointing up
    }
  return roots;
}

// ---- subdivision -----------------------------------------------
boolean canSubdivide(Tile t) {
  return t.depth < maxDepth;   // squares->squares, triangles->triangles, hexagons->6 triangles
}

ArrayList<Tile> children(Tile t) {
  ArrayList<Tile> ch = new ArrayList<Tile>();
  if (t.n == 4) {
    float s = t.R * sqrt(2), off = s / 4.0;
    ch.add(new Tile(t.cx - off, t.cy - off, t.R / 2, t.rot, 4, t.depth + 1));
    ch.add(new Tile(t.cx + off, t.cy - off, t.R / 2, t.rot, 4, t.depth + 1));
    ch.add(new Tile(t.cx - off, t.cy + off, t.R / 2, t.rot, 4, t.depth + 1));
    ch.add(new Tile(t.cx + off, t.cy + off, t.R / 2, t.rot, 4, t.depth + 1));
  } else if (t.n == 3) {
    for (int k = 0; k < 3; k++) {            // 3 corner triangles (same orientation)
      float a = t.rot + TWO_PI * k / 3.0;
      float ax = t.cx + t.R * cos(a), ay = t.cy + t.R * sin(a);
      ch.add(new Tile((t.cx + ax) / 2, (t.cy + ay) / 2, t.R / 2, t.rot, 3, t.depth + 1));
    }
    ch.add(new Tile(t.cx, t.cy, t.R / 2, t.rot + PI, 3, t.depth + 1));  // flipped centre
  } else if (t.n == 6) {
    // A regular hexagon is not a rep-tile, but it splits into 6 equilateral
    // triangles fanning from the centre (centre + two adjacent vertices; the
    // hexagon's side equals its circumradius R, so each triangle is equilateral).
    // Those become n==3 tiles and recurse via the rep-tile rule above -- giving
    // multi-scale detail inside the hexagon grid. Whole hexagons stay the coarse
    // scale; a shared hexagon edge is one triangle edge, so the grid still meets.
    for (int k = 0; k < 6; k++) {
      float a0 = t.rot + TWO_PI * k / 6.0;
      float a1 = t.rot + TWO_PI * (k + 1) / 6.0;
      Tile tri = triFromVerts(t.cx, t.cy,
                              t.cx + t.R * cos(a0), t.cy + t.R * sin(a0),
                              t.cx + t.R * cos(a1), t.cy + t.R * sin(a1));
      tri.depth = t.depth + 1;
      ch.add(tri);
    }
  }
  return ch;
}

// ---- rendering one tile ----------------------------------------
void drawPolyTile(Tile t, color fg, color bg) {
  int n = t.n;
  int[][][] alpha = connsFor(n);
  float[]   w     = weightsFor(n);
  int[][] conns = alpha[pickWeighted(w)];
  float rot = t.rot + int(random(n)) * (TWO_PI / n);   // random motif rotation

  float[] vx = new float[n], vy = new float[n];
  for (int k = 0; k < n; k++) {
    float a = rot + TWO_PI * k / n;
    vx[k] = t.cx + t.R * cos(a);
    vy[k] = t.cy + t.R * sin(a);
  }
  float[] mx = new float[n], my = new float[n];
  for (int k = 0; k < n; k++) {
    int k2 = (k + 1) % n;
    mx[k] = (vx[k] + vx[k2]) / 2;
    my[k] = (vy[k] + vy[k2]) / 2;
  }
  float side = dist(vx[0], vy[0], vx[1], vy[1]);

  // background polygon. Skipped when it would only repaint the canvas colour and
  // could seam against neighbours:
  //  (a) gradient-bg scheme (3): the smooth canvas gradient must show through;
  //  (b) whole hexagons (n==6): a hexagon only ever exists at depth 0, so its bg
  //      always equals the canvas colour -- drawing the opaque polygon lets a
  //      later tile slice a 1px AA seam between overlapping bands at shared edges.
  if (colorScheme != 3 && n != 6) {
    noStroke();
    fill(bg);
    beginShape();
    for (int k = 0; k < n; k++) vertex(vx[k], vy[k]);
    endShape(CLOSE);
  }

  // motif: all of this tile's bands as ONE stroked path (see drawTileBands), so
  // overlapping bands form a single antialiased shape with no 1px seams/cusps
  // between separately-drawn strokes. Square/triangle clip to the polygon (safety
  // against wide arcs); hexagon skips the clip so its ROUND-capped bands overlap
  // slightly across shared edges.
  if (n == 6 && colorScheme != 2) {
    // whole hexagons (uniform colour): defer the bands into the shared batch
    // path so ALL hexagon bands are stroked once -> no inter-tile seams. Mode 2
    // is per-tile coloured, so it can't batch and falls through to per-tile.
    for (int[] c : conns) appendConn(hexBatch, c[0], c[1], n, vx, vy, mx, my);
    hexBatchUsed = true;
    hexBatchFg   = fg;
    hexBatchSide = side;
  } else {
    boolean doClip = (n != 6);
    java.awt.Shape oldClip = doClip ? pushPolyClip(vx, vy, n) : null;
    drawTileBands(conns, n, vx, vy, mx, my, side, fg);
    if (doClip) popPolyClip(oldClip);
  }

  // wings (unclipped): bg disc at each vertex (r = side/3), fg disc at each
  // edge midpoint (r = side/6) -- structural connection points across scales.
  // Whole hexagon tiles need no wings (they're a uniform coarse layer); their
  // bands use ROUND caps (see drawTileBands) to overlap across shared edges.
  // (A subdivided hexagon becomes n==3 triangles, which DO get wings.)
  if (winged && n != 6) {
    // Drawn in the default CENTER ellipseMode using DIAMETERS (2*radius). Do NOT
    // switch to ellipseMode(RADIUS): arc() also honours ellipseMode, so leaving
    // it on RADIUS makes later arc() calls (here and in the next frame) read
    // their diameter args as radii -- doubling the arcs into a chunky mess.
    noStroke();
    fill(bg);                                          // vertex discs, r = side/3
    for (int k = 0; k < n; k++) ellipse(vx[k], vy[k], 2 * side / 3.0, 2 * side / 3.0);
    if (gradientStroke()) {                            // edge-midpoint discs, r = side/6
      for (int k = 0; k < n; k++) fillDiscG2(mx[k], my[k], side / 6.0);
    } else {
      fill(fg);
      for (int k = 0; k < n; k++) ellipse(mx[k], my[k], side / 3.0, side / 3.0);
    }
  }
}

// True when bands should be painted with the canvas-wide gradient (scheme 4),
// so each band's colour varies continuously across the canvas, not per tile.
boolean gradientStroke() { return colorScheme == 4 && gradPaint != null; }

// Draw all of a tile's bands as ONE Java2D stroked path. Stroking a single path
// (with each connection as a subpath) makes the whole motif one antialiased
// shape: overlapping bands union cleanly, with no 1px seams or cusps where
// separately-drawn strokes would meet (their AA edges otherwise leave hairline
// gaps). Solid colour, or the canvas gradient paint in the gradient-smooth scheme.
void drawTileBands(int[][] conns, int n,
                   float[] vx, float[] vy, float[] mx, float[] my,
                   float side, color fg) {
  if (conns.length == 0) return;              // blank tile
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  Path2D.Float path = new Path2D.Float();
  for (int[] c : conns) appendConn(path, c[0], c[1], n, vx, vy, mx, my);
  // hexagon bands overlap across edges with a ROUND cap (no clip there); square/
  // triangle end flush (CAP_BUTT) and rely on wings to bridge the shared edge.
  int cap = (n == 6) ? BasicStroke.CAP_ROUND : BasicStroke.CAP_BUTT;
  g2.setStroke(new BasicStroke(side / 3.0, cap, BasicStroke.JOIN_ROUND));
  g2.setPaint(gradientStroke() ? gradPaint : awtColor(fg));
  g2.draw(path);
}

// Stroke all accumulated whole-hexagon bands as ONE shape (uniform colour), so
// overlapping bands of separate hexagons union with no 1px seams. Hexagons use a
// ROUND cap and no clip (bands overlap across edges). Called from draw() after
// the depth-0 pass, before finer (triangle) tiles draw on top.
void strokeHexBatch() {
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  g2.setStroke(new BasicStroke(hexBatchSide / 3.0, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
  g2.setPaint(gradientStroke() ? gradPaint : awtColor(hexBatchFg));
  g2.draw(hexBatch);
}

// Append one connection to the path as a subpath: a straight band for opposite
// edges, else the circular arc (centre = intersection of the two edge lines)
// sampled into a polyline fine enough (~3px/segment) to read as smooth.
void appendConn(Path2D.Float path, int i, int j, int n,
                float[] vx, float[] vy, float[] mx, float[] my) {
  int d = min(abs(i - j), n - abs(i - j));
  if (n % 2 == 0 && d == n / 2) {             // opposite -> straight band
    path.moveTo(mx[i], my[i]); path.lineTo(mx[j], my[j]);
    return;
  }
  float[] c = lineIntersect(vx[i], vy[i], vx[(i + 1) % n], vy[(i + 1) % n],
                            vx[j], vy[j], vx[(j + 1) % n], vy[(j + 1) % n]);
  if (c == null) { path.moveTo(mx[i], my[i]); path.lineTo(mx[j], my[j]); return; }
  float r  = dist(mx[i], my[i], c[0], c[1]);
  float a0 = atan2(my[i] - c[1], mx[i] - c[0]);
  float a1 = atan2(my[j] - c[1], mx[j] - c[0]);
  float diff = a1 - a0;                        // shorter signed sweep -> interior arc
  while (diff <= -PI) diff += TWO_PI;
  while (diff > PI)  diff -= TWO_PI;
  int seg = max(8, ceil(r * abs(diff) / 3.0));
  for (int k = 0; k <= seg; k++) {
    float ph = a0 + diff * k / seg;
    float px = c[0] + r * cos(ph), py = c[1] + r * sin(ph);
    if (k == 0) path.moveTo(px, py); else path.lineTo(px, py);
  }
}

// Processing colour int (0xAARRGGBB) -> opaque java.awt.Color.
Color awtColor(color c) {
  return new Color((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF);
}

// Fill a disc with the gradient paint (gradient-smooth wing edge-midpoint discs).
void fillDiscG2(float cx, float cy, float r) {
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  g2.setPaint(gradPaint);
  g2.fill(new Ellipse2D.Float(cx - r, cy - r, 2 * r, 2 * r));
}

// Intersection of line (p1->p2) and line (p3->p4); null if parallel.
float[] lineIntersect(float x1, float y1, float x2, float y2,
                      float x3, float y3, float x4, float y4) {
  float den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
  if (abs(den) < 1e-6) return null;
  float pre = x1 * y2 - y1 * x2, post = x3 * y4 - y3 * x4;
  float px = (pre * (x3 - x4) - (x1 - x2) * post) / den;
  float py = (pre * (y3 - y4) - (y1 - y2) * post) / den;
  return new float[]{ px, py };
}

// ---- polygon clipping ------------------------------------------
// Processing's clip() only takes a rectangle, but the default JAVA2D
// renderer is backed by a Graphics2D that accepts arbitrary clip shapes.
// Set the clip to the tile polygon, returning the previous clip to restore.
java.awt.Shape pushPolyClip(float[] vx, float[] vy, int n) {
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  java.awt.Shape old = g2.getClip();
  Path2D.Float path = new Path2D.Float();
  path.moveTo(vx[0], vy[0]);
  for (int k = 1; k < n; k++) path.lineTo(vx[k], vy[k]);
  path.closePath();
  g2.clip(path);                 // intersect with any existing clip
  return old;
}

void popPolyClip(java.awt.Shape old) {
  ((PGraphicsJava2D) g).g2.setClip(old);
}

// Weighted pick over an arbitrary weights array.
int pickWeighted(float[] w) {
  float total = 0;
  for (float x : w) total += x;
  float r = random(total);
  for (int t = 0; t < w.length; t++) {
    r -= w[t];
    if (r < 0) return t;
  }
  return w.length - 1;
}
