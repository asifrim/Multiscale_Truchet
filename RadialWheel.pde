// ============================================================
//  RadialWheel.pde — fast exact per-pixel radial wheel Paint
//
//  A custom java.awt.Paint for the animated radial gradient-wheel (schemes 5/6
//  with gradRadial). Java2D's RadialGradientPaint bakes the colour stops into a LUT
//  it must rebuild every frame as the phase shifts (its cell boundaries jump → a
//  faint wobble); the linear wheel avoids that by sliding a fixed LUT geometrically.
//  This Paint stays exact + smooth AND fast (the live loop runs at animFrameRate, so
//  a slow paint = dropped frames / stutter, not a bad still frame). Three things make
//  it cheap:
//    1. The colour wheel LUT (colour-by-fraction) is cached once per palette in
//       `wheelLUT` — Java2D calls createContext per fill/stroke and the foreground
//       issues thousands of them, so it must NOT be rebuilt per primitive.
//    2. Each Paint precomputes a **distance²→colour LUT** with the phase baked in
//       (one sqrt per LUT entry, ~8k, instead of one sqrt per pixel, millions). The
//       phase is a smooth resampling of the cached wheel, so motion stays smooth and
//       the d² bins are fixed in space → no rebuild-boundary wobble.
//    3. getRaster walks each row with the inverse transform inlined and d² advanced
//       by the quadratic's second difference (two adds per pixel, no per-pixel sqrt
//       or multiply), then a single clamped table lookup → packed-ARGB write.
//  As a Paint, every fill/stroke site (background, ribbons, wing nubs/discs) uses it
//  unchanged via g2.setPaint().
// ============================================================

class RadialWheelPaint implements java.awt.Paint {
  final double cx, cy, scale;     // centre (user px) and d² → LUT-index factor
  final int[] d2lut;              // distance²-index → packed RGB at this phase
  static final int N2 = 8192;     // d² LUT resolution

  RadialWheelPaint(float cx, float cy, float radius, float phase, int[] wheelLUT) {
    this.cx = cx; this.cy = cy;
    double r = max(1e-3, radius);
    this.scale = (N2 - 1) / (r * r);                 // d² in [0, r²] → index in [0, N2-1]
    // d²-index k ↔ distance d = r·sqrt(k/(N2-1)) → wheel fraction = sqrt(k/(N2-1)) + phase
    // (independent of r), looked up in the cached colour wheel. One sqrt per entry.
    int[] L = new int[N2];
    int wn = wheelLUT.length, wmask = wn - 1;
    float inv = 1.0 / (N2 - 1);
    for (int k = 0; k < N2; k++) {
      float frac = (float) Math.sqrt(k * inv) + phase;
      frac -= (int) frac;                            // wrap to [0,1) (frac >= 0)
      L[k] = wheelLUT[(int) (frac * wn) & wmask];
    }
    this.d2lut = L;
  }

  public int getTransparency() { return java.awt.Transparency.OPAQUE; }
  public java.awt.PaintContext createContext(java.awt.image.ColorModel cm,
      java.awt.Rectangle deviceBounds, java.awt.geom.Rectangle2D userBounds,
      java.awt.geom.AffineTransform xform, java.awt.RenderingHints hints) {
    return new RadialWheelContext(cx, cy, scale, d2lut, xform);
  }
}

class RadialWheelContext implements java.awt.PaintContext {
  final double cx, cy, scale;
  final int[] d2lut; final int n2m1;
  final double m00, m01, m02, m10, m11, m12;        // inverse device→user affine
  final java.awt.image.ColorModel cm = java.awt.image.ColorModel.getRGBdefault();  // packed INT_ARGB

  RadialWheelContext(double cx, double cy, double scale, int[] d2lut,
                     java.awt.geom.AffineTransform xform) {
    this.cx = cx; this.cy = cy; this.scale = scale; this.d2lut = d2lut; this.n2m1 = d2lut.length - 1;
    java.awt.geom.AffineTransform inv;
    try { inv = xform.createInverse(); }
    catch (Exception e) { inv = new java.awt.geom.AffineTransform(); }
    m00 = inv.getScaleX(); m01 = inv.getShearX(); m02 = inv.getTranslateX();
    m10 = inv.getShearY(); m11 = inv.getScaleY(); m12 = inv.getTranslateY();
  }

  public void dispose() {}
  public java.awt.image.ColorModel getColorModel() { return cm; }

  // One tile. d²(i) along a row is quadratic in the column i, so it is advanced by its
  // second difference: two adds per pixel, no sqrt, no per-pixel transform multiply.
  public java.awt.image.Raster getRaster(int x, int y, int w, int h) {
    java.awt.image.WritableRaster raster = cm.createCompatibleWritableRaster(w, h);
    int[] px = ((java.awt.image.DataBufferInt) raster.getDataBuffer()).getData();
    double sx = m00, sy = m10;                        // user step per +1 device-x
    double acc = 2 * (sx * sx + sy * sy);             // second difference of d² (constant)
    double sc = scale; int hi = n2m1; int[] L = d2lut;
    for (int j = 0; j < h; j++) {
      double dx0 = x + 0.5, dy0 = y + j + 0.5;
      double ux = m00 * dx0 + m01 * dy0 + m02 - cx;   // user coords rel. centre, column 0
      double uy = m10 * dx0 + m11 * dy0 + m12 - cy;
      double g = ux * ux + uy * uy;                    // d² at column 0
      double delta = 2 * (ux * sx + uy * sy) + (sx * sx + sy * sy);   // d²(1) - d²(0)
      int row = j * w;
      for (int i = 0; i < w; i++) {
        int idx = (int) (g * sc);
        if (idx < 0) idx = 0; else if (idx > hi) idx = hi;
        px[row + i] = 0xFF000000 | L[idx];
        g += delta; delta += acc;                      // step d² to the next pixel
      }
    }
    return raster;
  }
}
