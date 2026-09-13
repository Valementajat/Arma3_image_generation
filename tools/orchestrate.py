#!/usr/bin/env python3
"""
SynthCap orchestrator — batch-runs Arma 3 across a list of worlds.

Modes:
  perrun    one Arma process per world via -init=playMission

Responsibilities:
  * generate  <arma>/Missions/synthcap.<world>/  per world (sqm + scripts + params)
  * launch    arma3_x64.exe with the right flags
  * sweep     PNGs out of the profile Screenshots dir into out/<world>/ continuously
  * watchdog  kill a run that stops producing frames
  * collect   labels_*.jsonl written by the synthcap extension

The mission signals completion by writing {"type":"done"} through the extension
(add this as the last line of randMap.sqf, before endMission "END1").
"""

from __future__ import annotations

import argparse
import collections
import json
import random
import re
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
import zlib

# ---------------------------------------------------------------------------
# CONFIG — edit these
# ---------------------------------------------------------------------------

ARMA_DIR = Path(r"D:\SteamLibrary\steamapps\common\Arma 3")
ARMA_EXE = ARMA_DIR / "arma3_x64.exe"

# Separate profile dir per orchestrator instance. Required if you run more than
# one Arma at once, otherwise the two instances fight over Screenshots/.
PROFILE_DIR = Path(r"D:\synthcap\profile")
PROFILE_NAME = "synthcap"

OUT_DIR = Path(r"D:\synthcap\out")          # must match the path in randMap.sqf
SRC_DIR = Path(".\\mission")          # where your .sqf files live

# Steam workshop root for Arma 3 (appid 107410). Usually a sibling of
# steamapps\common, but it can live on a different library drive.
WORKSHOP_DIR = ARMA_DIR.parent.parent / "workshop" / "content" / "107410"

# Load order matters: frameworks first, then content that depends on them.
MOD_IDS: list[tuple[str, str]] = [
    ("450814997",  "CBA_A3"),
    ("583496184",  "CUP Terrains - Core"),
    ("497660133",  "CUP Weapons"),
    ("497661914",  "CUP Units"),
    ("541888371",  "CUP Vehicles"),
    ("3465921651", "CUP Finnish Defence Forces"),
    ("3333292879", "CUP Norwegian Armed Forces"),
    ("3459905206", "CUP Polish Armed Forces"),
    ("3312210548", "CUP Ukrainian Armed Forces"),
    
    ("2648308937", "IFA3 AIO"),
    ("917042703",  "SFP Finnish Forces Pack"),
    ("826911897",  "SFP Swedish Forces Pack"),
    ("3153001741", "RK62 Pack"),
    ("909320014",  "HAFM Helicopters"),
    ("1630816076", "Northern Fronts Terrains"),
]


def resolve_mods() -> list[str]:
    paths, missing = [], []
    for wid, name in MOD_IDS:
        p = WORKSHOP_DIR / wid
        if (p / "addons").is_dir():
            paths.append(str(p))
        else:
            missing.append(f"{name} ({wid})")
    if missing:
        print("WARNING: not subscribed/downloaded:\n  " + "\n  ".join(missing),
              file=sys.stderr)
    return paths


MODS: list[str] = resolve_mods()


WORLD_SETS: dict[str, list[str]] = {
    "vanilla": ["Stratis", "Altis", "Malden"],
    "cup":     [],   # fill from --mode dump-worlds
    "ifa3":    ["i44_merderet_v2", "i44_merderet_koth","mcn_neaville_winter", "I44_Merderet_Winter", "SWU_Ardennes_1944_Winter" ],
    "nf":      ["tem_suursaariw","tem_suursaari", "tem_karelia", "tem_vinjesvingen", "SWU_Ardennes_1940", "tem_olhava","SWU_Aachen_Outskirts","SWU_Greece_Pella_Region",  "tem_chernarusd","tem_talvivaara","raateroadw", "SWU_Greece_Pella_Region" ],
}

WORLD_SETS["all"] = list(dict.fromkeys(
    w for k, v in WORLD_SETS.items() for w in v
))


WORLDS = WORLD_SETS["all"]


""" WORLDS = [
    "Stratis",
    "Altis",
    "Tanoa",
    "Livonia",
]
 """

RUNS_PER_WORLD = 1

SEED_MOD = 16_777_213
BASE_SEED = 1337


