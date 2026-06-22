// Metal.pde -- SDF-based metallic shading for the foreground "ink".
//
// A flat 2D Truchet shape has no surface normal, so any metallic look must SYNTHESISE
// one. The matcap attempt assumed a half-tube (every ribbon a cylinder), which read as
// rubber tubes. The fix is a better normal model driven by a signed distance field of
// the whole ink region (so thin ribbons and the big inverted "flats" are treated the
// same): a FLAT metal top with a narrow chamfered edge.
//
// Pipeline (all plain Java2D + a per-pixel loop -- no OpenGL/GLSL, no external assets):
//   1. buildInkMask()   -- render the duotone figure/ground in 1-bit (ink vs paper),
//                          coarse-first, AA on (the AA coverage doubles as the edge alpha).
//   2. edtSquared()     -- exact Euclidean distance transform (Felzenszwalb &
//                          Huttenlocher, separable) -> distance-to-edge per ink pixel.
//   3. shadeMetalLayer()-- per pixel derive a normal from the SDF (round-bevel or
//                          flat-rim), shade it as metal (Blinn-Phong + 2-stop environment
//                          reflection + Fresnel), write ARGB (AA coverage as alpha).
//   4. drawMetalTiling()-- composite the metal layer over the paper canvas.
//
// Render-only; off => byte-identical (gated behind `if (metalMode)` in renderTiling).

import java.awt.image.BufferedImage;

// ---- globals (declared here; global to the merged PApplet) --------------
boolean metalMode      = false;   // master toggle
int     metalMaterial  = 0;       // index into metalMats[]
int     metalBevelStyle = 0;      // 0 = round-bevel (flat top + chamfer), 1 = flat-rim
float   metalBevelPx   = 10;      // bevel/rim width in px at 1080p (scaled by resolution)
float   metalLightDeg  = 118;     // light azimuth (degrees), rotates the key light in-plane

// One metal material: albedo + a 2-stop environment (sky/ground) it reflects + a
// specular exponent. `metal` tints the (dominant) environment reflection by the base
// colour; a dielectric would show a diffuse body instead (kept for future presets).
class MetalMat {
  String  name;
  float[] base, sky, gnd;
  float   shin;
  boolean metal;
  MetalMat(String n, float[] b, float[] s, float[] g, float sh, boolean m) {
    name = n; base = b; sky = s; gnd = g; shin = sh; metal = m;
  }
}
MetalMat[] metalMats;

void buildMetalMats() {
  metalMats = new MetalMat[] {
    new MetalMat("gold",   new float[]{1.00, 0.78, 0.34}, new float[]{1.00, 0.93, 0.72}, new float[]{0.22, 0.15, 0.05}, 60, true),
    new MetalMat("chrome", new float[]{0.85, 0.87, 0.90}, new float[]{0.95, 0.97, 1.00}, new float[]{0.10, 0.12, 0.18}, 90, true),
    new MetalMat("copper", new float[]{0.95, 0.55, 0.35}, new float[]{1.00, 0.80, 0.62}, new float[]{0.20, 0.07, 0.03}, 55, true),
    new MetalMat("steel",  new float[]{0.60, 0.63, 0.68}, new float[]{0.82, 0.85, 0.92}, new float[]{0.12, 0.14, 0.18}, 45, true),
    new MetalMat("brass",  new float[]{0.88, 0.72, 0.38}, new float[]{0.98, 0.90, 0.66}, new float[]{0.18, 0.13, 0.05}, 50, true)
  };
}
void ensureMetalMats() { if (metalMats == null) buildMetalMats(); }
MetalMat activeMetal() { ensureMetalMats(); return metalMats[constrain(metalMaterial, 0, metalMats.length - 1)]; }
String metalMatName()  { return activeMetal().name; }
int parseMetalMat(String tok) {
  ensureMetalMats();
  try { return constrain(Integer.parseInt(tok), 0, metalMats.length - 1); } catch (NumberFormatException e) { }
  for (int i = 0; i < metalMats.length; i++) if (metalMats[i].name.equalsIgnoreCase(tok)) return i;
  return 0;
}

// Is this tile an "inverted" duotone level -- the dark ink is its BACKGROUND mass, not
// its ribbons? Then the ink mask fills the polygon and carves the bands out as paper.
// Only duotone has the ink/paper duality; other schemes treat the foreground as ink.
boolean tileInkInverted(Tile t) {
  return colorScheme == 0 && invertPerLevel && (t.depth % 2 == 1);
}

