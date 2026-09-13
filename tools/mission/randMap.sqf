[SC_masterSeed] call SC_fnc_srand;

private _badCls = SC_vehiclePool select { !isClass (configFile >> "CfgVehicles" >> _x) };
if (count _badCls > 0) then {
    diag_log text format ["SYNTHCAP|BADCLASS|%1", _badCls];
    SC_vehiclePool = SC_vehiclePool - _badCls;
};
if (count SC_vehiclePool == 0) exitWith {
    diag_log "SynthCap: ABORT — vehicle pool empty after class validation.";
    endMission "END1";
};

/* 
private _perMapPasses = 1 max floor (worldSize / 200); */
private _perMapPasses = 4 ;
diag_log format ["SynthCap: perMapPasses = %1", _perMapPasses];


enableEnvironment [false, true];
setViewDistance 3000;
setObjectViewDistance [2500, 100];
SC_failedFrames = [];
SC_targets  = [];
SC_smokeObjs = [];
private _totalRejects = 0;

private _clutter = [];
SC_runId = format ["%1_%2", worldName, round diag_tickTime];

// exact-count assignment from a [state, fraction] mix, shuffled
SC_fnc_quota = {
    params ["_mix", "_n"];
    private _out = [];
    {
        _x params ["_state", "_frac"];
        for "_k" from 1 to (round (_frac * _n)) do { _out pushBack _state };
    } forEach _mix;
    while { count _out < _n } do { _out pushBack ((_mix select 0) select 0) };
    _out resize _n;
    _out call SC_fnc_shuffle
};

// ============================================================================
// SCENE GENERATION
// ============================================================================
setAccTime 3;
for "_pass" from 1 to _perMapPasses do {

    
    private _anchor = [];
    for "_aTry" from 1 to 4 do {
        _anchor = call SC_fnc_randAnchor;
        if !(_anchor isEqualTo []) exitWith {};
    };
    if (_anchor isEqualTo []) then {
        diag_log format ["SynthCap: pass %1 — no valid anchor, skipping.", _pass];
        continue;
    };

    diag_log format ["SynthCap: pass %1 anchor = [%2, %3]",
        _pass, (_anchor select 0) toFixed 0, (_anchor select 1) toFixed 0];

        // +1 so the top of the range is reachable
    private _vehicleCount = floor ([SC_vehicleCountRange_min,
                                    SC_vehicleCountRange_max + 1] call SC_fnc_randRange);

    // scale the spread to the terrain — 1000 m off-anchor is most of Suursaari
    private _radMax = SC_vehicleSpawnRad_max_max min (worldSize / 6);
    private _radMin = SC_vehicleSpawnRad_min min (_radMax / 2);

    private _passTargets = [];
    private _rejects = 0;
    private _why = createHashMap;

    private _attempts = 0;
    while { count _passTargets < _vehicleCount && _attempts < _vehicleCount * 30 } do {
        _attempts = _attempts + 1;
        private _type = SC_vehiclePool call SC_fnc_pick;

        private _r = _radMin + (_radMax - _radMin) * sqrt (call SC_fnc_rand);
        private _cand = _anchor getPos [_r, 360 * (call SC_fnc_rand)];

        private _bad = "";
        if (surfaceIsWater _cand) then { _bad = "water" };

        private _flat = [];
        if (_bad == "") then {
            _flat = _cand isFlatEmpty [6, -1, 0.6, 6, 0, false, objNull];
            if (_flat isEqualTo []) then { _bad = "notflat" };
        };

        if (_bad != "") then {
            _why set [_bad, (_why getOrDefault [_bad, 0]) + 1];
            _rejects = _rejects + 1;
            continue;
        };

        private _spawnPos = [_flat select 0, _flat select 1, 0];
        private _veh = createVehicle [_type, _spawnPos, [], 0, "CAN_COLLIDE"];
        if (isNull _veh) then {
            _why set ["nullveh", (_why getOrDefault ["nullveh", 0]) + 1];
            diag_log text format ["SYNTHCAP|REJECT|nullveh|%1", _type];
            _rejects = _rejects + 1;
            continue;
        };
        _veh setPosATL _spawnPos;

        SC_targets   pushBack _veh;
        _passTargets pushBack _veh;
    };

        if (count _passTargets == 0) then {
        diag_log format ["SynthCap: pass %1 — anchor barren (%2), retrying elsewhere.", _pass, _why];
        _anchor = call SC_fnc_randAnchor;
        
        continue;
    };

    // --- 2b. assign damage + orientation by quota, not by dice ---
    private _n = count _passTargets;
    private _dmg    = [SC_damageMix, _n] call SC_fnc_quota;
    private _orient = [SC_orientMix, _n] call SC_fnc_quota;

    {
        [_x, _orient select _forEachIndex] call SC_fnc_applyOrientation;
        [_x, _dmg    select _forEachIndex] call SC_fnc_applyDamage;

        private _s = _x getVariable ["SC_smokeObj", objNull];
        if (!isNull _s) then { SC_smokeObjs pushBack _s };
    } forEach _passTargets;

    _totalRejects = _totalRejects + _rejects;
     diag_log format ["SynthCap: pass %1 — spawned %2, rejected %3 %4. dmg=%5 orient=%6",
        _pass, _n, _rejects, _why, _dmg, _orient];

       // --- 3. settle, then freeze ---
        private _t0 = time;
        waitUntil {
            sleep 0.25;
            (_passTargets findIf { (vectorMagnitude velocity _x) > 0.15 } == -1)
            || (time > _t0 + 12)
        };
        sleep 0.5;
        _passTargets call SC_fnc_freeze;
};

