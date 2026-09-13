# SynthCap

SynthCap is a synthetic-data generator for vehicle detection models: it uses Arma 3 as a renderer to spawn vehicles in randomized poses, damage states, weather and lighting, photograph them from a scripted UAV-style camera, and emit a 2D bounding box + metadata label for every visible object. Output is PNG images plus JSONL label files, suitable for training an object detector.

It has three moving parts that only make sense together:

| Layer | Where | Runs |
|---|---|---|
| Orchestrator | `orchestrate.py` | On your machine, outside Arma. Drives one or many Arma processes across a list of worlds/maps. |
| Mission scripts | `init.sqf`, `params.sqf`, `randMap.sqf`, `fn/*.sqf` | Inside Arma, as a mission. Do the actual spawning, camera work, and labeling. |
| Native extension | `synthcap_rust/` (Rust, builds to `synthcap_x64.dll`) | Loaded into Arma via `callExtension`. Fast buffered file I/O for the label writer, since SQF's own file I/O is awkward/slow for this. |

This README covers what the pieces do, how to build and configure them, and the gotchas that are easy to get wrong (several are already called out in code comments — they're consolidated here so you don't have to go hunting).

## Contents

- [How it fits together](#how-it-fits-together)
- [Prerequisites](#prerequisites)
- [Suggested repo layout](#suggested-repo-layout)
- [Building the Rust extension](#building-the-rust-extension)
- [Configuring a run](#configuring-a-run)
- [Running it](#running-it)
- [Output layout and label schema](#output-layout-and-label-schema)
- [Determinism](#determinism)
- [Gotchas (from the code's own comments)](#gotchas-from-the-codes-own-comments)
- [Known gaps / loose ends in this codebase](#known-gaps--loose-ends-in-this-codebase)
- [Extension command reference](#extension-command-reference)
- [Suggested first run](#suggested-first-run)

## How it fits together

1. **`orchestrate.py`** builds a mission folder under `<Arma3>/Missions/synthcap.<world>/` by copying the SQF sources and appending a generated config block (seed, resolution, aperture, pose bands, output dir) to the end of `params.sqf`.
2. It launches `arma3_x64.exe` with flags for a minimal, windowed, unsigned, mod-loaded session, and points it at that mission.
3. **`init.sqf`** compiles and runs every script in order (`params.sqf`, then `fn/rng.sqf`, `fn/camera.sqf`, `fn/project.sqf`, `fn/visibility.sqf`, `fn/capture.sqf`, `fn/sqfFileWrapper.sqf`), then after a short delay hands off to `randMap.sqf`.
4. **`randMap.sqf`** is the scene generator and capture loop:
   - Seeds the custom PRNG (`fn/rng.sqf`) from `SC_masterSeed` — SQF's built-in `random` cannot be seeded, so the mission never calls it; everything goes through `SC_fnc_rand`/`SC_fnc_randRange` instead, which is what makes a `(terrain, sceneIndex, masterSeed)` triple reproducible.
   - Runs several "passes": picks a random terrain anchor, spawns 1–8 vehicles around it from `SC_vehicleTable` (rejecting water/non-flat spots), assigns damage and orientation states by exact quota (not per-vehicle dice — see `SC_fnc_quota`), lets them physically settle, then freezes simulation on them.
   - Caches each vehicle's 3D bounding-box sample points once, since the scene is frozen and nothing will move again (`fn/project.sqf`'s `SC_fnc_cacheBoxPoints`).
   - Loops **weather combo × pose band × look point**: applies weather/time-of-day, poses the camera (`fn/camera.sqf`), cheaply checks whether the frame would contain anything worth keeping before bothering to shoot, then calls `SC_fnc_captureFrame` (`fn/capture.sqf`), which preloads the scene, takes the screenshot (retrying up to 5×), and — only once the PNG write is confirmed — logs one `META` line and one label line per kept object.
   - Runs a second "background" phase with vehicles hidden, to generate negative (no-target) frames.
5. Screenshots land in `<profile>/Screenshots/`. The orchestrator's `Sweeper` thread continuously moves them into `out/images/<world>/`, because Arma caps that folder at 250 MB by default and silently stops writing once it's full.
6. `orchestrate.py --mode collate` merges every `labels_*.jsonl` shard into `labels_all.jsonl`, dropping any label record whose image never actually made it to disk (crash, stall, or quota mid-run).

## Prerequisites

- **Arma 3** on Windows — the orchestrator shells out to `arma3_x64.exe` directly and all its configured paths are Windows paths (`D:\SteamLibrary\...`). It needs to run **without** `-noLogs`; the label pipeline depends on the RPT log existing.
- **Steam Workshop mods** matching the vehicle table in `params.sqf`: CBA_A3, CUP (Terrains Core, Weapons, Units, Vehicles + several nation packs), IFA3 AIO, SFP Finnish/Swedish packs, RK62 Pack, HAFM Helicopters, Northern Fronts Terrains. See `MOD_IDS` in `orchestrate.py`. A missing mod isn't fatal — `randMap.sqf` filters unresolvable classnames out of the spawn pool at startup and logs `SYNTHCAP|BADCLASS|...` — but your effective vehicle pool will silently shrink.
- **Rust** (stable), with a target matching your Arma install's architecture (x86_64 Windows) to build the extension.
- **Python 3.10+**, standard library only — `orchestrate.py` has no third-party dependencies.

## Suggested repo layout

The orchestrator's `find_script()` looks for each `fn/*.sqf` file either flat in `SRC_DIR` or under `SRC_DIR/fn/`, and `SRC_DIR` is hardcoded near the top of `orchestrate.py` as `./mission` (relative to wherever you invoke the script from). A layout that matches both conventions and keeps the repo tidy:

```
synthcap/
├── orchestrate.py
├── synthcap_rust/
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── src/
│       └── lib.rs
├── mission/                  # SRC_DIR — must contain init.sqf at its root
│   ├── init.sqf
│   ├── params.sqf
│   ├── randMap.sqf
│   └── fn/
│       ├── rng.sqf
│       ├── camera.sqf
│       ├── project.sqf
│       ├── visibility.sqf
│       ├── capture.sqf
│       └── sqfFileWrapper.sqf
└── out/                       # OUT_DIR — created automatically
    ├── images/<world>/*.png
    └── labels_*.jsonl
```

## Building the Rust extension

```
cd synthcap_rust
cargo build --release --target x86_64-pc-windows-msvc
```

`Cargo.toml` sets `crate-type = ["cdylib"]` and `name = "synthcap_x64"`, so the build produces `synthcap_x64.dll`. That naming is not cosmetic: SQF calls it as `"synthcap" callExtension [...]`, and Arma resolves an extension named `synthcap` to a file called `synthcap_x64.dll` on 64-bit. Keep the lib name in sync with the call name if you ever rename either.

Place the built DLL somewhere Arma will find it for the `synthcap` extension — next to `arma3_x64.exe` is the safe default for an unsigned dev extension loaded via `-filePatching`. Verify it loaded by checking the RPT for the `SYNTHCAP|EXT|version|...` line that `fn/sqfFileWrapper.sqf`'s `SC_fnc_extOpen` logs on startup; `synthcap version` returning empty means the DLL isn't being found or isn't loading (usually a missing VC++ runtime or wrong bitness).

## Configuring a run

Two layers, both worth understanding:

1. **`params.sqf`** — the mission's own baseline config, checked into source: image geometry, camera FOV, labeling thresholds (`SC_minVis`, `SC_minBoxPx`), the vehicle table (classname → category — this is the single source of truth for both the spawn pool and the labels; there's no way to spawn a class that isn't in this table), pose bands (altitude/pitch ranges per "shot type"), weather and time-of-day states with weights, damage/orientation mixes, and per-terrain exposure corrections. Its own comment says the orchestrator overwrites it per run — that isn't quite literal: `build_mission()` **appends** an `AUTOGENERATED per-run overrides` block to the end of the copied file (see `RunConfig.overrides_sqf()`), which reassigns `SC_masterSeed`, `SC_imgW`/`SC_imgH`, `SC_aperture`, `SC_poseBands`, `SC_outDir`, and recomputes the values derived from them (`SC_camReach`, `SC_cullCos`, `SC_labelRangePx`). Because SQF executes top to bottom, these overrides win over the earlier assignments in the same file — the checked-in values are effectively just defaults for scripts that don't go through the orchestrator.
2. **`orchestrate.py`'s `CONFIG` block** (top of the file) — `ARMA_DIR`, `PROFILE_DIR`, `OUT_DIR`, `SRC_DIR`, the mod list, world sets, base seed, and timeouts. Edit these constants directly before running; there's no separate config file for the Python side.

**Resolution gotcha to not skip:** `SC_imgW`/`SC_imgH` (or the orchestrator's `img_w`/`img_h`) must equal the *actual* pixel size of the screenshots Arma writes — i.e. window resolution × sampling %. `write_arma3_cfg()` keeps `Render_W/H == Resolution_W/H` at 100% sampling specifically so this always holds; if you change graphics sampling in-game or in the profile afterward, every bounding box in your dataset silently scales by a constant, wrong factor with no error anywhere.

## Running it

All commands from wherever `SRC_DIR` (`./mission`) resolves relative to:

```bash
# 1. Get real worldName classnames for whatever mods you have subscribed.
#    Writes out/worlds.txt and out/worlds_list.py.
python orchestrate.py --mode dump-worlds

# 2. Enumerate spawnable CfgVehicles across your mod set and auto-bucket them
#    into categories. Writes out/vehicles_table.sqf — paste into params.sqf's
#    SC_vehicleTable once you've eyeballed the classification.
python orchestrate.py --mode dump-vehicles

# 3. One Arma process per world, clean state each time. Use this for real
#     dataset generation.
python orchestrate.py --mode perrun --worlds vanilla --runs 1


# 4. Pure post-processing — merges every labels_*.jsonl in OUT_DIR into
#    labels_all.jsonl. Doesn't touch Arma at all; safe to run on a different
#    machine than the one that generated the data.
python orchestrate.py --mode collate
```

`--worlds` accepts set names and/or literal world classnames, mixed freely. Sets are defined in `WORLD_SETS`: `vanilla`, `cup` (empty until you fill it in from `dump-worlds` output), `ifa3`, `nf`, and `all` (every set concatenated, de-duplicated).  `perrun`  run `collate`'s automatically at the end.

## Output layout and label schema

```
out/
├── images/<world>/*.png          # perrun mode
├── labels_<runId>.jsonl          # one shard per mission run
├── labels_all.jsonl              # after collate
├── worlds.txt / worlds_list.py   # from dump-worlds
└── vehicles_table.sqf            # from dump-vehicles
```

Each `labels_*.jsonl` shard mixes two record shapes, written by `SC_fnc_extWrite` in `randMap.sqf` / `fn/capture.sqf`:

**Run header** (one per shard, written at mission start):
```json
{"type": "run", "id": "<world>_<tick>", "world": "...", "w": 1280, "h": 720, "cats": ["artillery", "car", "..."], "schema": 2}
```

**Per-object label** (one per kept object per captured frame):
```json
{"img": "sc_....png", "cls": "B_MBT_01_cannon_F", "cat": "tank", "bbox": [x, y, w, h], "vis": 0.87, "trunc": 0, "dmg": "intact", "ori": "upright"}
```
`bbox` is `[xMin, yMin, width, height]` in pixels, already clamped to the image rectangle. `vis` is the fraction (0–1) of sampled visibility rays that weren't occluded. `trunc` is 1 if the object's true box extends past the frame edge or any sample point fell outside the culling cone. `dmg` and `ori` are the damage/orientation state applied at spawn.

**Important:** the per-image `META` line that `fn/capture.sqf` also produces (world name, image size, camera position/altitude/pitch/heading/FOV, in-game date, overcast/fog/sun) is written with plain `diag_log`, **not** through `SC_fnc_extWrite` — so it only ever lands in the Arma `.rpt` log file, never in the JSONL. If your training pipeline needs per-image camera pose or weather metadata, you'll need to parse it out of the RPT (see [Known gaps](#known-gaps--loose-ends-in-this-codebase) below) or change `capture.sqf` to route `META` through the extension writer too.

## Determinism

`fn/rng.sqf` implements Wichmann–Hill rather than a more common LCG because SQF numbers are 32-bit floats: a Park–Miller-style LCG needs exact-integer products in the billions, which float32 silently rounds; Wichmann–Hill's three sub-generators keep every intermediate product under ~5.2M, safely inside float32's exact-integer range. `[seed] call SC_fnc_srand` seeds it; the mission calls this once at the top of `randMap.sqf` with `SC_masterSeed`. On the orchestrator side, `run_seed(world, run)` derives a stable per-`(world, run)` seed via CRC32, so batches are reproducible across separate Arma processes too, not just within one run.

## Gotchas (from the code's own comments)

Worth keeping in one place since they're scattered across five files and easy to relearn the hard way:

- **ASL, not AGL.** Camera and object positions are handled in ASL (above sea level). AGL semantics over water or on top of objects are inconsistent in Arma; ASL sidesteps it entirely.
- **Never `camSetTarget` the capture camera.** It hands orientation control to the engine, which then fights explicit pitch. `fn/camera.sqf` sets `setVectorDirAndUp` instead, because pitch feeds directly into the projection math and needs to be exact.
- **`camCommit 0` updates only the simulation camera; `worldToScreen` reads the rendered camera.** After posing the camera, the code waits two frames (`waitUntil { diag_frameNo > _f0 + 1 }`) before trusting any projection.
- **`worldToScreen` returns safe-zone-relative UI coordinates, not screen pixels.** `fn/project.sqf`'s `SC_fnc_uiToPx` applies the affine transform (`(ui - safeZoneOrigin) / safeZoneSize * imageSize`); skipping this is, per the comment, the single most common cause of "all my boxes are shifted or scaled."
- **Self-occlusion on bounding-box corners.** A ray from the camera to a vehicle's own far corners passes through its near-side hull. `checkVisibility` is always called with the object itself as the ignored object to prevent every vehicle from occluding itself.
- **`diag_log` truncates around 1000 characters per line.** That's why labels are written one JSON object per line/object rather than batched per scene.
- **`diag_log text format [...]`, never `diag_log format [...]` on a raw string.** Logging a bare string wraps it in quotes and escapes embedded quotes, corrupting JSON; `text` writes it verbatim.
- **Arma's default Screenshots folder is capped at 250 MB** and stops writing silently once full — this is why the Sweeper thread has to run continuously during capture, not just at the end.
- **Vehicle-table ordering matters.** `Truck_F` and `Wheeled_APC_F` both descend from `Car`, so more specific categories must be tested before falling back to generic ones (see the classification order comment in `fn/capture.sqf` and the heuristics in `orchestrate.py`'s `classify()`).
- **Never launch with `-noLogs`.** The entire labeling pipeline is downstream of the RPT log existing.
- **`camSetFov` takes approximately `tan(halfHorizontalFOV)`**, not degrees — verified empirically against the vanilla default (0.75 ≈ 74°); re-verify against your own build/aspect ratio rather than trusting the formula blindly.

## Known gaps / loose ends in this codebase

Things that don't quite close the loop as shipped, worth knowing about before you rely on them:

- **`dump_vehicles()` prints a path it never writes.** It writes `out/vehicles_table.sqf` but its final summary also prints `-> out/vehicles.json`, which is never created by the current code. Harmless (just a stale message), but don't go looking for that file.
- **`resolve_src()` in `orchestrate.py` is dead code.** It implements a fallback search for a mission source directory but is never called anywhere in `main()`; `SRC_DIR` is the hardcoded `./mission` constant actually used by `build_mission()`/`find_script()`. Point `SRC_DIR` at your real mission folder directly rather than relying on auto-discovery.
- **The Rust `sweep` extension command is unused.** `lib.rs` implements a background thread that moves `*.png` from one folder to another every 500 ms, exposed as the `sweep` extension command, but no `.sqf` file ever calls `"synthcap" callExtension ["sweep", ...]`. The equivalent job is done instead by the Python `Sweeper` thread in `orchestrate.py`. Safe to ignore unless you want to move that work in-process.
- **`SC_vehicleTable` in `params.sqf` targets specific CUP/SFP/IFA3/RK62/HAFM classnames.** If your Workshop subscriptions don't match `orchestrate.py`'s `MOD_IDS` exactly, a meaningful chunk of the table will be filtered out at mission start (logged as `SYNTHCAP|BADCLASS|...`), shrinking your effective spawn pool without failing the run. Run `--mode dump-vehicles` against your own mod set and regenerate the table rather than assuming the checked-in one applies.

## Extension command reference

Exposed by `lib.rs` via `arma-rs`, called as `"synthcap" callExtension ["<command>", [<args>]]`:

| Command | Args | Returns | Notes |
|---|---|---|---|
| `version` | — | `"synthcap <cargo version>"` | Sanity-check the DLL loaded at all. |
| `open` | `path` | `"ok"` / `"err:mkdir:..."` / `"err:open:..."` | Creates parent dirs, opens the file for buffered append. One open sink at a time (global `Mutex`). |
| `write` | `line` | `"ok"` / `"err:write:..."` / `"err:not_open"` | Appends a line + newline to the open sink. |
| `flush` | — | `"ok"` / `"err:flush:..."` / `"err:not_open"` | Called after every captured frame's labels. |
| `close` | — | `"ok"` | Flushes and drops the sink. |
| `exists` | `path` | `"1"` / `"0"` | |
| `sweep` | `src, dst` | `"ok"` / `"ok:already"` | Starts (once) a background thread moving `*.png` from `src` to `dst` every 500 ms. **Currently unused by any SQF script** — see Known Gaps. |
| `shutdown` | — | *(process exits)* | Closes the sink, then calls `std::process::exit(0)` — terminates the whole Arma process. Only called at the very end of `randMap.sqf`, after labels are closed. |

## Suggested first run

1. `cargo build --release` the extension; drop `synthcap_x64.dll` next to `arma3_x64.exe`.
2. Lay out `mission/` per [Suggested repo layout](#suggested-repo-layout) and point `SRC_DIR` in `orchestrate.py` at it.
3. Edit the `CONFIG` block in `orchestrate.py`: `ARMA_DIR`, `PROFILE_DIR`, `OUT_DIR`.
4. `python orchestrate.py --mode dump-worlds` — confirms the launch pipeline works end-to-end and gives you real world classnames for your mod set.
5. `python orchestrate.py --mode dump-vehicles` — generates a vehicle table matching what you actually have installed; paste the result into `params.sqf`.
6. Small smoke test: `python orchestrate.py --mode perrun --worlds Stratis --runs 1`.
7. Check `out/images/Stratis/*.png` against `out/labels_*.jsonl` for that run, and skim the Arma `.rpt` for any `SYNTHCAP|WARN|`, `SYNTHCAP|SKIP|`, or `SYNTHCAP|BADCLASS|` lines.
8. `python orchestrate.py --mode collate` (also runs automatically after step 6, but useful once you've accumulated several runs).