// ---- reusable buffers ----------------------------------------------------
BufferedImage metalMaskBuf;       // 1-bit-ish ink mask (AA grayscale: coverage = alpha)
BufferedImage metalLayerBuf;      // shaded metal ARGB

// Entry point (from renderTiling when metalMode is on). The canvas already holds the
// paper background (background(canvasBgColor()) ran in draw()), so we only build + shade
// + composite the metal ink on top. The carved paper channels of inverted tiles simply
// stay transparent in the layer and reveal the paper beneath.
void drawMetalTiling() {
  int W = width, H = height;
  int[] cov = buildInkMask(W, H);                  // 0..255 AA coverage of the ink
  boolean[] ink = new boolean[W * H];
  for (int i = 0; i < W * H; i++) ink[i] = cov[i] >= 128;
  float[] d2 = edtSquared(ink, W, H);              // squared distance to nearest paper
  int[] out = shadeMetalLayer(ink, d2, cov, W, H);

  if (metalLayerBuf == null || metalLayerBuf.getWidth() != W || metalLayerBuf.getHeight() != H)
    metalLayerBuf = new BufferedImage(W, H, BufferedImage.TYPE_INT_ARGB);
  metalLayerBuf.setRGB(0, 0, W, H, out, 0, W);
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  java.awt.Composite old = g2.getComposite();
  g2.setComposite(AlphaComposite.SrcOver);
  g2.drawImage(metalLayerBuf, 0, 0, null);
  g2.setComposite(old);
}

// Render the duotone figure/ground in grayscale (ink = white, paper = black), coarse-
// first (backgrounds then foregrounds per level), AA ON so the white coverage at the
// silhouette gives a clean anti-aliased edge alpha. Returns the coverage [0..255].
int[] buildInkMask(int W, int H) {
  if (metalMaskBuf == null || metalMaskBuf.getWidth() != W || metalMaskBuf.getHeight() != H)
    metalMaskBuf = new BufferedImage(W, H, BufferedImage.TYPE_INT_ARGB);
  Graphics2D mg = metalMaskBuf.createGraphics();
  mg.setComposite(AlphaComposite.Src);
  mg.setColor(new Color(0, 0, 0, 255));            // start all paper (black, opaque)
  mg.fillRect(0, 0, W, H);
  mg.setComposite(AlphaComposite.SrcOver);
  mg.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
  mg.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);
  Color INK = new Color(255, 255, 255), PAPER = new Color(0, 0, 0);

  for (int d = 0; d <= maxDepth; d++) {
    for (Tile lf : leaves) if (lf.depth == d) maskTileBg(mg, lf, INK, PAPER);
    for (Tile lf : leaves) if (lf.depth == d) maskTileFg(mg, lf, INK, PAPER);
  }
  mg.dispose();

  int[] argb = metalMaskBuf.getRGB(0, 0, W, H, null, 0, W);
  for (int i = 0; i < argb.length; i++) argb[i] = argb[i] & 0xFF;   // any channel = coverage
  return argb;
}

// Background mass: ink (white) on inverted levels, else paper (black). Includes the bg
// corner discs (the wings), which on inverted tiles are part of the metal.
void maskTileBg(Graphics2D mg, Tile t, Color INK, Color PAPER) {
  TileGeom gm = new TileGeom(t);
  boolean inkBg = tileInkInverted(t);
  mg.setColor(inkBg ? INK : PAPER);
  Path2D.Float poly = new Path2D.Float();
  poly.moveTo(gm.vx[0], gm.vy[0]);
  for (int k = 1; k < gm.vx.length; k++) poly.lineTo(gm.vx[k], gm.vy[k]);
  poly.closePath();
  mg.fill(poly);
  if (gm.wings) {
    float br = gm.bgR0 * animDiscScale;
    for (int k = 0; k < gm.bgWx.length; k++)
      mg.fill(new Ellipse2D.Float(gm.bgWx[k] - br, gm.bgWy[k] - br, 2 * br, 2 * br));
  }
}