def run_seed(world: str, run: int) -> int:
    """Stable across processes, unique per (world, run), safe for SQF."""
    return zlib.crc32(f"{BASE_SEED}:{world}:{run}".encode()) % SEED_MOD

# watchdog: kill the run if no new PNG appears for this long
STALL_TIMEOUT_S = 20
# hard ceiling per world regardless of progress
RUN_TIMEOUT_S = 60 * 90


# ---------------------------------------------------------------------------
# params.sqf overrides written per run
# ---------------------------------------------------------------------------

@dataclass
class RunConfig:
    world: str
    seed: int
    img_w: int = 1280
    img_h: int = 720
    aperture: float = 55.0        # fixed! -1 costs you 2 s of uiSleep per frame
    # nPts per band, raised hard — camera moves are cheap, scene build is not
    pose_bands: list = field(default_factory=lambda: [
        [120, 200, 70, 90, 80],
        [240, 340, 50, 80, 40],
        [340, 470, 55, 85, 30],
        [520, 700, 65, 90, 20],
        [700, 900, 40, 65, 10],
    ])
    # cluster anchors into one region per run so camPreload stops thrashing
    cluster_radius: int = 2500
    acc_time_build: float = 3.0

    def overrides_sqf(self) -> str:
        bands = ",\n    ".join(
            "[%d, %d, %d, %d, %d]" % tuple(b) for b in self.pose_bands
        )
        return f"""
// ==========================================================================
// AUTOGENERATED per-run overrides — appended by orchestrate.py. Do not edit.
// world={self.world}
// ==========================================================================
SC_masterSeed = {self.seed};
SC_imgW = {self.img_w};
SC_imgH = {self.img_h};
SC_aperture = {self.aperture};
SC_accTimeBuild = {self.acc_time_build};
SC_clusterRadius = {self.cluster_radius};
SC_outDir = "{str(OUT_DIR).replace(chr(92), chr(92) * 2)}";

SC_poseBands = [
    {bands}
];

// recompute anything derived from the values above
SC_camReach = 0;
{{
    _x params ["", "_aMax", "_pMin"];
    SC_camReach = SC_camReach max (_aMax / tan _pMin);
}} forEach SC_poseBands;
SC_cullCos = cos ((SC_hfovDeg / 2) * 1.4);
SC_labelRangePx = (5 * SC_imgW) / (SC_minBoxPx * 2 * tan (SC_hfovDeg / 2));
"""


# ---------------------------------------------------------------------------
# minimal mission.sqm — text format, one player unit
# ---------------------------------------------------------------------------
# NOTE: sqm position[] is {x, z, y} (Y is up). The spawn point below is
# arbitrary and may land in water on some terrains; init.sqf immediately
# relocates the player to a valid land anchor, so it does not matter.

MISSION_SQM = """version=54;
class EditorData
{
	moveGridStep=1;
	angleGridStep=0.2617994;
	scaleGridStep=1;
	autoGroupingDist=10;
	toggles=1;
	class ItemIDProvider { nextID=3; };
	class Camera
	{
		pos[]={1000,100,1000};
		dir[]={0,-1,0};
		up[]={0,0,1};
		aside[]={1,0,0};
	};
};
binarizationWanted=0;
addons[]={"A3_Characters_F"};
class AddonsMetaData {};
randomSeed=%(seed)d;
class ScenarioData { author="synthcap"; };
class Mission
{
	class Intel
	{
		startWeather=0;
		startWind=0.1;
		forecastWeather=0;
		forecastWind=0.1;
		year=2035; month=6; day=24; hour=12; minute=0;
	};
	class Entities
	{
		items=1;
		class Item0
		{
			dataType="Group";
			side="West";
			class Entities
			{
				items=1;
				class Item0
				{
					dataType="Object";
					class PositionInfo { position[]={1000,5,1000}; };
					side="West";
					flags=7;
					class Attributes { isPlayer=1; };
					id=1;
					type="B_Soldier_F";
				};
			};
			class Attributes {};
			id=0;
		};
	};
};
"""


DESCRIPTION_EXT = """// autogenerated by orchestrate.py
    author = "synthcap";
    onLoadName = "SynthCap";
    briefing = 0;        // skip the pre-mission briefing screen
    debriefing = 0;      // skip the post-mission debriefing screen
    respawn = 0;
    disabledAI = 1;
    showGPS = 0;
    showCompass = 0;
    showWatch = 0;
    class CfgDebriefing
    {
        class End1 { title = "done"; subtitle = ""; description = ""; pictureBackground = ""; };
    };
    """


