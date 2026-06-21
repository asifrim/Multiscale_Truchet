// ============================================================
//  TileWindow.pde — a third window listing the tile archetypes of the
//  active shape, each with a slider for its selection weight.
//
//  Like ControlWindow, this is its own PApplet launched from the main
//  sketch's setup() with PApplet.runSketch(); it holds a `parent`
//  reference. It reads the active shape's archetype set (parent.connsFor)
//  and edits that shape's weight array in place (parent.weightsFor) --
//  the same arrays pickWeighted() draws from -- then calls parent.redraw().
//
//  "Archetype" = one base tile (a connection set), NOT its rotations: the
//  generator applies a random rotation when it places the tile, so only the
//  distinct connection sets are listed here.
// ============================================================

public class TileWindow extends PApplet {
  Multiscale_Truchet parent;

  final int   margin = 14;
  final int   cols   = 2;       // archetypes laid out in a grid (more fit on screen)
  final int   rowH   = 54;      // small rows so many archetypes are visible at once
  final int   tileSz = 40;
  final float WMAX   = 8.0;     // slider maps weight 0..WMAX
  final int   y0     = 110;     // first row centre (clears header + tileset selector)
  int   activeRow = -1;

  // "Reload tiles.json" button (top-right of the header) -- re-reads the catalog so
  // tiles authored in the editor appear without restarting the visualizer.
  final int   reW = 132, reH = 24, reY = 10;
  float reX() { return width - margin - reW; }
  boolean reloadHot = false;

  // "Reset weights" button (left of Reload): zero every weight in the active set.
  final int   rsW = 110, rsH = 24, rsY = 10;
  float rsX() { return reX() - 8 - rsW; }
  boolean resetHot = false;

  // small per-tile "s" (solo) button between the tile preview and its slider.
  final int   soloSz = 18;
  float soloX(int col) { return cellX(col) + tileSz + 6; }

  // tileset selector strip: prev/next the active tileset for the current (shape, k).
  final int   selY = 60, selH = 26, navW = 30;
  float prevX() { return margin; }
  float nextX() { return margin + navW + 4; }
  boolean prevHot = false, nextHot = false;
  boolean hitNav(float x) { return mouseX >= x && mouseX <= x + navW && mouseY >= selY && mouseY <= selY + selH; }

  TileWindow(Multiscale_Truchet parent) { this.parent = parent; }

  public void settings() { size(640, 940); }   // big panel; small dense rows in 2 columns

  public void setup() {
    surface.setTitle("Truchet — Tiles");
  }

  // per-column geometry: a cell is [tile][slider track][value]
  float colW()         { return (width - 2 * margin) / (float) cols; }
  float cellX(int col) { return margin + col * colW(); }
  float tileCX(int col){ return cellX(col) + tileSz / 2.0 + 4; }
  float trkX0(int col) { return cellX(col) + tileSz + 32; }   // leaves room for the solo "s" button
  float trkX1(int col) { return cellX(col) + colW() - 30; }

  public void draw() {
   try {
    background(38);
    boolean isTrap = parent.shapeMode == 3;
    int     n    = parent.SHAPE_N[parent.shapeMode];
    int[][][] arch = isTrap ? parent.TRAP_CONNS : parent.connsFor(n);
    float[] w    = isTrap ? parent.TRAP_W       : parent.weightsFor(n);

    textAlign(LEFT, CENTER);
    fill(235); textSize(15);
    text(parent.SHAPE_NAMES[parent.shapeMode] + " tile archetypes (" + arch.length + ")", margin, 22);
    fill(150); textSize(11);
    text("drag a slider to set how often each is chosen", margin, 42);

    // reload-catalog button
    fill(reloadHot ? color(82) : color(60)); stroke(110); strokeWeight(1);
    rect(reX(), reY, reW, reH, 5); noStroke();
    fill(230); textAlign(CENTER, CENTER); textSize(12);
    text("Reload tiles.json", reX() + reW / 2.0, reY + reH / 2.0);
    textAlign(LEFT, CENTER);

    // reset-weights button (zeros every weight in the active set)
    fill(resetHot ? color(82) : color(60)); stroke(110); strokeWeight(1);
    rect(rsX(), rsY, rsW, rsH, 5); noStroke();
    fill(230); textAlign(CENTER, CENTER); textSize(12);
    text("Reset weights", rsX() + rsW / 2.0, rsY + rsH / 2.0);
    textAlign(LEFT, CENTER);

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
    text(lbl, nextX() + navW + 12, selY + selH / 2.0);

    for (int i = 0; i < arch.length; i++) {
      int col = i % cols, row = i / cols;
      float cy = y0 + row * rowH;
      float cx = tileCX(col);
      if (isTrap) drawTrapArchetype(arch[i], cx, cy, tileSz);
      else        drawArchetype(arch[i], n, cx, cy, tileSz);

      // weight slider
      float x0 = trkX0(col), x1 = trkX1(col);
      stroke(90); strokeWeight(2);
      line(x0, cy, x1, cy);
      noStroke();
      float kx = lerp(x0, x1, constrain(w[i] / WMAX, 0, 1));
      fill(i == activeRow ? color(255, 200, 0) : color(120, 180, 255));
      ellipse(kx, cy, 12, 12);
      fill(170); textSize(10); textAlign(LEFT, CENTER);
      text(nf(w[i], 0, 1), x1 + 6, cy);

      // solo "s" button: set this tile's weight to 1, all others to 0
      float sx = soloX(col), sy = cy - soloSz / 2.0;
      boolean sHot = mouseX >= sx && mouseX <= sx + soloSz && mouseY >= sy && mouseY <= sy + soloSz;
      fill(sHot ? color(255, 200, 0) : color(70, 110, 160)); stroke(110); strokeWeight(1);
      rect(sx, sy, soloSz, soloSz, 3); noStroke();
      fill(sHot ? 30 : 230); textAlign(CENTER, CENTER); textSize(11);
      text("s", sx + soloSz / 2.0, cy);
      textAlign(LEFT, CENTER);
    }
   } catch (Throwable e) { parent.dbgCrash(e); }   // attribute a Tiles-thread crash
  }

