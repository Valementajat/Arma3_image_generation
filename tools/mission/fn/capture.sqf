// ============================================================================
// SynthCap — frame capture: freeze -> preload -> label -> log -> screenshot
//
// FRAME-SYNC GUARANTEE: `screenshot` captures asynchronously at the end of
// some upcoming frame, while this script runs in the scheduler with no frame
// alignment whatsoever. Chasing "same frame" for a dynamic scene is a losing
// game — so we don't play it. The scene is FROZEN (simulation disabled,
// velocities zeroed) for the entire label+screenshot window; with nothing
// moving, every frame in the window is identical and sync is trivially exact.
//

// ----------------------------------------------------------------------------
// _obj call SC_fnc_category  -> coarse class label string
// ORDER MATTERS: Truck_F and Wheeled_APC_F are descendants of Car; Tank must
// be tested before anything else.
// ----------------------------------------------------------------------------


SC_fnc_category = {
    private _c = SC_categoryMap getOrDefault [typeOf _this, "vehicle"];
    if (_c isEqualTo "vehicle" && {!(typeOf _this in ["__none__"])}) then {
        diag_log text format ["SYNTHCAP|WARN|uncategorized class %1", typeOf _this];
    };
    _c
};
// ----------------------------------------------------------------------------
// _objectsArray call SC_fnc_freeze   /   ..._unfreeze
// Freeze AFTER physics settling (vehicles must drop onto their suspension
// first, ~1-2 s after spawn, or they hang frozen mid-air in every image).
// ----------------------------------------------------------------------------
SC_fnc_freeze = {
    { _x setVelocity [0,0,0]; _x enableSimulationGlobal false; } forEach _this;
};
SC_fnc_unfreeze = {
    { _x enableSimulationGlobal true; } forEach _this;
};


// True if any target would survive the label filters from the current camera.
// The scene is frozen and the camera is posed, so this is exactly what
// captureFrame will find after the shot — no risk of disagreement.
SC_fnc_frameHasTargets = {
    (SC_targets findIf {
        !(isNull _x) && {
            private _b = _x call SC_fnc_projectObject;
            !(_b isEqualTo []) && {
                (((_b select 2) min (_b select 3)) >= SC_minBoxPx)
                && { (_x call SC_fnc_visibility) >= SC_minVis }
            }
        }
    }) > -1
};



