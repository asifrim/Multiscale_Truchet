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

Running opens **two windows**: the visualization and a **Controls** panel (see
"Two-window architecture" below). Most parameters are adjustable live from the
panel; the keyboard still works on the visualization window: **SPACE** = new
seed, **4/3/6** = square/triangle/hexagon, **P/p** = prev/next palette,
**C** = colour scheme, **S** = save `truchet-####.png`.

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
the edge-line intersection). **Hexagons are single-scale and skip wings**
(`if (winged && n != 6)` in `drawPolyTile`): with uniform tile size the classic
arc-at-midpoint connection suffices and the nubs only add noise, so the hexagon
alphabet uses fully-connected tiles instead. Wings still matter for square and
triangle, which mix scales.

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
  quadtree; triangle rep-tile = 3 corner + 1 flipped medial; hexagon never
  subdivides — `canSubdivide` returns false for n=6). `drawPolyTile()` draws one
  tile: a connection between edges `i,j` is a straight band if opposite
  (`min(|i−j|, n−|i−j|) == n/2`), else an arc whose centre is `lineIntersect()`
  of the two edge lines (radius = midpoint→centre). Band width `side/3`. Random
  motif rotation = `rot + k·(2π/n)`, which keeps the footprint (so it still
  tiles) and just relabels edges. Square/triangle **clip the motif to the tile
  polygon** as a safety net (`pushPolyClip`/`popPolyClip`, which reach the JAVA2D
  `Graphics2D` since Processing's `clip()` is rectangle-only); wings draw after
  the clip is released so they still spill. Hexagons skip the clip and use
  `PROJECT` stroke caps so bands overlap across shared edges (closing the AA seam
  that wings hide on the other shapes).
- **`Palettes.pde`** — `PaletteManager`/`Palette`; colour source. `colorScheme`
  (`schemeName`) selects duotone (palette lightest/darkest, inverted per level),
  multi (`ribbonColor()`: light ground, one palette colour per level), or gradient
  (`setupGradient`/`gradientColor`: one random solid colour as ground, bands
  sample a random-direction gradient of the other colours). `tileFg`/`tileBg`
  take the `Tile` (gradient needs position). Keys `p`/`P` palettes, `R` rotate
  palette colour order (`Palette.rotate`), `C` scheme. There is no
  `cDark`/`cLight`. Gradient picks via `random()`, so `draw()` re-seeds
  (`randomSeed(seedVal)`) after `setupGradient()` to keep the tile layout
  identical across schemes for a given seed.
- **`ControlWindow.pde`** — a second PApplet (own window, launched in `setup()`
  via `runSketch`) with immediate-mode sliders/buttons writing straight to the
  main sketch's globals (`parent.*`) and calling `parent.redraw()`. If you add a
  tunable global, add a widget here too.

Per-shape alphabets: `TILE_CONNS`/`TILE_W` (square, in the main tab), `TRI_CONNS`
(triangle: blank + single arc — one port per edge allows at most one arc),
`HEX_CONNS` (hexagon: fully-connected matchings only, since single-scale —
including distance-2 "sweeping" arcs, which polygon clipping keeps in bounds).
`connsFor(n)`/`weightsFor(n)` pick the right one.

## Two-window architecture (control panel)

The Controls panel is a **second `PApplet`**, not a GUI library. Processing
supports multiple windows by running additional `PApplet` instances; the main
sketch's `setup()` launches `ControlWindow` with
`PApplet.runSketch(new String[]{"Controls"}, controls)` and hands it a `parent`
reference back to the main sketch. Widgets are drawn immediate-mode (custom
sliders/toggles/buttons) — no G4P/ControlP5 dependency.

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