# Prepended to init.sqf so the player never drowns / never ends the mission.
PLAYER_GUARD = """// --- orchestrator: neutralise the player unit -----------------------------
player allowDamage false;
player setCaptive true;
removeAllWeapons player;
player enableSimulation false;
"""

# ---------------------------------------------------------------------------
# video config — written into the profile dir before every launch
# ---------------------------------------------------------------------------
# Arma rewrites this file on exit, so it must be regenerated per launch rather
# than written once. Render_W/H MUST equal Resolution_W/H (100% sampling) or
# the screenshot comes out at the render size and every bbox is off by a
# constant scale factor
ARMA3_CFG = """language="English";
adapter=-1;
3D_Performance=1.000000;
Resolution_Bpp=32;
Resolution_W=%(w)d;
Resolution_H=%(h)d;
refresh=60;
Render_W=%(w)d;
Render_H=%(h)d;
FSAA=0;
postFX=0;
GPU_MaxFramesAhead=1;
GPU_DetectedFramesAhead=1;
HDRPrecision=16;
vsync=0;
AToC=0;
PPAA=0;
winX=0;
winY=0;
winW=%(w)d;
winH=%(h)d;
winDefW=%(w)d;
winDefH=%(h)d;
fullScreen=0;
"""


def write_arma3_cfg(cfg: RunConfig) -> None:
    (PROFILE_DIR / "Arma3.cfg").write_text(
        ARMA3_CFG % {"w": cfg.img_w, "h": cfg.img_h}, encoding="utf-8")





def _newest_rpt(after: float) -> Path | None:
    cands = [p for p in PROFILE_DIR.rglob("*.rpt") if p.stat().st_mtime >= after]
    return max(cands, key=lambda p: p.stat().st_mtime) if cands else None


# Small, fast-loading, always present regardless of mod set.
DUMP_WORLD = "Stratis"
 
# Poll the .rpt this often; Arma buffers writes, so keep collecting for a few
# passes after SCWORLD_END rather than killing the instant we see it.
POLL_S = 2.0
GRACE_POLLS = 3
 
 
# NOTE: raw string. SQF does not use backslash escapes — a backslash in an SQF
# string literal is literal — so the path must not be escaped on the way in.
DUMP_INIT_SQF = r"""
// --- orchestrator: enumerate CfgWorlds -------------------------------------
private _rows = [];
{
    if (isClass _x && {getText (_x >> "worldName") != ""}) then {
        _rows pushBack format ["%1;%2;%3",
            configName _x,
            getText (_x >> "description"),
            getNumber (_x >> "mapSize")];
    };
} forEach (configProperties [configFile >> "CfgWorlds", "true", false]);
 
_rows sort true;
 
{ diag_log text ("SCWORLD;" + _x) } forEach _rows;
diag_log text format ["SCWORLD_END;%1", count _rows];
 
// Best-effort direct write. Wrapped so a missing/renamed extension cannot
// abort the script before endMission.
private _ok = false;
if (!isNil {SC_DUMP_PATH}) then {
    try {
        "synthcap" callExtension ["open", [SC_DUMP_PATH]];
        { "synthcap" callExtension ["write", [_x]] } forEach _rows;
        "synthcap" callExtension ["close", []];
        _ok = true;
    } catch {
        diag_log text format ["SCWORLD_EXT_FAIL;%1", _exception];
    };
};
diag_log text format ["SCWORLD_EXT;%1", _ok];
 
endMission "END1";
"""
 
 
def _sqf_path(p: Path) -> str:
    """Match the escaping convention already used for SC_outDir."""
    return str(p).replace(chr(92), chr(92) * 2)
 
 
