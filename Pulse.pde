// ============================================================
//  Pulse.pde — animated "light pulse" flowing along the connection paths.
//
//  The tiling's bands form continuous curves across tiles + scale levels (the
//  thirds invariant makes abutting/coarse-fine band ends share EXACT screen
//  coordinates). This builds a graph from those shared endpoints, traces the
//  connected chains/loops, and animates a comet (bright head + fading trail)
//  along each path -- like energy through an energized circuit.
//
//  It is a pure OVERLAY: never touches `leaves`, never sets dirtyLayout. The
//  path graph is built from the NEUTRAL (animation-off) geometry and cached;
//  only the comet position + glow layer recompute per frame, from the
//  deterministic clock `animSeconds`. Composited before applySymmetry() so the
//  pixel-mirror modes reflect the comets too.
// ============================================================

// ---- tunables (render params; no layout rebuild) --------------------------
boolean pulseEnabled = false;     // toggle (Controls Anim tab / TRUCHET_PULSE)
boolean headlessPulse = false;    // TRUCHET_PULSE forces build+draw before leaves exist
float   pulseSpeed = 0;           // px/sec; <=0 => default ~width*0.16
float   pulseTrail = 0;           // px comet trail; <=0 => default min(160,0.12*width)
int     pulseCount = 0;           // 0 = all paths; else the N longest
int     pulseColorMode = 2;       // 0 palette-bright, 1 white-hot, 2 complementary accent
boolean dirtyPaths = true;        // rebuild the path graph next frame

final float PULSE_QUANT = 0.35;   // endpoint match tolerance (px) -- sub-pixel: shared
                                  // crossings are the SAME computed point, not just close
final float PULSE_STEP  = 2.0;    // arc-length resample spacing (px)

// ---- the traced paths (cached; rebuilt only on layout change) -------------
class PulsePath {
  float[] x, y, s, w;   // resampled points + cumulative arc length + LOCAL band width
  float len;            // total arc length
  boolean closed;       // loop (seamless wrap) vs open chain (fade at ends)
  float bandW;          // representative band width (fallback)
  float phase;          // staggered start offset (arc length)
}
ArrayList<PulsePath> pulsePaths = new ArrayList<PulsePath>();

// transient build records
class PulseSeg { float[] pts; int a, b; float bandW; boolean used; }

BufferedImage glowLayer;          // reusable canvas-size overlay (like shadowLayer)

// ---------------------------------------------------------------------------
// Flatten a Path2D into [x0,y0,x1,y1,...] (single-subpath wire connections).
float[] pathToPolyline(Path2D.Float p) {
  ArrayList<Float> out = new ArrayList<Float>();
  java.awt.geom.PathIterator it = p.getPathIterator(null);
  float[] c = new float[6];
  while (!it.isDone()) {
    int t = it.currentSegment(c);
    if (t == java.awt.geom.PathIterator.SEG_MOVETO || t == java.awt.geom.PathIterator.SEG_LINETO) {
      out.add(c[0]); out.add(c[1]);
    }
    it.next();
  }
  float[] arr = new float[out.size()];
  for (int i = 0; i < arr.length; i++) arr[i] = out.get(i);
  return arr;
}

// ---- build the path graph -------------------------------------------------
// Endpoint spatial hash: bucket (size PULSE_QUANT) -> node ids; snap a query to an
// existing node within PULSE_QUANT (probing the 3x3 neighbourhood to dodge the
// bucket-boundary split). Coords come from the same portXY/sampler math on both
// sides of an edge, so a sub-pixel tolerance merges shared crossings exactly.
HashMap<Long,ArrayList<Integer>> pnBuckets;
ArrayList<float[]> pnPos;

long pnKey(int qx, int qy) { return (((long) qx) << 32) ^ (qy & 0xffffffffL); }

int pnNodeFor(float x, float y) {
  int qx = round(x / PULSE_QUANT), qy = round(y / PULSE_QUANT);
  for (int dx = -1; dx <= 1; dx++) for (int dy = -1; dy <= 1; dy++) {
    ArrayList<Integer> b = pnBuckets.get(pnKey(qx + dx, qy + dy));
    if (b == null) continue;
    for (int id : b) {
      float[] p = pnPos.get(id);
      if (dist(p[0], p[1], x, y) <= PULSE_QUANT) return id;
    }
  }
  int id = pnPos.size();
  pnPos.add(new float[]{ x, y });
  long k = pnKey(qx, qy);
  ArrayList<Integer> b = pnBuckets.get(k);
  if (b == null) { b = new ArrayList<Integer>(); pnBuckets.put(k, b); }
  b.add(id);
  return id;
}

