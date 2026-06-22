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

Running opens **two windows**: the visualization and a single unified **Controls**
panel (1920×1080). The panel has three zones: a vertical tab rail on the left, the
active tab's parameter widgets in the middle column, and — always visible on the right
— the **tile pane** (shape + anchors/side switches, the active tileset selector, and
the 16 tile slots with per-tile weight sliders, the old separate "Tiles" window folded
in). See "Multi-window architecture" below. Most parameters are adjustable live from the
panel; the keyboard still
works on the visualization window: **SPACE** = new seed, **4/3/6/t** =
square/triangle/hexagon/trapezoid, **P/p** = prev/next palette, **R** = rotate palette
(in duotone, instead assigns two random palette colours to fg/bg — see `rotatePalette`),
**C** = colour scheme, **M** = symmetry (none/vertical/horizontal/quad/rot 180/
tile mir V/H/quad), **e** = toggle 3D extrusion, **E** = cycle extrude mode
(oblique/1-point), **a** = toggle animation, **g** = toggle base-grid overlay,
**l** = toggle line mode (parallel/concentric strokes), **k** = toggle Kumiko
lattice style (thin mitered strips, no wings — see "Kumiko lattice style" below),
**d** = toggle debug logging (see "Debug logging" below),
**S** = save a parameter-stamped PNG.

**Saving** (`saveTiling`, S key or the Controls Save button): the filename encodes
the displayed parameters + seed (e.g.
`truchet_trapezoid_duotone_seed4242_g5_d4_sub60_pal12.png`), and the **exact
headless command that reproduces the frame is printed to the console** (with
`TRUCHET_SCALE=2` so you can re-render the identical composition at higher
resolution — every render-affecting global has a matching `TRUCHET_*` override).
Headless runs (`TRUCHET_OUT`) also echo `name:` + `reproduce:` lines. Saves land in
a flat, gitignored `hires/` folder (`renderDir()`), parameter-stamped filename as
the index; the printed reproduce command writes its scaled export there too.

The filename (`saveBaseName`/`appearanceTokens`) is a *faithful* spec, not just an
index: beyond the always-shown layout fields it appends any appearance param that
**deviates from its default** — anchors/side (`k4`), line duty/subdiv (`line15d30s60`),
the duotone random fg/bg (`duo3-7`), shadow strength/size/angle (`sh50-40-45`), extrude
vp/depth/shade — so a default render keeps a short name but a tweak is never silently
dropped on a headless re-render (`reproduceCmd` still lists *every* param
unconditionally, `TRUCHET_ANCHORS` included). Continuous values round to integer
percent/degrees in the name.

**Render manifest — the authoritative, complete recipe (`renderManifest`/
`loadManifest`).** The filename is a lossy human index and `reproduceCmd` is env-only;
both historically omitted three pieces of *implicit* state — tile weights (Tiles-panel
edits), `anchorsPerSide`, and palette rotation — so a re-render could silently diverge
(this actually bit a real reproduction: a `k4` triangle frame re-rendered at the
default `k1` and at uniform weights, a completely different pattern). The fix: **every
save writes a JSON sidecar beside the PNG** (`foo.png` → `foo.json`, both the GUI
`saveTiling` and the headless `TRUCHET_OUT` path). The manifest holds **every render
global PLUS the exact tile catalog** (`currentCatalogJson()` — every tileset (all
shapes, all k) plus trapezoid weights, in the v2 `tiles.json` schema) **plus the
active-tileset selection** (`activeTilesets`, the per-(n,k) chosen tileset index) **and
the palette's exact colour order** (captures rotation). `TRUCHET_LOAD=foo.json`
(parsed first in `setup()`, so explicit `TRUCHET_*` vars still override — load a frame,
bump `TRUCHET_SCALE`) and the Controls **"Load render…"** button (`manifestChosen`)
both restore it via `loadManifest`, which sets the globals, overwrites the palette
colours, and applies the embedded catalog through the shared `applyCatalog()` (same
in-place reassignment `loadTileCatalog` uses, so `connsFor`/`weightsFor` and the panels
pick it up by reference). Because the catalog is *embedded*, reproduction is
**independent of `tiles.json` drift** — verified byte-identical (max pixel diff 0) even
after `tiles.json` weights are changed out from under it. `TRUCHET_SCALE`/`W`/`H` stay
env-only (they are output *resolution*, not composition), so one manifest renders the
same frame at any size. A GUI manifest load sets `controlsNeedSync`, and
`ControlWindow.syncFromParent()` refreshes the panel widgets next frame (otherwise the
sliders show stale values and the next drag would push the old set back).

The **GUI app starts with the active tileset's authored weights** — selecting a
curated 16-tile **tileset** is the point, so there is no blank-slate reset (the old
`zeroAllWeights()` startup call was removed). Tweak the mix live with the Tiles-panel
sliders, or switch tilesets with its selector. A tileset slot with weight 0 (or a blank
slot) is simply never picked; if *every* weight in the active tileset is 0,
`pickWeighted()` returns −1 and tiles render **blank** (wings only).

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
    itself under the axis reflection, with the edge origin `c0` per axis — vertical
    `(PI−2·rot)/(2π/n)`, horizontal `−2·rot/(2π/n)` — and for quad straddlers,
    symmetric about *both*; weighted as the normal roll conditioned on
    symmetry). The reflection acts on **ports** (`rotPort`/`reflPort`): a port
    (edge e, slot s) → (edge c0−1−e, slot k−1−s) — the edge reflects and, because a
    reflection reverses anchor order along an edge, the slot reverses too (k=1 = the
    plain edge reflection `e → c0−1−e`). So multi-anchor straddlers (k>1) get a
    truly self-symmetric motif, not just an edge-symmetric one. `addSymTwins()`
    emits the orbit (≤3 twins; an axis the tile straddles fixes it, collapsing the
    diagonal onto the surviving reflection).
    - **All four structural modes (4–7) work for any k** (verified 0% pixel
      mismatch at k=2 on the exact axes). The twin/rotation transforms reuse the
      source motif unchanged: a reflection/rotation is affine, mapping source
      vertex e → twin vertex e and so source anchor (e,s) → twin anchor (e,s)
      (slot preserved), making the twin the exact mirror with no port relabelling.
      The one subtlety: a multi-anchor connection across *opposite* (parallel)
      edges is a bezier, and `lineIntersect`'s tiny-denominator cutoff would flip a
      near-parallel pair between bezier and a huge-radius arc under FP noise —
      breaking the twin match — so the arc/bezier choice uses the scale-invariant
      `nearlyParallel` (|sin| of the edge angle) instead, which a tile and its
      flipped twin always agree on.
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