  // One prev/next nav button for the tileset selector (greyed when disabled).
  void drawNav(float x, String s, boolean hot, boolean enabled) {
    fill(enabled ? (hot ? color(82) : color(60)) : color(46));
    stroke(enabled ? 110 : 70); strokeWeight(1);
    rect(x, selY, navW, selH, 5); noStroke();
    fill(enabled ? 230 : 110); textAlign(CENTER, CENTER); textSize(14);
    text(s, x + navW / 2.0, selY + selH / 2.0 - 1);
    textAlign(LEFT, CENTER);
  }

  // Draw one archetype (its connection set) as a small tile preview, using a
  // fixed light/dark scheme so the SHAPE reads clearly regardless of palette.
  // Winged shapes (square/triangle, not whole hexagons) also draw their wings --
  // the bg-colour corner discs (r = side/3) and fg-colour edge-midpoint nubs
  // (r = side/6) -- so the preview matches the canvas tile. Winged previews are
  // drawn a bit smaller so the unclipped corner discs stay within the row.
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
    // reload-catalog button: re-read tiles.json on the viz thread (via a flag, like
    // the Controls Save button) and rebuild, so newly authored tiles appear live.
    if (mouseX >= reX() && mouseX <= reX() + reW && mouseY >= reY && mouseY <= reY + reH) {
      parent.logAction("TILE reload-catalog");   // prime race suspect: re-reads tiles.json
      parent.reloadCatalogRequested = true;
      parent.redraw();
      return;
    }
    // reset-weights button: zero every weight in the active set
    if (mouseX >= rsX() && mouseX <= rsX() + rsW && mouseY >= rsY && mouseY <= rsY + rsH) {
      resetWeights();
      return;
    }
    // tileset prev/next (current shape + k)
    if (parent.shapeMode != 3 && parent.tilesetCount() > 1) {
      if (hitNav(prevX())) { parent.setActiveTileset(-1); parent.redraw(); return; }
      if (hitNav(nextX())) { parent.setActiveTileset(+1); parent.redraw(); return; }
    }
    int count = (parent.shapeMode == 3 ? parent.TRAP_CONNS
                                       : parent.connsFor(parent.SHAPE_N[parent.shapeMode])).length;
    // solo buttons (checked before the slider, since the "s" button overlaps the
    // slider's left hit margin): set this tile's weight to 1, all others to 0.
    for (int i = 0; i < count; i++) {
      int col = i % cols, row = i / cols;
      float cy = y0 + row * rowH, sx = soloX(col), sy = cy - soloSz / 2.0;
      if (mouseX >= sx && mouseX <= sx + soloSz && mouseY >= sy && mouseY <= sy + soloSz) {
        soloTile(i);
        return;
      }
    }
    for (int i = 0; i < count; i++) {
      int col = i % cols, row = i / cols;
      float cy = y0 + row * rowH;
      if (abs(mouseY - cy) < rowH / 2 - 2 && mouseX > trkX0(col) - 14 && mouseX < trkX1(col) + 26) {
        activeRow = i;
        setWeight(i);
        return;
      }
    }
  }

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

  public void mouseDragged() { if (activeRow >= 0) setWeight(activeRow); }
  public void mouseReleased() { activeRow = -1; }
  public void mouseMoved() {
    reloadHot = mouseX >= reX() && mouseX <= reX() + reW && mouseY >= reY && mouseY <= reY + reH;
    resetHot  = mouseX >= rsX() && mouseX <= rsX() + rsW && mouseY >= rsY && mouseY <= rsY + rsH;
    prevHot   = hitNav(prevX());
    nextHot   = hitNav(nextX());
  }

  void setWeight(int i) {
    int col = i % cols;
    float t = constrain((mouseX - trkX0(col)) / (trkX1(col) - trkX0(col)), 0, 1);
    float[] w = (parent.shapeMode == 3) ? parent.TRAP_W
                                        : parent.weightsFor(parent.SHAPE_N[parent.shapeMode]);
    w[i] = t * WMAX;
    parent.logAction("TILE weight[" + i + "] = " + nf(w[i], 0, 2));
    parent.dirtyLayout = true;   // weights drive the motif roll in collectTile -> rebuild
    parent.redraw();
  }
}
