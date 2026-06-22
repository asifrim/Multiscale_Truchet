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
import java.awt.geom.AffineTransform;
import java.awt.AlphaComposite;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.File;                              // tiles.json existence check (see loadTileCatalog)

int shapeMode = 0;                         // 0 = square, 1 = triangle, 2 = hexagon, 3 = trapezoid
String[] SHAPE_NAMES = { "square", "triangle", "hexagon", "trapezoid" };
int[]    SHAPE_N     = { 4, 3, 6, 4 };     // [3] is nominal; trapezoid uses Tile.trap, not n

// Whole-hexagon band batching (see drawPolyTile / strokeHexBatch). Hexagons are
// all depth 0 and (except the per-tile mode 2) share one colour, so their bands
// are accumulated into ONE path and stroked once -- a single antialiased shape
// with no 1px seams where overlapping bands of separate tiles would otherwise meet.
Path2D.Float hexBatch;
Path2D.Float hexSolidBatch;     // line mode: whole-hex strokes that opted out of subdivision
boolean hexBatchUsed;
color   hexBatchFg;
float   hexBatchSide;

// ---- a polygon tile --------------------------------------------
class Tile {
  float cx, cy, R, rot;
  int n, depth;
  int mi = 0, mk = 0;     // motif: index into connsFor(n) + rotation steps; set in
                          // collectTile so a symmetry twin can reuse its source's motif
  // One-shot morph (see startMorph): the TARGET motif this tile is cross-dissolving
  // toward. Rolled in rollMorphTargets; mi/mk become miTo/mkTo at commitMorph. When
  // no morph is active (or mi==miTo && mk==mkTo) the render path is byte-identical.
  int miTo = 0, mkTo = 0;
  float morphOff = 0;         // staggered morph: this tile's start offset in [0, morphSpread]
                              // so tiles begin/finish at slightly different times (0 = in sync)
  boolean straddle = false;   // sits on a structural-symmetry axis (its own mirror) ->
                              // its morph target must be axis-symmetric (rollSymmetricTarget)
  boolean flip = false;   // mirror twin: reverse the vertex winding (see TileGeom),
                          // which draws the exact mirror image of the motif
  // --- trapezoid tiles (shapeMode 3) ---------------------------------------
  // The half-hexagon trapezoid is NOT a regular n-gon (irregular vertices, and
  // its long edge carries TWO ports -> 5 ports total), so it can't be described
  // by (cx,cy,R,rot,n). Instead it stores a complex SIMILARITY in a y-up
  // "canonical" frame: world(z) = p0 + z*e, with the canonical unit tile from
  // trapezoid_prototype.py. cx/cy still hold the SCREEN centroid (for culling +
  // gradient colour); n stays 4 (the polygon's vertex count, used for clip/fill).
  boolean trap = false;
  float p0x, p0y, ex, ey;   // canonical placement (complex p0 and e)
  Tile(float cx, float cy, float R, float rot, int n, int depth) {
    this.cx = cx; this.cy = cy; this.R = R; this.rot = rot;
    this.n = n; this.depth = depth;
  }
}

// ---- trapezoid (half-hexagon) tile, ported from trapezoid_prototype.py -----
// Canonical tile (short edge = 1), vertices CCW with the long edge first:
//   V0(0,0) V1(2,0) V2(1.5,H) V3(0.5,H),  H = sqrt(3)/2.
// The long edge V0->V1 holds two ports (Mitchell's multiple-points-per-side
// generalization); every port is the central third of a unit segment, so band
// width is 1/3 everywhere and the multi-scale thirds invariant holds. Ports are
// indexed 0=B1, 1=B2, 2=R, 3=T, 4=L (see TRAP_PORT). All six connections are
// circular arcs whose centre lies ON both ports' edge lines, so bands cross
// edges perpendicularly with crossing width 1/3.
final float TRAP_H = 0.86602540378;            // sqrt(3)/2
float trapPPU = 100;                            // pixels per canonical unit (set in trapezoidRoots)

// polygon vertices (for bg fill + clip), 4
final float[][] TRAP_V    = { {0,0}, {2,0}, {1.5,TRAP_H}, {0.5,TRAP_H} };
// background wing-disc centres (4 corners + the base-midpoint "virtual corner"), 5
final float[][] TRAP_CORN = { {0,0}, {2,0}, {1.5,TRAP_H}, {0.5,TRAP_H}, {1,0} };
// foreground wing-nub centres = the 5 ports (B1,B2,R,T,L). 5 is odd, so one port
// is always unmatched per motif -- its nub caps it.
final float[][] TRAP_PORT = { {0.5,0}, {1.5,0}, {1.75,TRAP_H/2}, {1.0,TRAP_H}, {0.25,TRAP_H/2} };

// motif alphabet: lists of port-index pairs (cf. TILE_CONNS but with 5 ports).
int[][][] TRAP_CONNS = {
  { {4,0}, {2,1} },   // L-B1 + R-B2
  { {4,0}, {3,2} },   // L-B1 + T-R
  { {4,3}, {2,1} },   // L-T  + R-B2
  { {4,3}, {0,1} },   // L-T  + B1-B2
  { {3,2}, {0,1} },   // T-R  + B1-B2
  { {4,2}, {0,1} },   // L-R sweep + B1-B2
  { {0,1}          },  // B1-B2 only
  { {4,2}          },  // L-R sweep only
};
float[] TRAP_W = { 3, 3, 3, 3, 3, 4, 1, 1 };

// Subdivision: a half-hexagon trapezoid is EXACTLY 3 unit equilateral triangles
// (two up + one down), so it splits into those and recurses them as n==3 tiles --
// the lattice-preserving strategy the hexagon uses. (The earlier rep-4 split into
// 4 rotated half-trapezoids tiled by area but moved the children's ports OFF the
// connection lattice, so subdivided trapezoids didn't connect; see children().)
// Each entry is one triangle's 3 canonical vertices. The triangles' boundary
// edges reproduce the trapezoid's exact port structure -- the long edge is the
// two up-triangles' bases (2 ports), the top edge the down-triangle's base (1),
// each leg one triangle edge (1) -- so a whole trapezoid and a subdivided one
// connect seamlessly, and adjacent subdivided trapezoids share the native
// triangle lattice.
final float[][][] TRAP_TRIS = {
  { {0,0},       {1,0},       {0.5, TRAP_H} },   // A: up   (base = left half of long edge)
  { {0.5,TRAP_H},{1.5,TRAP_H},{1.0, 0}      },   // B: down (base = top edge)
  { {1,0},       {2,0},       {1.5, TRAP_H} },   // C: up   (base = right half of long edge)
};

