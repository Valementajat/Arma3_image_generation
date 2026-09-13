SC_extOK = false;

SC_fnc_extOpen = {
    params ["_path"];
    private _v = "synthcap" callExtension ["version", []];
    if ((_v select 0) isEqualTo "") exitWith {
        diag_log text format ["SYNTHCAP|EXT|no response|%1", _v]; false
    };
    diag_log text format ["SYNTHCAP|EXT|version|%1", _v];
    private _r = "synthcap" callExtension ["open", [_path]];
    SC_extOK = ((_r select 0) isEqualTo "ok");
    diag_log text format ["SYNTHCAP|EXT|open|%1|%2", _path, _r];
    SC_extOK
};

SC_fnc_extWrite = {
    params ["_line"];
    if (!SC_extOK) exitWith {};
    private _r = "synthcap" callExtension ["write", [_line]];
    if !((_r select 0) isEqualTo "ok") then {
        diag_log text format ["SYNTHCAP|EXTERR|%1", _r];
    };
};

// rounding helper — keeps scientific notation out of the JSON
SC_fnc_r = {
    params ["_v", ["_d", 2]];
    private _m = 10 ^ _d;
    (round (_v * _m)) / _m
};