void rebuildPulsePaths() {
  pulsePaths = new ArrayList<PulsePath>();
  if (!pulseEnabled && !headlessPulse) return;
  if (leaves == null || leaves.isEmpty()) return;

  // Build on NEUTRAL geometry: the breaking anim channels (sweep/radius/rot/band)
  // intentionally tear cross-tile connection, so freeze them to identity here.
  float sBand = animBandScale, sDisc = animDiscScale, sSweep = animArcSweep,
        sRad = animArcRadius, sRot = animRotOffset;
  animBandScale = animDiscScale = animArcSweep = animArcRadius = 1; animRotOffset = 0;

  ArrayList<PulseSeg> segs = new ArrayList<PulseSeg>();
  pnBuckets = new HashMap<Long,ArrayList<Integer>>();
  pnPos = new ArrayList<float[]>();
  try {
    for (Tile lf : leaves) {
      TileGeom gm = new TileGeom(lf);
      for (int ci = 0; ci < gm.conns.length; ci++) {
        float[] poly = gm.sampleBand(ci);
        if (poly == null || poly.length < 4) continue;
        PulseSeg sg = new PulseSeg();
        sg.pts = poly;
        sg.bandW = gm.bandW;
        sg.a = pnNodeFor(poly[0], poly[1]);
        sg.b = pnNodeFor(poly[poly.length - 2], poly[poly.length - 1]);
        if (sg.a == sg.b) continue;                 // degenerate / self-loop -> skip
        segs.add(sg);
      }
    }
  } finally {
    animBandScale = sBand; animDiscScale = sDisc; animArcSweep = sSweep;
    animArcRadius = sRad;  animRotOffset = sRot;
  }

  int N = pnPos.size();
  int[] degree = new int[N];
  ArrayList<ArrayList<Integer>> inc = new ArrayList<ArrayList<Integer>>();
  for (int i = 0; i < N; i++) inc.add(new ArrayList<Integer>());
  float[] nodeBW = new float[N];
  for (int si = 0; si < segs.size(); si++) {
    PulseSeg sg = segs.get(si);
    degree[sg.a]++; degree[sg.b]++;
    inc.get(sg.a).add(si); inc.get(sg.b).add(si);
    nodeBW[sg.a] = max(nodeBW[sg.a], sg.bandW);
    nodeBW[sg.b] = max(nodeBW[sg.b], sg.bandW);
  }

  // CROSS-SCALE BRIDGING: a coarse band centre-line ends at its edge MIDPOINT, but
  // the two finer children's centre-lines end at 1/4 & 3/4 of that edge -- so they
  // never share a node (only the filled band regions abut). Plus the winged alphabet
  // leaves genuine terminals. Result: many degree-1 "open ends". Bridge nearby open
  // ends with a short connector so a comet flows across the seam. Greedy nearest-pair
  // matching keeps every node degree <= 2, so the simple chain/loop tracer still works.
  {
    ArrayList<Integer> ends = new ArrayList<Integer>();   // degree-1 node ids
    for (int i = 0; i < N; i++) if (degree[i] == 1) ends.add(i);
    ArrayList<float[]> cand = new ArrayList<float[]>();  // {dist, i, j}
    for (int a = 0; a < ends.size(); a++) for (int b = a + 1; b < ends.size(); b++) {
      int i = ends.get(a), j = ends.get(b);
      float[] pi = pnPos.get(i), pj = pnPos.get(j);
      float d = dist(pi[0], pi[1], pj[0], pj[1]);
      float tol = 1.3 * max(nodeBW[i], nodeBW[j]);    // ~ the cross-scale gap (edge/4)
      if (d > 0.5 && d <= tol) cand.add(new float[]{ d, i, j });
    }
    java.util.Collections.sort(cand, new java.util.Comparator<float[]>() {
      public int compare(float[] a, float[] b) { return Float.compare(a[0], b[0]); }
    });
    for (float[] c : cand) {
      int i = (int) c[1], j = (int) c[2];
      if (degree[i] != 1 || degree[j] != 1) continue;  // keep degree <= 2
      float[] pi = pnPos.get(i), pj = pnPos.get(j);
      PulseSeg br = new PulseSeg();
      br.pts = new float[]{ pi[0], pi[1], pj[0], pj[1] };
      br.a = i; br.b = j;
      br.bandW = 0.5 * (nodeBW[i] + nodeBW[j]);
      int si = segs.size();
      segs.add(br);
      degree[i]++; degree[j]++;
      inc.get(i).add(si); inc.get(j).add(si);
    }
  }

  // Pass 1: open chains starting at every junction (degree != 2).
  for (int j = 0; j < N; j++) {
    if (degree[j] == 2) continue;
    for (int si : inc.get(j))
      if (!segs.get(si).used) tracePath(segs, degree, inc, j, si, false);
  }
  // Pass 2: leftover all-degree-2 segments -> closed loops.
  for (int si = 0; si < segs.size(); si++)
    if (!segs.get(si).used) {
      PulseSeg sg = segs.get(si);
      tracePath(segs, degree, inc, sg.a, si, true);
    }

  // Interior open-end diagnostic (cross-scale linking health): a degree-1 node not
  // on the canvas border means two crossings that should have merged didn't.
  if (debugLog) {
    int interiorEnds = 0, border = 8;
    for (int i = 0; i < N; i++) if (degree[i] == 1) {
      float[] p = pnPos.get(i);
      if (p[0] > border && p[0] < width - border && p[1] > border && p[1] < height - border) interiorEnds++;
    }
    dbg("PULSE", "paths=" + pulsePaths.size() + " segs=" + segs.size()
        + " nodes=" + N + " interiorOpenEnds=" + interiorEnds);
  }

  java.util.Collections.sort(pulsePaths, new java.util.Comparator<PulsePath>() {
    public int compare(PulsePath a, PulsePath b) { return Float.compare(b.len, a.len); }
  });
}

