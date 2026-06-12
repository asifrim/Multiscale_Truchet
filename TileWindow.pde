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

  final int   margin = 16;
  final int   rowH   = 84;
  final int   tileSz = 62;
  final float WMAX   = 8.0;     // slider maps weight 0..WMAX
  final int   y0     = 100;     // first row centre (clears the two header lines)
  float trackX0, trackX1;
  int   activeRow = -1;

  TileWindow(Multiscale_Truchet parent) { this.parent = parent; }

  public void settings() { size(380, 600); }

  public void setup() {
    surface.setTitle("Truchet — Tiles");
    trackX0 = margin + tileSz + 26;
    trackX1 = width - margin - 34;
  }

  public void draw() {
    background(38);
    int     n    = parent.SHAPE_N[parent.shapeMode];
    int[][][] arch = parent.connsFor(n);
    float[] w    = parent.weightsFor(n);

    textAlign(LEFT, CENTER);
    fill(235); textSize(15);
    text(parent.SHAPE_NAMES[parent.shapeMode] + " tile archetypes", margin, 24);
    fill(150); textSize(11);
    text("drag a slider to set how often each is chosen", margin, 44);

    for (int i = 0; i < arch.length; i++) {
      float cy = y0 + i * rowH;
      drawArchetype(arch[i], n, margin + tileSz / 2.0, cy, tileSz);

      // weight slider
      stroke(90); strokeWeight(3);
      line(trackX0, cy, trackX1, cy);
      noStroke();
      float kx = lerp(trackX0, trackX1, constrain(w[i] / WMAX, 0, 1));
      fill(i == activeRow ? color(255, 200, 0) : color(120, 180, 255));
      ellipse(kx, cy, 16, 16);
      fill(170); textSize(11); textAlign(LEFT, CENTER);
      text(nf(w[i], 0, 1), trackX1 + 8, cy);
    }
  }

  // Draw one archetype (its connection set) as a small tile preview, using a
  // fixed light/dark scheme so the SHAPE reads clearly regardless of palette.
  void drawArchetype(int[][] conns, int n, float ccx, float ccy, float sz) {
    float R   = sz * 0.46;
    float rot = (n == 4) ? QUARTER_PI : -HALF_PI;   // square axis-aligned; tri/hex point up
    float[] vx = new float[n], vy = new float[n];
    for (int k = 0; k < n; k++) {
      float a = rot + TWO_PI * k / n;
      vx[k] = ccx + R * cos(a);
      vy[k] = ccy + R * sin(a);
    }
    float[] mx = new float[n], my = new float[n];
    for (int k = 0; k < n; k++) {
      int k2 = (k + 1) % n;
      mx[k] = (vx[k] + vx[k2]) / 2;
      my[k] = (vy[k] + vy[k2]) / 2;
    }
    float side = dist(vx[0], vy[0], vx[1], vy[1]);

    // tile background
    noStroke();
    fill(230);
    beginShape();
    for (int k = 0; k < n; k++) vertex(vx[k], vy[k]);
    endShape(CLOSE);

    // bands (same construction as Shapes.pde: opposite -> line, else arc)
    stroke(35);
    strokeWeight(side / 3.0);
    strokeCap(n == 6 ? ROUND : SQUARE);
    noFill();
    for (int[] c : conns) {
      int i = c[0], j = c[1], d = min(abs(i - j), n - abs(i - j));
      if (n % 2 == 0 && d == n / 2) { line(mx[i], my[i], mx[j], my[j]); continue; }
      float[] cc = parent.lineIntersect(vx[i], vy[i], vx[(i + 1) % n], vy[(i + 1) % n],
                                        vx[j], vy[j], vx[(j + 1) % n], vy[(j + 1) % n]);
      if (cc == null) { line(mx[i], my[i], mx[j], my[j]); continue; }
      float r  = dist(mx[i], my[i], cc[0], cc[1]);
      float a0 = atan2(my[i] - cc[1], mx[i] - cc[0]);
      float a1 = atan2(my[j] - cc[1], mx[j] - cc[0]);
      float diff = a1 - a0;
      while (diff <= -PI) diff += TWO_PI;
      while (diff > PI)  diff -= TWO_PI;
      arc(cc[0], cc[1], 2 * r, 2 * r, diff >= 0 ? a0 : a0 + diff, diff >= 0 ? a0 + diff : a0);
    }

    // faint tile outline
    noFill();
    stroke(95);
    strokeWeight(1);
    beginShape();
    for (int k = 0; k < n; k++) vertex(vx[k], vy[k]);
    endShape(CLOSE);
  }

  // ---- interaction ----
  public void mousePressed() {
    int rows = parent.connsFor(parent.SHAPE_N[parent.shapeMode]).length;
    for (int i = 0; i < rows; i++) {
      float cy = y0 + i * rowH;
      if (abs(mouseY - cy) < 18 && mouseX > trackX0 - 18 && mouseX < trackX1 + 18) {
        activeRow = i;
        setWeight(i);
        return;
      }
    }
  }

  public void mouseDragged() { if (activeRow >= 0) setWeight(activeRow); }
  public void mouseReleased() { activeRow = -1; }

  void setWeight(int i) {
    float t = constrain((mouseX - trackX0) / (trackX1 - trackX0), 0, 1);
    parent.weightsFor(parent.SHAPE_N[parent.shapeMode])[i] = t * WMAX;
    parent.redraw();
  }
}
