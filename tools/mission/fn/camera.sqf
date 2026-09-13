// ============================================================================
// SynthCap — UAV camera rig
//
// Design notes / Arma gotchas:
//  * We use camCreate + cameraEffect (still the current API for scripted
//    cameras; the "UAV" in-game camera is a UI construct on top of the same
//    machinery and gives us no extra control, so we don't use it).
//  * Orientation is set with setVectorDirAndUp, NOT camSetTarget. camSetTarget
//    makes the engine own the orientation and fight you; with dir+up vectors
//    the pitch is EXACT, which matters because pitch feeds the projection
//    geometry. Never call camSetTarget on this camera.
//  * Position is set in ASL (sea level) coordinates for precision, derived
//    from terrain height. getPos/setPos AGL semantics over objects/water are
//    a famous footgun; ASL sidesteps it.
//  * camSetFov value ~= tan(halfHorizontalFov). Verified against vanilla
//    default (0.75 -> ~74°). Empirically re-verify with the calibration scene.
// ============================================================================

// ----------------------------------------------------------------------------
// [_anchorPos2D, _altAGL, _pitchDeg, _headingDeg, _hfovDeg] call SC_fnc_setCamera
//
//  _anchorPos2D : [x, y] world position the camera looks AT (ground anchor)
//  _altAGL      : camera altitude in metres above the ANCHOR's terrain height
//  _pitchDeg    : 90 = nadir (straight down), 45 = oblique, min ~20 sensible
//  _headingDeg  : compass direction the camera faces (0 = north)
//  _hfovDeg     : horizontal field of view in degrees
//
// Returns the camera object. Reuses one global camera (SC_cam).
// ----------------------------------------------------------------------------
SC_fnc_setCamera = {
    params ["_anchor", "_alt", "_pitch", "_hdg", "_hfov"];

    if (isNil "SC_cam" || {isNull SC_cam}) then {
        SC_cam = "camera" camCreate [0, 0, 0];
        SC_cam cameraEffect ["Internal", "Back"];
        showCinemaBorder false;
        setAperture SC_aperture;
    };

    _anchor params ["_ax", "_ay"];
    private _groundASL = getTerrainHeightASL [_ax, _ay];

    // For oblique pitch, back the camera off horizontally (opposite to its
    // heading) so the anchor point stays at screen centre:
    // horizontal offset = alt / tan(pitch). At nadir the offset is 0.
    private _pitchC = _pitch max 1 min 90;              // clamp: avoid tan(0)
    private _horiz  = if (_pitchC > 89.9) then { 0 } else { _alt / tan _pitchC };

    private _camPosASL = [
        _ax - _horiz * sin _hdg,
        _ay - _horiz * cos _hdg,
        _groundASL + _alt
    ];

    // --- keep the camera inside the world ----------------------------------
    // Backoff reaches SC_camReach (~1072 m on the current bands). Near the
    // border that lands the camera off-terrain. Flip the heading to point
    // away from map centre, which puts the camera inland of the anchor.
    private _m = 50;
    private _cx = _camPosASL select 0;
    private _cy = _camPosASL select 1;
    if (_cx < _m || _cy < _m || _cx > mapSize - _m || _cy > mapSize - _m) then {
        _hdg = ([_ax, _ay] getDir [mapSize / 2, mapSize / 2]) + 180;
        _camPosASL = [
            _ax - _horiz * sin _hdg,
            _ay - _horiz * cos _hdg,
            _groundASL + _alt
        ];
        diag_log text format ["SYNTHCAP|CAMFLIP|%1,%2|hdg->%3",
            _ax toFixed 0, _ay toFixed 0, _hdg toFixed 0];
    };

    // Direction & up vectors from heading + pitch (Arma: X east, Y north, Z up;
    // sin/cos take DEGREES in SQF — one of the few languages where that's true)
    private _dir = [ sin _hdg * cos _pitchC,  cos _hdg * cos _pitchC, -sin _pitchC ];
    private _up  = [ sin _hdg * sin _pitchC,  cos _hdg * sin _pitchC,  cos _pitchC ];

    SC_cam setPosASL _camPosASL;
    SC_cam setVectorDirAndUp [_dir, _up];
    SC_cam camSetFov tan (_hfov / 2);
    SC_cam camCommit 0;

    // worldToScreen reads the RENDERED camera. camCommit 0 updates only the
    // simulation camera, so every projection made before the next drawn frame
    // uses the PREVIOUS pose. Two frames is belt-and-braces.
    private _f0 = diag_frameNo;
    waitUntil { diag_frameNo > _f0 + 1 };

    // Stash pose metadata for the label logger
    SC_camMeta = [_camPosASL, _alt, _pitchC, _hdg, _hfov];

    SC_cam
};

// ----------------------------------------------------------------------------
// call SC_fnc_destroyCamera — return view to the player unit and clean up
// ----------------------------------------------------------------------------
SC_fnc_destroyCamera = {
    if (!isNil "SC_cam" && {!isNull SC_cam}) then {
        SC_cam cameraEffect ["Terminate", "Back"];
        camDestroy SC_cam;
        SC_cam = objNull;
    };
    setAperture -1;
    showHUD true;
    enableEnvironment [true, true];
    0 setOvercast 0; 0 setFog 0; 0 setRain 0;
    forceWeatherChange;
};