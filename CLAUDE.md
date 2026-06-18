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
works on the visualization window: **SPACE** = new seed, **4/3/6/t** =
square/triangle/hexagon/trapezoid, **P/p** = prev/next palette, **R** = rotate palette
(in duotone, instead assigns two random palette colours to fg/bg — see `rotatePalette`),
**C** = colour scheme, **M** = symmetry (none/vertical/horizontal/quad/rot 180/
tile mir V/H/quad), **e** = toggle 3D extrusion, **E** = cycle extrude mode
(oblique/1-point), **a** = toggle animation, **g** = toggle base-grid overlay,
**l** = toggle line mode (parallel/concentric strokes), **S** = save a
parameter-stamped PNG.

**Saving** (`saveTiling`, S key or the Controls Save button): the filename encodes
the displayed parameters + seed (e.g.
`truchet_trapezoid_duotone_seed4242_g5_d4_sub60_pal12.png`), and the **exact
headless command that reproduces the frame is printed to the console** (with
`TRUCHET_SCALE=2` so you can re-render the identical composition at higher
resolution — every render-affecting global has a matching `TRUCHET_*` override).
Headless runs (`TRUCHET_OUT`) also echo `name:` + `reproduce:` lines.

**Symmetry** (`symmetryMode`) comes in two mechanisms, deliberately different:

- **Pixel mirrors** (modes 1–3, `applySymmetry()` in the main tab) are a
  post-render pixel reflection, applied in `draw()` after the tiles and before
  the save: the strip between the axis and the near border is `get()` and drawn
  back flipped onto the far side. The axis snaps to the grid's mirror line at or
  past the canvas centre (`symPitchX`/`symPitchY`: square = grid lines; triangle
  = side/2 columns and row lines; hexagon = hexW/2 columns and row-centre
  lines), so the seam follows tile geometry and — because the reflected copy
  equals the original along the axis — is seamless for every shape and colour
  scheme. Cheap and works for both axes at once (quad), but the copied half's
  drop shadows point the mirrored way.
- **Tile-level modes** (4 = rot 180; 5/6/7 = tile mirror V/H/quad) are
  structural: `draw()` generates only the fundamental domain (half or quadrant)
  of roots and adds a transformed twin per leaf, then everything renders in one
  normal pass — wings spill across the join both ways, layering holds, shadows
  keep one light direction, and gradients stay continuous; no pixel seam exists.
  (A pixel-copy rot 180 was tried first and rejected: a rotated copy does not
  match the original pointwise along the seam, leaving orphaned wing-disc halves
  and a hard shadow cut.) Each leaf's motif (`Tile.mi`/`mk`) is fixed in
  `collectTile()` rather than rolled at draw time so twins can reuse it.
  - **Rot 180** (mode 4): a half-turn twin is just `rot + PI` with the same
    motif. The centre must be a **2-fold rotation centre of the grid**:
    squares/triangles use `(width/2, grid/row line ≥ height/2)`; hexagons
    rotate about a slanted-edge midpoint (`width/2 + hexW/4`, half-row line —
    `rotCentreX/Y`), which maps hex row r → row 2·rs+1−r with the stagger
    parity working out.
  - **Tile mirrors** (modes 5 V / 6 H / 7 quad): a mirrored motif is drawn by
    reversing the tile's vertex winding (`Tile.flip`, handled in `TileGeom`),
    so no per-shape edge-relabelling tables are needed. The twins are
    `(2·ax−cx, cy, PI−rot, flip)` for V, `(cx, 2·ay−cy, −rot, flip)` for H, and
    `(2·ax−cx, 2·ay−cy, rot+PI, no-flip)` for the quad diagonal (= a
    180-rotation, two reflections, so no winding flip). **Tile-level twinning
    needs no *global* grid mirror line** — the reflected half is self-consistent
    by construction, so only the seam matters: the axis may run along tile
    edges/vertices or through tile centres, never cutting a body off-centre.
    The vertical axis is `width/2` (the grid divides width exactly → a mirror
    column of all three grids). The horizontal axis `mirrorAxisY()` snaps to the
    nearest grid mirror line to mid-canvas (height is *not* divided evenly, so
    it sits slightly off-centre): square `s0/2` line, triangle strip boundary
    (`rowH` spacing — no straddlers; the up-triangle bases there tile
    edge-to-edge and their flipped twins share those exact edges), or hexagon
    row-centre line. A **straddler** (tile centred on an axis: odd-grid square
    columns, one triangle per V-strip, every other hex row, etc.) is its own
    mirror, so `collectSym()` recurses straddlers mirror-aware (far-side
    children dropped — a twin covers them — and on-axis children kept) and
    straddler leaves roll a **self-symmetric motif** (`pickSymmetricMotifMulti`
    + `selfMirrorMotif`: keep the (mi, mk) pairs whose connection set maps onto
    itself under the edge reflection `e → c0−1−e`, with `c0` per axis — vertical
    `(PI−2·rot)/(2π/n)`, horizontal `−2·rot/(2π/n)` — and for quad straddlers,
    symmetric about *both*; weighted as the normal roll conditioned on
    symmetry). `addSymTwins()` emits the orbit (≤3 twins; an axis the tile
    straddles fixes it, collapsing the diagonal onto the surviving reflection).
    NB: because the H axis is off-centre, verifying H symmetry by pixel-diffing
    against an *integer*-rounded reflected coordinate massively inflates the
    mismatch on horizontal-ish edges (≈7%); reflect with the exact float axis
    (e.g. PIL `AFFINE` + bicubic) and it drops to ≈0 — the symmetry is exact.