def dump_worlds(timeout: float = 300.0) -> int:
    """Enumerate every CfgWorlds class in the current mod set.
 
    Writes out/worlds.txt and out/worlds_list.py, prints the listing, and
    returns a process exit code.
    """
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
 
    dest = ARMA_DIR / "Missions" / f"synthcap_dump.{DUMP_WORLD}"
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
 
    (dest / "mission.sqm").write_text(MISSION_SQM % {"seed": 0}, encoding="utf-8")
    (dest / "description.ext").write_text(DESCRIPTION_EXT, encoding="utf-8")
    (dest / "init.sqf").write_text(
        f'SC_DUMP_PATH = "{_sqf_path(OUT_DIR / "worlds.txt")}";\n'
        + PLAYER_GUARD
        + DUMP_INIT_SQF,
        encoding="utf-8",
    )
 
    # Keep the profile's video config consistent with everything else so this
    # run does not leave a stale resolution behind for the next capture.
    write_arma3_cfg(RunConfig(world=DUMP_WORLD, seed=0))
 
    t0 = time.time() - 1
    args = base_args() + [f'-init=playMission["","synthcap_dump.{DUMP_WORLD}"]']
    print(f"enumerating worlds via synthcap_dump.{DUMP_WORLD} "
          f"({len(MODS)} mods loaded)")
    
    proc = subprocess.Popen(args)
    rows: list[list[str]] = []
    saw_end = False
    grace = 0
    rpt: Path | None = None
 
    try:
        while time.time() - t0 < timeout:
            time.sleep(POLL_S)
 
            if rpt is None:
                rpt = _newest_rpt(t0)
                if rpt is None:
                    continue
 
            text = rpt.read_text(encoding="utf-8", errors="replace")
            rows = []
            for line in text.splitlines():
                i = line.find("SCWORLD;")
                if i != -1:
                    rows.append(line[i + len("SCWORLD;"):].rstrip().split(";"))
            if "SCWORLD_END;" in text:
                saw_end = True
 
            if saw_end:
                grace += 1
                if grace >= GRACE_POLLS:
                    break
            elif rows:
                # frames are arriving; extend patience a little
                print(f"  ...{len(rows)} worlds so far", end="\r", flush=True)
    finally:
        proc.kill()
        proc.wait(timeout=10)
        shutil.rmtree(dest, ignore_errors=True)
 
    print()
    if not rows:
        print("no worlds logged.", file=sys.stderr)
        print(f"  rpt searched: {rpt if rpt else '(none found in ' + str(PROFILE_DIR) + ')'}",
              file=sys.stderr)
        print("  check: did the game reach a mission, or sit at the main menu?",
              file=sys.stderr)
        print("  if it sat at the menu, the mission folder name or DUMP_WORLD is wrong.",
              file=sys.stderr)
        return 1
    if not saw_end:
        print(f"WARNING: timed out after {timeout:.0f}s without SCWORLD_END; "
              f"listing may be truncated", file=sys.stderr)
 
    # de-dupe case-insensitively, keep first spelling seen
    seen: set[str] = set()
    out: list[tuple[str, str, str]] = []
    for row in rows:
        cn = row[0]
        desc = row[1] if len(row) > 1 else ""
        size = row[2] if len(row) > 2 else "0"
        if cn.lower() in seen:
            continue
        seen.add(cn.lower())
        out.append((cn, desc, size))
    out.sort(key=lambda r: r[0].lower())
 
    listing = "\n".join(f'"{cn}",  # {desc} ({size}m)' for cn, desc, size in out)
    (OUT_DIR / "worlds.txt").write_text(listing, encoding="utf-8")
 
    # paste-ready python
    (OUT_DIR / "worlds_list.py").write_text(
        "ALL_WORLDS = [\n"
        + "\n".join(f'    "{cn}",  # {desc} ({size}m)' for cn, desc, size in out)
        + "\n]\n",
        encoding="utf-8",
    )
 
    print(listing)
    print(f"\n{len(out)} worlds -> {OUT_DIR / 'worlds.txt'}")
    print(f"{' ' * 13}-> {OUT_DIR / 'worlds_list.py'}")
 
    # flag the classnames that just cost you 90 minutes each
    configured = {w for v in WORLD_SETS.values() for w in v}
    missing = sorted(w for w in configured if w.lower() not in seen)
    if missing:
        print("\nWARNING: configured in WORLD_SETS but NOT in CfgWorlds:",
              file=sys.stderr)
        for w in missing:
            near = [cn for cn in seen if cn[:6] == w.lower()[:6]]
            hint = f"  (did you mean: {', '.join(sorted(near)[:4])})" if near else ""
            print(f"  {w}{hint}", file=sys.stderr)
 
    return 0

# ---------------------------------------------------------------------------
# mission folder construction
# ---------------------------------------------------------------------------

