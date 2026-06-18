// ============================================================================
// Image mode -- "Truchet halftone": render a source image as a mosaic of
// multi-scale Truchet patches, choosing each cell's patch by brightness (like
// ASCII art, but the glyphs are little multi-scale tilings).
//
// Two phases, both reusing the normal tile pipeline (collectTile + renderTiling):
//
//   1. CALIBRATION (buildLibrary): generate `libSize` candidate patches -- each a
//      single square cell subdivided to its own depth/density from its own RNG
//      seed -- render them batched onto the canvas and read back the mean
//      luminance of each (its "brightness"). A patch's subdivide probability is
//      swept across [0,1] so the library spans sparse/bright -> dense/dark.
//
//   2. COMPOSE (buildMosaic): lay the active square grid (gridN = imgCols), sample
//      the source image's brightness per cell, and place the library patch whose
//      measured brightness best matches -- then render the whole mosaic at once.
//
// Brightness is measured on the *rendered* pixels in the current palette, so the
// mapping is faithful to whatever colour scheme is active (duotone reads cleanest).
// ============================================================================

// Perceptual luminance of an ARGB pixel int (0..255).
float lumOf(int c) {
  return 0.299 * ((c >> 16) & 0xff) + 0.587 * ((c >> 8) & 0xff) + 0.114 * (c & 0xff);
}

// Flatten any transparency onto a white background and force the image opaque.
// Essential for logos/SVG exports: a transparent PNG stores its background pixels
// as RGB (0,0,0) with alpha 0 -- identical in RGB to a black foreground -- so
// without this the sampled brightness is uniform and the image vanishes into one
// repeated patch. Compositing over white makes transparent areas read as bright.
void flattenOntoWhite(PImage img) {
  img.loadPixels();
  for (int i = 0; i < img.pixels.length; i++) {
    int c = img.pixels[i];
    float a = ((c >> 24) & 0xff) / 255.0;
    int r = round(((c >> 16) & 0xff) * a + 255 * (1 - a));
    int g = round(((c >>  8) & 0xff) * a + 255 * (1 - a));
    int b = round(( c        & 0xff) * a + 255 * (1 - a));
    img.pixels[i] = 0xff000000 | (r << 16) | (g << 8) | b;
  }
  img.updatePixels();
}

// Subdivide one square cell into a self-contained patch, using a fixed seed +
// subdivide probability so the same (seed, subdiv) always yields the same patch
// regardless of where it lands. Returns the patch's leaves (does not touch the
// global `leaves` beyond restoring it). The motif rolls (mi/mk) are baked in by
// collectTile, exactly as in the normal pipeline.
ArrayList<Tile> collectPatch(int seed, float subdiv, Tile root) {
  ArrayList<Tile> saved = leaves;
  float savedProb = subdivideProb;
  leaves = new ArrayList<Tile>();
  subdivideProb = subdiv;
  randomSeed(seed);
  collectTile(root);
  ArrayList<Tile> out = leaves;
  leaves = saved;
  subdivideProb = savedProb;
  return out;
}

// Phase 1: build + measure the brightness library into libSeed/libSubdiv/libBright.
void buildLibrary() {
  libSeed   = new int[libSize];
  libSubdiv = new float[libSize];
  libBright = new float[libSize];
  randomSeed(987654321);                       // deterministic library across runs
  for (int i = 0; i < libSize; i++) {
    libSeed[i]   = (int) random(1, 1e7);
    libSubdiv[i] = (float) i / (libSize - 1);  // sweep density low->high for full range...
    libSubdiv[i] = constrain(libSubdiv[i] + random(-0.12, 0.12), 0, 1);  // ...with jitter
  }
  libSubdiv[0] = 0.0;            // guarantee one un-subdivided (brightest) patch

  // Batched measurement grid: square cells tiling the canvas (e.g. 16x9 at 120px).
  int cellPx = 120;
  int cols = max(1, width  / cellPx);
  int rows = max(1, height / cellPx);
  int perRound = cols * rows;
  int guard = round(cellPx * 0.25);            // ignore the outer ring (neighbour wing spill)
  float R0 = cellPx * sqrt(2) / 2.0;

  int idx = 0;
  while (idx < libSize) {
    ArrayList<Tile> round = new ArrayList<Tile>();
    int[] slotIdx = new int[perRound];
    for (int s = 0; s < perRound; s++) slotIdx[s] = -1;
    for (int s = 0; s < perRound && idx < libSize; s++, idx++) {
      int gx = s % cols, gy = s / cols;
      Tile root = new Tile((gx + 0.5) * cellPx, (gy + 0.5) * cellPx, R0, QUARTER_PI, 4, 0);
      round.addAll(collectPatch(libSeed[idx], libSubdiv[idx], root));
      slotIdx[s] = idx;
    }
    leaves = round;
    background(canvasBgColor());
    renderTiling();
    loadPixels();
    for (int s = 0; s < perRound; s++) {
      if (slotIdx[s] < 0) continue;
      int gx = s % cols, gy = s / cols;
      int x0 = gx * cellPx + guard, x1 = (gx + 1) * cellPx - guard;
      int y0 = gy * cellPx + guard, y1 = (gy + 1) * cellPx - guard;
      double sum = 0; int cnt = 0;
      for (int y = y0; y < y1; y++)
        for (int x = x0; x < x1; x++) { sum += lumOf(pixels[y * width + x]); cnt++; }
      libBright[slotIdx[s]] = (float) (sum / max(1, cnt));
    }
  }
}