// Ribbons + fg nubs + solid dots: ink (white) on normal levels (and all non-duotone
// schemes), paper (black) on inverted levels (carving channels out of the metal mass).
void maskTileFg(Graphics2D mg, Tile t, Color INK, Color PAPER) {
  TileGeom gm = new TileGeom(t);
  Color c = tileInkInverted(t) ? PAPER : INK;
  mg.setColor(c);
  if (gm.hasBands()) {
    int cap = gm.wholeHex ? BasicStroke.CAP_ROUND : BasicStroke.CAP_BUTT;
    Path2D.Float bands = new Path2D.Float(), thin = new Path2D.Float();
    gm.appendBandsSplit(bands, thin);
    mg.setStroke(new BasicStroke(gm.bandW * animBandScale, cap, BasicStroke.JOIN_ROUND));
    mg.draw(bands);
    if (gm.hasThinMotif()) { mg.setStroke(new BasicStroke(gm.motifStrokeW(), BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND)); mg.draw(thin); }
  }
  float fr = gm.fgR0 * animDiscScale;
  if (gm.wings)
    for (int k = 0; k < gm.fgWx.length; k++)
      mg.fill(new Ellipse2D.Float(gm.fgWx[k] - fr, gm.fgWy[k] - fr, 2 * fr, 2 * fr));
  for (float[] p : gm.dotXY())
    mg.fill(new Ellipse2D.Float(p[0] - fr, p[1] - fr, 2 * fr, 2 * fr));
}

// ---- exact Euclidean distance transform (Felzenszwalb & Huttenlocher) ----
// Returns squared distance from each pixel to the nearest PAPER pixel (0 at paper, and
// the squared distance-to-edge inside the ink). Separable: 1D transform down columns,
// then across rows.
float[] edtSquared(boolean[] ink, int W, int H) {
  final float INF = 1e20;
  float[] g = new float[W * H];
  for (int i = 0; i < g.length; i++) g[i] = ink[i] ? INF : 0;
  int maxd = max(W, H);
  float[] f = new float[maxd], d = new float[maxd], z = new float[maxd + 1];
  int[] v = new int[maxd];
  for (int x = 0; x < W; x++) {                    // columns
    for (int y = 0; y < H; y++) f[y] = g[y * W + x];
    edt1d(f, d, v, z, H);
    for (int y = 0; y < H; y++) g[y * W + x] = d[y];
  }
  for (int y = 0; y < H; y++) {                    // rows
    int row = y * W;
    for (int x = 0; x < W; x++) f[x] = g[row + x];
    edt1d(f, d, v, z, W);
    for (int x = 0; x < W; x++) g[row + x] = d[x];
  }
  return g;
}

// 1D squared distance transform of the sampled function f[0..n-1] -> d.
void edt1d(float[] f, float[] d, int[] v, float[] z, int n) {
  final float INF = 1e20;
  int k = 0;
  v[0] = 0; z[0] = -INF; z[1] = INF;
  for (int q = 1; q < n; q++) {
    float s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k]);
    while (s <= z[k]) {
      k--;
      s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2.0 * q - 2.0 * v[k]);
    }
    k++; v[k] = q; z[k] = s; z[k + 1] = INF;
  }
  k = 0;
  for (int q = 0; q < n; q++) {
    while (z[k + 1] < q) k++;
    int dq = q - v[k];
    d[q] = dq * dq + f[v[k]];
  }
}