SCRIPT_ROOT = ["init.sqf", "params.sqf", "randMap.sqf"]
SCRIPT_FN = ["rng.sqf", "camera.sqf", "project.sqf", "visibility.sqf",
              "capture.sqf", "sqfFileWrapper.sqf"]



def resolve_src(explicit: str | None) -> Path:
    if explicit:
        p = Path(explicit).expanduser().resolve()
        if not (p / "init.sqf").exists():
            raise FileNotFoundError(f"no init.sqf in {p}")
        return p
    here = Path(__file__).parent.resolve()
    for cand in [here, here.parent, here.parent / "mission",
                 here.parent / "src", here.parent / "synthcap"]:
        if (cand / "init.sqf").exists():
            return cand
    # last resort: search the tree above us
    for cand in here.parent.rglob("init.sqf"):
        return cand.parent
    raise FileNotFoundError(
        f"could not find init.sqf near {here} — pass --src explicitly")


def find_script(root: Path, name: str) -> Path:
    """Scripts may sit flat in the source root or under fn/."""
    for cand in (root / name, root / "fn" / name):
        if cand.exists():
            return cand
    raise FileNotFoundError(f"missing source script: {name} (looked in {root} and {root/'fn'})")


def build_mission(world: str, cfg: RunConfig) -> Path:
    """Create <arma>/Missions/synthcap.<world>/ from the source scripts."""
    dest = ARMA_DIR / "Missions" / f"synthcap.{world}"
    if dest.exists():
        shutil.rmtree(dest)
    (dest / "fn").mkdir(parents=True)

    (dest / "mission.sqm").write_text(MISSION_SQM % {"seed": cfg.seed},
                                      encoding="utf-8")
    (dest / "description.ext").write_text(DESCRIPTION_EXT, encoding="utf-8")

   



    for name in SCRIPT_ROOT:
        text = find_script(SRC_DIR, name).read_text(encoding="utf-8")
        if name == "init.sqf":
            text = PLAYER_GUARD + text
        if name == "params.sqf":
            text = text + cfg.overrides_sqf()
        (dest / name).write_text(text, encoding="utf-8")

    for name in SCRIPT_FN:
        shutil.copy2(find_script(SRC_DIR, name), dest / "fn" / name)

    return dest



# ---------------------------------------------------------------------------
# screenshot sweeper
# ---------------------------------------------------------------------------

class Sweeper(threading.Thread):
    """Drains PNGs out of the profile dir. Arma caps the Screenshots folder
    (~250 MB by default) and silently stops writing once it is full."""

    def __init__(self, profile_dir: Path, dest: Path, interval: float = 0.5, since=None):
        super().__init__(daemon=True)
        self.profile_dir = profile_dir
        self.dest = dest
        self.interval = interval
        self.stop_flag = threading.Event()
        self.moved = 0
        self.last_move = time.monotonic()
        self.since = (since if since is not None else time.time()) - 2.0  # clock tolerance



    def _pass(self) -> None:
        for png in self.profile_dir.rglob("*.png"):
            if self.dest in png.parents:
                continue
            try:
                if png.stat().st_mtime < self.since:
                    png.unlink()      # stale: drop it, do not count it
                    continue
            except OSError:
                continue


            try:
                target = self.dest / png.name
                if target.exists():
                    target = self.dest / f"{png.stem}_{int(time.time()*1000)}.png"
                shutil.move(str(png), str(target))
                self.moved += 1
                self.last_move = time.monotonic()
            except OSError:
                pass  # still being written; catch it next pass

    def run(self) -> None:
        self.dest.mkdir(parents=True, exist_ok=True)
        while not self.stop_flag.is_set():
            self._pass()
            time.sleep(self.interval)
        self._pass()  # final drain

    def stall_seconds(self) -> float:
        return time.monotonic() - self.last_move


# ---------------------------------------------------------------------------
# launching
# ---------------------------------------------------------------------------

def base_args() -> list[str]:
    args = [
        str(ARMA_EXE),
        "-noSplash",
        "-skipIntro",
        "-noPause",
        "-noLauncher",
        "-world=empty",          # skip loading a menu terrain: much faster boot
        "-filePatching",         # load loose mission files without packing a PBO
        "-window",
        "-noBorder",
        "-posX=0",
        "-posY=0",
        "-noSound",
        "-showScriptErrors",
        f"-profiles={PROFILE_DIR}",
        f"-name={PROFILE_NAME}",
    ]
    if MODS:
        args.append("-mod=" + ";".join(MODS))
    return args


