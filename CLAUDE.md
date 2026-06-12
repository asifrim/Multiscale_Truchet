# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file Processing (Java mode) sketch that generates **multi-scale Truchet
tilings** in the style of Christopher Carlson. The entire program is
`Multiscale_Truchet.pde`. There is no build system, package manager, or test
suite — it is a creative-coding sketch.

## Running

There is no CLI here by default; Processing is the runtime. Processing 4.5.2 **is
installed in this WSL environment** (`/opt/processing`, with `processing` and
`processing-java` on the PATH via `/usr/local/bin`). WSLg provides the display
(`DISPLAY=:0`), so GUI windows render. The repo path `/mnt/e/Multiscale_Truchet`
is a WSL mount of a Windows drive.

- **IDE:** `processing` (launches the Processing IDE), or open
  `Multiscale_Truchet.pde` in the Processing IDE on the Windows host and press Run.
- **Headless / command line:**
  `processing-java --sketch=/mnt/e/Multiscale_Truchet --run`
  - Use an **absolute** `--sketch` path. This build does *not* accept the relative
    `--sketch=.` (it then looks for `..pde` and fails with "Not a valid sketch
    folder"). From inside the project folder, `--sketch="$PWD"` works.
  - `--build` compiles only (no window); `--run` opens a window and renders.

The Processing sketch folder name must match the `.pde` filename, so the main
sketch must stay named `Multiscale_Truchet.pde` at the repo root.

Running opens **three windows**: the visualization, a **Controls** panel, and a
**Tiles** panel (per-shape archetype weights) — see "Multi-window architecture"
below. Most parameters are adjustable live from the panels; the keyboard still
works on the visualization window: **SPACE** = new seed, **4/3/6** =
square/triangle/hexagon, **P/p** = prev/next palette, **R** = rotate palette,
**C** = colour scheme, **M** = mirror symmetry (none/vertical/horizontal/quad),
**S** = save `truchet-####.png`.

**Mirror symmetry** (`symmetryMode`, `applySymmetry()` in the main tab) is a
post-render pixel reflection, applied in `draw()` after the tiles and before the
save: the strip between the axis and the near border is `get()` and drawn back
flipped onto the far side. The axis snaps to the grid's mirror line at or past
the canvas centre (`symPitchX`/`symPitchY`: square = grid lines; triangle =
side/2 columns and row lines; hexagon = hexW/2 columns and row-centre lines), so
the seam follows tile geometry and — because the reflected copy equals the
original along the axis — is seamless for every shape and colour scheme.

### Verifying changes

Processing runs here, so prefer `processing-java --sketch=<abs path> --run` (or
`--build` for a quick compile check). A Python+Pillow port of the algorithm also
exists for rendering a preview PNG without a display (`preview.png` was produced
this way). Either way, when changing the tile geometry, render and *look* at the
result rather than assuming — the connection math is easy to get subtly wrong.

## Installing Processing in WSL (how the current install was built)

The official Processing 4 release ships only a portable `.zip` (no `.tgz` with a
prebuilt `processing-java` script anymore), so the install was assembled by hand.
To redo it:

1. **Download & extract** the latest portable build:
   ```sh
   curl -fL -o /tmp/processing.zip \
     https://github.com/processing/processing4/releases/download/processing-1313-4.5.2/processing-4.5.2-linux-x64-portable.zip
   python3 -c "import zipfile; zipfile.ZipFile('/tmp/processing.zip').extractall('/tmp/px')"
   mv /tmp/px/Processing /opt/processing
   ```
   The layout is jpackage-style: runtime jars in `/opt/processing/lib/app/`, and a
   bundled Temurin 17 JDK + Processing resources (`core/`, `modes/`, `lib/`) under
   `/opt/processing/lib/app/resources/`.

2. **Restore exec bits** — Python's `zipfile` strips Unix permissions, so every
   JDK binary loses `+x`. Both `bin/` *and* `lib/` matter (`--run` spawns a child
   JVM that needs `lib/jspawnhelper`):
   ```sh
   chmod -R +x /opt/processing/lib/app/resources/jdk/bin \
               /opt/processing/lib/app/resources/jdk/lib \
               /opt/processing/bin
   ```

3. **Install X11/GL system libs** the bundled JDK's AWT needs (it touches AWT even
   on `--build`):
   ```sh
   apt-get update && apt-get install -y libxtst6 libxrender1 libxext6 libxi6 \
     libxxf86vm1 libxrandr2 libxcursor1 libxinerama1 libfreetype6 fontconfig \
     libgl1 libglu1-mesa
   ```