// Arc spec for a trapezoid connection between ports i,j (any order):
// { centreX, centreY, midRadius, startDeg, endDeg } in CANONICAL coords, CCW.
// Centres sit on both ports' edge lines => perpendicular crossings, width 1/3.
float[] trapArcSpec(int a, int b) {
  int lo = min(a, b), hi = max(a, b);
  if (lo == 0 && hi == 1) return new float[]{ 1.0,      0.0,         0.5, 0,   180 };  // B1-B2 U-turn
  if (lo == 1 && hi == 2) return new float[]{ 2.0,      0.0,         0.5, 120, 180 };  // R-B2 corner
  if (lo == 2 && hi == 3) return new float[]{ 1.5,      TRAP_H,      0.5, 180, 300 };  // T-R  corner
  if (lo == 3 && hi == 4) return new float[]{ 0.5,      TRAP_H,      0.5, 240, 360 };  // L-T  corner
  if (lo == 0 && hi == 4) return new float[]{ 0.0,      0.0,         0.5, 0,   60  };  // L-B1 corner
  return                         new float[]{ 1.0, 1.7320508,        1.5, 240, 300 };  // L-R sweep (apex)
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

// Alphabet for shape n at the current global anchorsPerSide (k): the 16 conns /
// weights of the ACTIVE tileset for (n, k), or a single blank motif if that (n, k)
// has no tileset yet. The Tiles panel writes weights into the returned array by
// reference, so edits land in the live tileset.
int[][][] connsFor(int n) {
  Tileset ts = activeTilesetFor(n);
  return ts != null ? ts.conns : BLANK_CONNS;
}
float[] weightsFor(int n) {
  Tileset ts = activeTilesetFor(n);
  return ts != null ? ts.weights : BLANK_W;
}

// ---- building the top-level tiling -----------------------------
ArrayList<Tile> buildRoots() {
  if (shapeMode == 3) return trapezoidRoots();
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

// Trapezoid (half-hexagon) field. Up- and down-pointing trapezoids tile the
// plane two-per-row on a staggered lattice (matching trapezoid_prototype.py's
// render_field): an "up" tile has e = (1,0), a "down" tile e = (-1,0) (a 180
// flip). Canonical y is up; the per-tile transform (see TileGeom) flips it to
// screen. trapPPU sizes the field so ~gridN tiles span the width (each lattice
// column is 3 canonical units wide).
ArrayList<Tile> trapezoidRoots() {
  ArrayList<Tile> roots = new ArrayList<Tile>();
  trapPPU = (float) width / (gridN * 3.0);
  float ppu = trapPPU;
  int cols = ceil(width / ppu / 3.0) + 2;
  int rows = ceil(height / ppu / TRAP_H) + 2;
  for (int k = -1; k < rows; k++) {
    float shift = 1.5 * (k & 1);
    for (int j = -2; j < cols; j++) {
      roots.add(trapTile(3 * j + shift,         k * TRAP_H,        1, 0, 0));   // up
      roots.add(trapTile(3 * j + 3.5 + shift,  (k + 1) * TRAP_H,  -1, 0, 0));   // down
    }
  }
  return roots;
}

// Build a trapezoid Tile from its canonical placement (p0, e). cx/cy hold the
// SCREEN centroid (canonical centroid (1, H/2)); R approximates the tile size.
Tile trapTile(float p0x, float p0y, float ex, float ey, int depth) {
  float ccx = trapSX(p0x, p0y, ex, ey, 1.0, TRAP_H / 2.0);
  float ccy = trapSY(p0x, p0y, ex, ey, 1.0, TRAP_H / 2.0);
  float side = sqrt(ex * ex + ey * ey) * trapPPU;
  Tile t = new Tile(ccx, ccy, side, 0, 4, depth);
  t.trap = true;
  t.p0x = p0x; t.p0y = p0y; t.ex = ex; t.ey = ey;
  return t;
}

// Canonical point (zx,zy) -> screen X / Y under placement (p0,e). Canonical y is
// up; screen y is down, hence the flip.
float trapSX(float p0x, float p0y, float ex, float ey, float zx, float zy) {
  return (p0x + (zx * ex - zy * ey)) * trapPPU;
}
float trapSY(float p0x, float p0y, float ex, float ey, float zx, float zy) {
  return height - (p0y + (zx * ey + zy * ex)) * trapPPU;
}

// ---- subdivision -----------------------------------------------
boolean canSubdivide(Tile t) {
  return t.depth < maxDepth;   // squares->squares, triangles->triangles, hexagons->6 triangles
}

ArrayList<Tile> children(Tile t) {
  ArrayList<Tile> ch = new ArrayList<Tile>();
  // NB: test t.trap BEFORE t.n -- a trapezoid has n==4 (its polygon vertex count)
  // and would otherwise be caught by the square branch and subdivided as squares.
  if (t.trap) {
    // Split into the 3 equilateral triangles (TRAP_TRIS), transformed from the
    // tile's canonical frame to screen via its (p0,e) placement, then recorded as
    // n==3 tiles -- which recurse with the triangle rep-tile rule below. Whole
    // trapezoids stay the coarse scale; finer detail is triangular (cf. hexagon).
    // The triangles' boundary edges reproduce the trapezoid's exact port lattice,
    // so a whole trapezoid and a subdivided one connect seamlessly.
    for (float[][] tri : TRAP_TRIS) {
      float ax = trapSX(t.p0x, t.p0y, t.ex, t.ey, tri[0][0], tri[0][1]);
      float ay = trapSY(t.p0x, t.p0y, t.ex, t.ey, tri[0][0], tri[0][1]);
      float bx = trapSX(t.p0x, t.p0y, t.ex, t.ey, tri[1][0], tri[1][1]);
      float by = trapSY(t.p0x, t.p0y, t.ex, t.ey, tri[1][0], tri[1][1]);
      float cx = trapSX(t.p0x, t.p0y, t.ex, t.ey, tri[2][0], tri[2][1]);
      float cy = trapSY(t.p0x, t.p0y, t.ex, t.ey, tri[2][0], tri[2][1]);
      Tile tt = triFromVerts(ax, ay, bx, by, cx, cy);
      tt.depth = t.depth + 1;
      ch.add(tt);
    }
  } else if (t.n == 4) {
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

// ---- rendering one tile -----------------------------------------
// A depth level renders in THREE PASSES (see draw() in the main tab):
//   A. drawTileBackground -- polygon fill + bg corner wing discs
//   B. addTileShadow      -- the level's single unioned drop-shadow layer
//   C. drawTileForeground -- bands + fg edge-midpoint wing discs
// so a tile's shadow falls across every same-level background (including the
// neighbours' corner discs that spill onto it) yet stays beneath every
// same-level band, regardless of tile order inside the level. The motif is
// fixed on the Tile (mi/mk, chosen in collectTile), so all passes agree.

// Per-pass geometry of a placed tile. The render passes read it through a shape-
// neutral interface: vx/vy (polygon outline, for bg fill + clip), bgWx/bgWy +
// fgWx/fgWy (background and foreground wing-disc centres), `side` (short-edge
// length -> band stroke side/3, discs side/3 & side/6), `wings`, and appendBands()
// (the band centre-lines). For regular n-gons the wing centres are the vertices
// (bg) and edge midpoints (fg); the trapezoid supplies its own 5 corners + 5 ports.
class TileGeom {
  boolean trap;
  int n; int[][] conns;
  // Morph (one-shot motif cross-dissolve): when non-null, conns is the UNION of the
  // from + to motifs and these give each conn's reveal fraction (1 = full) and the
  // end it grows from. null => no morph for this tile => byte-identical render path.
  float[] connFrac = null;
  int[]   connGrowEnd = null;
  // Per union-conn: the motif it belongs to (mi, mk) + its index within that motif's
  // alphabet -> a stable line-subdiv coin that doesn't flip when the morph commits.
  int[]   connOwnMi = null, connOwnMk = null, connOwnCi = null;
  float[] vx, vy, mx, my;          // polygon vertices + edge midpoints (regular)
  float[] bgWx, bgWy, fgWx, fgWy;  // wing-disc centres (bg corners / fg ports)
  boolean wings;
  float side;
  // multi-anchor (anchorsPerSide = k): k ports per side at (s+0.5)/k along the edge.
  // k = 1 reproduces the classic single-midpoint tile EXACTLY (same code path).
  // Band width / wing radii scale by 1/k (side/(3k), side/(6k)) so a k-anchor edge
  // crosses at the central third of each 1/k sub-segment -- the multi-scale seam
  // generalises (a coarse edge's crossings stay a subset of its children's).
  int   anchors = 1;
  float bandW;                     // band stroke width  = side/(3k)
  float fgR0;                      // fg nub radius       = side/(6k)
  float bgR0;                      // bg corner radius    = side/(3k)
  boolean wholeHex;                // a single-anchor hexagon: the wing-less batched coarse layer
  float cxC, cyC;                  // polygon centre (interior anchor port)
  // trapezoid effective placement (p0,e with animRotOffset folded in about the centroid)
  float tpx, tpy, tex, tey;

  TileGeom(Tile t) {
    trap = t.trap;
    n = t.n;
    if (trap) { initTrap(t); return; }

    anchors = max(1, anchorsPerSide);
    int[][][] alpha = connsFor(n);
    if (alpha == null) { dbg("NULL", "connsFor(" + n + ") null at k=" + anchorsPerSide + " mi=" + t.mi); alpha = BLANK_CONNS; }
    conns = (t.mi >= 0 && t.mi < alpha.length) ? alpha[t.mi] : new int[0][];   // mi = -1 -> blank tile
    // one-shot morph: replace conns with the from+to union (+ per-conn fractions).
    if (morphActive && (t.mi != t.miTo || t.mk != t.mkTo)) {
      int[][] fromC = conns;
      int[][] toRaw = (t.miTo >= 0 && t.miTo < alpha.length) ? alpha[t.miTo] : new int[0][];
      int ds = t.mkTo - t.mk;
      int[][] toC = new int[toRaw.length][];
      for (int i = 0; i < toRaw.length; i++) toC[i] = rotConn(toRaw[i], ds, n, anchors);
      applyMorphUnion(t, fromC, toC, morphLocalMix(t));
    }
    // flip = mirror twin: wind the vertices the other way (and negate the motif
    // rotation), which renders the exact mirror image of the source's motif --
    // edge k of the flipped tile is the reflection of edge k of the source, so
    // the connection list applies unchanged.
    float dir = t.flip ? -1 : 1;
    // motif rotation (chosen in collectTile) + the animation rotation offset
    // (animRotOffset is 0 when animation is off; non-zero spins the whole tile,
    // which BREAKS the seamless cross-tile connection -- expressive, see Animation.pde).
    float rot = t.rot + dir * t.mk * (TWO_PI / n) + dir * animRotOffset;
    vx = new float[n]; vy = new float[n];
    for (int k = 0; k < n; k++) {
      float a = rot + dir * TWO_PI * k / n;
      vx[k] = t.cx + t.R * cos(a);
      vy[k] = t.cy + t.R * sin(a);
    }
    mx = new float[n]; my = new float[n];
    for (int k = 0; k < n; k++) {
      int k2 = (k + 1) % n;
      mx[k] = (vx[k] + vx[k2]) / 2;
      my[k] = (vy[k] + vy[k2]) / 2;
    }
    cxC = 0; cyC = 0;
    for (int k = 0; k < n; k++) { cxC += vx[k]; cyC += vy[k]; }
    cxC /= n; cyC /= n;          // polygon centre (an interior anchor port)
    side = dist(vx[0], vy[0], vx[1], vy[1]);
    // a whole hexagon (the batched, wing-less coarse layer) only exists at k = 1;
    // multi-anchor hexagons are treated like any winged polygon (clip + wings).
    wholeHex = (n == 6 && anchors == 1);
    wings = winged && !wholeHex && !kumikoStyle;   // Kumiko = bare strips, no wing discs
    bandW = side / (3.0 * anchors);
    fgR0  = side / (6.0 * anchors);
    bgR0  = side / (3.0 * anchors);
    if (anchors == 1) {
      bgWx = vx; bgWy = vy;        // bg discs at the vertices (corners)
      fgWx = mx; fgWy = my;        // fg nubs at the edge midpoints
    } else {
      fgWx = new float[n * anchors]; fgWy = new float[n * anchors];
      // bg discs at the k sub-segment BOUNDARIES per edge (i/k for i = 0..k-1):
      // i = 0 is the corner (vertex e); i = 1..k-1 are the points BETWEEN adjacent
      // anchors. With radius side/(3k) they fill the edge gaps between bands, so
      // each 1/k sub-segment reads as a k=1 edge (bg-disc / band / bg-disc) and the
      // discs coincide across a shared edge exactly like the corner discs.
      bgWx = new float[n * anchors]; bgWy = new float[n * anchors];
      for (int e = 0; e < n; e++) {
        int e2 = (e + 1) % n;
        for (int s = 0; s < anchors; s++) {
          int p = e * anchors + s;
          float ta = (s + 0.5) / anchors;       // anchor (fg nub) at (s+0.5)/k
          fgWx[p] = vx[e] + ta * (vx[e2] - vx[e]);
          fgWy[p] = vy[e] + ta * (vy[e2] - vy[e]);
          float tb = (float) s / anchors;       // boundary (bg disc) at s/k
          bgWx[p] = vx[e] + tb * (vx[e2] - vx[e]);
          bgWy[p] = vy[e] + tb * (vy[e2] - vy[e]);
        }
      }
    }
  }

  // Trapezoid: fold animRotOffset (a spin about the canonical centroid Cc) into
  // the effective placement, then transform the canonical vertices/corners/ports.
  // Rotating z about Cc by theta and applying p0 + z*e is the same as a new
  // similarity (p0', e') with e' = e*e^{i*theta} and p0' = p0 + Cc*e - Cc*e'.
  void initTrap(Tile t) {
    conns = (t.mi >= 0 && t.mi < TRAP_CONNS.length) ? TRAP_CONNS[t.mi] : new int[0][];   // mi = -1 -> blank
    if (morphActive && t.mi != t.miTo) {   // trapezoid morph (mk always 0, no relabel)
      int[][] toC = (t.miTo >= 0 && t.miTo < TRAP_CONNS.length) ? TRAP_CONNS[t.miTo] : new int[0][];
      applyMorphUnion(t, conns, toC, morphLocalMix(t));
    }
    anchors = 1; wholeHex = false;       // trapezoid keeps its bespoke 5-port geometry
    float th = animRotOffset;                 // 0 when animation is off -> identity
    float c = cos(th), s = sin(th);
    float epx = t.ex * c - t.ey * s, epy = t.ex * s + t.ey * c;   // e' = e*e^{i th}
    float Ccx = 1.0, Ccy = TRAP_H / 2.0;
    // p0' = p0 + Cc*e - Cc*e'  (complex)
    tpx = t.p0x + (Ccx * t.ex - Ccy * t.ey) - (Ccx * epx - Ccy * epy);
    tpy = t.p0y + (Ccx * t.ey + Ccy * t.ex) - (Ccx * epy + Ccy * epx);
    tex = epx; tey = epy;
    side = sqrt(t.ex * t.ex + t.ey * t.ey) * trapPPU;
    bandW = side / 3.0; fgR0 = side / 6.0; bgR0 = side / 3.0;

    vx = new float[TRAP_V.length];    vy = new float[TRAP_V.length];
    for (int k = 0; k < TRAP_V.length; k++)    { vx[k] = tsx(TRAP_V[k][0], TRAP_V[k][1]);    vy[k] = tsy(TRAP_V[k][0], TRAP_V[k][1]); }
    bgWx = new float[TRAP_CORN.length]; bgWy = new float[TRAP_CORN.length];
    for (int k = 0; k < TRAP_CORN.length; k++) { bgWx[k] = tsx(TRAP_CORN[k][0], TRAP_CORN[k][1]); bgWy[k] = tsy(TRAP_CORN[k][0], TRAP_CORN[k][1]); }
    fgWx = new float[TRAP_PORT.length]; fgWy = new float[TRAP_PORT.length];
    for (int k = 0; k < TRAP_PORT.length; k++) { fgWx[k] = tsx(TRAP_PORT[k][0], TRAP_PORT[k][1]); fgWy[k] = tsy(TRAP_PORT[k][0], TRAP_PORT[k][1]); }
    wings = winged && !kumikoStyle;   // 5 ports is odd -> always need nub caps (unless Kumiko)
  }

  // canonical (zx,zy) -> screen, using the effective placement (incl. anim spin).
  float tsx(float zx, float zy) { return (tpx + (zx * tex - zy * tey)) * trapPPU; }
  float tsy(float zx, float zy) { return height - (tpy + (zx * tey + zy * tex)) * trapPPU; }

  boolean hasBands() { return conns.length > 0; }

  // Append every connection's centre-line to `path` as a subpath. Regular tiles
  // use the edge-pair construction (appendConn); trapezoids use their explicit
  // arc specs (appendTrapConn). Stroked at width side/3 by the caller.
  void appendBands(Path2D.Float path) { appendBandsOffset(path, 0); }

  // Circuit motifs (inline components + point glyphs) are fine linework, so they
  // are stroked at a THIN weight proportional to their feature size -- not the full
  // band width (side/3), which would blob their detail together. They render in a
  // separate path; appendBandsSplit routes them apart from the regular bands.
  boolean thinMotif(int code) { return isInlineComp(code) || isPointGlyph(code); }
  boolean hasThinMotif() { for (int[] cn : conns) if (thinMotif(cn[0])) return true; return false; }
  float motifStrokeW()   { return max(0.75, side / (10.0 * anchors) * animBandScale); }
  // ---- one-shot morph -----------------------------------------------
  // Build the from+to union conn list with a reveal fraction per connection:
  //  persistent (in both) -> 1, departing (from-only) -> 1-mix, arriving (to-only)
  //  -> mix, where mix = smoothstep(morphT). `to` is already relabelled into this
  //  geom's (mk) frame. Sets conns / connFrac / connGrowEnd.
  void applyMorphUnion(Tile t, int[][] fromC, int[][] toC, float mix) {
    ArrayList<int[]> uc = new ArrayList<int[]>();
    ArrayList<Float> uf = new ArrayList<Float>();
    ArrayList<int[]> own = new ArrayList<int[]>();    // {mi, mk, ci} of the owning motif
    for (int ciF = 0; ciF < fromC.length; ciF++) {
      int ciT = indexOfConn(toC, fromC[ciF]);
      uc.add(fromC[ciF]);
      if (ciT >= 0) { uf.add(1.0);       own.add(new int[]{ t.miTo, t.mkTo, ciT }); }  // persistent -> target identity
      else          { uf.add(1.0 - mix); own.add(new int[]{ t.mi,   t.mk,   ciF }); }  // departing  -> source identity
    }
    for (int ciT = 0; ciT < toC.length; ciT++)
      if (indexOfConn(fromC, toC[ciT]) < 0) { uc.add(toC[ciT]); uf.add(mix); own.add(new int[]{ t.miTo, t.mkTo, ciT }); }  // arriving -> target
    conns = uc.toArray(new int[0][]);
    connFrac = new float[uf.size()];
    connOwnMi = new int[uf.size()]; connOwnMk = new int[uf.size()]; connOwnCi = new int[uf.size()];
    for (int i = 0; i < uf.size(); i++) {
      connFrac[i] = uf.get(i);
      connOwnMi[i] = own.get(i)[0]; connOwnMk[i] = own.get(i)[1]; connOwnCi[i] = own.get(i)[2];
    }
    // grow from the end held by a persistent (frac==1) conn, so a new band emerges
    // from surviving structure; departing bands retract toward that same end.
    java.util.HashSet<Integer> anchored = new java.util.HashSet<Integer>();
    for (int i = 0; i < conns.length; i++)
      if (connFrac[i] >= 1 && conns[i][0] < CONN_TAG) { anchored.add(conns[i][0]); anchored.add(conns[i][1]); }
    connGrowEnd = new int[conns.length];
    for (int i = 0; i < conns.length; i++) {
      int[] c = conns[i];
      if (c[0] < CONN_TAG && anchored.contains(c[1]) && !anchored.contains(c[0])) connGrowEnd[i] = 1;
    }
  }
  // Canonical key for set membership: tagged primitives by code + sorted ports,
  // plain pairs by sorted ports + the straight flag (an arc and a straight band
  // between the same ports are different connections).
  String connKey(int[] c) {
    if (c[0] >= CONN_TAG) {
      int[] ps = new int[c.length - 1];
      for (int i = 1; i < c.length; i++) ps[i - 1] = c[i];
      java.util.Arrays.sort(ps);
      StringBuilder sb = new StringBuilder("T" + c[0]);
      for (int p : ps) sb.append('_').append(p);
      return sb.toString();
    }
    int lo = min(c[0], c[1]), hi = max(c[0], c[1]);
    boolean straight = (c.length >= 3 && c[2] == 1);
    return "P" + lo + "_" + hi + (straight ? "s" : "");
  }
  boolean containsConn(int[][] list, int[] c) { return indexOfConn(list, c) >= 0; }
  int indexOfConn(int[][] list, int[] c) {
    String k = connKey(c);
    for (int i = 0; i < list.length; i++) if (connKey(list[i]).equals(k)) return i;
    return -1;
  }

  // Line-mode per-stroke subdiv state for connection ci. Non-morph -> the plain
  // tile/ci hash (byte-identical). Morphing -> keyed on the connection's OWNING motif
  // so it stays consistent through the morph + commit (no thin<->thick flip).
  boolean subdivided(Tile t, int ci) {
    if (connOwnMi == null) return strokeSubdivided(t, ci);
    return strokeSubdividedHash(t, connOwnMi[ci], connOwnMk[ci], connOwnCi[ci]);
  }

  // Split append (offset 0): regular bands -> `bands`, thin circuit motifs -> `thin`.
  void appendBandsSplit(Path2D.Float bands, Path2D.Float thin) {
    if (trap) { appendBands(bands); return; }            // trapezoid has no circuit motifs
    for (int ci = 0; ci < conns.length; ci++)
      appendMotifConnF(thinMotif(conns[ci][0]) ? thin : bands, ci, 0);
  }

  // Append every connection's centre-line, displaced by a constant PERPENDICULAR
  // `offset` (px) -- offset 0 is the centre-line (the solid-band path); line mode
  // calls this once per line in the bundle (see lineOffsets / drawTileBands).
  void appendBandsOffset(Path2D.Float path, float offset) {
    for (int ci = 0; ci < conns.length; ci++) appendOneBand(path, ci, offset);
  }

  // Append a SINGLE connection's centre-line (displaced by `offset`) -- line mode
  // decides per stroke whether to subdivide it into a bundle or draw it full
  // thickness (see drawTileLineBundle / lineSubdivProb), so it appends one at a time.
  void appendOneBand(Path2D.Float path, int ci, float offset) {
    if (trap) appendTrapConnF(path, ci, offset);
    else      appendMotifConnF(path, ci, offset);
  }

  // Append connection ci, truncated to its morph reveal fraction (1 = full = the
  // original verbatim path, so a non-morphing tile is byte-identical).
  void appendMotifConnF(Path2D.Float path, int ci, float offset) {
    float f = (connFrac == null) ? 1 : connFrac[ci];
    if (f >= 1) { appendMotifConn(path, conns[ci], offset); return; }
    if (f <= 0) return;
    Path2D.Float scratch = new Path2D.Float();
    appendMotifConn(scratch, conns[ci], offset);
    appendTruncated(path, scratch, f, connGrowEnd[ci]);
  }
  void appendTrapConnF(Path2D.Float path, int ci, float offset) {
    int[] cn = conns[ci];
    float f = (connFrac == null) ? 1 : connFrac[ci];
    if (f >= 1) { appendTrapConn(path, cn[0], cn[1], offset); return; }
    if (f <= 0) return;
    Path2D.Float scratch = new Path2D.Float();
    appendTrapConn(scratch, cn[0], cn[1], offset);
    appendTruncated(path, scratch, f, connGrowEnd[ci]);
  }

  // Pulse path-tracing: the centre-line of connection ci as a flat polyline
  // [x0,y0,x1,y1,...] (offset 0), or null if it's not a traceable "wire". Wires =
  // plain pairs / straight / hump / inline components (the comet rides the chord of
  // a component, not its zigzag); EXCLUDE dots/rings/terminals/glyphs (decorative
  // marks, no through-conduit). Endpoints equal portXY(pa)/portXY(pb) by
  // construction, so abutting tiles' segments share exact coordinates -> linkable.
  float[] sampleBand(int ci) {
    int[] cn = conns[ci];
    if (!trap) {
      int code = cn[0];
      if (code == CONN_DOT || code == CONN_CIRCLE || isPointGlyph(code)) return null;
      if (isInlineComp(code)) {                       // ride the straight chord A->B
        float[] A = portXY(cn[1]), B = portXY(cn[2]);
        return new float[]{ A[0], A[1], B[0], B[1] };
      }
      // CONN_HUB is a multi-spoke junction (degree>2); skip as a single segment.
      if (code == CONN_HUB) return null;
    }
    Path2D.Float p = new Path2D.Float();
    appendOneBand(p, ci, 0);
    return pathToPolyline(p);
  }

  // Dispatch one (non-trapezoid) connection: a tagged primitive (hub/hump, see
  // TILE_CONNS) or a plain edge pair {i,j}.
  void appendMotifConn(Path2D.Float path, int[] cn, float offset) {
    if (cn[0] == CONN_HUB)  { appendHub(path, cn, n, vx, vy, mx, my, offset); return; }   // k=1 only
    if (cn[0] == CONN_HUMP) { appendHump(path, cn[1], cn[2], mx, my, offset); return; }   // k=1 only
    if (cn[0] == CONN_CIRCLE) {                                                            // a ring at a port
      float[] c = portXY(cn[1]);
      appendCircle(path, c[0], c[1], side / (3.0 * anchors), offset);
      return;
    }
    if (cn[0] == CONN_DOT) return;     // a solid disc -- a filled element, drawn by the fill passes, not stroked
    if (isInlineComp(cn[0])) {         // resistor / inductor / capacitor / stepped between two ports
      float[] A = portXY(cn[1]), B = portXY(cn[2]);
      appendComponent(path, cn[0], A[0], A[1], B[0], B[1], side / (3.5 * anchors), offset);
      return;
    }
    if (cn[0] == CONN_TERM) {          // small open ring (concentric in line mode, like CONN_CIRCLE)
      float[] c = portXY(cn[1]);
      appendCircle(path, c[0], c[1], side / (6.0 * anchors), offset);
      return;
    }
    if (cn[0] == CONN_GROUND || cn[0] == CONN_ARROW || cn[0] == CONN_CROSS) {
      appendGlyph(path, cn[0], cn[1]);  // stroked glyph; ignores offset (drawn once at the centre-line)
      return;
    }
    int pa = cn[0], pb = cn[1];
    // a connection is a straight line when explicitly flagged ([a,b,1]) or when it
    // touches an interior port (centre / apothem midpoint -- no edge line to arc on).
    boolean straight = (cn.length >= 3 && cn[2] == 1) || isInteriorPort(pa) || isInteriorPort(pb);
    if (anchors > 1 || straight) appendPortConn(path, pa, pb, straight, offset);
    else                         appendConn(path, pa, pb, n, vx, vy, mx, my, offset);     // k=1 edge pair (unchanged)
  }

  // Ports: n*k edge anchors, then n apothem midpoints, the centre, then n vertices
  // (corners). isInteriorPort is true for everything past the edge anchors: they
  // share "no single edge line", so their connections are drawn straight -- a vertex
  // (like an apothem midpoint / the centre) has no one edge to arc on. Vertex ports
  // are the Kumiko lattice points (strips run corner -> edge midpoint -> centroid).
  boolean isInteriorPort(int p) { return p >= n * anchors; }
  // Centres of any solid-point (CONN_DOT) motifs -- filled discs (radius side/(6k))
  // drawn by the fill passes (foreground / shadow / extrude), like wing nubs.
  // {x, y, frac} per CONN_DOT (frac = morph reveal, 1 when not morphing). The fill
  // passes scale the disc radius by frac so a dot grows/shrinks with the morph.
  ArrayList<float[]> dotXY() {
    ArrayList<float[]> out = new ArrayList<float[]>();
    if (trap) return out;
    for (int ci = 0; ci < conns.length; ci++) if (conns[ci][0] == CONN_DOT) {
      float[] c = portXY(conns[ci][1]);
      out.add(new float[]{ c[0], c[1], (connFrac == null) ? 1 : connFrac[ci] });
    }
    return out;
  }
  // Screen position of port p: edge anchors (fgWx), then apothem midpoints (centre
  // -> edge midpoint, halfway), then the centre, then the n vertices (corners).
  // (k=1: fgWx == edge midpoints.)
  float[] portXY(int p) {
    int E = n * anchors;
    if (p < E)      return new float[]{ fgWx[p], fgWy[p] };
    if (p < E + n)  { int e = p - E; return new float[]{ (cxC + mx[e]) / 2, (cyC + my[e]) / 2 }; }
    if (p == E + n) return new float[]{ cxC, cyC };
    int v = p - (E + n + 1); return new float[]{ vx[v], vy[v] };   // vertex (corner) port
  }

  // Multi-anchor connection between two ports (port p = edge*k + slot, anchor at
  // (slot+0.5)/k along edge p/k). When both anchors are equidistant from the two
  // edge lines' intersection (all symmetric pairs, incl. every k=1 case) the band
  // is a perpendicular CIRCULAR ARC -- the classic Truchet curve. Otherwise (free
  // pairing of asymmetric anchors, or parallel edges) it is a cubic BEZIER whose
  // end tangents run along the inward edge normals, so it still crosses each edge
  // perpendicular at the anchor (the seamless-connection condition). Sampled into a
  // polyline like appendConn, so every downstream pass (stroke/shadow/extrude) works.
  void appendPortConn(Path2D.Float path, int pa, int pb, boolean straight, float offset) {
    float[] A = portXY(pa), B = portXY(pb);
    float pax = A[0], pay = A[1], pbx = B[0], pby = B[1];
    if (straight) { appendStraight(path, pax, pay, pbx, pby, offset); return; }
    int k = anchors;                                  // here both ports are edge anchors
    int ea = pa / k, eb = pb / k, ea2 = (ea + 1) % n, eb2 = (eb + 1) % n;
    // Scale-invariant parallel test: |sin(angle between edges)|. Decides arc vs
    // bezier from the edge directions, NOT from lineIntersect's tiny-denominator
    // cutoff -- otherwise a near-parallel pair (e.g. opposite edges) flips between
    // bezier and a huge-radius arc under floating-point noise, which broke the
    // mirror match between a tile and its flipped twin.
    float[] C = nearlyParallel(vx[ea], vy[ea], vx[ea2], vy[ea2], vx[eb], vy[eb], vx[eb2], vy[eb2])
                ? null
                : lineIntersect(vx[ea], vy[ea], vx[ea2], vy[ea2], vx[eb], vy[eb], vx[eb2], vy[eb2]);
    if (C != null) {
      float ra = dist(pax, pay, C[0], C[1]), rb = dist(pbx, pby, C[0], C[1]);
      if (ra > 0.1 && abs(ra - rb) <= 1e-3 * max(ra, rb)) {     // equal radii -> arc
        float r = ra * animArcRadius + offset;
        if (r < 0.1) r = 0.1;
        float a0 = atan2(pay - C[1], pax - C[0]);
        float a1 = atan2(pby - C[1], pbx - C[0]);
        float diff = a1 - a0;
        while (diff <= -PI) diff += TWO_PI;
        while (diff > PI)  diff -= TWO_PI;
        diff *= animArcSweep;
        int seg = max(8, ceil(r * abs(diff) / 3.0));
        for (int q = 0; q <= seg; q++) {
          float ph = a0 + diff * q / seg;
          float px = C[0] + r * cos(ph), py = C[1] + r * sin(ph);
          if (q == 0) path.moveTo(px, py); else path.lineTo(px, py);
        }
        return;
      }
    }
    // cubic bezier with tangents along the inward edge normals
    float cxC = 0, cyC = 0;
    for (int q = 0; q < n; q++) { cxC += vx[q]; cyC += vy[q]; }
    cxC /= n; cyC /= n;
    float[] na = inwardNormal(vx[ea], vy[ea], vx[ea2], vy[ea2], pax, pay, cxC, cyC);
    float[] nb = inwardNormal(vx[eb], vy[eb], vx[eb2], vy[eb2], pbx, pby, cxC, cyC);
    float h = 0.42 * dist(pax, pay, pbx, pby);
    float c1x = pax + na[0] * h, c1y = pay + na[1] * h;
    float c2x = pbx + nb[0] * h, c2y = pby + nb[1] * h;
    int seg = max(10, ceil(dist(pax, pay, pbx, pby) / 3.0));
    for (int q = 0; q <= seg; q++) {
      float u = (float) q / seg;
      float bx = bez(pax, c1x, c2x, pbx, u), by = bez(pay, c1y, c2y, pby, u);
      if (offset != 0) {                                   // parallel-curve offset (line mode)
        float tx = bezD(pax, c1x, c2x, pbx, u), ty = bezD(pay, c1y, c2y, pby, u);
        float tl = max(1e-4, sqrt(tx * tx + ty * ty));
        bx += -ty / tl * offset; by += tx / tl * offset;
      }
      if (q == 0) path.moveTo(bx, by); else path.lineTo(bx, by);
    }
  }

  // A point glyph (ground / arrow / cross) stroked at a port, oriented INWARD
  // (port -> tile centre; defaults to screen-up at the centre port). Built in a
  // local frame (u = inward unit, w = perpendicular) and appended as stroked
  // subpaths, so it flows through every pass like a band. Offset is ignored (a
  // glyph is a fixed mark, not a parallel bundle).
  void appendGlyph(Path2D.Float path, int code, int port) {
    float[] P = portXY(port);
    float ux = cxC - P[0], uy = cyC - P[1];
    float L = sqrt(ux * ux + uy * uy);
    if (L < 1e-3) { ux = 0; uy = -1; } else { ux /= L; uy /= L; }   // inward unit
    float wx = -uy, wy = ux;                                        // perpendicular
    float g = side / (6.0 * anchors);                              // base unit (nub radius)
    emitGlyph(path, code, P[0], P[1], ux, uy, wx, wy, g);
  }

  // One trapezoid connection: a circular arc (in canonical coords) sampled into a
  // screen-space polyline. animArcRadius/animArcSweep modulate it exactly as
  // appendConn does for regular tiles (both 1.0 when animation is off).
  void appendTrapConn(Path2D.Float path, int a, int b, float offset) {
    float[] sp = trapArcSpec(a, b);
    // radial offset in canonical units (screen radius = r*side, so px offset/side);
    // a centre on both ports' edge lines makes this a constant perpendicular offset.
    float r  = sp[2] * animArcRadius + offset / max(1e-3, side);
    if (r < 1e-3) r = 1e-3;
    float a0 = radians(sp[3]);
    float diff = (radians(sp[4]) - a0) * animArcSweep;
    int seg = max(8, ceil(r * side * abs(diff) / 3.0));   // r*side = screen arc radius
    for (int k = 0; k <= seg; k++) {
      float ph = a0 + diff * k / seg;
      float zx = sp[0] + r * cos(ph), zy = sp[1] + r * sin(ph);
      float px = tsx(zx, zy), py = tsy(zx, zy);
      if (k == 0) path.moveTo(px, py); else path.lineTo(px, py);
    }
  }
}

// Pass A: the tile's background -- polygon fill, then the background half of
// the wings (bg disc at each vertex, r = side/3, unclipped so it spills).
void drawTileBackground(Tile t, color bg) {
  TileGeom gm = new TileGeom(t);
  // background polygon. Skipped when it would only repaint the canvas colour and
  // could seam against neighbours:
  //  (a) gradient-bg scheme (3): the smooth canvas gradient must show through;
  //  (b) whole hexagons (n==6): a hexagon only ever exists at depth 0, so its bg
  //      always equals the canvas colour -- drawing the opaque polygon lets a
  //      later tile slice a 1px AA seam between overlapping bands at shared edges.
  if (colorScheme != 3 && !gm.wholeHex) {
    noStroke();
    fill(bg);
    beginShape();
    for (int k = 0; k < gm.n; k++) vertex(gm.vx[k], gm.vy[k]);
    endShape(CLOSE);
  }

  // Whole hexagon tiles need no wings (they're a uniform coarse layer); their
  // bands use ROUND caps (see drawTileBands) to overlap across shared edges.
  // (A subdivided hexagon becomes n==3 triangles, which DO get wings.)
  if (gm.wings) {
    // Drawn in the default CENTER ellipseMode using DIAMETERS (2*radius). Do NOT
    // switch to ellipseMode(RADIUS): arc() also honours ellipseMode, so leaving
    // it on RADIUS makes later arc() calls (here and in the next frame) read
    // their diameter args as radii -- doubling the arcs into a chunky mess.
    noStroke();
    fill(bg);                                          // corner discs, r = side/(3k) (* anim)
    float bgD = 2 * gm.bgR0 * animDiscScale;
    for (int k = 0; k < gm.bgWx.length; k++)
      ellipse(gm.bgWx[k], gm.bgWy[k], bgD, bgD);
  }
}

// Pass C: the tile's foreground -- bands as ONE stroked path (see
// drawTileBands), so overlapping bands form a single antialiased shape with no
// 1px seams/cusps between separately-drawn strokes; then the fg half of the
// wings (disc at each edge midpoint, r = side/6 -- structural connection
// points across scales). Square/triangle clip the bands to the polygon (safety
// against wide arcs); hexagon skips the clip so its ROUND-capped bands overlap
// slightly across shared edges.
void drawTileForeground(Tile t, color fg) {
  TileGeom gm = new TileGeom(t);
  if (gm.wholeHex && colorScheme != 2) {
    // whole hexagons (uniform colour): defer the bands into the shared batch
    // path so ALL hexagon bands are stroked once -> no inter-tile seams. Mode 2
    // is per-tile coloured, so it can't batch and falls through to per-tile.
    if (lineMode)
      for (float off : lineOffsets(lineBundleW(gm))) gm.appendBandsOffset(hexBatch, off);
    else
      gm.appendBands(hexBatch);
    hexBatchUsed = true;
    hexBatchFg   = fg;
    hexBatchSide = gm.side;
  } else {
    // Line mode skips the polygon clip: the thin lines stay within the band
    // region anyway, and clipping at the tile edge would slice the round caps
    // back to flat. (Solid bands keep the clip as a safety net for wide arcs.)
    // Kumiko skips the clip too, so thin strips spill across tile edges and meet
    // their neighbours at the shared lattice points (vertices / edge midpoints).
    boolean doClip = !gm.wholeHex && !lineMode && !kumikoStyle;
    java.awt.Shape oldClip = doClip ? pushPolyClip(gm.vx, gm.vy, gm.vx.length) : null;
    drawTileBands(gm, fg);
    if (doClip) popPolyClip(oldClip);
  }

  if (gm.wings) {
    float fgR = gm.fgR0 * animDiscScale;                // fg nub radius
    if (lineMode) {
      // concentric rings at the connection points -> the little target/spiral
      // circles of the parallel-line style. The radii are the SAME offset grid
      // the band lines use (the nub caps a band of width 2*fgR), so a ring of
      // radius |offset_k| passes through that line's edge crossing and -- the line
      // crossing perpendicular to the edge -- is tangent to it there. That shared
      // grid/phase is what makes the rings and lines line up.
      Graphics2D g2 = ((PGraphicsJava2D) g).g2;
      g2.setStroke(new BasicStroke(lineStroke(), BasicStroke.CAP_BUTT, BasicStroke.JOIN_ROUND));
      g2.setPaint(gradientStroke() ? gradPaint : awtColor(fg));
      float minR = linePitch() * 0.25;          // skip the ~0 (centre-line) ring
      for (int k = 0; k < gm.fgWx.length; k++)
        for (float off : lineOffsets(2 * fgR)) {
          if (off <= minR) continue;             // positive half only
          float d = 2 * off;
          g2.draw(new Ellipse2D.Float(gm.fgWx[k] - off, gm.fgWy[k] - off, d, d));
        }
    } else {
      noStroke();
      if (gradientStroke()) {
        for (int k = 0; k < gm.fgWx.length; k++) fillDiscG2(gm.fgWx[k], gm.fgWy[k], fgR);
      } else {
        fill(fg);
        float fgD = 2 * gm.fgR0 * animDiscScale;          // diameter (radius side/(6k) * anim)
        for (int k = 0; k < gm.fgWx.length; k++)
          ellipse(gm.fgWx[k], gm.fgWy[k], fgD, fgD);
      }
    }
  }

  // solid points (CONN_DOT): filled discs of band width at any port, always solid
  // (even in line mode), regardless of wings -- so they work at interior ports too.
  ArrayList<float[]> dots = gm.dotXY();
  if (!dots.isEmpty()) {
    noStroke();
    float r0 = gm.fgR0 * animDiscScale;
    for (float[] p : dots) {
      float r = r0 * p[2];                              // morph: scale radius by reveal frac
      if (r <= 0) continue;
      if (gradientStroke()) fillDiscG2(p[0], p[1], r);
      else { fill(fg); ellipse(p[0], p[1], 2 * r, 2 * r); }
    }
  }
}

// ---- line-mode opaque-ribbon passes ------------------------------
// These split drawTileForeground's line-mode work into three level-wide passes
// (see drawForegroundLevel) so each band reads as an opaque ribbon: rings first,
// an opaque background-coloured ribbon base over them, then the fg line bundle
// last (across all tiles, for continuous hatching). Hexagons (the whole-hex
// coarse layer, scheme != 2) stay transparent and batched, exactly as before.

// Pass 1: the wing nubs at the ports. A port that is an endpoint of a
// full-thickness (solid) stroke gets a SOLID disc (radius side/6), exactly like
// solid mode -- being fg it merges into the opaque stroke that covers it in pass
// 3, so a solid stroke ends in a clean rounded nub instead of a ring. Subdivided
// strokes' ports (and unused ports) keep the concentric rings -- the little
// target/spiral circles. Each port belongs to at most one connection, so the
// solid/subdivided choice per port is unambiguous (see solidPorts).
void drawTileLineRings(Tile t, color fg) {
  TileGeom gm = new TileGeom(t);
  if (!gm.wings) return;
  float fgR = gm.fgR0 * animDiscScale;
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  g2.setStroke(new BasicStroke(lineStroke(), BasicStroke.CAP_BUTT, BasicStroke.JOIN_ROUND));
  g2.setPaint(gradientStroke() ? gradPaint : awtColor(fg));
  boolean[] solidPort = solidPorts(gm, t);
  float minR = linePitch() * 0.25;            // skip the ~0 (centre-line) ring
  for (int k = 0; k < gm.fgWx.length; k++) {
    if (solidPort[k]) {                        // solid stroke endpoint -> solid disc nub
      float dd = 2 * fgR;
      g2.fill(new Ellipse2D.Float(gm.fgWx[k] - fgR, gm.fgWy[k] - fgR, dd, dd));
      continue;
    }
    for (float off : lineOffsets(2 * fgR)) {   // subdivided / unused -> concentric rings
      if (off <= minR) continue;              // positive half only
      float dd = 2 * off;
      g2.draw(new Ellipse2D.Float(gm.fgWx[k] - off, gm.fgWy[k] - off, dd, dd));
    }
  }
}

// Which ports are endpoints of a full-thickness (non-subdivided) stroke -- those
// get a solid disc nub rather than rings (see drawTileLineRings). Indexed like
// gm.fgWx (regular: edge midpoints; trapezoid: TRAP_PORT order), and the
// connection endpoints index into the same array.
boolean[] solidPorts(TileGeom gm, Tile t) {
  boolean[] sp = new boolean[gm.fgWx.length];
  for (int ci = 0; ci < gm.conns.length; ci++)
    if (!gm.subdivided(t, ci)) {
      int[] cn = gm.conns[ci];
      if (cn[0] < sp.length) sp[cn[0]] = true;
      if (cn[1] < sp.length) sp[cn[1]] = true;
    }
  return sp;
}

// Pass 2: the opaque ribbon base -- the solid side/3 band painted in the tile's
// BACKGROUND colour, so it covers the rings under through-bands and any band/band
// overlap. Clipped to the polygon like the solid path (safety for wide arcs), so
// only the half of a port ring that spills into a neighbour survives -- a matched
// neighbour's base covers that too (ring vanishes), an unmatched one leaves it as
// the spiral cap. Whole hexagons (scheme != 2) keep their transparent batched
// bundle, so they are skipped here.
void drawTileRibbonBase(Tile t, color bg) {
  TileGeom gm = new TileGeom(t);
  if (!gm.hasBands()) return;
  if (gm.wholeHex && colorScheme != 2) return;
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  boolean doClip = !gm.wholeHex;
  java.awt.Shape oldClip = doClip ? pushPolyClip(gm.vx, gm.vy, gm.vx.length) : null;
  Path2D.Float path = new Path2D.Float();
  gm.appendBands(path);
  int cap = gm.wholeHex ? BasicStroke.CAP_ROUND : BasicStroke.CAP_BUTT;
  g2.setPaint(awtColor(bg));
  g2.setStroke(new BasicStroke(gm.bandW * animBandScale, cap, BasicStroke.JOIN_ROUND));
  g2.draw(path);
  if (doClip) popPolyClip(oldClip);
}

// Pass 3: the foreground -- per stroke, either the thin parallel/concentric line
// bundle (subdivided) or the original full-thickness side/3 stroke. lineSubdivProb
// is P(subdivided); the choice is a stable hash of the tile+connection (so it
// holds per seed and updates live when the slider moves, no layout rebuild). Drawn
// last so the bundles stay continuous across tile joins; the full-thickness ones,
// being opaque fg, cover the pass-2 ribbon base under them. Whole hexagons defer
// into the shared batch paths exactly as drawTileForeground does.
void drawTileLineBundle(Tile t, color fg) {
  TileGeom gm = new TileGeom(t);
  if (gm.wholeHex && colorScheme != 2) {
    for (int ci = 0; ci < gm.conns.length; ci++)
      if (gm.subdivided(t, ci))
        for (float off : lineOffsets(lineBundleW(gm))) gm.appendOneBand(hexBatch, ci, off);
      else
        gm.appendOneBand(hexSolidBatch, ci, 0);
    hexBatchUsed = true;
    hexBatchFg   = fg;
    hexBatchSide = gm.side;
    return;
  }
  if (!gm.hasBands()) return;
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  Path2D.Float lines = new Path2D.Float();   // subdivided strokes
  Path2D.Float solid = new Path2D.Float();   // full-thickness strokes
  for (int ci = 0; ci < gm.conns.length; ci++) {
    if (gm.subdivided(t, ci))
      for (float off : lineOffsets(lineBundleW(gm))) gm.appendOneBand(lines, ci, off);
    else
      gm.appendOneBand(solid, ci, 0);
  }
  g2.setPaint(gradientStroke() ? gradPaint : awtColor(fg));
  int cap = gm.wholeHex ? BasicStroke.CAP_ROUND : BasicStroke.CAP_BUTT;
  g2.setStroke(bandStroke(gm.bandW, gm.side, cap));
  g2.draw(solid);
  g2.setStroke(new BasicStroke(lineStroke(), BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
  g2.draw(lines);
  // solid points: filled discs on top (paint already fg)
  float dr0 = gm.fgR0 * animDiscScale;
  for (float[] p : gm.dotXY()) { float dr = dr0 * p[2]; if (dr > 0) g2.fill(new Ellipse2D.Float(p[0] - dr, p[1] - dr, 2 * dr, 2 * dr)); }
}

// Stable per-stroke (tile + connection) coin flip: true => subdivide into the
// line bundle, false => draw the original full-thickness stroke. A deterministic
// hash of the tile's identity (so it's fixed per seed and doesn't reshuffle each
// frame or when the slider moves), thresholded by lineSubdivProb. The endpoints
// short-circuit so prob 1 is byte-identical to plain line mode.
boolean strokeSubdivided(Tile t, int ci) { return strokeSubdividedHash(t, t.mi, t.mk, ci); }
// The coin is keyed on the OWNING motif (mi, mk) + the connection's index WITHIN that
// motif. Non-morph passes the tile's own (mi, mk, ci) -> byte-identical to before. A
// morphing tile passes the identity of the motif each connection belongs to (target
// for surviving/arriving conns, source for departing) so the subdiv state is the SAME
// before, during, and after the morph -- no thin<->thick flip when the morph commits.
boolean strokeSubdividedHash(Tile t, int mi, int mk, int ci) {
  if (lineSubdivProb >= 1.0) return true;
  if (lineSubdivProb <= 0.0) return false;
  int h = Float.floatToIntBits(t.cx);
  h = h * 31 + Float.floatToIntBits(t.cy);
  h = h * 31 + t.depth;
  h = h * 31 + mi;
  h = h * 31 + mk;
  h = h * 31 + ci;
  h ^= (h >>> 16); h *= 0x7feb352d; h ^= (h >>> 15); h *= 0x846ca68b; h ^= (h >>> 16);
  return (h & 0x7fffffff) / 2147483647.0 < lineSubdivProb;
}

// ---- drop shadow (pass B) ----------------------------------------
// All casters of one depth level -- band strokes + fg wing nubs, each tile
// offset along shadowAngle by shadowSize * its stroke width (side/3) -- are
// drawn OPAQUE into one offscreen mask, then the mask is composited onto the
// canvas once at shadowStrength. One mask + one composite means abutting and
// overlapping shadows merge seamlessly: no double-darkening where casters
// overlap, and no cuts at tile borders (per-tile clipped shadows read as
// randomly-angled fragments). Translucent black darkens whatever lies beneath
// by the same step in every colour scheme, flat or gradient. Level ordering
// does the rest: the mask lands after the level's backgrounds, beneath its
// bands, and deeper levels paint their own backgrounds over it.
BufferedImage shadowLayer;        // reusable canvas-sized mask

Graphics2D beginShadowLayer() {
  if (shadowLayer == null || shadowLayer.getWidth() != width || shadowLayer.getHeight() != height)
    shadowLayer = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
  Graphics2D sg = shadowLayer.createGraphics();
  sg.setComposite(AlphaComposite.Clear);               // wipe the previous level
  sg.fillRect(0, 0, width, height);
  sg.setComposite(AlphaComposite.SrcOver);
  sg.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
  sg.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);
  sg.setColor(Color.BLACK);
  return sg;
}

void addTileShadow(Graphics2D sg, Tile t) {
  TileGeom gm = new TileGeom(t);
  float off = shadowSize * gm.bandW;
  AffineTransform oldT = sg.getTransform();
  sg.translate(off * cos(shadowAngle), off * sin(shadowAngle));
  if (gm.hasBands()) {
    int cap = gm.wholeHex ? BasicStroke.CAP_ROUND : BasicStroke.CAP_BUTT;
    Path2D.Float bands = new Path2D.Float(), thin = new Path2D.Float();
    gm.appendBandsSplit(bands, thin);
    sg.setStroke(new BasicStroke(gm.bandW * animBandScale, cap, BasicStroke.JOIN_ROUND));
    sg.draw(bands);
    if (gm.hasThinMotif()) {                   // circuit motifs cast a thin shadow, not a band-wide one
      sg.setStroke(new BasicStroke(gm.motifStrokeW(), BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
      sg.draw(thin);
    }
  }
  float r = gm.fgR0 * animDiscScale;
  if (gm.wings)                               // the fg nubs cast shadows too
    for (int k = 0; k < gm.fgWx.length; k++)
      sg.fill(new Ellipse2D.Float(gm.fgWx[k] - r, gm.fgWy[k] - r, 2 * r, 2 * r));
  for (float[] p : gm.dotXY()) {              // solid points cast shadows too
    float rd = r * p[2];                       // morph: scale by reveal frac
    if (rd > 0) sg.fill(new Ellipse2D.Float(p[0] - rd, p[1] - rd, 2 * rd, 2 * rd));
  }
  sg.setTransform(oldT);
}

void compositeShadowLayer(Graphics2D sg) {
  sg.dispose();
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  java.awt.Composite old = g2.getComposite();
  g2.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER,
                                             constrain(shadowStrength, 0, 1)));
  g2.drawImage(shadowLayer, 0, 0, null);
  g2.setComposite(old);
}

// ---- 3D extrusion (graffiti block depth) -------------------------
// The foreground ribbons gain solid side walls extruded toward a vanishing
// point, viewed head-on. One depth LEVEL at a time (called from draw() between
// the all-backgrounds pass and that level's top faces, coarse-first): build the
// level's foreground silhouette (band path + wing nubs) ONCE, then re-draw it as
// many overlapping "slices" stepping toward the VP -- OBLIQUE translates each
// slice in parallel (block); 1-POINT scales each slice about the VP (converging,
// thinner at the back). Every slice is the SAME flat side colour painted into one
// ARGB layer, so the stack unions into one clean wall (same-colour-over-same-
// colour blending leaves no internal seam); the layer is composited once. Drawing
// the silhouette as vector geometry under an AffineTransform (rather than scaling
// a raster) keeps the thin side/3 + side/6 features crisp at every depth.
BufferedImage extrudeLayer;       // reusable canvas-sized body layer

// One flat dark shade of the ribbon colour for every side wall.
color sideColor() { return lerpColor(palettes.current().darkest(), color(0), constrain(extrudeShade, 0, 1)); }
float vpScreenX() { return vpX * width; }
float vpScreenY() { return vpY * height; }

void drawExtrudeLevel(int d) {
  // collect this level's silhouette: all band subpaths + wing-nub discs. Within a
  // level every tile is the same size, so one representative side/n/cap applies.
  Path2D.Float bands = new Path2D.Float();
  Path2D.Float thin  = new Path2D.Float();              // circuit motifs (thin walls)
  ArrayList<float[]> nubs = new ArrayList<float[]>();   // {cx, cy, r}
  float repSide = 0, repBandW = 0; boolean repWholeHex = false; boolean any = false, anyThin = false;
  for (Tile lf : leaves) {
    if (lf.depth != d) continue;
    TileGeom gm = new TileGeom(lf);
    gm.appendBandsSplit(bands, thin);
    if (gm.hasThinMotif()) anyThin = true;
    float r = gm.fgR0 * animDiscScale;
    if (gm.wings)                               // whole-hex tiles have no nubs
      for (int k = 0; k < gm.fgWx.length; k++) nubs.add(new float[]{ gm.fgWx[k], gm.fgWy[k], r });
    for (float[] p : gm.dotXY()) { float rd = r * p[2]; if (rd > 0) nubs.add(new float[]{ p[0], p[1], rd }); }   // solid points extrude too (morph-scaled)
    repSide = gm.side; repBandW = gm.bandW; repWholeHex = gm.wholeHex; any = true;
  }
  if (!any) return;
  float depthPx = extrudeDepth * repSide;       // depth scales with tile size
  if (depthPx < 0.5) return;
  int cap = repWholeHex ? BasicStroke.CAP_ROUND : BasicStroke.CAP_BUTT;

  float bandW  = repBandW * animBandScale;
  float motifW = anyThin ? max(0.75, repSide / (10.0 * anchorsPerSide) * animBandScale) : 0;
  Path2D.Float thinArg = anyThin ? thin : null;
  Graphics2D sg = beginExtrudeLayer();          // cleared, AA on, paint = side colour
  AffineTransform base = sg.getTransform();     // identity

  if (extrudeMode == 0) {                        // OBLIQUE: parallel translate toward the VP
    float dx = vpScreenX() - width / 2.0, dy = vpScreenY() - height / 2.0;
    float dl = max(1e-3, sqrt(dx * dx + dy * dy));
    dx /= dl; dy /= dl;
    int n = constrain(ceil(depthPx / 0.75), 1, 1200);
    for (int s = 0; s <= n; s++) {
      float t = depthPx * s / n;
      sg.setTransform(base);
      sg.translate(dx * t, dy * t);
      stampExtrudeBody(sg, bands, nubs, thinArg, bandW, motifW, cap);
    }
  } else {                                       // 1-POINT: scale each slice about the VP
    float vx = vpScreenX(), vy = vpScreenY();
    float Dc = max(1, dist(width / 2.0, height / 2.0, vx, vy));
    float rBack = constrain(1 - depthPx / Dc, 0.2, 0.98);   // back face shrinks toward VP
    float diag = sqrt(width * (float) width + height * (float) height);
    int n = constrain(ceil((1 - rBack) * (diag + Dc) / 0.75), 1, 1200);
    for (int s = 0; s <= n; s++) {
      float ratio = lerp(1, rBack, (float) s / n);
      AffineTransform at = new AffineTransform(base);
      at.translate(vx, vy); at.scale(ratio, ratio); at.translate(-vx, -vy);
      sg.setTransform(at);                       // also scales the stroke -> thinner at back
      stampExtrudeBody(sg, bands, nubs, thinArg, bandW, motifW, cap);
    }
  }
  sg.setTransform(base);
  compositeExtrudeLayer(sg);
}

// One depth slice of the body: the level's bands + nubs (band width) and, if any,
// the thin circuit motifs (proportional width) -- all in the side colour. The slice
// transform (set by the caller) scales these strokes, so walls converge in 1-point.
void stampExtrudeBody(Graphics2D sg, Path2D.Float bands, ArrayList<float[]> nubs,
                      Path2D.Float thin, float bandW, float motifW, int cap) {
  sg.setStroke(new BasicStroke(bandW, cap, BasicStroke.JOIN_ROUND));
  sg.draw(bands);
  for (float[] nb : nubs)
    sg.fill(new Ellipse2D.Float(nb[0] - nb[2], nb[1] - nb[2], 2 * nb[2], 2 * nb[2]));
  if (thin != null) {
    sg.setStroke(new BasicStroke(motifW, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
    sg.draw(thin);
  }
}

Graphics2D beginExtrudeLayer() {
  if (extrudeLayer == null || extrudeLayer.getWidth() != width || extrudeLayer.getHeight() != height)
    extrudeLayer = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
  Graphics2D sg = extrudeLayer.createGraphics();
  sg.setComposite(AlphaComposite.Clear);
  sg.fillRect(0, 0, width, height);
  sg.setComposite(AlphaComposite.SrcOver);       // slices accumulate opaquely
  sg.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
  sg.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);
  sg.setColor(awtColor(sideColor()));
  return sg;
}

void compositeExtrudeLayer(Graphics2D sg) {
  sg.dispose();
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  java.awt.Composite old = g2.getComposite();
  g2.setComposite(AlphaComposite.SrcOver);        // opaque side walls
  g2.drawImage(extrudeLayer, 0, 0, null);
  g2.setComposite(old);
}

// True when bands should be painted with the canvas-wide gradient (scheme 4),
// so each band's colour varies continuously across the canvas, not per tile.
boolean gradientStroke() {
  if (colorScheme == 4 && gradPaint == null) dbg("NULL", "gradPaint null in scheme 4 (gradient-smooth)");
  return colorScheme == 4 && gradPaint != null;
}

// Draw all of a tile's bands as ONE Java2D stroked path. Stroking a single path
// (with each connection as a subpath) makes the whole motif one antialiased
// shape: overlapping bands union cleanly, with no 1px seams or cusps where
// separately-drawn strokes would meet (their AA edges otherwise leave hairline
// gaps). Solid colour, or the canvas gradient paint in the gradient-smooth scheme.
// The solid-band stroke. Classic: the side/3 band with the caller's cap and a
// ROUND join. Kumiko style: a thin uniform strip (stripWidthFrac * side) with a
// SQUARE cap + MITER join, the sharp woodwork-lattice look. animBandScale is
// applied here so the one identity (off -> width = bandW * scale) stays exact.
BasicStroke bandStroke(float bandW, float side, int cap) {
  if (kumikoStyle)
    return new BasicStroke(max(0.5, stripWidthFrac * side * animBandScale),
                           BasicStroke.CAP_SQUARE, BasicStroke.JOIN_MITER);
  return new BasicStroke(bandW * animBandScale, cap, BasicStroke.JOIN_ROUND);
}

void drawTileBands(TileGeom gm, color fg) {
  if (!gm.hasBands()) return;                 // blank tile
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  // hexagon bands overlap across edges with a ROUND cap (no clip there); square/
  // triangle/trapezoid end flush (CAP_BUTT) and rely on wings to bridge the edge.
  int cap = gm.wholeHex ? BasicStroke.CAP_ROUND : BasicStroke.CAP_BUTT;
  g2.setPaint(gradientStroke() ? gradPaint : awtColor(fg));
  if (lineMode) {                             // bundle of thin parallel/concentric lines
    Path2D.Float lines = new Path2D.Float();
    for (float off : lineOffsets(lineBundleW(gm))) gm.appendBandsOffset(lines, off);
    g2.setStroke(new BasicStroke(lineStroke(), BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
    g2.draw(lines);
    return;
  }
  // Regular bands at band width; circuit motifs at a thin proportional weight.
  Path2D.Float bands = new Path2D.Float(), thin = new Path2D.Float();
  gm.appendBandsSplit(bands, thin);
  g2.setStroke(bandStroke(gm.bandW, gm.side, cap));
  g2.draw(bands);
  if (gm.hasThinMotif()) {
    g2.setStroke(new BasicStroke(gm.motifStrokeW(), BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
    g2.draw(thin);
  }
}

// Stroke all accumulated whole-hexagon bands as ONE shape (uniform colour), so
// overlapping bands of separate hexagons union with no 1px seams. Hexagons use a
// ROUND cap and no clip (bands overlap across edges). Called from draw() after
// the depth-0 pass, before finer (triangle) tiles draw on top.
void strokeHexBatch() {
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  float hw = lineMode ? lineStroke() : hexBatchSide / 3.0 * animBandScale;   // bundle already in hexBatch
  g2.setPaint(gradientStroke() ? gradPaint : awtColor(hexBatchFg));
  // line mode: full-thickness strokes that opted out of subdivision, stroked at side/3.
  if (lineMode) {
    g2.setStroke(new BasicStroke(hexBatchSide / 3.0 * animBandScale, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
    g2.draw(hexSolidBatch);
  }
  if (lineMode) g2.setStroke(new BasicStroke(hw, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
  else          g2.setStroke(bandStroke(hexBatchSide / 3.0, hexBatchSide, BasicStroke.CAP_ROUND));
  g2.draw(hexBatch);
}

// Append one connection to the path as a subpath: a straight band for opposite
// edges, else the circular arc (centre = intersection of the two edge lines)
// sampled into a polyline fine enough (~3px/segment) to read as smooth.
void appendConn(Path2D.Float path, int i, int j, int n,
                float[] vx, float[] vy, float[] mx, float[] my, float offset) {
  int d = min(abs(i - j), n - abs(i - j));
  if (n % 2 == 0 && d == n / 2) {             // opposite -> straight band (perp. offset)
    appendStraight(path, mx[i], my[i], mx[j], my[j], offset);
    return;
  }
  float[] c = lineIntersect(vx[i], vy[i], vx[(i + 1) % n], vy[(i + 1) % n],
                            vx[j], vy[j], vx[(j + 1) % n], vy[(j + 1) % n]);
  if (c == null) { appendStraight(path, mx[i], my[i], mx[j], my[j], offset); return; }
  // a constant radial offset == a constant perpendicular offset of the arc, so line
  // bundles of abutting tiles stay aligned along the shared edge.
  float r  = dist(mx[i], my[i], c[0], c[1]) * animArcRadius + offset;
  if (r < 0.1) r = 0.1;
  float a0 = atan2(my[i] - c[1], mx[i] - c[0]);
  float a1 = atan2(my[j] - c[1], mx[j] - c[0]);
  float diff = a1 - a0;                        // shorter signed sweep -> interior arc
  while (diff <= -PI) diff += TWO_PI;
  while (diff > PI)  diff -= TWO_PI;
  diff *= animArcSweep;                         // anim: grow/shrink sweep (both 1.0 when off)
  int seg = max(8, ceil(r * abs(diff) / 3.0));
  for (int k = 0; k <= seg; k++) {
    float ph = a0 + diff * k / seg;
    float px = c[0] + r * cos(ph), py = c[1] + r * sin(ph);
    if (k == 0) path.moveTo(px, py); else path.lineTo(px, py);
  }
}

// A centre-spoke junction: a straight band from the tile CENTRE (centroid of the
// vertices) to each listed edge midpoint. A 3-spoke hub renders as a T/Y, the
// spokes union at the centre into one clean shape. Each spoke enters its edge
// perpendicular at the central third, so the tile stays seamless and multi-scale-
// safe (2 spokes = a band, 4 = the CrossCross +). `cn` = { CONN_HUB, e0, e1, ... }.
void appendHub(Path2D.Float path, int[] cn, int n,
               float[] vx, float[] vy, float[] mx, float[] my, float offset) {
  float cx = 0, cy = 0;
  for (int k = 0; k < n; k++) { cx += vx[k]; cy += vy[k]; }
  cx /= n; cy /= n;
  for (int s = 1; s < cn.length; s++) {
    int e = cn[s];
    appendStraight(path, cx, cy, mx[e], my[e], offset);   // reuse perpendicular-offset helper
  }
}

// An opposite-edge connection drawn as a hump/arch instead of a straight band:
// a raised cosine from midpoint i to midpoint j, bulging toward the perpendicular
// side. The raised cosine has ZERO slope at both ends, so the band enters each
// edge horizontally (perpendicular) at the central third -- seamless, like a
// straight band, but arched. Bulge = 0.30*chord keeps the stroke inside the tile.
void appendHump(Path2D.Float path, int i, int j,
                float[] mx, float[] my, float offset) {
  float ax = mx[i], ay = my[i], bx = mx[j], by = my[j];
  float dx = bx - ax, dy = by - ay;
  float dl = max(1e-6, sqrt(dx * dx + dy * dy));
  float nx = dy / dl, ny = -dx / dl;          // perpendicular (W->E gives (0,-1) = up = N)
  float bulge = dl * 0.30;
  int seg = max(12, ceil(dl / 3.0));
  for (int k = 0; k <= seg; k++) {
    float t = (float) k / seg;
    float h = bulge * (1 - cos(TWO_PI * t)) / 2.0;   // 0 at ends, bulge at middle, flat tangents
    float px = ax + dx * t + nx * (h + offset);
    float py = ay + dy * t + ny * (h + offset);
    if (k == 0) path.moveTo(px, py); else path.lineTo(px, py);
  }
}

// ---- circuit-inspired primitives --------------------------------
// An inline component (resistor / inductor / capacitor / stepped) between ports
// A and B: straight leads + a motif in the middle, amplitude `amp` (perpendicular).
// The motif is authored in a unit frame -- {sFrac (0..1 along A->B), d (px perp),
// moveFlag?} -- then mapped to screen with `offset` folded into the perpendicular,
// so the line-mode bundle becomes parallel copies (like a band).
void appendComponent(Path2D.Float path, int code,
                     float ax, float ay, float bx, float by, float amp, float offset) {
  float dx = bx - ax, dy = by - ay;
  float L  = max(1e-6, sqrt(dx * dx + dy * dy));
  float ux = dx / L, uy = dy / L, wx = -uy, wy = ux;     // along, perpendicular
  float[][] sd = componentSD(code, amp);
  boolean started = false;
  for (float[] p : sd) {
    float s = p[0] * L, d = p[1] + offset;
    float px = ax + ux * s + wx * d, py = ay + uy * s + wy * d;
    if (!started || (p.length > 2 && p[2] == 1)) { path.moveTo(px, py); started = true; }
    else path.lineTo(px, py);
  }
}

// The unit-frame polyline of an inline component. Rows: {sFrac, dPx} or
// {sFrac, dPx, 1} where the trailing 1 starts a new subpath (capacitor plates).
float[][] componentSD(int code, float a) {
  if (code == CONN_RES)                                  // resistor: sawtooth zigzag
    return new float[][]{ {0,0},{0.30,0},{0.35,a},{0.45,-a},{0.55,a},{0.65,-a},{0.70,0},{1,0} };
  if (code == CONN_STEP)                                 // stepped: square-wave crenellation (right angles)
    return new float[][]{ {0,0},{0.2,0},{0.2,a},{0.4,a},{0.4,0},{0.6,0},{0.6,a},{0.8,a},{0.8,0},{1,0} };
  if (code == CONN_CAP)                                  // capacitor: leads + two perpendicular plates, gap between
    return new float[][]{ {0,0},{0.44,0}, {0.44,-a,1},{0.44,a}, {0.56,-a,1},{0.56,a}, {0.56,0,1},{1,0} };
  // CONN_IND: inductor -- straight leads + 3 semicircular bumps (same side) over [0.25,0.75]
  ArrayList<float[]> pts = new ArrayList<float[]>();
  pts.add(new float[]{0,0}); pts.add(new float[]{0.25,0});
  int nb = 3; float s0 = 0.25, w = 0.5 / nb;
  for (int b = 0; b < nb; b++)
    for (int q = 1; q <= 8; q++) { float t = q / 8.0; pts.add(new float[]{ s0 + w * (b + t), a * sin(PI * t) }); }
  pts.add(new float[]{1,0});
  return pts.toArray(new float[0][]);
}

// Stroke a point glyph (ground / arrow / cross) into `path`, in the inward-oriented
// local frame (u = inward unit, w = perpendicular) centred at (px,py), base unit g.
void emitGlyph(Path2D.Float path, int code, float px, float py,
               float ux, float uy, float wx, float wy, float g) {
  if (code == CONN_GROUND) {                             // stem + 3 decreasing bars
    glyphSeg(path, px,py,ux,uy,wx,wy, 0,0,        1.4*g,0);
    glyphSeg(path, px,py,ux,uy,wx,wy, 1.4*g,-1.4*g, 1.4*g,1.4*g);
    glyphSeg(path, px,py,ux,uy,wx,wy, 2.0*g,-0.9*g, 2.0*g,0.9*g);
    glyphSeg(path, px,py,ux,uy,wx,wy, 2.6*g,-0.45*g,2.6*g,0.45*g);
  } else if (code == CONN_ARROW) {                       // shaft + inward chevron
    glyphSeg(path, px,py,ux,uy,wx,wy, 0,0, 1.7*g,0);
    glyphPt(path, px,py,ux,uy,wx,wy, 0.9*g,-g, true);
    glyphPt(path, px,py,ux,uy,wx,wy, 1.7*g,0,  false);
    glyphPt(path, px,py,ux,uy,wx,wy, 0.9*g,g,  false);
  } else if (code == CONN_CROSS) {                       // plus centred on the port
    glyphSeg(path, px,py,ux,uy,wx,wy, -g,0, g,0);
    glyphSeg(path, px,py,ux,uy,wx,wy, 0,-g, 0,g);
  }
}
// One local-frame segment (s = along inward u, t = along perpendicular w).
void glyphSeg(Path2D.Float path, float px, float py, float ux, float uy, float wx, float wy,
              float s0, float t0, float s1, float t1) {
  path.moveTo(px + ux*s0 + wx*t0, py + uy*s0 + wy*t0);
  path.lineTo(px + ux*s1 + wx*t1, py + uy*s1 + wy*t1);
}
void glyphPt(Path2D.Float path, float px, float py, float ux, float uy, float wx, float wy,
             float s, float t, boolean move) {
  float x = px + ux*s + wx*t, y = py + uy*s + wy*t;
  if (move) path.moveTo(x, y); else path.lineTo(x, y);
}

// A straight band centre-line (ax,ay)->(bx,by), displaced perpendicular by `offset`.
void appendStraight(Path2D.Float path, float ax, float ay, float bx, float by, float offset) {
  if (offset != 0) {
    float dx = bx - ax, dy = by - ay;
    float dl = max(1e-6, sqrt(dx * dx + dy * dy));
    float nx = -dy / dl * offset, ny = dx / dl * offset;   // unit normal * offset
    ax += nx; ay += ny; bx += nx; by += ny;
  }
  path.moveTo(ax, ay); path.lineTo(bx, by);
}

// A ring centred at (cx,cy), centre-line radius r, as a closed circular subpath
// (stroked at band width by the caller). `offset` shifts the radius, so line mode's
// offset bundle becomes concentric rings (the target-circle look); offsets that
// shrink the radius past ~0 are skipped.
void appendCircle(Path2D.Float path, float cx, float cy, float r, float offset) {
  float rr = (r * animArcRadius) + offset;
  if (rr < 0.1) return;
  int seg = max(16, ceil(TWO_PI * rr / 3.0));
  for (int q = 0; q <= seg; q++) {
    float a = TWO_PI * q / seg;
    float px = cx + rr * cos(a), py = cy + rr * sin(a);
    if (q == 0) path.moveTo(px, py); else path.lineTo(px, py);
  }
  path.closePath();
}

// ---- morph helpers ------------------------------------------------
// Relabel a connection's ports by `ds` edge-steps, so a TO motif (authored in its
// own mk frame) is expressed in the FROM tile's mk frame for the union/diff. Every
// port slot of every conn shape (plain pair, hub, hump, component, single-port
// primitive) is shifted; the trailing straight flag stays.
int[] rotConn(int[] c, int ds, int n, int k) {
  if (ds == 0) return c;
  int[] r = c.clone();
  if (c[0] >= CONN_TAG) {
    if (c[0] == CONN_HUB) { for (int i = 1; i < c.length; i++) r[i] = rotPortFull(c[i], ds, n, k); }
    else if (c[0] == CONN_HUMP || isInlineComp(c[0])) { r[1] = rotPortFull(c[1], ds, n, k); r[2] = rotPortFull(c[2], ds, n, k); }
    else { r[1] = rotPortFull(c[1], ds, n, k); }   // single-port: circle/dot/term/ground/arrow/cross
  } else {
    r[0] = rotPortFull(c[0], ds, n, k);
    r[1] = rotPortFull(c[1], ds, n, k);
  }
  return r;
}
// rotPort extended to vertex (corner / Kumiko) ports, which a plain rotPort leaves
// fixed. Edge anchors + apothem mids spin via rotPort; the centre is fixed; a vertex
// follows its corner under the rotation.
int rotPortFull(int p, int ds, int n, int k) {
  int E = n * k;
  int m = ((ds % n) + n) % n;
  if (p < E + n) return rotPort(p, m, n, k);     // edge anchors + apothem midpoints
  if (p == E + n) return p;                       // centre (fixed)
  int v = p - (E + n + 1); return E + n + 1 + ((v + m) % n);   // vertex (corner)
}

// Append `src` to `dst`, but with each subpath truncated to a leading `frac`
// (0<frac<1) of its own arc-length -- a connection growing along its path. growEnd
// 0 grows from the subpath start, 1 from its end (so a band grows from its anchored
// port). frac>=1 is handled by the caller (verbatim, byte-identical).
void appendTruncated(Path2D.Float dst, Path2D.Float src, float frac, int growEnd) {
  java.awt.geom.PathIterator it = src.getPathIterator(null);
  float[] co = new float[6];
  ArrayList<float[]> sub = new ArrayList<float[]>();
  while (!it.isDone()) {
    int type = it.currentSegment(co);
    if (type == java.awt.geom.PathIterator.SEG_MOVETO) {
      if (!sub.isEmpty()) { emitTrunc(dst, sub, frac, growEnd); sub = new ArrayList<float[]>(); }
      sub.add(new float[]{ co[0], co[1] });
    } else if (type == java.awt.geom.PathIterator.SEG_LINETO) {
      sub.add(new float[]{ co[0], co[1] });
    }
    // SEG_CLOSE: the closing edge is already represented (appendCircle repeats the
    // first point at q==seg), so a truncated ring is just a leading open arc.
    it.next();
  }
  if (!sub.isEmpty()) emitTrunc(dst, sub, frac, growEnd);
}
void emitTrunc(Path2D.Float dst, ArrayList<float[]> pts, float frac, int growEnd) {
  int m = pts.size();
  if (m < 2) return;
  if (growEnd == 1) java.util.Collections.reverse(pts);
  float total = 0;
  for (int i = 1; i < m; i++) total += dist(pts.get(i-1)[0], pts.get(i-1)[1], pts.get(i)[0], pts.get(i)[1]);
  float target = total * frac;
  dst.moveTo(pts.get(0)[0], pts.get(0)[1]);
  float acc = 0;
  for (int i = 1; i < m; i++) {
    float[] a = pts.get(i-1), b = pts.get(i);
    float seg = dist(a[0], a[1], b[0], b[1]);
    if (acc + seg >= target) {
      float u = (target - acc) / max(1e-6, seg);
      dst.lineTo(a[0] + (b[0]-a[0]) * u, a[1] + (b[1]-a[1]) * u);
      return;
    }
    dst.lineTo(b[0], b[1]); acc += seg;
  }
}

// cubic Bezier value + derivative at u (for multi-anchor connections).
float bez(float p0, float p1, float p2, float p3, float u) {
  float v = 1 - u;
  return v*v*v*p0 + 3*v*v*u*p1 + 3*v*u*u*p2 + u*u*u*p3;
}
float bezD(float p0, float p1, float p2, float p3, float u) {
  float v = 1 - u;
  return 3*v*v*(p1-p0) + 6*v*u*(p2-p1) + 3*u*u*(p3-p2);
}

// True when two edges are within ~0.06 deg of parallel (|sin| < 1e-3), so a
// multi-anchor connection across them is a bezier, not a (huge-radius) arc. Uses
// the normalized direction cross product -> scale-invariant and FP-stable, so a
// tile and its flipped twin always agree on the branch (see appendPortConn).
boolean nearlyParallel(float ax, float ay, float bx, float by,
                       float cx, float cy, float dx2, float dy2) {
  float ux = bx - ax, uy = by - ay, vx2 = dx2 - cx, vy2 = dy2 - cy;
  float lu = sqrt(ux*ux + uy*uy), lv = sqrt(vx2*vx2 + vy2*vy2);
  if (lu < 1e-6 || lv < 1e-6) return true;
  return abs(ux*vy2 - uy*vx2) / (lu*lv) < 1e-3;
}

// Unit normal of edge (ax,ay)->(bx,by), pointing INWARD (toward the tile centre
// (cx,cy)) -- the band's tangent at an anchor (px,py) on that edge.
float[] inwardNormal(float ax, float ay, float bx, float by,
                     float px, float py, float cx, float cy) {
  float dx = bx - ax, dy = by - ay;
  float dl = max(1e-6, sqrt(dx*dx + dy*dy));
  float nx = -dy / dl, ny = dx / dl;
  if (nx * (cx - px) + ny * (cy - py) < 0) { nx = -nx; ny = -ny; }
  return new float[]{ nx, ny };
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
  if (total <= 0) return -1;          // no archetype has any weight -> a blank tile
  float r = random(total);
  for (int t = 0; t < w.length; t++) {
    r -= w[t];
    if (r < 0) return t;
  }
  return w.length - 1;
}