FIRST_FRAME_TIMEOUT_S = 300     # generous: covers terrain load + scene build

def wait_for_run(proc, sweeper, label, timeout):
    t0 = time.monotonic()
    while True:
        rc = proc.poll()
        if rc is not None:
            return f"exited rc={rc}"
        elapsed = time.monotonic() - t0
        if sweeper.moved == 0:
            if elapsed > FIRST_FRAME_TIMEOUT_S:
                proc.kill()
                return "NO_FIRST_FRAME (bad worldName? check .rpt for CfgWorlds)"
        elif sweeper.stall_seconds() > STALL_TIMEOUT_S:
            proc.kill()
            return f"STALLED after {sweeper.moved} frames"
        if elapsed > timeout:
            proc.kill()
            return "TIMEOUT"
        time.sleep(2.0)

def purge_screenshots(profile_dir: Path) -> int:
    n = 0
    for png in profile_dir.rglob("*.png"):
        try:
            png.unlink()
            n += 1
        except OSError:
            pass
    return n


def run_perrun(worlds: list[str], runs: int) -> None:
    for r in range(runs):
        for world in worlds:
            seed = run_seed(world, r)
            cfg = RunConfig(world=world, seed=seed)
            build_mission(world, cfg)
            write_arma3_cfg(cfg)

            dest = OUT_DIR / "images" / world
            sweeper = Sweeper(PROFILE_DIR, dest)
            sweeper.start()

            args = base_args() + [f'-init=playMission["","synthcap.{world}"]']
            print(f"[{world}] run {r+1}/{runs} seed={seed} -> {dest}")
            t0 = time.monotonic()

            purge_screenshots(PROFILE_DIR)
            proc = subprocess.Popen(args)
            status = wait_for_run(proc, sweeper, world, RUN_TIMEOUT_S)

            sweeper.stop_flag.set()
            sweeper.join(timeout=10)
            dt = time.monotonic() - t0
            rate = sweeper.moved / dt * 3600 if dt else 0
            print(f"[{world}] {status} — {sweeper.moved} frames in "
                  f"{dt/60:.1f} min ({rate:.0f}/h)")



DUMP_VEH_SQF = r"""
// --- orchestrator: enumerate CfgVehicles -----------------------------------
private _rows = [];
{
    private _cn = configName _x;
    if (getNumber (_x >> "scope") == 2 && {getText (_x >> "model") != ""}) then {
        private _kind = "";
        {
            if (_cn isKindOf _x) exitWith { _kind = _x };
        } forEach ["Motorcycle", "Tank", "Car", "Helicopter", "Plane",
                    "StaticWeapon"];
        if (_kind != "") then {
            _rows pushBack format ["%1;%2;%3;%4;%5;%6;%7;%8;%9;%10",
                _cn, _kind,
                getText (_x >> "editorSubcategory"),
                getText (_x >> "vehicleClass"),
                getText (_x >> "faction"),
                toLower (getText (_x >> "model")),
                getNumber (_x >> "transportSoldier"),
                getNumber (_x >> "armor"),
                getNumber (_x >> "maximumLoad"),
                configSourceMod _x];
        };
    };
} forEach ("true" configClasses (configFile >> "CfgVehicles"));

_rows sort true;
{ diag_log text ("SCVEH;" + _x) } forEach _rows;
diag_log text format ["SCVEH_END;%1", count _rows];

endMission "END1";
"""