4. **Create the `processing-java` wrapper** (the portable zip omits it). The key
   flag is `-Dcompose.application.resources.dir=.../resources` — without it
   Processing can't locate its home folder and reports "The package processing
   does not exist". File `/opt/processing/processing-java`:
   ```sh
   #!/bin/sh
   PROC_HOME=/opt/processing
   JAVA="$PROC_HOME/lib/app/resources/jdk/bin/java"
   APPLIB="$PROC_HOME/lib/app"
   exec "$JAVA" \
     -Djna.nosys=true \
     -Dcompose.application.resources.dir="$APPLIB/resources" \
     -Dskiko.library.path="$APPLIB" \
     -Djava.awt.headless=false \
     -cp "$APPLIB/*" \
     processing.mode.java.Commander "$@"
   ```
   Then put both commands on the PATH:
   ```sh
   chmod +x /opt/processing/processing-java
   ln -sf /opt/processing/processing-java /usr/local/bin/processing-java
   ln -sf /opt/processing/bin/Processing   /usr/local/bin/processing
   ```

5. **Verify:** `processing-java --sketch=/mnt/e/Multiscale_Truchet --build`
   should print `Finished.`

## The one thing to understand before editing tile geometry

Multi-scale connection depends entirely on a single invariant: **wherever a band
crosses a tile edge, the black/white boundary meets that edge at the 1/3 and 2/3
points**, with the band occupying the central third (width `s/3`).

This is what lets tiles of different sizes abut seamlessly: a size-`S` tile's
edge crossings sit at `S/3` and `2S/3`; the two size-`S/2` tiles along that same
edge cross at `S/6, S/3` and `2S/3, 5S/6` — so `S/3` and `2S/3` are shared
exactly and the curves join. Corner arcs therefore use **radius `s/2` with stroke
weight `s/3`** (centred stroke → inner radius `s/3`, outer `2s/3`), and
`strokeCap(SQUARE)` so band ends lie flush along the edge. Any change to these
ratios breaks cross-scale connectivity.

**Colours invert every scale level** (`depth % 2` in `drawTile`) for contrast.

**Winged tiles** (`winged`, default on) are what make connection *structural*
rather than reliant on colour inversion: every tile gets a background disc at
each corner (radius `s/3`) and a foreground disc at each edge midpoint (radius
`s/6`), drawn **unclipped** so they spill into neighbours. A coarse edge's
midpoint is the shared corner of the two half-size tiles along it, so the discs
coincide and join the scales. This requires drawing **coarse-first** (the
`for depth` loop over collected `leaves` in `draw()`), so finer tiles sit on top
— Carlson's "smaller tiles on top of larger". Do not revert to drawing during
recursion; that breaks the layering. These constants (`s/3`, `s/6`) mirror
Steele's `lineWidth` and `lineWidth/2`.

The same invariant generalizes to n-gons (band width = `side/3`; arc radius from
the edge-line intersection). A **whole hexagon tile skips wings** (`winged && n !=
6` in `drawPolyTile`) and uses fully-connected tiles — the classic arc-at-midpoint
connection. Hexagons get multi-scale by **subdividing into 6 equilateral
triangles** (a hexagon is not a rep-tile; see `children()`); those triangles *do*
use wings. So hexagon mode mixes whole-hexagon tiles (coarse) with winged triangle
detail (finer).

**Seams / antialiasing.** Each tile's bands are stroked as ONE Java2D path
(`drawTileBands`), so a tile's own bands union into a single antialiased shape (no
1px gaps between separately-drawn strokes). Whole hexagons have no wings to bridge
*inter*-tile joins, so **all hexagon bands are batched into one path and stroked
once** (`strokeHexBatch`, called from `draw()` after the depth-0 pass) — the whole
hexagon layer is a single AA shape, eliminating seams between tiles. They share
one colour at depth 0 (the per-tile `gradient` scheme, mode 2, is the exception
and falls back to per-tile via `colorScheme != 2` in `drawPolyTile`). Hexagon
bands use a `ROUND` cap so they overlap smoothly across edges. Square/triangle
keep per-tile clip + wings, which hide their joins.