// Per-pixel metal shading. Normal from the SDF: a unit "outward" direction (gradient of
// the smoothed distance) tilted up by an angle that depends on distance-to-edge --
// round-bevel = flat top, tilt only within the bevel; flat-rim = flat everywhere + a
// bright specular rim at the very edge. Output ARGB with the AA coverage as alpha.
int[] shadeMetalLayer(boolean[] ink, float[] d2, int[] cov, int W, int H) {
  MetalMat m = activeMetal();
  float bevel = max(1.0, metalBevelPx * (H / 1080.0));   // resolution-independent width
  float maxTilt = radians(68);
  // key light
  float th = radians(metalLightDeg);
  float lx = cos(th) * 0.62, ly = sin(th) * 0.62, lz = 0.78;
  float ll = sqrt(lx * lx + ly * ly + lz * lz); lx /= ll; ly /= ll; lz /= ll;
  float hx = lx, hy = ly, hz = lz + 1; float hl = sqrt(hx * hx + hy * hy + hz * hz); hx /= hl; hy /= hl; hz /= hl;

  float[] dist = new float[W * H];                 // distance (px), lightly smoothed
  for (int i = 0; i < dist.length; i++) dist[i] = sqrt(d2[i]);
  float[] sm = boxBlur(dist, W, H);                // tame stair-step on curved edges

  int[] out = new int[W * H];
  boolean flatRim = (metalBevelStyle == 1);
  float rimW = max(2.0, bevel * 0.6);              // flat-rim highlight width (scales w/ bevel/res)
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      int i = y * W + x;
      if (!ink[i]) { out[i] = 0; continue; }       // paper -> transparent
      // gradient of the smoothed distance (central differences); outward = -gradient
      int xm = x > 0 ? i - 1 : i, xp = x < W - 1 ? i + 1 : i;
      int ym = y > 0 ? i - W : i, yp = y < H - 1 ? i + W : i;
      float gx = (sm[xp] - sm[xm]) * 0.5, gy = (sm[yp] - sm[ym]) * 0.5;
      float gl = sqrt(gx * gx + gy * gy);
      float ox = 0, oy = 0;
      if (gl > 1e-4) { ox = -gx / gl; oy = -gy / gl; }

      float ang;
      if (flatRim) ang = 0;
      else         ang = (1.0 - constrain(dist[i] / bevel, 0, 1)) * maxTilt;
      float s = sin(ang);
      float nx = ox * s, ny = oy * s, nz = cos(ang);

      int rgb = shadeMetalPixel(m, nx, ny, nz, lx, ly, lz, hx, hy, hz);
      if (flatRim) {                               // bright bevelled rim at the edge
        float rim = constrain(1.0 - dist[i] / rimW, 0, 1);
        if (rim > 0) rgb = addWhite(rgb, rim * rim * 0.9);   // eased -> a crisp bright lip
      }
      int a = constrain(cov[i], 0, 255);
      out[i] = (a << 24) | rgb;
    }
  }
  return out;
}

// Blinn-Phong + 2-stop environment reflection + Fresnel for one normal. Returns 0xRRGGBB.
int shadeMetalPixel(MetalMat m, float nx, float ny, float nz,
                    float lx, float ly, float lz, float hx, float hy, float hz) {
  float diff = max(0, nx * lx + ny * ly + nz * lz);
  float spec = pow(max(0, nx * hx + ny * hy + nz * hz), m.shin);
  float fres = pow(1 - nz, 3);
  float envt = constrain((2 * nz * ny) * 0.5 + 0.5, 0, 1);
  float er = lerp(m.gnd[0], m.sky[0], envt), eg = lerp(m.gnd[1], m.sky[1], envt), eb = lerp(m.gnd[2], m.sky[2], envt);
  float r, gg, b;
  if (m.metal) {
    r = 0.85 * er * m.base[0] + 0.12 * m.base[0] + 0.10 * diff * m.base[0];
    gg = 0.85 * eg * m.base[1] + 0.12 * m.base[1] + 0.10 * diff * m.base[1];
    b = 0.85 * eb * m.base[2] + 0.12 * m.base[2] + 0.10 * diff * m.base[2];
  } else {
    r = (0.2 + 0.8 * diff) * m.base[0]; gg = (0.2 + 0.8 * diff) * m.base[1]; b = (0.2 + 0.8 * diff) * m.base[2];
  }
  r += 0.85 * spec + 0.30 * fres; gg += 0.85 * spec + 0.30 * fres; b += 0.85 * spec + 0.30 * fres;
  int ri = round(constrain(r, 0, 1) * 255), gi = round(constrain(gg, 0, 1) * 255), bi = round(constrain(b, 0, 1) * 255);
  return (ri << 16) | (gi << 8) | bi;
}

int addWhite(int rgb, float amt) {
  int r = min(255, round(((rgb >> 16) & 0xFF) + amt * 255));
  int g = min(255, round(((rgb >> 8) & 0xFF) + amt * 255));
  int b = min(255, round((rgb & 0xFF) + amt * 255));
  return (r << 16) | (g << 8) | b;
}

// 3x3 box blur of a float field (one pass) -- smooths the SDF so curved-edge normals
// don't stair-step. Edge-clamped.
float[] boxBlur(float[] a, int W, int H) {
  float[] o = new float[W * H];
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++) {
      float s = 0; int n = 0;
      for (int dy = -1; dy <= 1; dy++) {
        int yy = y + dy; if (yy < 0 || yy >= H) continue;
        for (int dx = -1; dx <= 1; dx++) {
          int xx = x + dx; if (xx < 0 || xx >= W) continue;
          s += a[yy * W + xx]; n++;
        }
      }
      o[y * W + x] = s / n;
    }
  }
  return o;
}