def _run_dump(tag: str, init_sqf: str, marker: str,
              timeout: float = 300.0) -> tuple[list[list[str]], bool, Path | None]:
    """Build a throwaway mission, run it, scrape '<marker>;' lines from the rpt."""
    dest = ARMA_DIR / "Missions" / f"synthcap_{tag}.{DUMP_WORLD}"
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    (dest / "mission.sqm").write_text(MISSION_SQM % {"seed": 0}, encoding="utf-8")
    (dest / "description.ext").write_text(DESCRIPTION_EXT, encoding="utf-8")
    (dest / "init.sqf").write_text(PLAYER_GUARD + init_sqf, encoding="utf-8")

    write_arma3_cfg(RunConfig(world=DUMP_WORLD, seed=0))

    t0 = time.time() - 1
    args = base_args() + [f'-init=playMission["","synthcap_{tag}.{DUMP_WORLD}"]']
    print(f"running {tag} dump ({len(MODS)} mods loaded)")
    proc = subprocess.Popen(args)

    rows: list[list[str]] = []
    saw_end, grace, rpt = False, 0, None
    pre = f"{marker};"
    try:
        while time.time() - t0 < timeout:
            time.sleep(POLL_S)
            if rpt is None:
                rpt = _newest_rpt(t0)
                if rpt is None:
                    continue
            text = rpt.read_text(encoding="utf-8", errors="replace")
            rows = [line[line.find(pre) + len(pre):].rstrip().split(";")
                    for line in text.splitlines() if pre in line]
            if f"{marker}_END;" in text:
                saw_end = True
            if saw_end:
                grace += 1
                if grace >= GRACE_POLLS:
                    break
            elif rows:
                print(f"  ...{len(rows)} rows so far", end="\r", flush=True)
    finally:
        proc.kill()
        proc.wait(timeout=10)
        shutil.rmtree(dest, ignore_errors=True)

    print()
    return rows, saw_end, rpt

# ---------------------------------------------------------------------------
# label collation
# ---------------------------------------------------------------------------

def collate(out: Path) -> None:
    """Merge every labels_*.jsonl into one file, dropping records whose image
    never made it to disk."""
    shards = sorted(out.glob("labels_*.jsonl"))
    if not shards:
        print("no label shards found")
        return

    images = {p.name for p in (out / "images").rglob("*.png")}
    merged = out / "labels_all.jsonl"
    kept = dropped = runs = 0

    with merged.open("w", encoding="utf-8") as fh:
        for shard in shards:
            for line in shard.read_text(encoding="utf-8").splitlines():
                if not line.strip():
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    dropped += 1
                    continue
                if rec.get("type") == "run":
                    runs += 1
                    fh.write(line + "\n")
                    continue
                if rec.get("img") and rec["img"] not in images:
                    dropped += 1
                    continue
                fh.write(line + "\n")
                kept += 1

    print(f"collated {len(shards)} shards / {runs} runs -> {merged}")
    print(f"  {kept} label records kept, {dropped} orphaned/malformed dropped")
    print(f"  {len(images)} images on disk")


FIELDS = ["cls", "kind", "subcat", "vclass", "faction",
          "model", "transport", "armor", "load", "mod"]
SKIP_CATS = {"boat", "skip"}

SUBCAT = {
    "EdSubcat_Cars":            "car",
    "EdSubcat_Armored_Wheeled": "apc",
    "EdSubcat_APCs":            "ifv",
    "EdSubcat_Tanks":           "tank",
    "EdSubcat_Trucks":          "truck",
    "EdSubcat_Artillery":       "artillery",
    "EdSubcat_Helicopters":     "heli",
    "EdSubcat_Planes":          "plane",
    
    "EdSubcat_StaticWeapons":   "static",
    "EdSubcat_AAs":             "static",
    "EdSubcat_ATs":             "static",
}

OVERRIDES: dict[str, str] = {
    # fill in as you audit — beats re-running the game to argue with a heuristic
    # "CUP_O_BMP2_RU": "ifv",
}

def classify(r: dict) -> str:
    if r["cls"] in OVERRIDES:
        return OVERRIDES[r["cls"]]
    if r["subcat"] in SUBCAT:
        return SUBCAT[r["subcat"]]

    kind, blob = r["kind"], f"{r['cls']} {r['model']}".lower()
    if kind == "Helicopter":   return "heli"
    if kind == "Plane":        return "plane"
    """ if kind == "Ship":         return "boat" """
    if kind == "StaticWeapon": return "static"
    if kind == "Motorcycle":   return "bike"
    if kind == "Tank":
        if re.search(r"halftrack|sdkfz25|m3a1", blob):    return "apc"
        return "ifv" if r["transport"] > 0 else "tank"
    # Car
    if re.search(r"quad|atv", blob):                      return "quad"
    if re.search(r"truck|ural|kamaz|t810|zil|v3s|opel|studebaker|gaz|sisu",
                 blob):                                   return "truck"
    if r["load"] > 8000:                                  return "truck"
    if r["armor"] >= 120:                                 return "mrap"
    return "car"