**Gotcha — `arc()` honours `ellipseMode`.** The tile arcs call
`arc(cx, cy, 2*r, 2*r, ...)` assuming the default `CENTER` mode (args = width/
height). So never leave `ellipseMode(RADIUS)` set: the wing discs are therefore
drawn in `CENTER` mode using *diameters*, not `RADIUS`. A stray
`ellipseMode(RADIUS)` makes every subsequent `arc()` read its diameter as a
radius — doubling the arcs into a chunky mess on the next shape/frame. This was
the actual cause of the "hexagon looks broken after switching shapes" bug (not
the grid — the hex grid is a correct staggered tessellation).

## Structure of the sketch

Four `.pde` tabs (Processing merges them into one PApplet):

- **`Multiscale_Truchet.pde`** — globals, `setup()`/`draw()`, colour, keys.
  `draw()` calls `buildRoots()`, recursively `collectTile()`s into the global
  `ArrayList<Tile> leaves`, then draws **coarse-first** (loop over depth) — the
  layering winged tiles depend on. `collectTile()` either subdivides
  (`canSubdivide()` && `random < subdivideProb`) or records a leaf. Do not draw
  during recursion; it breaks the coarse-first layering.
- **`Shapes.pde`** — the generalized n-gon engine, added when triangle/hexagon
  support landed. A `Tile` is `(cx, cy, R, rot, n, depth)`. `shapeMode`
  (0/1/2 → square/triangle/hexagon, keys 4/3/6) drives `buildRoots()`
  (`squareRoots`/`triangleRoots`/`hexagonRoots`) and `children()` (square
  quadtree; triangle rep-tile = 3 corner + 1 flipped medial; hexagon = 6
  equilateral triangles fanning from the centre, which then recurse as n==3 —
  `canSubdivide` is just `depth < maxDepth`). `drawPolyTile()` draws one
  tile: a connection between edges `i,j` is a straight band if opposite
  (`min(|i−j|, n−|i−j|) == n/2`), else an arc whose centre is `lineIntersect()`
  of the two edge lines (radius = midpoint→centre). Band width `side/3`. Random
  motif rotation = `rot + k·(2π/n)`, which keeps the footprint (so it still
  tiles) and just relabels edges. Square/triangle **clip the motif to the tile
  polygon** as a safety net (`pushPolyClip`/`popPolyClip`, which reach the JAVA2D
  `Graphics2D` since Processing's `clip()` is rectangle-only); wings draw after
  the clip is released so they still spill. Hexagons skip the clip and use
  `ROUND` stroke caps so bands overlap across shared edges (closing the AA seam
  that wings hide on the other shapes).
- **`Palettes.pde`** — `PaletteManager`/`Palette`; colour source. `colorScheme`
  (`schemeName`) selects one of four: duotone (lightest/darkest, inverted per
  level), multi (`ribbonColor()`: light ground, one palette colour per level),
  gradient (`gradientColor`: one random solid ground colour, bands sample a
  random-direction gradient of the other colours, one flat colour per tile),
  gradient-bg (a *smooth* full-canvas gradient, solid ribbons; `drawPolyTile`
  skips the bg polygon when `colorScheme==3` so the gradient shows through), or
  gradient-smooth (solid ground, ribbons painted with the smooth gradient
  continuously). The gradient family shares `setupGradient()`, which also builds
  a Java2D `LinearGradientPaint` (`gradPaint`) matching `gradientColor`'s
  projection; schemes 3 and 4 use it via `g2` (`drawGradientBackground` fills the
  canvas; `gradientStroke()`/`drawTileBands`/`fillDiscG2` stroke the bands and wing
  discs). `tileFg`/`tileBg` take the `Tile` (gradient needs position). Keys
  `p`/`P` palettes, `R` rotate palette colour order (`Palette.rotate`), `C`
  scheme. There is no `cDark`/`cLight`. The gradient schemes pick via `random()`,
  so `draw()` re-seeds (`randomSeed(seedVal)`) after `setupGradient()` to keep the
  tile layout identical across schemes.
- **`ControlWindow.pde`** — a second PApplet (own window, launched in `setup()`
  via `runSketch`) with immediate-mode sliders/buttons writing straight to the
  main sketch's globals (`parent.*`) and calling `parent.redraw()`. If you add a
  tunable global, add a widget here too.
- **`TileWindow.pde`** — a third PApplet window listing the active shape's tile
  **archetypes** (`parent.connsFor(n)` — base connection sets, no rotations) with
  a slider per archetype that writes its selection weight into
  `parent.weightsFor(n)` (the same `TILE_W`/`TRI_W`/`HEX_W` `pickWeighted` reads)
  and calls `parent.redraw()`. It draws each archetype with its own
  `drawArchetype()` (a compact copy of the band geometry, using `parent.lineIntersect`)
  since drawing must target *this* window's canvas, not the main one. It reads
  `parent.shapeMode` each frame, so it relists automatically when the shape changes.

Per-shape alphabets: `TILE_CONNS`/`TILE_W` (square, in the main tab), `TRI_CONNS`
(triangle: blank + single arc — one port per edge allows at most one arc),
`HEX_CONNS` (whole-hexagon tiles: fully-connected matchings only — including
distance-2 "sweeping" arcs; a subdivided hexagon becomes triangles and uses
`TRI_CONNS`). `connsFor(n)`/`weightsFor(n)` pick the right one.

## Multi-window architecture (control panels)

The GUI panels are **separate `PApplet`s**, not a GUI library. Processing
supports multiple windows by running additional `PApplet` instances; the main
sketch's `setup()` launches each with
`PApplet.runSketch(new String[]{"..."}, win)` and hands it a `parent`
reference back to the main sketch (currently two: `ControlWindow` and
`TileWindow`). Widgets are drawn immediate-mode (custom sliders/toggles/buttons)
— no G4P/ControlP5 dependency. The points below say "control window" but apply to
both panels.

Gotchas that matter when editing this:

- **`size()` must be in `ControlWindow.settings()`**, not `setup()`. The Processing
  preprocessor only auto-relocates `size()` for the main tab; a `PApplet`
  subclass must declare it in `settings()` or the window won't size correctly.
- **Two animation threads.** The control window runs its own draw loop; the
  visualization is `noLoop()`. Widgets write to `parent.*` globals and then call
  `parent.redraw()` to repaint the viz. Reads of `parent` state for *display*
  (palette name, swatches, current shape/scheme) are best-effort cross-thread —
  fine for a control panel, but don't build logic that assumes atomicity.
- **Save goes through a flag, not a direct call.** The Save button sets
  `parent.saveRequested = true` and calls `redraw()`; the actual `saveFrame()`
  runs at the end of the viz's `draw()` (step 3). This guarantees the saved PNG
  is the fully-drawn frame and avoids grabbing the pixel buffer from the wrong
  thread mid-render.
- **Keep widgets in sync with globals.** `syncParent()` maps sliders/toggles onto
  `parent.gridN/maxDepth/subdivideProb/winged/invertPerLevel` by index/field; the
  shape/scheme/palette buttons call the same mutators the keyboard does. If you
  add a tunable global, add a widget here and extend `syncParent()` (or its
  button handler) too, or the panel and keys will drift out of agreement.

## Reference material

- `Literature/bridges2020-191.pdf` — Kerry Mitchell, *"Generalizations of Truchet
  Tiles"* (Bridges 2020): the "two points per side at thirds / four arcs per
  tile" generalization this sketch's geometry builds on.
- Oliver Steele, *"Generalized Truchet Tiles"*
  (https://observablehq.com/@osteele/truchet-tile-generation): source of the
  edge-pair tile representation. It generalizes to n-gons (the arc centre is the
  intersection of the two edge lines; for squares that is the shared corner,
  radius = half-side — matching this sketch). It is single-scale; the
  quadtree + colour-inversion multi-scale logic here is the Carlson part.
- Carlson's multi-scale post (linked in the sketch header) is the target aesthetic.