**Debug logging** (`TRUCHET_DEBUG=1` env, or the **d** key live; main tab). A
thread-tagged action+phase log for tracing crashes — built because the two windows
(viz, Controls) run on separate threads and mutate the shared globals, so the
prime suspect for the intermittent NPE is a **cross-thread race** (a panel edit swaps
the catalog / nulls `gradPaint` / rebuilds `leaves` mid-render). The facility
(`dbg`/`logAction`/`phase`/`dbgCrash`) prints `[+<s>][<thread>] CAT: msg` to the
console **and** to `logs/debug-<ms>.log` (gitignored, opened lazily, append mode), so
a crash that closes the window is still captured. `dbg()` early-returns when off, so
the off path is **byte-identical** (verified: same headless PNG with and without
`TRUCHET_DEBUG`, no `logs/` written). What it records:
- **ACTION** — every user action with its effect: `keyPressed` (logged at entry as
  `KEY '<k>'`), Controls toggles/buttons/sliders (`logAction` per branch +
  `setSliderFromMouse`), Tiles weight edits + reload, and the `manifestChosen`/
  `imageChosen` file dialogs (the prime race triggers). `lastAction` is quoted in a
  crash dump.
- **PHASE** — a cheap `renderPhase` breadcrumb set before each `draw()` step
  (`updateAnim`/`setupGradient`/`rebuildLeaves`/`renderTiling`/`applySymmetry`/…).
  Assigned always (read by the crash dump); the `dbg` line is emitted only when
  animation is **off**, so continuous playback doesn't flood the log.
- **CRASH** — `draw()` and **both panels' `draw()`** are wrapped in
  `try/catch (Throwable)` → `dbgCrash`, which dumps the offending **thread**,
  `lastAction`, `renderPhase`, a state line (scheme/shape/k/sym/image/line/extrude/
  seed) and the full stack trace to console + log, then `noLoop()`s to stop a flood.
  A crash is always recorded even if `d` was never pressed.
- **NULL** — defensive warnings (not throws) at the suspect dereferences
  (`gradPaint` in scheme 4, a null tile alphabet in `TileGeom`, `sourceImg` in
  `sampleGrid`) so a near-miss names the site.

The last `ACTION` + `thread` + `phase` before a `CRASH` block is what pins the
trigger. This only instruments — fixing the race (e.g. routing the offending panel
mutation through a viz-thread flag like `reloadCatalogRequested`/`saveRequested`) is a
follow-up.
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
Optional overrides: `TRUCHET_LOAD` (path to a render manifest `.json` — restores the
complete recipe as a baseline; any other `TRUCHET_*` set alongside still overrides it,
e.g. `TRUCHET_LOAD=foo.json TRUCHET_SCALE=4` re-renders the saved frame at 8K — see
"Render manifest" above), `TRUCHET_SHAPE` (0 square, 1 triangle, 2 hexagon, 3 trapezoid),
`TRUCHET_SCHEME` (0–4), `TRUCHET_SEED`, `TRUCHET_PALETTE` (index, wraps),
`TRUCHET_DUO` (`"bgIdx,fgIdx"` = duotone fg/bg as two palette-colour indices, the
reproducible form of the duotone "rotate"; omit for the default luminance extremes),
`TRUCHET_SYM` (0–7),
`TRUCHET_SHOWGRID` (0/1 = overlay the base root-tile lattice on top of the render;
re-derived from `buildRoots()` so it covers the whole canvas in every symmetry
mode — see `drawGridOverlay`), `TRUCHET_GRID`, `TRUCHET_DEPTH` (0 = single scale), `TRUCHET_SUBDIV` (subdivide
probability 0–1; `1` = uniform finest scale, handy for isolating subdivision
behaviour from coarse/fine mixing), `TRUCHET_ANCHORS` (anchor points per side k,
1–4; 1 = classic single-midpoint tiles; k>1 draws the active tileset's multi-anchor
tile types for that k — see "Multiple anchor points per side"), `TRUCHET_TILESET`
(active tileset index for the current shape+k; selects which 16-tile set renders — see
"Shared tile catalog"), `TRUCHET_SHADOW` (0/1),
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
Kumiko lattice style (thin mitered strips — see "Kumiko lattice style" below):
`TRUCHET_KUMIKO` (0/1), `TRUCHET_STRIP` (strip width as a fraction of the tile
side, default 0.10).
Metal style (foreground ink shaded as metal — see "Metal material style" below):
`TRUCHET_METAL` (0/1), `TRUCHET_METAL_MAT` (index OR name: gold/chrome/copper/steel/
brass), `TRUCHET_METAL_STYLE` (0 round-bevel, 1 flat-rim), `TRUCHET_METAL_BEVEL`
(bevel/rim width in px at 1080p, scaled by resolution, default 10),
`TRUCHET_METAL_LIGHT` (key-light azimuth, degrees).
Animation (headless verification of motion — the loop never starts in headless;
these pin a single deterministic frame): `TRUCHET_ANIM_T` (seconds → LFO-driven
frame at that phase), `TRUCHET_ANIM_RATE` (master LFO Hz), `TRUCHET_ANIM_DEPTH`
(set all LFO depths so motion is visible), and `TRUCHET_ANIM="name=v01,..."` to
pin exact registry values (e.g. `discMod=1.0`, `rotationMod=0.85`), which also
exercises the future MIDI sink.
Light pulse (comet along the connection paths — see `Pulse.pde`): `TRUCHET_PULSE`
(0/1 enable), `TRUCHET_PULSE_SPEED` (px/s), `TRUCHET_PULSE_TRAIL` (comet trail px),
`TRUCHET_PULSE_COUNT` (0 = all paths, else the N longest), `TRUCHET_PULSE_COLOR`
(0 palette-bright / 1 white-hot / 2 complementary accent). Pin the comet position
with `TRUCHET_ANIM_T` (the pulse rides the same deterministic `animSeconds` clock).
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