def build_table(rows, per_cat=40, per_cat_per_mod=8, seed=1337):
    by_model = collections.defaultdict(list)
    for r in rows:
        by_model[r["model"]].append(r)
    reps = [min(v, key=lambda r: len(r["cls"])) for v in by_model.values()]

    # deterministic shuffle so the caps don't just take whatever sorts first
    rnd = random.Random(seed)
    rnd.shuffle(reps)

    cat_counts = collections.Counter()
    pair_counts = collections.Counter()
    table = []
    for r in reps:
        cat = classify(r)
        if cat in SKIP_CATS:
            continue
        mod = r["mod"] or "vanilla"
        if cat_counts[cat] >= per_cat or pair_counts[(cat, mod)] >= per_cat_per_mod:
            continue
        cat_counts[cat] += 1
        pair_counts[(cat, mod)] += 1
        table.append((r["cls"], cat, mod))

    table.sort(key=lambda t: (t[1], t[0]))
    for cat in sorted(cat_counts):
        mods = {m: n for (c, m), n in pair_counts.items() if c == cat}
        print(f"  {cat:10s} {cat_counts[cat]:3d}  {mods}")
    return table


def emit_table(table) -> str:
    rows = ",\n".join(f'    ["{c}", "{cat}"]   // {mod}' for c, cat, mod in table)
    return f"SC_vehicleTable = [\n{rows}\n];\n"
def dump_vehicles(per_cat: int = 40) -> int:
    rows, saw_end, rpt = _run_dump("vdump", DUMP_VEH_SQF, "SCVEH", timeout=420.0)
    if not rows:
        print(f"no vehicles logged. rpt: {rpt}", file=sys.stderr)
        return 1
    if not saw_end:
        print("WARNING: no SCVEH_END — listing may be truncated", file=sys.stderr)

    recs: list[dict[str, object]] = []
    for row in rows:
        if len(row) < len(FIELDS):
            continue
        d: dict[str, object] = dict(zip(FIELDS, row[:len(FIELDS)]))
        for k in ("transport", "armor", "load"):
            try:
                d[k] = float(str(d[k]))
            except ValueError:
                d[k] = 0.0
        recs.append(d)

   
    table = build_table(recs, per_cat=per_cat)
    cats = sorted({cat for _, cat, _ in table})
    sqf = (f"// autogenerated: {len(table)} classes from {len(recs)} scope=2 entries\n"
           f"SC_categories = [{', '.join(f'"{c}"' for c in cats)}];\n\n"
           + emit_table(table))
    (OUT_DIR / "vehicles_table.sqf").write_text(sqf, encoding="utf-8")

    by_mod = collections.Counter(r["mod"] for r in recs)
    print(f"\n{len(recs)} spawnable -> {len(table)} after model-dedupe")
    for mod, n in by_mod.most_common():
        print(f"  {n:5d}  {mod}")
    print(f"\n-> {OUT_DIR / 'vehicles.json'}\n-> {OUT_DIR / 'vehicles_table.sqf'}")
    return 0





# ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mode",
                    choices=[ "perrun", "collate", "dump-worlds", "dump-vehicles"],
                    default="perrun")
    ap.add_argument("--worlds", nargs="*", default=None,
                    help="world class names and/or set names "
                         f"({', '.join(WORLD_SETS)}); default: vanilla")
    ap.add_argument("--runs", type=int, default=RUNS_PER_WORLD)
    args = ap.parse_args()

    # collate is pure post-processing — it must work on a box with no Arma
    if args.mode == "collate":
        collate(OUT_DIR)
        return 0

    # everything below launches the game, so fail fast on a bad ARMA_DIR
    if not ARMA_EXE.exists():
        print(f"arma exe not found: {ARMA_EXE}", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)

    if args.mode == "dump-worlds":
        return dump_worlds()

    if args.mode == "dump-vehicles":
        return dump_vehicles()

    requested = args.worlds or list(WORLDS)
    worlds: list[str] = []
    for w in requested:
        for name in WORLD_SETS.get(w, [w]):
            if name not in worlds:
                worlds.append(name)

    if not worlds:
        print("no worlds selected — check WORLD_SETS / --worlds",
              file=sys.stderr)
        return 1

    t0 = time.monotonic()
    if args.mode == "run_perrun":
        run_perrun(worlds, args.runs)
    else:
        print("Invalid mode seleced")
        return 0
    print(f"\ntotal wall clock: {(time.monotonic()-t0)/60:.1f} min")

    collate(OUT_DIR)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())