// ----------------------------------------------------------------------------
// [_imageName, _objects] call SC_fnc_captureFrame
//
// Assumes: camera already posed (SC_fnc_setCamera), objects already frozen.
// Must run in SCHEDULED environment (execVM/spawn) — it sleeps.
// Returns: number of labelled objects, or -1 if the frame was not written.
//
// ORDER MATTERS: the screenshot is taken BEFORE any label lines are logged.
// If the write fails, we bail without emitting META/OBJ lines, so the .rpt
// can never contain labels for an image that doesn't exist on disk.
// ----------------------------------------------------------------------------
SC_fnc_captureFrame = {
    params ["_img", "_objects"];
    private _lines = [];

    // --- guard: overlay must be off, or boxes get baked into the pixels -----
    if !((missionNamespace getVariable ["SC_overlayEH", -1]) isEqualTo -1) exitWith {
        diag_log text format ["SYNTHCAP|ABORT|%1|overlay active", _img];
        -1
    };

    // --- guard: camera must exist ------------------------------------------
    if (isNil "SC_cam" || {isNull SC_cam}) exitWith {
        diag_log text format ["SYNTHCAP|ABORT|%1|no camera", _img];
        -1
    };

    // --- stream terrain/objects/LODs in before we shoot ---------------------
    SC_cam camPreload 0;
    private _t0 = time;
    waitUntil { sleep 0.05; (camPreloaded SC_cam) || (time > _t0 + 5) };
    if (!(camPreloaded SC_cam)) then {
        diag_log text format ["SYNTHCAP|WARN|%1|preload timeout", _img];
    };

/*     if (SC_aperture < 0) then { uiSleep 2 };   // auto-exposure needs to adapt
 */    
    sleep 0.3;                               // settle margin

    // --- shoot, with retries ------------------------------------------------
    private _ok = false;
    private _attempts = 0;
    for "_a" from 1 to 5 do {
        _attempts = _a;
        _ok = screenshot _img;
        if (_ok) exitWith {};
        sleep 0.5;
    };
    diag_log text format ["SYNTHCAP|SHOT|%1|%2|%3", _img, _ok, _attempts];

    if (!_ok) exitWith {
        SC_failedFrames pushBack _img;
        diag_log text format ["SYNTHCAP|SKIP|%1|no labels written", _img];
        sleep 0.5;
        -1
    };

    // ======================================================================
    // Image exists on disk from here down. Safe to emit labels.
    // ======================================================================

    // --- META line: everything the converter needs about this image --------
    SC_camMeta params ["_cp", "_alt", "_pitch", "_hdg", "_hfov"];
    diag_log text format [
        "SYNTHCAP|META|%1|%2|%3|%4|%5|%6|%7|%8|%9|%10|%11|%12|%13|%14|%15",
        _img, worldName, SC_imgW, SC_imgH,
        _cp select 0, _cp select 1, _cp select 2,
        _alt, _pitch, _hdg, _hfov,
        dateToNumber date, overcast, fog, sunOrMoon
    ];
   

    // --- per-object labels --------------------------------------------------
    private _kept = 0;
    {
        private _obj = _x;
        if (isNull _obj) then { continue };

        private _box = _obj call SC_fnc_projectObject;
        if (_box isEqualTo []) then { continue };            // offscreen

        _box params ["_bx", "_by", "_bw", "_bh", "_trunc"];
        if ((_bw min _bh) < SC_minBoxPx) then { continue };  // too tiny

        private _vis = _obj call SC_fnc_visibility;
        if (_vis < SC_minVis) then { continue };             // too occluded

        // in captureFrame, replacing the OBJ diag_log:
        _lines pushBack (format [
            "{""img"":""%1"",""cls"":""%2"",""cat"":""%3"",""bbox"":[%4,%5,%6,%7],""vis"":%8,""trunc"":%9,""dmg"":""%10"",""ori"":""%11""}",
            _img, typeOf _obj, _obj call SC_fnc_category,
            [_bx] call SC_fnc_r, [_by] call SC_fnc_r,
            [_bw] call SC_fnc_r, [_bh] call SC_fnc_r,
            [_vis, 3] call SC_fnc_r, [_trunc, 3] call SC_fnc_r,
            _obj getVariable ["SC_damage", "intact"],
            _obj getVariable ["SC_orient", "upright"]
        ]);
        _kept = _kept + 1;
    } forEach _objects;

   
    

    { [_x] call SC_fnc_extWrite } forEach _lines;
    "synthcap" callExtension ["flush", []];
    diag_log text format ["SYNTHCAP|END|%1|%2", _img, _kept];

    sleep 0.25;   // give the async PNG write breathing room before scene changes
    _kept
};


// Terrain-placed vehicles and wrecks that deleteVehicle never touches.
// Extend per terrain — run the discovery snippet below once and read the RPT.
SC_bgClearTypes  = ["LandVehicle", "Ship", "Air", "StaticWeapon"];
SC_bgClearPrefix = ["Land_Wreck_", "Land_Car_", "Land_UWreck_"];

SC_fnc_hideClutter = {
    params ["_pos"];
    private _r = SC_camReach + SC_maxLabelRange;
    private _hidden = [];
    {
        if (!isObjectHidden _x) then { _x hideObjectGlobal true; _hidden pushBack _x };
    } forEach (nearestObjects [_pos, SC_bgClearTypes, _r]);
    {
        private _o = _x;
        private _t = typeOf _o;
        if ((SC_bgClearPrefix findIf { (_t select [0, count _x]) isEqualTo _x }) > -1) then {
            if (!isObjectHidden _o) then { _o hideObjectGlobal true; _hidden pushBack _o };
        };
    } forEach (nearestObjects [_pos, [], _r, false, true]);
    diag_log text format ["SYNTHCAP|CLUTTER|%1|hid %2", _pos, count _hidden];
    _hidden
};