**Multiple anchor points per side** (`anchorsPerSide` = k, global; `TRUCHET_ANCHORS`,
Controls slider, default 1). A side carries **k ports** at `(s+0.5)/k` along the
edge (k=1 = the classic single midpoint). Everything scales by `1/k`: band width
`side/(3k)`, fg nub radius `side/(6k)`, and the bg wing discs (radius `side/(3k)`)
sit at the **k sub-segment boundaries per edge** (`s/k`, `s=0..k-1`) — i.e. the
corners *plus* the points *between* adjacent anchors — so each port crosses at the
central third of its `1/k` sub-segment and the bg discs fill the edge gaps between
bands. Every `1/k` sub-segment therefore reads as a self-contained k=1 edge
(bg-disc / band / bg-disc), and like the corner discs the between-anchor discs
coincide across a shared edge. (`bgWx` lists the n·k boundaries, `fgWx` the n·k
anchors; for k=1 they collapse to vertices / edge midpoints, byte-identical.) The
thirds invariant
**generalises**: a coarse edge's crossings stay a subset of its children's (verified
k=2), so the seamless multi-scale join holds — but **only when k is uniform across
the whole tiling** (a k=2 edge crosses at {1/6,1/3,2/3,5/6}, a k=3 edge at
{1/9,2/9,…}; they don't align), which is why k is a *global render parameter*, not
per-tile.

**Ports** number `n·k + 2n + 1`: the `n·k` **edge anchors** (`port = edge·k + slot`),
then `n` **apothem midpoints** (`n·k + e` = halfway from the centre to edge e's
midpoint), then the **centre** (`n·k + n`), then the `n` **vertices** (corners,
`n·k + n + 1 + v`). The apothem/centre/vertices are all *interior* ports
(`isInteriorPort`, `portXY` — vertices read as interior so they too get drawn
straight: a corner has no single edge line to arc on) — connection endpoints with no
wing nub (only edge anchors get nubs/the wing lattice). Vertices are the **Kumiko
lattice points**: strips run corner → opposite edge midpoint → centroid (asanoha).
They were appended *after* the centre so every existing `tiles.json` conn index is
unchanged. `selfMirrorMotif` returns false for any conn touching a vertex port
(`rotPort`/`reflPort` don't map corners), so straddlers in the structural symmetry
modes skip vertex motifs. A connection is:
- a **perpendicular circular arc** when both ports are edge anchors equidistant from
  their two edge-lines' intersection (all symmetric pairs, and every k=1 case →
  identical to the old path);
- a **cubic Bézier** (edge-anchor pair, asymmetric) with end tangents along the
  inward edge normals — still perpendicular at each anchor → seamless;
- a **straight line** when the connection is explicitly flagged `[a, b, 1]` *or*
  touches an interior port (no edge line to arc on). Straight connections between
  *adjacent* edges cross the edge off-perpendicular, so they don't connect across
  scales (decorative); the wing nubs still bridge same-scale neighbours.
- a **ring** — the tagged primitive `[CONN_CIRCLE, port]` (`= 102`) appends a closed
  circle (centre-line radius `side/(3k)`) at any port, stroked at band width like a
  band, so it flows through every pass and becomes **concentric rings** in line mode.
  Edge-port rings are clipped to the tile (half rings); interior-port rings are
  whole. `selfMirrorMotif` treats circle motifs as non-self-mirror (tagged), so
  straddlers skip them; twins mirror them fine (a ring is rotation-symmetric).
- a **solid point** — `[CONN_DOT, port]` (`= 103`) is a filled disc of band width
  (radius `side/(6k)`, the wing-nub size) at any port. A fill, not a stroke, so it is
  NOT in the band path (`appendMotifConn` returns for it); instead `gm.dotXY()` lists
  the dot centres and the four fill passes (`drawTileForeground`, `drawTileLineBundle`,
  `addTileShadow`, `drawExtrudeLevel`) draw/extrude/shadow them like wing nubs. Solid
  in every mode (no rings in line mode). Mainly useful at interior ports (which get no
  automatic nub); like circles it is tagged, so straddlers skip it and twins mirror it.

**Circuit-inspired primitives (`= 104..111`, `isInlineComp`/`isPointGlyph`).** Two
families of decorative motifs (NOT thirds-invariant — like adjacent-edge straight
bands), all **stroked polylines** so they flow through every pass via
`appendMotifConn` (solid stroke, drop shadow, 3D extrude, and line-mode offset =
parallel copies). Because they are fine linework, they are stroked at a **thin,
size-proportional weight** (`TileGeom.motifStrokeW()` = `side/(10k)`), NOT the full
band width `side/3` — which would blob their detail together. `appendBandsSplit`
routes the circuit motifs (`thinMotif()` = `isInlineComp || isPointGlyph`) into a
separate path from the regular bands; the solid (`drawTileBands`), shadow
(`addTileShadow`), and extrude (`drawExtrudeLevel`/`stampExtrudeBody`) passes each
stroke that path at `motifStrokeW()`. Line mode already strokes everything thin
(`lineStroke`), so it is unchanged. Mirrored in the tile-pane preview
(`ControlWindow.drawArchConn`/`drawArchGlyph`, reusing `parent.componentSD`) and the
standalone editor (`drawComponent`/`drawGlyph`).
- **inline components** `[code, a, b]` join two ports with straight leads + a motif
  in the middle, amplitude `side/(3.5k)`. `appendComponent` maps a unit-frame
  `componentSD(code, amp)` table — rows `{sFrac, dPerp}` or `{…, 1}` to start a new
  subpath (capacitor plates) — onto the A→B axis, folding the line-mode `offset` into
  the perpendicular. `CONN_RES` (`104`, resistor sawtooth zigzag), `CONN_IND` (`105`,
  inductor — 3 same-side semicircle bumps), `CONN_CAP` (`106`, two perpendicular
  plates with a gap between the leads), `CONN_STEP` (`107`, square-wave crenellation
  / right-angle steps).
- **point glyphs** `[code, port]` stamp one port and auto-orient **inward** (port →
  centroid; screen-up at the centre port), via `TileGeom.appendGlyph` → top-level
  `emitGlyph` in a local frame (`u` inward, `w` perpendicular, base unit `g =
  side/(6k)`). Offset is ignored (a glyph is a fixed mark, not a bundle).
  `CONN_GROUND` (`108`, stem + 3 decreasing bars), `CONN_ARROW` (`109`, shaft +
  inward chevron), `CONN_CROSS` (`111`, a `+`). `CONN_TERM` (`110`, a small open ring)
  is the exception — drawn via `appendCircle` at radius `side/(6k)`, so it goes
  concentric in line mode like `CONN_CIRCLE`.

All are sampled into the same polyline the stroke/shadow/extrude/line passes consume
(`TileGeom.appendPortConn`; the dispatch in `appendMotifConn` routes to it for any
`anchors > 1`, any interior port, or any straight-flagged conn, else the old k=1
`appendConn`). k=1 with plain edge pairs is byte-identical to before (the per-pass
`gm.bandW`/`fgR0`/`bgR0` equal `side/3`,`side/6`,`side/3`, and `gm.wholeHex` equals
the old `n==6` test). Multi-anchor hexagons are treated like any winged polygon (clip
+ wings); the wing-less batched coarse layer is `wholeHex = n==6 && k==1` only.
Per-(shape,k) alphabets are the **active tileset** for that (shape,k) (16 slots,
authored in the editor; `connsFor`/`weightsFor` → `activeTilesetFor(n)`); a (shape,k)
with no tileset renders blank (`BLANK_CONNS`). The straddler self-symmetry
test (`selfMirrorMotif` + `rotPort`/`reflPort`) is interior-port aware: an apothem
midpoint follows its edge under rotation/reflection, the centre is fixed — so
structural symmetry stays exact with interior/straight motifs (verified 0% at k=2).

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

### Kumiko lattice style (thin mitered strips)

`kumikoStyle` (key **k**, Controls toggle, `TRUCHET_KUMIKO`) renders bands as **thin
uniform strips with a `JOIN_MITER`/`CAP_SQUARE` join** — the Japanese woodwork-lattice
look (組子) — instead of the thick `side/3` Truchet band. Width is `stripWidthFrac *
side` (`TRUCHET_STRIP`, "strip width" slider, default `0.10`). It is the render-time
companion to the **vertex (corner) ports** the tile editor exposes: classic Kumiko
motifs are straight strips between vertices, edge midpoints, and the centroid
(asanoha = the three triangle medians, corner → opposite edge midpoint, crossing at
the centroid — author it as triangle conns `[7,1] [8,2] [9,0]` at k=1).

Three gates flip together when `kumikoStyle` is on: **wings off** (`wings = winged &&
!wholeHex && !kumikoStyle`, so no bg corner discs / fg nubs — bare strips on the
ground), **clip off** (`doClip = … && !kumikoStyle`, so strips spill across tile edges
and meet their neighbours at the shared lattice points), and the **thin mitered
stroke** at the three solid stroke sites via the shared `bandStroke(bandW, side, cap)`
helper (`drawTileBands`, `strokeHexBatch`, `drawTileLineBundle`'s full-thickness path).
Render-only — no layout rebuild — and **off ⇒ byte-identical** to the classic bands
(`bandStroke` collapses to the original `new BasicStroke(bandW·anim, cap, JOIN_ROUND)`,
and the wing/clip gates to their old expressions). **Multi-scale stays seamless**
because a coarse triangle's vertices and edge midpoints coincide with its rep-tile
children's lattice points, so a strip routed through those crosses edges at points that
subdivide consistently (no thirds-invariant needed — Kumiko strips connect at the
lattice, not via wing nubs). Wired into the filename (`_kumiko`+width%), `reproduceCmd`,
and the render manifest (`kumiko`/`stripWidth`) like every other render global; a
saved Kumiko frame re-renders byte-identical from its manifest (verified, max diff 0).

### Metal material style (foreground ink as shaded metal)

`metalMode` (Controls "metal" toggle on the Render tab, `TRUCHET_METAL`) renders the
foreground **ink** as a metallic surface (gold / chrome / copper / steel / brass). A
flat 2D shape has no surface normal, so the look hinges entirely on the **normal
model** — an earlier matcap attempt assumed a half-tube (every ribbon a cylinder) and
read as rubber. The fix (see `Metal.pde`): synthesise normals from a **signed distance
field of the whole ink region**, so thin ribbons and the big inverted "flats" are
treated identically, as a **flat metal top with a narrow chamfered edge**. No
OpenGL/GLSL and no external assets — it is plain Java2D + a per-pixel pass.

Pipeline (`drawMetalTiling`, hooked first in `renderTiling`, gated `if (metalMode)`;
it needs the whole figure at once so it replaces the per-level foreground passes):
1. **`buildInkMask`** — render the duotone figure/ground in grayscale (ink = white,
   paper = black), coarse-first (backgrounds then foregrounds per level), **AA on** so
   the white coverage at the silhouette doubles as a clean edge alpha. Ink is the
   ribbons on normal levels and the **background mass** on inverted levels
   (`tileInkInverted`), bands carved back out as paper — so the inverted flats become
   metal too (the thing the matcap couldn't do). Non-duotone schemes treat the
   foreground as ink.
2. **`edtSquared`** — exact Euclidean distance transform (Felzenszwalb & Huttenlocher,
   separable 1D passes) → distance-to-edge per ink pixel.
3. **`shadeMetalLayer`** — per pixel: outward direction = −gradient of the (box-blurred)
   distance; **round-bevel** tilts the normal up only within `bevel` px of the edge
   (flat top elsewhere), **flat-rim** keeps the top flat and adds a bright bevelled lip
   at the edge. The normal is shaded as metal (`shadeMetalPixel`: Blinn-Phong + a
   2-stop environment reflection + Fresnel; metals tint the environment by the base
   colour). AA coverage from step 1 is the output alpha → crisp anti-aliased silhouette.
4. Composite the ARGB metal layer over the paper canvas (`background(canvasBgColor())`
   already laid the light paper down, which also shows through the carved channels).

Two **bevel styles** (toggle/`TRUCHET_METAL_STYLE`): `0` round-bevel (dimensional cut
metal), `1` flat-rim (flat foil with a highlighted edge). `metalBevelPx` (the "bevel
width" slider) is px at 1080p, scaled by resolution so it is export-independent;
`metalLightDeg` rotates the key light. Works across all shapes (square/triangle/
hexagon/trapezoid) and k. **Off ⇒ byte-identical** (single gated branch in
`renderTiling`; verified). Wired into the filename (`_metal-<name>[-rim]`, +`b`/`l`
when bevel/light deviate), `reproduceCmd`, and the render manifest (`metal`/`metalMat`/
`metalStyle`/`metalBevel`/`metalLight`); a saved metal frame re-renders byte-identical
from its manifest (verified). **Interactions:** the background stays the flat paper
colour (only the ink is materialised); under image mode a metal change sets `imgDirty`
(it changes patch brightness). Cost: a full-canvas EDT + per-pixel shade — fine at
1080p, a few seconds at 8K (a render-time pass, not for live animation). A future
option is a GLSL/deferred lighting pass for speed + true cubemap reflections.

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
- **`ControlWindow.pde`** — the single unified control panel: a second PApplet
  (own window, `1920×1080`, launched in `setup()` via `runSketch`) with immediate-mode
  sliders/buttons writing straight to the main sketch's globals (`parent.*`) and calling
  `parent.redraw()`. **Three zones** (`draw()` → `drawRail()` / `drawControlColumn()` /
  `drawTilePane()`, with zone backgrounds + divider lines):
  - **Left tab rail** — a vertical stack of the seven tab buttons (`drawRail`/`tabAt`
    are vertical now). A click sets `activeTab`.
  - **Middle control column** — the active tab's widgets, laid out from the shared
    `contentTop` (tabs reuse the same vertical space): **Tiles** (grid, depth, subdiv
    sliders + winged, grid-overlay toggles), **Color** (scheme, palette
    prev/next/rotate + swatches, invert/level), **Sym** (symmetry mode + a help blurb),
    **Shadow** (drop/global shadow + angle/size/strength, extrude 3D + mode, vp x/y,
    extrude depth/shade), **Anim** (animate, rate, disc/band/rot/arc depth), **Render**
    (line mode, count/duty/subdiv, kumiko style, strip width), and **Image** (image mode
    + halftone params + Load image). Each widget carries a `tab` index;
    `draw()`/`mousePressed()` only render + hit-test the active tab's widgets (plus the
    `tab -1` **persistent action bar** — New seed / Save PNG / Load render… — at the
    column bottom). **Wiring is by named reference** (`sGrid`, `tgShadow`, …), *not* list
    index, so widgets can be freely reordered without misbinding. The "Load render…"
    button `selectInput`s a manifest → `manifestChosen`; "Load image…" → `imageChosen`.
    Image-mode widgets set `imgDirty`. If you add a tunable global, add a widget here too
    (via the `addSlider`/`addToggle`/`addButton` factory helpers, passing the owning tab)
    — and extend **both** `syncParent()` (widgets → globals, on edit) and
    `syncFromParent()` (globals → widgets, after a manifest load sets `controlsNeedSync`),
    or the panel drifts out of agreement.
  - **Right tile pane** (`drawTilePane`, always visible — folded in from the old
    separate Tiles window) — for the active shape's **active tileset**. A header carries
    the **shape + anchors/side** segmented switches (a row of shape-pictogram buttons and
    a row of 1–4 number buttons, custom-drawn via `drawShapeButton`/`drawSegButton`/
    `drawShapePicto`, hit-tested in `tilePanePressed()` — they drive which tileset shows),
    a **tileset selector** (`◀ / label / ▶`, via `parent.setActiveTileset(±1)` +
    `parent.tilesetCount()`/`activeTilesetOrdinal()`; hidden for the built-in trapezoid),
    and **Reload tiles.json** / **Reset weights** buttons. Below, a roomy **2-column grid
    of 16 slot cards** lists the tileset's slots (`parent.connsFor(n)`, or
    `parent.TRAP_CONNS` for the trapezoid) each with a large preview, a **solo** button,
    and a weight slider that writes into `parent.weightsFor(n)` / `parent.TRAP_W` **in
    place** (the same array `pickWeighted` reads — NOT part of `syncParent`). Each slot is
    drawn by `drawArchetype()` (band geometry via `parent.lineIntersect`, with
    hub/hump/glyph/component branches in `drawArchConn`/`drawArchGlyph`) or
    `drawTrapArchetype()` (sampling `parent.trapArcSpec`). It reads
    `parent.shapeMode`/`anchorsPerSide` each frame, so it relists automatically. Tile-pane
    geometry helpers are pane-prefixed (`tileCellX`/`tileTrkX0`/`tileTrkX1`/`soloX`) to
    avoid colliding with the control-column slider helpers (`trkX0(Slider)`/`trkX1(Slider)`).
    **Reload tiles.json** re-reads the catalog *without restarting* — it sets
    `parent.reloadCatalogRequested` (a flag, like the Save button, so the swap runs on the
    viz thread at the top of `draw()`, not cross-thread); `draw()` then calls
    `loadTileCatalog()` + sets `dirtyLayout`. Because `loadTileCatalog`/`applyCatalog`
    reassign the tileset maps in place and the panel reads them by reference, newly
    authored tilesets appear immediately — the live-reload the "author → restart" workflow
    used to require.
  - **Headless panel verification** (the project forbids screenshotting windows):
    `TRUCHET_PANEL_OUT=path` dumps the panel's first fully-drawn frame to `path` and exits
    (the `save()` + `System.exit` live at the end of `ControlWindow.draw()`); pair it with
    `TRUCHET_PANEL_TAB=0..6` to open on a specific tab and the usual `TRUCHET_SHAPE`/
    `TRUCHET_ANCHORS`/etc. to pin the pane's state. Mirrors `TILEEDITOR_OUT`.
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
  `*` in the panel). The registry also carries `pulseSpeedMod/pulseWidthMod/
  pulseGlowMod` for the light-pulse overlay (see `Pulse.pde`).
- **`Pulse.pde`** — an animated **light pulse** (comet: bright head + fading trail)
  flowing along the connection curves, like energy through an energized circuit. It
  is a pure **overlay**: never touches `leaves`/`dirtyLayout`, fully gated (off ⇒
  output byte-identical). **Path graph** (`rebuildPulsePaths`, cached): per leaf,
  `TileGeom.sampleBand(ci)` returns each "wire" connection's centre-line polyline
  (plain pairs/straight/hump/inline-component-chord; dots/rings/glyphs/hubs
  excluded); endpoints are spatial-hashed (`PULSE_QUANT` ≈0.35px, 3×3 neighbour
  probe) so segments sharing a coordinate link into **chains + loops** (band ends
  carry ≤1 conn/tile → mostly degree-≤2). Built on **neutral geometry** (anim
  frame-globals frozen to identity around the build) so the graph is layout-only and
  stable; rebuilt from `rebuildLeaves` (sets `dirtyPaths`) + the `draw()` guard.
  **Cross-scale bridging:** for k=1 a centre-line crosses an edge at its *midpoint*
  (½), but a coarse↔fine boundary puts the fine midpoints at ¼/¾ — so centre-lines
  don't share a node (only the filled band *regions* abut). A bridging pass greedily
  connects nearby degree-1 open-ends (within ≈`1.3·max(bandW)` — the edge/4 gap) with
  a short connector segment, **keeping every node degree ≤2** so the simple chain/loop
  tracer still works — this lets a comet flow across scale seams and merges short
  runs into longer paths. (Genuine terminals where the neighbour has no band stay
  open — the comet fades there; `interiorOpenEnds` under `TRUCHET_DEBUG` tracks how
  many remain.) **Pulse model**: head arc-pos `= speed·animSeconds + per-path phase`,
  deterministic + looping; closed loops wrap seamlessly, open paths slide in/out past
  the ends (fade). **Glow**: an offscreen `glowLayer` (cloning the extrude-layer idiom)
  stroked as segmented sub-spans with head→tail alpha falloff and a 3-stroke bloom;
  the glow **fills the LOCAL band width** (`PulsePath.w` stores per-sample band width,
  so the comet lights up whatever ribbon it's in — thick on coarse, thin on fine — and
  transitions across a bridged scale seam), with a soft halo just outside and a bright
  inner core; colour is a **complementary accent** (`pulseRGB`, palette-bright /
  white-hot alternatives via `pulseColorMode`). Composited in `draw()` **between `renderTiling()` and
  `applySymmetry()`** so pixel mirrors reflect the comets. Globals
  `pulseEnabled/pulseSpeed/pulseTrail/pulseCount` (Controls "Anim" tab toggle +
  sliders; `pulseCount` 0 = all paths). Headless: `TRUCHET_PULSE` (+`_SPEED/_TRAIL/
  _COUNT/_COLOR`); phase pins via the existing `TRUCHET_ANIM_T`. Cross-scale
  health diagnostic (`TRUCHET_DEBUG`): `interiorOpenEnds` count.
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
- **`Metal.pde`** — the **metal material style** (see "Metal material style" above):
  material presets (`MetalMat`/`buildMetalMats`), the per-pixel metal shader
  (`shadeMetalPixel`), the separable exact-EDT distance transform (`edtSquared`/
  `edt1d`), the 1-bit ink-mask render (`buildInkMask`/`maskTileBg`/`maskTileFg`,
  `tileInkInverted`), and `drawMetalTiling` which ties SDF → normals → shade →
  composite. Self-contained Java2D (no OpenGL/GLSL).
- **Layout caching** (main tab): `leaves`/gradient are rebuilt only when
  `dirtyLayout`/`dirtyGradient` are set (in `rebuildLeaves`/`setupGradient` guards),
  not every animated frame. Every layout-affecting mutator (seed, grid, depth,
  subdiv, shape, symmetry, tile weights) sets `dirtyLayout`; palette/scheme set
  `dirtyGradient`; image-mode mutators set `imgDirty`. If you add a mutator that
  changes the tiling or colours, set the matching flag or the change won't show
  while animating.

**Tagged tile primitives (square).** The 4-edge matching alphabet is mathematically
complete at 5 archetypes (blank / single arc / single band / two diagonal arcs /
two crossing bands — all the ways to pair ≤4 edges). To go beyond pairs, two
`TILE_CONNS` entries are **tagged primitives**: a connection whose first slot is
`>= CONN_TAG` (100) is not an edge pair but `{CONN_HUMP, i, j}` (an opposite-edge
arch — a raised cosine that enters i and j perpendicular at the central third, so
it stays seamless and multi-scale-safe) or `{CONN_HUB, e0, e1, …}` (a centre-spoke
junction — straight spokes from the tile centroid to each listed edge midpoint; a
3-spoke hub is a T/Y, generalizing the band = 2-spoke and CrossCross = 4-spoke).
`TileGeom.appendBandsOffset` dispatches these (`appendMotifConn` → `appendHub`/
`appendHump`) so they flow through every pass (bands, shadow, extrude, line mode)
and the Tiles panel preview. They're excluded from straddler self-symmetry
(`selfMirrorMotif` returns false for tagged conns). Rotation (`mk`) covers all
orientations, so one hub + one hump archetype yields the full T/arch families.

Per-shape alphabets: `TILE_CONNS`/`TILE_W` (square, in the main tab), `TRI_CONNS`
(triangle: blank + single arc — one port per edge allows at most one arc),
`HEX_CONNS` (whole-hexagon tiles: fully-connected matchings only — including
distance-2 "sweeping" arcs; a subdivided hexagon becomes triangles and uses
`TRI_CONNS`), and `TRAP_CONNS`/`TRAP_W` (trapezoid: 8 motifs over its **5 ports**,
indices into `TRAP_PORT`, not edges). `connsFor(n)`/`weightsFor(n)` pick the right
one for the regular shapes; the trapezoid is keyed on `Tile.trap` instead (its `n`
is 4 and would otherwise alias the square), so `collectTile`, `TileGeom`, and the
panels branch on `trap`/`shapeMode == 3` to reach `TRAP_CONNS`/`TRAP_W`.

The hardcoded square/triangle/hexagon alphabets (`TILE_CONNS`/`TRI_*`/`HEX_*`) are
**built-in seed defaults** only — used to seed a fresh `tiles.json`; at runtime
rendering routes through the **active tileset** (see "Shared tile catalog" below). The
trapezoid is *not* catalogued (port-based, bespoke arc specs) and stays hardcoded.

## Shared tile catalog (`tiles.json`): named 16-tile tilesets + tile editor

Tile types are organised into **TILESETS**: a tileset is **exactly 16 tile slots**
that share a shape and a k (anchors/side). Each (shape, k) may have several tilesets;
the visualizer selects which one is **active** (Tiles-panel selector / `TRUCHET_TILESET`),
and renders from it. The shared `tiles.json` (repo root) is authored in a standalone
editor and read by the visualizer, so: build a tileset in the editor → select it in the
visualizer. Runtime state lives in `tilesetsByNK` (key `"n_k"` → `ArrayList<Tileset>`)
and `activeTilesetIdx` (key `"n_k"` → active index); `connsFor(n)`/`weightsFor(n)` →
`activeTilesetFor(n)` resolve the active set's 16 conns/weights (by reference, so panel
edits land live), `BLANK_CONNS` if that (shape, k) has none.