// Walk from `startNode` along seg `si`, through degree-2 nodes, until a junction /
// dead end (open) or back to start (closed). Builds a concatenated polyline -> a
// resampled PulsePath added to pulsePaths.
void tracePath(ArrayList<PulseSeg> segs, int[] degree, ArrayList<ArrayList<Integer>> inc,
               int startNode, int si, boolean closed) {
  ArrayList<Float> pts = new ArrayList<Float>();
  ArrayList<Float> bws = new ArrayList<Float>();   // band width per point (for per-sample glow)
  int cur = startNode;
  int seg = si;
  float repBandW = segs.get(si).bandW;
  boolean first = true;
  while (true) {
    PulseSeg sg = segs.get(seg);
    sg.used = true;
    int other = (sg.a == cur) ? sg.b : sg.a;
    appendSegOriented(pts, bws, sg, sg.a == cur, first);   // start at `cur`'s end
    first = false;
    cur = other;
    // continue only through clean degree-2 nodes with an unused onward segment
    if (degree[cur] != 2) break;
    int next = -1;
    for (int k : inc.get(cur)) if (!segs.get(k).used) { next = k; break; }
    if (next < 0) break;            // closed loop: came back (start seg already used)
    seg = next;
  }
  addResampledPath(pts, bws, closed, repBandW);
}

// Append seg's points to `pts` (+ per-point band width to `bws`) oriented to begin
// at the joining node; drop the duplicate joint when continuing a walk.
void appendSegOriented(ArrayList<Float> pts, ArrayList<Float> bws, PulseSeg sg, boolean forward, boolean first) {
  int np = sg.pts.length / 2;
  if (forward) {
    for (int i = (first ? 0 : 1); i < np; i++) { pts.add(sg.pts[2*i]); pts.add(sg.pts[2*i+1]); bws.add(sg.bandW); }
  } else {
    for (int i = (first ? np - 1 : np - 2); i >= 0; i--) { pts.add(sg.pts[2*i]); pts.add(sg.pts[2*i+1]); bws.add(sg.bandW); }
  }
}

// Resample a polyline to uniform PULSE_STEP arc length -> PulsePath (incl. local width).
void addResampledPath(ArrayList<Float> raw, ArrayList<Float> rawW, boolean closed, float bandW) {
  int np = raw.size() / 2;
  if (np < 2) return;
  float[] px = new float[np], py = new float[np], pw = new float[np], cum = new float[np];
  for (int i = 0; i < np; i++) { px[i] = raw.get(2*i); py[i] = raw.get(2*i+1); pw[i] = rawW.get(i); }
  cum[0] = 0;
  for (int i = 1; i < np; i++) cum[i] = cum[i-1] + dist(px[i-1], py[i-1], px[i], py[i]);
  float total = cum[np-1];
  if (total < 3 * PULSE_STEP) return;             // ignore tiny stubs

  int m = max(2, round(total / PULSE_STEP));
  PulsePath rp = new PulsePath();
  rp.x = new float[m+1]; rp.y = new float[m+1]; rp.s = new float[m+1]; rp.w = new float[m+1];
  int seg = 0;
  for (int i = 0; i <= m; i++) {
    float q = total * i / m;
    while (seg < np - 2 && cum[seg+1] < q) seg++;
    float segLen = max(1e-5, cum[seg+1] - cum[seg]);
    float t = constrain((q - cum[seg]) / segLen, 0, 1);
    rp.x[i] = lerp(px[seg], px[seg+1], t);
    rp.y[i] = lerp(py[seg], py[seg+1], t);
    rp.w[i] = max(2, lerp(pw[seg], pw[seg+1], t));
    rp.s[i] = q;
  }
  rp.len = total; rp.closed = closed; rp.bandW = max(2, bandW);
  rp.phase = total * pulseFrac(pulsePaths.size(), px[0], py[0]);
  pulsePaths.add(rp);
}