// Sort the library by brightness: fills libOrder (patch indices, ascending
// brightness) and libSortedB (their brightnesses) for nearest-match lookup.
int[]   libOrder;
float[] libSortedB;
void sortLibrary() {
  libOrder   = new int[libSize];
  libSortedB = new float[libSize];
  for (int i = 0; i < libSize; i++) libOrder[i] = i;
  for (int i = 1; i < libSize; i++) {        // insertion sort (libSize is small)
    int   ki = libOrder[i];
    float kb = libBright[ki];
    int j = i - 1;
    while (j >= 0 && libBright[libOrder[j]] > kb) { libOrder[j + 1] = libOrder[j]; j--; }
    libOrder[j + 1] = ki;
  }
  for (int i = 0; i < libSize; i++) libSortedB[i] = libBright[libOrder[i]];
}

// Reduce the source image to a cols x rows brightness grid (each pixel = the
// area-averaged brightness of that cell). Two fit modes, since the canvas aspect
// rarely matches the source:
//  - cover  (imgContain=false): crop the source to the grid aspect, fill the frame
//    (no padding, but the image edges are cropped) -- good for photos.
//  - contain (imgContain=true, default): scale the WHOLE image to fit and pad the
//    rest with the bright background, so nothing is cropped -- good for logos.
PImage sampleGrid(int cols, int rows) {
  float targetAR = (float) cols / rows;
  float srcAR = (float) sourceImg.width / sourceImg.height;

  if (!imgContain) {                                   // cover: crop to grid aspect
    int cw, ch;
    if (srcAR > targetAR) { ch = sourceImg.height; cw = round(ch * targetAR); }
    else                  { cw = sourceImg.width;  ch = round(cw / targetAR); }
    cw = constrain(cw, 1, sourceImg.width);
    ch = constrain(ch, 1, sourceImg.height);
    int cx = (sourceImg.width - cw) / 2, cy = (sourceImg.height - ch) / 2;
    PImage crop = sourceImg.get(cx, cy, cw, ch);
    crop.resize(cols, rows);
    return crop;
  }

  // contain: scale the whole image to fit inside cols x rows, centre it, pad white.
  int iw, ih;
  if (srcAR > targetAR) { iw = cols;                ih = max(1, round(cols / srcAR)); }
  else                  { ih = rows;                iw = max(1, round(rows * srcAR)); }
  PImage scaled = sourceImg.get();
  scaled.resize(iw, ih);
  PImage grid = createImage(cols, rows, RGB);
  grid.loadPixels();
  for (int i = 0; i < grid.pixels.length; i++) grid.pixels[i] = 0xffffffff;   // bright pad
  grid.updatePixels();
  grid.set((cols - iw) / 2, (rows - ih) / 2, scaled);
  return grid;
}

// Pick a library patch whose brightness matches `target`, choosing among the K
// nearest (by a position hash) so equal-brightness cells don't all repeat one
// patch. Returns a patch index into libSeed/libSubdiv.
int pickPatch(float target, int gx, int gy) {
  int k0 = 0; float bd = 1e9;
  for (int k = 0; k < libSize; k++) {
    float d = abs(libSortedB[k] - target);
    if (d < bd) { bd = d; k0 = k; }
  }
  int K = min(3, libSize);
  int h = abs((gx * 73856093) ^ (gy * 19349663));
  int pick = constrain(k0 - 1 + (h % K), 0, libSize - 1);
  return libOrder[pick];
}

// Phase 2: place a patch per grid cell by image brightness, into global `leaves`,
// then render the mosaic.
void buildMosaic() {
  sortLibrary();
  float minB = libSortedB[0], maxB = libSortedB[libSize - 1];

  gridN = imgCols;
  ArrayList<Tile> roots = squareRoots();
  int cols = gridN;
  int rows = roots.size() / cols;
  PImage grid = sampleGrid(cols, rows);
  grid.loadPixels();

  leaves = new ArrayList<Tile>();
  for (int gi = 0; gi < roots.size(); gi++) {
    int gx = gi % cols, gy = gi / cols;
    float b = lumOf(grid.pixels[gy * cols + gx]) / 255.0;   // 0..1 cell brightness
    b = pow(b, imgGamma);
    if (imgInvert) b = 1 - b;
    float target = imgStretch ? lerp(minB, maxB, b) : b * 255.0;
    int p = pickPatch(target, gx, gy);
    leaves.addAll(collectPatch(libSeed[p], libSubdiv[p], roots.get(gi)));
  }

  background(canvasBgColor());
  renderTiling();
}

// selectInput() callback (from the Controls "Load image…" button). Must be public
// on the main sketch, which is the callback object passed to selectInput.
void imageChosen(File selection) {
  if (selection == null) return;            // user cancelled
  imagePath = selection.getAbsolutePath();
  sourceImg = null;                          // force reload
  imageMode = true;
  imgDirty  = true;
  redraw();
}

// Entry point from draw(): (re)build the halftone when dirty, else re-render the
// cached mosaic (global `leaves` already holds it).
void drawImageMode() {
  if (sourceImg == null && imagePath != null) {
    sourceImg = loadImage(imagePath);
    if (sourceImg == null) {
      println("Image mode: could not load image: " + imagePath);
      imageMode = false;
      background(canvasBgColor());
      return;
    }
    flattenOntoWhite(sourceImg);     // composite transparency onto white (logos!)
  }
  if (sourceImg == null) { background(canvasBgColor()); return; }

  if (imgDirty) {
    buildLibrary();
    buildMosaic();
    imgDirty = false;
  } else {
    background(canvasBgColor());
    renderTiling();
  }
}