`loadTileCatalog()` (main tab, early in `setup()` — before the headless `TRUCHET_OUT`
return) loads `tiles.json`: **missing** → seed a fresh v2 default (one k=1 tileset per
shape from the built-in alphabets, padded to 16) and write it; **old v1 (flat) file** →
**back it up to `tiles.v1.backup.json`** and replace with the fresh seed (start fresh,
no auto-migration); **v2** → `applyCatalog`. A v1 catalog *embedded in an old manifest*
is converted on the fly (`v1ToV2`, splitting each (shape,k) group into 16-tile sets) so
old renders still reproduce.

- **Schema (v2):** `{ "version":2, "tilesets":[ … ] }`; each tileset is
  `{ "shape":"square", "sides":n, "anchors":k, "tiles":[ …16… ] }`. `sides`/`anchors`
  are per-tileset; each of the 16 `tiles` is `{ "conns":[…], "weight":n }` (a blank
  slot = `{ "conns":[], "weight":0 }`). A connection is a JSON array of ints — a plain
  `[i,j]` edge/port pair, `[a,b,1]` (straight), **or** a tagged primitive
  `[CONN_HUB,…]`/`[CONN_HUMP,i,j]`/`[CONN_CIRCLE,p]`/`[CONN_DOT,p]` (codes ≥100);
  `jsonToConns`/`connsToJson` round-trip **variable-length** conns. Ports index `n*k`
  edge anchors + `n` apothem midpoints + the centre + `n` vertices (the Kumiko lattice
  points). See "Multiple anchor points per side" and "Ports" above. (`jsonToTileset`/
  `tilesetToJson` (de)serialize a tileset; `currentCatalogJson` dumps every tileset for
  the manifest; the trapezoid keeps a separate `"trapezoid"` weights array.)