// Local band width at arc position q (binary search of cumulative s) -> glow width.
float pathWidthAt(PulsePath p, float q) {
  int lo = 0, hi = p.s.length - 1;
  while (lo < hi) { int mid = (lo + hi) >> 1; if (p.s[mid] < q) lo = mid + 1; else hi = mid; }
  return p.w[constrain(lo, 0, p.w.length - 1)];
}

// deterministic per-path phase offset in [0,1) (no random()) for staggered firing
float pulseFrac(int idx, float x, float y) {
  float v = sin(idx * 12.9898 + x * 0.0173 + y * 0.0131) * 43758.5453;
  return v - floor(v);
}

// point on a path at arc position q (binary search of cumulative s)
void pathPointAt(PulsePath p, float q, float[] out) {
  int lo = 0, hi = p.s.length - 1;
  while (lo < hi) { int mid = (lo + hi) >> 1; if (p.s[mid] < q) lo = mid + 1; else hi = mid; }
  int i = max(1, lo);
  float segLen = max(1e-5, p.s[i] - p.s[i-1]);
  float t = constrain((q - p.s[i-1]) / segLen, 0, 1);
  out[0] = lerp(p.x[i-1], p.x[i], t);
  out[1] = lerp(p.y[i-1], p.y[i], t);
}

// ---- glow overlay layer (models beginExtrudeLayer / compositeExtrudeLayer) -
Graphics2D beginGlowLayer() {
  if (glowLayer == null || glowLayer.getWidth() != width || glowLayer.getHeight() != height)
    glowLayer = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
  Graphics2D gl = glowLayer.createGraphics();
  gl.setComposite(AlphaComposite.Clear);
  gl.fillRect(0, 0, width, height);
  gl.setComposite(AlphaComposite.SrcOver);
  gl.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
  gl.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);
  return gl;
}

void compositeGlowLayer(Graphics2D gl) {
  gl.dispose();
  Graphics2D g2 = ((PGraphicsJava2D) g).g2;
  java.awt.Composite old = g2.getComposite();
  g2.setComposite(AlphaComposite.SrcOver);
  g2.drawImage(glowLayer, 0, 0, null);
  g2.setComposite(old);
}