A 4-fold (90°) mode is geometrically impossible on the non-square canvas
(rotated sources fall off-canvas; tile twins would need a square-symmetric
domain), so it is intentionally absent.

### Verifying changes

**Never screenshot the windows** (scrot/xdotool are unreliable under WSLg and
the user has forbidden it) — make the sketch render the image itself. A one-shot
headless mode exists for exactly this (parsed in `setup()`, saved at the end of
`draw()`):

```sh
TRUCHET_OUT=/tmp/out.png TRUCHET_SHAPE=2 TRUCHET_SEED=7 \
  processing-java --sketch=/mnt/e/Multiscale_Truchet --run
```

renders one frame to `TRUCHET_OUT` and exits, skipping the GUI windows.
**Resolution.** The canvas defaults to 1920×1080 but the tiling is fully
resolution-independent (every length derives from `width`/`height`), so a larger
canvas gives the SAME composition at higher resolution — a print/wallpaper export.
Set size in `settings()` via `TRUCHET_W`/`TRUCHET_H` (explicit pixels) or
`TRUCHET_SCALE` (multiply the default — `2` → 4K 3840×2160, `4` → 8K). These also
enlarge the interactive window (window == canvas in Processing); for a "small
window, big PNG" export use the headless path (`TRUCHET_OUT`), which opens no
window. Big sizes cost memory (the shadow/extrude `BufferedImage` layers are
`width*height*4` bytes each, ~133 MB apiece at 8K). Example:
`TRUCHET_SCALE=2 TRUCHET_OUT=/tmp/4k.png processing-java --sketch=… --run`.
Optional overrides: `TRUCHET_SHAPE` (0 square, 1 triangle, 2 hexagon, 3 trapezoid),
`TRUCHET_SCHEME` (0–4), `TRUCHET_SEED`, `TRUCHET_PALETTE` (index, wraps),
`TRUCHET_DUO` (`"bgIdx,fgIdx"` = duotone fg/bg as two palette-colour indices, the
reproducible form of the duotone "rotate"; omit for the default luminance extremes),
`TRUCHET_SYM` (0–7),
`TRUCHET_SHOWGRID` (0/1 = overlay the base root-tile lattice on top of the render;
re-derived from `buildRoots()` so it covers the whole canvas in every symmetry
mode — see `drawGridOverlay`), `TRUCHET_GRID`, `TRUCHET_DEPTH` (0 = single scale), `TRUCHET_SUBDIV` (subdivide
probability 0–1; `1` = uniform finest scale, handy for isolating subdivision
behaviour from coarse/fine mixing), `TRUCHET_SHADOW` (0/1),
`TRUCHET_SHADOW_STR` (darkness 0–1), `TRUCHET_SHADOW_SIZE` (offset, fraction of
the band stroke; unclamped here for exaggerated tests), `TRUCHET_SHADOW_ANGLE`
(shadow direction, degrees), `TRUCHET_SHADOW_GLOBAL`
(0 = per-level mask, 1 = one full-scene mask), `TRUCHET_WINGED` (0/1 = Carlson
wings on/off), `TRUCHET_INVERT` (0/1 = duotone
per-level colour inversion; off makes one hue always foreground — handy when a
shadow on an inverted-level *background* reads as if the background were
casting), `TRUCHET_EXTRUDE` (0/1 = 3D extrusion), `TRUCHET_EXTRUDE_MODE`
(0 oblique, 1 one-point), `TRUCHET_VPX`/`TRUCHET_VPY` (vanishing point,
normalised canvas coords, may be off-canvas), `TRUCHET_EXTRUDE_DEPTH` (fraction
of tile side), `TRUCHET_EXTRUDE_SHADE` (side darkness 0–1).
Line mode (parallel/concentric strokes — see "Line mode" below): `TRUCHET_LINE`
(0/1), `TRUCHET_LINE_COUNT` (lines across a depth-0 band, sets the global pitch),
`TRUCHET_LINE_DUTY` (ink fraction of the pitch, 0–1), `TRUCHET_LINE_SUBDIV`
(0–1 = per-stroke probability of subdividing into the line bundle vs drawing the
original full-thickness stroke; `1` = all lines, plain line mode).
Animation (headless verification of motion — the loop never starts in headless;
these pin a single deterministic frame): `TRUCHET_ANIM_T` (seconds → LFO-driven
frame at that phase), `TRUCHET_ANIM_RATE` (master LFO Hz), `TRUCHET_ANIM_DEPTH`
(set all LFO depths so motion is visible), and `TRUCHET_ANIM="name=v01,..."` to
pin exact registry values (e.g. `discMod=1.0`, `rotationMod=0.85`), which also
exercises the future MIDI sink.
Image mode ("Truchet halftone" — see `ImageMode.pde`): `TRUCHET_IMG` (path to a
source image → enables image mode), `TRUCHET_IMG_COLS` (mosaic columns; rows
derived from the canvas aspect, = `gridN` in image mode), `TRUCHET_IMG_LIB`
(brightness-library size, default 256), `TRUCHET_IMG_GAMMA` (gamma on sampled
cell brightness; >1 darkens midtones), `TRUCHET_IMG_STRETCH` (0/1 = map image
brightness across the library's full achievable range, default on),
`TRUCHET_IMG_INVERT` (0/1 = invert the brightness→patch mapping),
`TRUCHET_IMG_CONTAIN` (1 = fit the whole image and pad with the bright background,
default; 0 = cover/crop to the canvas aspect). Combine with
`TRUCHET_SCHEME`/`TRUCHET_PALETTE` (brightness is measured in the active palette),
e.g. `TRUCHET_OUT=/tmp/o.png TRUCHET_IMG=/tmp/face.png TRUCHET_IMG_COLS=48`.
Use `--build` for a
quick compile check. Python+Pillow ports of the algorithm also exist for geometry checks
without Processing (`preview.png`, `trapezoid_prototype.py`). Either way, when
changing the tile geometry, render and *look* at the result rather than
assuming — the connection math is easy to get subtly wrong.

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

### Line mode (parallel / concentric strokes)

`lineMode` (key **l**, Controls toggle, `TRUCHET_LINE`) renders each band not as
one solid stroke of width `side/3` but as a **bundle of thin lines at constant
perpendicular offset from the centre-line** — the fingerprint/topographic look.
The mechanism is exact, not faked: a straight band's offset is a parallel
translate of its endpoints along the edge normal; an arc's offset is a
**concentric arc** (`radius = r0 + offset`), and since the connection invariant
puts every band centre-line *perpendicular* to the edge it crosses (the arc
centre is the intersection of the two edge lines, which lies on each edge line,
so the radius to the crossing runs *along* the edge), a constant radial offset is
a constant perpendicular offset. Equal-offset lines of two abutting tiles
therefore land on the **same points along the shared edge** (`midpoint ± offset`),
so the bundles flow continuously across tiles at one scale. Cross-scale joins
(coarse centre-line at the 1/2 point vs. fine ones at 1/4, 3/4) don't line-match;
the fg wing nub — drawn in line mode as **concentric rings** — bridges them and
reads as the style's little target/spiral circles. The ring radii are the **same
offset grid** the band lines use (`lineOffsets(2·fgR)`, positive half), so a ring
of radius `|offset_k|` passes through that line's edge crossing and — the line
crossing perpendicular to the edge — is **tangent** to it there; that shared
grid/phase is what makes the rings and lines align (anchoring the rings to the
nub radius instead leaves them a half-pitch off).

Pitch is a **constant pixel spacing** = (depth-0 band `bandWidth0`) / `lineCount`,
computed once in `rebuildLeaves` from `buildRoots()[0]`, so the hatching reads at
one density across the whole canvas and every export resolution; a band of width
`w` simply holds `round(w/pitch)` lines (`lineOffsets`), finer tiles fewer. Line
stroke weight = `pitch · lineDuty` (`lineStroke()`), leaving paper between lines.
Implemented entirely at render time: `appendConn`/`appendTrapConn`/`appendStraight`
gained an `offset` param (0 = the original centre-line, so shadow/extrude — which
call `appendBands` = offset 0 — and the whole off path stay **byte-identical**);
`drawTileBands`, the hex-batch branch, `strokeHexBatch`, and the wing-disc pass
each branch on `lineMode`. Lines are stroked `CAP_ROUND`, and line mode **skips
the polygon clip** (`doClip = (n!=6) && !lineMode`) — the thin strokes stay within
the band region, and clipping at the tile edge would slice the round caps back to
flat. The bg corner discs stay solid (the "paper" gaps).
Works with every colour scheme (gradient included, via `g2` + `gradPaint`) and
shape; only the depth-0/whole-hexagon band continuity is line-aligned (subdivided
detail abuts via rings, as above). Globals: `lineMode`/`lineCount`/`lineDuty`/
`bandWidth0` (main tab).

**Opaque ribbons** (line mode, every scheme except 3 — gradient-bg, whose smooth
canvas gradient must show through). The line bundle is drawn over an **opaque
`side/3` ribbon base** in the tile's *background* colour, so a band is not
transparent: where it runs through a port it covers that port's wing ring (two
arcs joining no longer show the little circle), and crossing/overlapping bands
cover cleanly instead of letting the strokes underneath show through (crossings
read as an over/under weave). A port the band does **not** continue across (an
unmatched / cross-scale join) keeps its ring's outer half — the arc curls into the
spiral. Geometry makes this exact: a port ring's radius is `≤ side/6` and the
band is `side/3` wide, so the ribbon base covers the ring at a through-port and
the clip drops only the half that spills into a neighbour (a matched neighbour's
base covers that half too → ring vanishes; an unmatched one leaves the spiral).
Because the base is opaque it would erase a neighbour's lines at the join, so the
three steps run **level-wide, not per tile** (`drawForegroundLevel`): pass 1 all
wing rings, pass 2 all ribbon bases, pass 3 all line bundles — the bundle on top
across every tile keeps the hatching continuous (`drawTileLineRings`/
`drawTileRibbonBase`/`drawTileLineBundle`). Whole hexagons (scheme ≠ 2) stay the
transparent batched layer (nothing problematic sits under the coarse layer).
Solid mode and scheme 3 keep the original single per-tile `drawTileForeground`
path.