- **Editor:** `TileEditor/TileEditor.pde` is a **separate sketch** (not a window of
  the main one), in a subfolder — Processing only compiles a sketch folder's
  top-level `.pde`, so it does not affect building/running the main sketch. Run it
  with `processing-java --sketch=/mnt/e/Multiscale_Truchet/TileEditor --run`. Pick
  Square/Triangle/Hexagon and an **anchors/side** count (k = 1..4), then create/select
  a **tileset** for that (shape, k) — **New set** appends 16 blank slots, **< Set /
  Set >** browse, **Del set** removes — and click a cell in the **4×4 slot grid** to
  make it the edit target (its content loads into the work buffer). Author the motif:
  pick a **tool** from the pictogram palette (right of the preview), then click points.
  Clickable points are the edge anchors, the **interior** ports — the apothem midpoints
  and the centre, drawn with a green tint — and the **vertices** (corners), drawn
  **amber** (the Kumiko lattice points); connections touching an interior *or* vertex
  port are always straight lines. The palette has two groups (`tool` int, `TOOL_*`;
  `drawToolButton`/`drawToolIcon`): **Connect (2 clicks)** — click one point then a
  second — is **Arc** (default: perpendicular arc / bezier, matching the engine),
  **Line** (straight `[a,b,1]`), and the four inline components **Res / Ind / Cap /
  Step** (`[CONN_RES/IND/CAP/STEP, a, b]`); **Stamp (1 click)** drops a single-port
  glyph — **Ring** (`[CONN_CIRCLE,p]`), **Dot** (`[CONN_DOT,p]`), **Gnd**
  (`[CONN_GROUND,p]`), **Arrow** (`[CONN_ARROW,p]`), **Term** (`[CONN_TERM,p]`),
  **Cross** (`[CONN_CROSS,p]`); clicking the same port again with a stamp tool removes
  it. A point may carry **more than one connection** (repeat from the same point);
  **right-click** a point to remove the most-recent connection touching it. The
  component/glyph geometry is duplicated from the engine (`drawComponent`/`componentSD`/
  `drawGlyph`, mirroring `Shapes.pde appendComponent`/`emitGlyph`). The editor shows/edits only the active **tileset**
  for the current **(shape, k)** (other (shape, k) stay untouched in the file). The
  **4×4 slot grid** along the bottom (`drawSlotGrid`) shows the active tileset's 16
  slots (index + weight; the slot being edited is boxed; blank slots are empty) — click
  one to edit it. Set a weight; **Save** writes the work buffer **into the current slot**
  (overwrite), **Clear** blanks it. A **Wings** toggle
  button shows/hides the Carlson wings
  (`showWings`; square/triangle only — whole hexagons never have wings), so you can
  judge a motif either as the bare clipped bands or with its connection discs. A
  **Kumiko** toggle (`kumikoStyle`) previews the motif in the main sketch's Kumiko
  lattice style — thin uniform strips (`stripWidthFrac`·side, default 0.10) with a
  square cap + mitered join and wings forced off — so a vertex-port motif (asanoha,
  etc.) reads as it will render. (The interactive preview, rotations column, and
  slot grid all share `renderTile`, so they follow both toggles.) A
  **rotations column** down the right edge shows small
  thumbnails of every phase the placer can roll (the tile rotated by `k·(2π/n)`,
  `k = 0..n-1`) — `renderTile(...)` draws both the large interactive tile and the
  thumbnails. It writes the same `tiles.json` the visualizer loads, so the
  workflow is: build a tileset in the editor at some k → in the visualizer set
  **anchors/side to the same k** (Controls / `TRUCHET_ANCHORS`), pick the **tileset**
  (Tiles-panel selector), and hit **"Reload tiles.json"** (or restart) → the set is in
  rotation. (The catalog is also read at startup; the Reload button is the live path.)
  - Headless verification (never screenshot the window): `TILEEDITOR_OUT=path`
    saves the first fully-drawn frame and exits; `TILEEDITOR_SHAPE` (0/1/2),
    `TILEEDITOR_ANCHORS` (k), `TILEEDITOR_TILESET` (active tileset index),
    `TILEEDITOR_SLOT` (0–15), `TILEEDITOR_CONNS` (`"a-b,a-b,..."` port pairs) preload
    state, `TILEEDITOR_WINGS` (0/1) sets the wings toggle, `TILEEDITOR_KUMIKO` (0/1)
    sets the Kumiko-strip preview, and `TILEEDITOR_SAVE=1` writes the preloaded buffer
    into the chosen tileset/slot (creating a tileset if none) and exits (save
    round-trip test), e.g. `TILEEDITOR_OUT=/tmp/e.png TILEEDITOR_SHAPE=0
    TILEEDITOR_ANCHORS=2 TILEEDITOR_SLOT=0 TILEEDITOR_CONNS="1-2,3-4,5-6,7-0"`.
