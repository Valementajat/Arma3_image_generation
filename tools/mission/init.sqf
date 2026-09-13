// ============================================================================
// SynthCap — init.sqf (runs automatically when the mission starts)
// ============================================================================
if (!hasInterface) exitWith {};   // SP editor preview only; no dedicated logic yet
{
    private _f = _x;
    private _code = compile preprocessFileLineNumbers _f;
    if (isNil "_code") then {
        systemChat format ["SynthCap: FAILED to compile %1 - check RPT.", _f];
    } else {
        call _code;
    };
} forEach [
    "params.sqf",
    "fn\rng.sqf",
    "fn\camera.sqf",
    "fn\project.sqf",
    "fn\visibility.sqf",
    "fn\capture.sqf",
    "fn\sqfFileWrapper.sqf"
];

/* diag_log str ("synthcap" callExtension "version"); */

// small delay so the world finishes loading before we start
[] spawn {
    sleep 1;
    execVM "randMap.sqf";
};