if (count SC_targets == 0) exitWith {
    diag_log "SynthCap: ABORT — no vehicles spawned.";
    "synthcap" callExtension ["close", []];
    uiSleep 1;
    private _r = "synthcap" callExtension ["shutdown", []];
    diag_log text format ["SYNTHCAP|SHUTDOWN|%1", _r];
    endMission "END1";
};
// look points come from where the vehicles actually ended up, not from the
// sampled spawn positions — tipped/inverted ones shift during settling
SC_lookPoints = SC_targets apply { getPosATL _x };


SC_targets call SC_fnc_cacheBoxPoints;
setAccTime 1;

diag_log format ["SynthCap: %1 vehicles, %2 rejects, %3 look points.",
    count SC_targets, _totalRejects, count SC_lookPoints];




// ============================================================================
// 4. CAPTURE — weather outermost
// ============================================================================
if (SC_captureMode) then {

    // Label generation
    if !([format ["D:\synthcap\out\labels_%1.jsonl", SC_runId]] call SC_fnc_extOpen) exitWith {
        diag_log "SynthCap: ABORT — extension not available.";
    };

    private _catJson = format ["[%1]", (SC_categories apply { format ["""%1""", _x] }) joinString ","];
    [format ["{""type"":""run"",""id"":""%1"",""world"":""%2"",""w"":%3,""h"":%4,""cats"":%5,""schema"":2}",
    SC_runId, worldName, SC_imgW, SC_imgH, _catJson]] call SC_fnc_extWrite;
    
    
   


    showHUD false;
    if (SC_aperture >= 0) then { setAperture SC_aperture };

    // sample distinct weather combos for this run
    private _combos = [];
    while { count _combos < SC_weatherPerScene } do {
        private _c = call SC_fnc_pickWeather;
        if !(_combos findIf { _x isEqualTo _c } > -1) then { _combos pushBack _c };
    };


    private _frames = 0;
    private _ptsPerWeather = 0;
    { _ptsPerWeather = _ptsPerWeather + ((_x select 4) min (count SC_lookPoints)) } forEach SC_poseBands;
    private _total = (count _combos) * _ptsPerWeather;
    diag_log format ["SynthCap: capture begins — %1 frames planned (%2 weather x %3 points x %4 poses).",
        _total, count _combos, count SC_lookPoints, count SC_poseBands];


    {
        private _wName = [_x] call SC_fnc_applyWeather;

        {
        private _band = _x;
        _band params ["", "", "", "", "_nPts"];
        private _bi = _forEachIndex;

        private _pts = if (_nPts >= count SC_lookPoints) then { SC_lookPoints }
                    else { (SC_lookPoints call SC_fnc_shuffle) select [0, _nPts] };

        {
            private _look = +_x;
            _look set [2, getTerrainHeightASL _x];
            ([_band] call SC_fnc_samplePose) params ["_alt", "_pitch", "_hdg"];

            private _img = format ["sc_%1_w%2_v%3_p%4.png", SC_runId, _wName, _bi, _forEachIndex];

            // Break centre bias — aim off the vehicle by a random offset within the
            // frame. Vertical extent is the binding one, so size the jitter off that.
            private _halfV = _alt * tan (SC_hfovDeg / 2) * SC_imgH / SC_imgW;
            private _jr = SC_aimJitter * _halfV * sqrt (call SC_fnc_rand);
            private _ja = 360 * (call SC_fnc_rand);
            private _aim = [(_look select 0) + _jr * sin _ja, (_look select 1) + _jr * cos _ja, 0];
            _aim set [2, getTerrainHeightASL _aim];

            [_aim, _alt, _pitch, _hdg, SC_hfovDeg] call SC_fnc_setCamera;

            if !(call SC_fnc_frameHasTargets) then {
                diag_log text format ["SYNTHCAP|SKIPFRAME|v%1 p%2|no targets", _bi, _forEachIndex];
                continue;
            };

            [_img, SC_targets] call SC_fnc_captureFrame;
            _frames = _frames + 1;
        } forEach _pts;
    } forEach SC_poseBands;
} forEach _combos;



// ---- teardown ----
{ deleteVehicle _x } forEach SC_smokeObjs;   // do this FIRST
SC_smokeObjs = [];
{ deleteVehicle _x } forEach SC_targets;
SC_targets = [];
sleep 1;



// ---- phase B: same weather combos, no vehicles, no projection guard ----
{
    private _wName = [_x] call SC_fnc_applyWeather;
    {
        private _band = _x;
        _band params ["", "", "", "", "_nPts"];
        private _bi = _forEachIndex;
                for "_k" from 1 to (round (_nPts * SC_emptyFrac / (1 - SC_emptyFrac)) max 1) do {

                    
            private _look = call SC_fnc_randAnchor;
            if (_look isEqualTo []) then { continue };
            _look set [2, getTerrainHeightASL _look];
            _clutter append ([_look] call SC_fnc_hideClutter);

            private _left = (nearestObjects [_look, SC_bgClearTypes, SC_labelRangePx]) select { !(isObjectHidden _x) };
            if (count _left > 0) then {
                diag_log text format ["SYNTHCAP|SKIPFRAME|bg|%1 unhidden: %2",
                    count _left, _left apply { typeOf _x }];
                continue;
            };

            ([_band] call SC_fnc_samplePose) params ["_alt", "_pitch", "_hdg"];
            [_look, _alt, _pitch, _hdg, SC_hfovDeg] call SC_fnc_setCamera;
            [format ["sc_%1_w%2_v%3_bg%4.png", SC_runId, _wName, _bi, _k], []] call SC_fnc_captureFrame;
        };
    } forEach SC_poseBands;
} forEach _combos;

};

// ============================================================================
// 5. CLEANUP
// ============================================================================


{ deleteVehicle _x } forEach SC_smokeObjs;
SC_smokeObjs = [];
SC_targets call SC_fnc_unfreeze;

// Close label write
"synthcap" callExtension ["close", []];

{ _x hideObjectGlobal false } forEach _clutter;
call SC_fnc_destroyCamera;




diag_log "SynthCap: complete.";
diag_log "Next: python tools/parse_rpt.py, then tools/visualize.py — see README.";

endMission "END1";

["{""type"":""done"",""run"":""" + SC_runId + """}"] call SC_fnc_extWrite;
"synthcap" callExtension ["close", []];
uiSleep 1;
private _r = "synthcap" callExtension ["shutdown", []];
diag_log text format ["SYNTHCAP|SHUTDOWN|%1", _r];