- Being a separate sketch, the editor **duplicates** the few geometry bits it
  needs (`lineIntersect`, and the vertex/edge-midpoint + band/arc construction
  copied from `ControlWindow.drawArchetype`, including the hub/hump render branches so
  loaded motifs preview correctly) rather than sharing them. It uses the same
  `rot`/`R` convention as `drawArchetype`, so a preview matches the tile pane and
  the canvas. Edge indices are rotation-invariant for tiling, so one representative
  orientation suffices. No connectivity rule is enforced — crossing bands (square
  `[0,2],[1,3]`) and **multiple connections sharing one edge** are both allowed.
  The tile pane's
  in-memory weight edits are *not* persisted; on restart `tiles.json` wins (the
  editor is the catalog's source of truth).

## Multi-window architecture (control panels)

The GUI panel is a **separate `PApplet`**, not a GUI library. Processing
supports multiple windows by running additional `PApplet` instances; the main
sketch's `setup()` launches the panel with
`PApplet.runSketch(new String[]{"Controls"}, controls)` and hands it a `parent`
reference back to the main sketch (one panel now: `ControlWindow`, which absorbed
the former separate `TileWindow`). Widgets are drawn immediate-mode (custom
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
  `parent.saveRequested = true` and calls `redraw()`; the actual save
  (`saveTiling()`) runs at the end of the viz's `draw()` (step 4). This guarantees
  the saved PNG is the fully-drawn frame and avoids grabbing the pixel buffer from
  the wrong thread mid-render. `saveTiling()` builds the parameter-stamped filename
  (`saveBaseName()`) and prints the reproduce command (`reproduceCmd()`).
- **Keep widgets in sync with globals.** `syncParent()` maps sliders/toggles onto
  `parent.*` by **named reference** (`sGrid`, `tgShadow`, …, registered via the
  `addSlider`/`addToggle`/`addButton` helpers with their owning tab); the
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