// the comet glow colour (RGB; alpha applied per sub-segment)
int[] pulseRGB() {
  if (pulseColorMode == 1) return new int[]{ 255, 255, 255 };
  if (pulseColorMode == 0) {
    color c = palettes.current().lightest();
    return new int[]{ (int) red(c), (int) green(c), (int) blue(c) };
  }
  color base = palettes.current().darkest();          // complementary accent
  float[] hsb = java.awt.Color.RGBtoHSB((int) red(base), (int) green(base), (int) blue(base), null);
  int rgb = java.awt.Color.HSBtoRGB((hsb[0] + 0.5) % 1.0, max(0.65, hsb[1]), 1.0);
  return new int[]{ (rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff };
}

// ---- the per-frame overlay -------------------------------------------------
void drawPulses() {
  if (!pulseEnabled && !headlessPulse) return;
  if (pulsePaths.isEmpty()) return;

  float spd   = (pulseSpeed > 0 ? pulseSpeed : width * 0.16) * pulseSpeedScale;
  float trail = (pulseTrail > 0 ? pulseTrail : min(160, 0.12 * width)) * pulseTrailScale;
  if (trail < 4) trail = 4;
  int sel = (pulseCount <= 0) ? pulsePaths.size() : min(pulseCount, pulsePaths.size());
  int[] rgb = pulseRGB();

  Graphics2D gl = beginGlowLayer();
  for (int pi = 0; pi < sel; pi++) {
    PulsePath p = pulsePaths.get(pi);
    float head = spd * animSeconds + p.phase;
    if (p.closed) {
      float hs = pmod(head, p.len);
      drawCometWindow(gl, p, hs, trail, rgb, true);
    } else {
      float hs = pmod(head, p.len + 2 * trail) - trail;  // slide in/out past the ends
      drawCometWindow(gl, p, hs, trail, rgb, false);
    }
  }
  compositeGlowLayer(gl);
}

// Draw the lit window of a path: arc range [headS - trail, headS], segmented along
// arc length so each chunk gets head->tail falloff alpha, with a 3-stroke bloom.
// The trail is clamped to a fraction of the path so short paths aren't fully lit.
void drawCometWindow(Graphics2D gl, PulsePath p, float headS, float trail, int[] rgb, boolean closed) {
  float eff = min(trail, 0.5 * p.len);
  if (eff < 4) eff = min(trail, p.len);
  float chunk = 9;
  int steps = max(2, ceil(eff / chunk));
  for (int i = 0; i < steps; i++) {
    float s1 = headS - eff * (i + 1) / steps;       // tail end of this chunk
    float s0 = headS - eff * i / steps;             // head end of this chunk
    float u  = (i + 0.5) / steps;                   // 0 at head .. 1 at tail
    float a  = constrain(pow(1 - u, 1.8) * pulseGlowScale, 0, 1);
    if (a < 0.02) continue;
    float midS = (p.closed) ? headS - eff * u : constrain(headS - eff * u, 0, p.len);
    float bw = pathWidthAt(p, p.closed ? pmod(midS, p.len) : midS);   // LOCAL band width
    drawArcSegment(gl, p, s0, s1, a, bw, rgb, closed);
  }
}

// Stroke one arc sub-range [sHi..sLo] of a path (handling closed-loop wrap). The glow
// fills the LOCAL band width `bw` (the comet lights up the ribbon it's in), with a
// soft halo just beyond it and a brighter inner core.
void drawArcSegment(Graphics2D gl, PulsePath p, float sHi, float sLo, float alpha, float bw, int[] rgb, boolean closed) {
  Path2D.Float poly = new Path2D.Float();
  boolean started = appendArcRange(poly, p, sLo, sHi, closed);
  if (!started) return;
  strokeGlow(gl, poly, 1.35 * bw, alpha * 0.16, rgb);   // soft halo just outside the band
  strokeGlow(gl, poly, bw,        alpha * 0.60, rgb);    // fills the band width
  strokeGlow(gl, poly, 0.5 * bw,  alpha * 0.95, rgb);    // bright core
}

void strokeGlow(Graphics2D gl, Path2D.Float poly, float w, float alpha, int[] rgb) {
  if (alpha <= 0.004) return;
  gl.setStroke(new BasicStroke(max(1, w), BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
  gl.setColor(new Color(rgb[0], rgb[1], rgb[2], constrain(round(alpha * 255), 0, 255)));
  gl.draw(poly);
}

// Append the path's samples between arc s in [lo,hi] into `poly`. For closed loops,
// lo<0 wraps to the end. Returns true if anything was added.
boolean appendArcRange(Path2D.Float poly, PulsePath p, float lo, float hi, boolean closed) {
  boolean any = false;
  if (closed) {
    lo = pmod(lo, p.len); hi = pmod(hi, p.len);
    if (hi < lo) {                                   // window straddles the seam -> two spans
      any |= appendSpan(poly, p, lo, p.len);
      any |= appendSpan(poly, p, 0, hi, !any);
    } else {
      any |= appendSpan(poly, p, lo, hi);
    }
  } else {
    lo = constrain(lo, 0, p.len); hi = constrain(hi, 0, p.len);
    if (hi - lo < 0.5) return false;
    any |= appendSpan(poly, p, lo, hi);
  }
  return any;
}

boolean appendSpan(Path2D.Float poly, PulsePath p, float lo, float hi) { return appendSpan(poly, p, lo, hi, true); }
boolean appendSpan(Path2D.Float poly, PulsePath p, float lo, float hi, boolean moveFirst) {
  if (hi - lo < 0.5) return false;
  float[] pt = new float[2];
  boolean first = moveFirst;
  // walk sample indices whose s lies in [lo,hi], plus the exact endpoints
  pathPointAt(p, lo, pt); if (first) { poly.moveTo(pt[0], pt[1]); first = false; } else poly.lineTo(pt[0], pt[1]);
  for (int i = 0; i < p.s.length; i++) if (p.s[i] > lo && p.s[i] < hi) poly.lineTo(p.x[i], p.y[i]);
  pathPointAt(p, hi, pt); poly.lineTo(pt[0], pt[1]);
  return true;
}

// positive modulo
float pmod(float a, float m) { float r = a % m; return r < 0 ? r + m : r; }