**Per-stroke subdivision** (`lineSubdivProb`, key-less, Controls "line subdiv"
slider, `TRUCHET_LINE_SUBDIV`). In line mode each *stroke* (one connection of one
tile) is independently rendered either as the thin line bundle or as the original
full-thickness `side/3` stroke; the slider is `P(subdivided)` (`1` = all lines =
plain line mode, byte-identical; `0` = all full-thickness). The choice is a
**stable hash** of the tile identity + connection index (`strokeSubdivided`), so
it holds per seed and updates live when the slider moves — no layout rebuild
(`dirtyLayout` not set). It lives in pass 3 (`drawTileLineBundle`, which now
iterates connections one at a time via `TileGeom.appendOneBand` and strokes a
`solid` path at `side/3` plus a `lines` path at `lineStroke()`); a full-thickness
stroke is opaque fg so it covers the pass-2 ribbon base and the pass-1 rings under
it. Whole hexagons split the same way into `hexBatch` (lines) + `hexSolidBatch`
(full-thickness), both flushed in `strokeHexBatch`. Each port belongs to at most
one connection, so the wing nub follows its stroke: a full-thickness stroke's
ports get a **solid disc** nub (like solid mode — it merges into the opaque
stroke), while subdivided-stroke ports and unused ports keep the concentric rings
(`solidPorts` / `drawTileLineRings`). (Curved thin strokes are also kept smooth by setting Java2D
`KEY_STROKE_CONTROL = VALUE_STROKE_PURE` — the default `STROKE_NORMALIZE` snaps
thin strokes to the pixel grid and visibly jags long arcs; set once per frame on
the main `g2` and on the shadow/extrude offscreen layers.)

## Structure of the sketch

The `.pde` tabs are merged into one PApplet:

- **`Multiscale_Truchet.pde`** — globals, `setup()`/`draw()`, colour, keys.
  `draw()` calls `buildRoots()`, recursively `collectTile()`s into the global
  `ArrayList<Tile> leaves`, then draws **coarse-first** (loop over depth) — the
  layering winged tiles depend on. `collectTile()` either subdivides
  (`canSubdivide()` && `random < subdivideProb`) or records a leaf. Do not draw
  during recursion; it breaks the coarse-first layering. The coarse-first draw
  loop is factored into `renderTiling()` (operates on the global `leaves`) so
  image mode can reuse it for both its calibration rounds and the final mosaic;
  `draw()` either takes the image-mode branch (`drawImageMode()`) or the normal
  background → `rebuildLeaves()` → `renderTiling()` → `applySymmetry()` path.
  **Drop shadows** render each depth level in three passes — all backgrounds,
  then ONE unioned shadow mask (every caster offset by `shadowSize·side/3` along
  `shadowAngle`, drawn opaque into an offscreen `BufferedImage`, composited once
  at `shadowStrength`), then all foregrounds — so a shadow sits above its level's
  backgrounds and below its bands with a single light direction, and same-level
  shadows never double-darken (one mask). `shadowGlobal` (default off, toggle in
  Controls) switches to ONE full-scene mask drawn after *all* backgrounds: coarse
  tiles then cast across finer regions, at the cost of the per-level cue that
  finer backgrounds occlude the coarser shadow beneath them. Shadow size scales
  with `side`, so finer tiles cast proportionally finer shadows automatically.
  **3D extrusion** (`extrude3D`, keys `e`/`E`, Controls toggle + mode button) is
  a graffiti block-depth effect: the foreground ribbons gain solid side walls
  extruded toward a vanishing point, viewed head-on (the tiling is NOT
  perspective-warped). Reuses the shadow's offscreen-layer idea. When on, `draw()`
  takes a separate branch: **all** backgrounds first (so a finer tile's background
  can never chop a coarser ribbon's wall), then the optional drop shadow on that
  flat plane, then per level coarse-first it calls `drawExtrudeLevel(d)` (build +
  composite that level's walls) and draws the level's top faces on top — so finer
  walls/faces land over coarser (Carlson's "smaller on top"). `drawExtrudeLevel`
  builds the level's silhouette (band path + wing nubs) once, then re-draws it as
  many overlapping "slices" stepping toward the VP into one ARGB `extrudeLayer`
  (separate from `shadowLayer`): **oblique** translates each slice in parallel
  (direction = canvas-centre→VP); **1-point** scales each slice about the VP
  (`AffineTransform`, converging + thinner at the back). Every slice is the SAME
  flat `sideColor()` (darkened palette `darkest()`), so the stack unions into one
  clean wall with no internal seam (same-colour-over-same-colour), composited
  once. Vector re-draw (not raster rescale) keeps the thin `side/3`/`side/6`
  features crisp at every depth. Depth scales with the level's `side` (coarse
  ribbons extrude deeper). Hex bands must be stroked by the body builder itself
  (the `hexBatch` is top-face-only). Slice count N is derived from screen-space
  travel and clamped (≤1200) so a near VP in 1-point can't explode it. Gated:
  with `extrude3D` off, `draw()` is byte-for-byte the original path.
- **`Shapes.pde`** — the generalized n-gon engine, added when triangle/hexagon
  support landed. A `Tile` is `(cx, cy, R, rot, n, depth)`. `shapeMode`
  (0/1/2/3 → square/triangle/hexagon/trapezoid, keys 4/3/6/t) drives `buildRoots()`
  (`squareRoots`/`triangleRoots`/`hexagonRoots`/`trapezoidRoots`) and `children()` (square
  quadtree; triangle rep-tile = 3 corner + 1 flipped medial; hexagon = 6
  equilateral triangles fanning from the centre, which then recurse as n==3 —
  `canSubdivide` is just `depth < maxDepth`). `drawPolyTile()` draws one
  tile: a connection between edges `i,j` is a straight band if opposite
  (`min(|i−j|, n−|i−j|) == n/2`), else an arc whose centre is `lineIntersect()`
  of the two edge lines (radius = midpoint→centre). Band width `side/3`. The
  motif (alphabet index `mi` + rotation steps `mk`, chosen in `collectTile()` so
  rot-180 twins can share it) rotates by `rot + mk·(2π/n)`, which keeps the
  footprint (so it still tiles) and just relabels edges. Square/triangle **clip the motif to the tile
  polygon** as a safety net (`pushPolyClip`/`popPolyClip`, which reach the JAVA2D
  `Graphics2D` since Processing's `clip()` is rectangle-only); wings draw after
  the clip is released so they still spill. Hexagons skip the clip and use
  `ROUND` stroke caps so bands overlap across shared edges (closing the AA seam
  that wings hide on the other shapes).
  - **Trapezoid** (`shapeMode == 3`, the **half-hexagon**, ported from
    `trapezoid_prototype.py`) is the one shape that is *not* a regular n-gon, so it
    bypasses the `(cx,cy,R,rot,n)` vertex math: a trapezoid `Tile` carries a complex
    **similarity** `(p0, e)` in a y-up *canonical* frame (`world(z) = p0 + z·e`; the
    canonical unit tile has short edge 1, long edge 2, height √3/2 — see `TRAP_V`),
    flagged `Tile.trap`, with `cx/cy` holding the screen centroid and `n` left at 4
    (the polygon vertex count, for bg fill + clip). Its long edge carries **two
    ports** (5 ports total: `TRAP_PORT` = B1,B2,R,T,L), so 5 is odd and one port is
    always unmatched — the fg wing nub caps it. All six connections are circular
    **arcs** with explicit canonical centres (`trapArcSpec`, centres lie on both
    ports' edge lines → perpendicular crossings, width 1/3); the L–R "sweep" centres
    on the cut-off apex. `trapezoidRoots()` lays the staggered up/down lattice
    (`e = ±1`). **Subdivision is lattice-preserving** (`children()`): a half-hexagon
    trapezoid is exactly **3 unit equilateral triangles** (`TRAP_TRIS`, two up + one
    down), so it splits into those — transformed to screen via `(p0,e)` and recorded
    as `n==3` tiles, which then recurse with the triangle rep-tile rule (the same
    strategy the hexagon uses; whole trapezoids stay the coarse scale, finer detail
    is triangular). The 3 triangles' boundary edges reproduce the trapezoid's exact
    port lattice — the long edge = the two up-triangles' bases (2 ports), the top
    edge = the down-triangle's base (1), each leg = one triangle edge (1) — so a
    whole trapezoid and a subdivided one connect seamlessly, giving the classical
    continuous multi-scale pattern. (An earlier rep-4 split into 4 rotated
    half-trapezoids would have moved the children's ports off the connection lattice;
    it also never ran, because a trapezoid has `n==4` and was caught by the square
    quadtree branch — `children()` now tests `t.trap` **before** `t.n`.)
    `TileGeom.initTrap()` builds the *whole-trapezoid* screen geometry and exposes
    the *shape-neutral* interface every render pass reads: `vx/vy` (outline),
    `bgWx/bgWy` + `fgWx/fgWy` (wing-disc centres — 5 corners / 5 ports for the
    trapezoid, vertices / edge midpoints for regular shapes), `wings`, `side`, and
    `appendBands()` (centre-lines: `appendConn` for regular, `appendTrapConn` for the
    trapezoid). It uses the same `side/3` clip + wings path as square/triangle. The
    structural symmetry modes (4–7, grid-specific) are skipped for it
    (`rebuildLeaves`); pixel mirrors (1–3) still apply. Whole-trapezoid tile weights
    live in `TRAP_W` (not `weightsFor(n)`, which would alias the square); subdivided
    detail uses the triangle alphabet (`TRI_CONNS`/`TRI_W`).
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
  `p`/`P` palettes, `R`/Controls "rotate" = `rotatePalette()` (scheme-aware: in
  **duotone** it picks two random palette colours for fg/bg — `rotateDuotone` sets
  `duoRandom` + `duoBgIdx`/`duoFgIdx` (bg = the lighter), read by
  `tileFg`/`tileBg`/`canvasBgColor`, reproduced via `TRUCHET_DUO`. The pair must
  clear a **minimum luminance gap** (`0.4·` the palette's own range, always
  achievable) and differ from the current pair, so each press visibly changes.
  It draws from its **own** `java.util.Random` (`duoRng`), NOT Processing's
  `random()`: `draw()` reseeds `random()` to `seedVal` every frame (the
  `dirtyGradient` block), so reusing it picked the identical pair on every press —
  the original bug. Rotating the colour *order* is invisible in duotone since its
  extremes are luminance-picked, so for every **other** scheme `R` cycles the
  colour order via `Palette.rotate`. Selecting another palette clears `duoRandom`
  back to the luminance extremes), `C` scheme. There is no `cDark`/`cLight`. The gradient schemes pick via `random()`,
  so `draw()` re-seeds (`randomSeed(seedVal)`) after `setupGradient()` to keep the
  tile layout identical across schemes. `loadDefaults()` seeds **45** palettes
  from the COLOURlovers all-time most-loved list (hex verified against two
  verbatim top-100 dumps); `loadFromColourLovers()` can still refresh live but is
  Cloudflare-blocked in practice. To bake in more, add `fromHex(...)` lines there.
- **`ControlWindow.pde`** — a second PApplet (own window, launched in `setup()`
  via `runSketch`) with immediate-mode sliders/buttons writing straight to the
  main sketch's globals (`parent.*`) and calling `parent.redraw()`. If you add a
  tunable global, add a widget here too. The bottom **Image mode** section
  (img cols/lib/gamma sliders, image/stretch/invert toggles, a `selectInput`
  "Load image…" button) drives the Truchet halftone; its widgets set `imgDirty`.
- **`TileWindow.pde`** — a third PApplet window listing the active shape's tile
  **archetypes** (`parent.connsFor(n)`, or `parent.TRAP_CONNS` for the trapezoid —
  base connection sets, no rotations) with a slider per archetype that writes its
  selection weight into `parent.weightsFor(n)` / `parent.TRAP_W` (the same
  `TILE_W`/`TRI_W`/`HEX_W`/`TRAP_W` `pickWeighted` reads) and calls
  `parent.redraw()`. It draws each archetype with its own `drawArchetype()` (a
  compact copy of the band geometry, using `parent.lineIntersect`) — or
  `drawTrapArchetype()` (sampling `parent.trapArcSpec`) for the trapezoid — since
  drawing must target *this* window's canvas, not the main one. It reads
  `parent.shapeMode` each frame, so it relists automatically when the shape changes
  (the window is sized tall enough for the trapezoid's 8 archetypes).
- **`Animation.pde`** — the animation engine. The tile layout is stable per seed,
  so animation never rebuilds tiles: it modulates *render-time* geometry. A small
  registry (`AnimState anim`, normalized `volatile` `-1..+1` values:
  `bandWidthMod/discMod/rotationMod/arcSweepMod/arcRadiusMod/colorMod`) is the
  single sink — `setAnimValue(name, v01)` is the **thread-safe MIDI seam** a future
  Windows-host `javax.sound.midi` handler will write to. For now per-target `Lfo`s
  on a deterministic clock (`animSeconds`) drive it (`driveAnimFromLFOs`,
  `animSource == 0`). `draw()` calls `updateAnim()` once at the top, which advances
  the clock and writes the read-only frame-globals (`animBandScale`, `animDiscScale`,
  `animArcSweep`, `animArcRadius`, `animRotOffset`) the render passes multiply into
  the `side/3` strokes, disc radii, arc `r`/`diff`, and `TileGeom` rotation. When
  animation is off these are identity, so a static frame is byte-identical to before.
  `setAnimEnabled()` flips `noLoop()` ↔ `loop()`. **Connection-safe** modulators:
  `discMod` (and `colorMod`, reserved). **Connection-breaking** (intentional, the
  expressive set): `bandWidthMod`, `arcSweepMod`, `arcRadiusMod`, `rotationMod` —
  they move band edge-crossings off the 1/3–2/3 points so ribbons no longer meet at
  edges. Controls default the safe channel on, breaking ones at depth 0 (labelled
  `*` in the panel).
- **`ImageMode.pde`** — **Truchet halftone**: render a source image as a mosaic of
  multi-scale Truchet patches chosen by brightness (ASCII-art, but the "glyphs"
  are little tilings). Two phases, both reusing `collectTile` + `renderTiling`:
  **(1) calibration** (`buildLibrary`) generates `libSize` candidate patches —
  each one square cell subdivided from its own RNG seed (`collectPatch` pins the
  seed *and* `subdivideProb`, which is swept across `[0,1]` so the library spans
  sparse/bright → dense/dark) — renders them batched on the canvas and reads back
  each one's mean luminance via `loadPixels()` (ignoring a guard ring to avoid
  neighbour wing-spill); **(2) compose** (`buildMosaic`) lays the square grid
  (`gridN = imgCols`), area-samples the image per cell (`sampleGrid` cover-crops to
  the grid aspect), and places the patch whose measured brightness best matches
  (`sortLibrary` + `pickPatch`, nearest among K by a position hash so equal cells
  don't all repeat one patch), then renders the whole mosaic. Brightness is read
  off the *rendered* pixels in the active palette, so the mapping is faithful to
  any colour scheme (duotone reads cleanest). On load, `flattenOntoWhite()`
  composites any transparency onto white — **essential for logo/SVG PNGs**, whose
  transparent background is stored as RGB (0,0,0), identical to a black foreground,
  so without it the whole image samples as uniform black and collapses to one
  repeated patch. `sampleGrid` reduces the image to the cell grid in one of two
  fit modes (`imgContain`: contain + pad with the bright bg, default, nothing
  cropped — good for logos; else cover/crop — good for photos). Cached via
  `imgDirty`: rebuilt only
  when the image, mapping params, palette/scheme, or any patch-appearance global
  (depth, subdiv, winged, invert) changes. `imageChosen()` is the Controls
  "Load image…" `selectInput` callback. **The patch's intrinsic brightness is
  measured in isolation; the final mosaic adds a little uniform darkening from
  neighbours' overlapping wings — acceptable, and the histogram-stretch + nearest
  match absorb it. If you change tile geometry/colour, the library must be
  remeasured (it is, on `imgDirty`).**
- **Layout caching** (main tab): `leaves`/gradient are rebuilt only when
  `dirtyLayout`/`dirtyGradient` are set (in `rebuildLeaves`/`setupGradient` guards),
  not every animated frame. Every layout-affecting mutator (seed, grid, depth,
  subdiv, shape, symmetry, tile weights) sets `dirtyLayout`; palette/scheme set
  `dirtyGradient`; image-mode mutators set `imgDirty`. If you add a mutator that
  changes the tiling or colours, set the matching flag or the change won't show
  while animating.

Per-shape alphabets: `TILE_CONNS`/`TILE_W` (square, in the main tab), `TRI_CONNS`
(triangle: blank + single arc — one port per edge allows at most one arc),
`HEX_CONNS` (whole-hexagon tiles: fully-connected matchings only — including
distance-2 "sweeping" arcs; a subdivided hexagon becomes triangles and uses
`TRI_CONNS`), and `TRAP_CONNS`/`TRAP_W` (trapezoid: 8 motifs over its **5 ports**,
indices into `TRAP_PORT`, not edges). `connsFor(n)`/`weightsFor(n)` pick the right
one for the regular shapes; the trapezoid is keyed on `Tile.trap` instead (its `n`
is 4 and would otherwise alias the square), so `collectTile`, `TileGeom`, and the
panels branch on `trap`/`shapeMode == 3` to reach `TRAP_CONNS`/`TRAP_W`.

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
  `parent.saveRequested = true` and calls `redraw()`; the actual save
  (`saveTiling()`) runs at the end of the viz's `draw()` (step 4). This guarantees
  the saved PNG is the fully-drawn frame and avoids grabbing the pixel buffer from
  the wrong thread mid-render. `saveTiling()` builds the parameter-stamped filename
  (`saveBaseName()`) and prints the reproduce command (`reproduceCmd()`).
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
