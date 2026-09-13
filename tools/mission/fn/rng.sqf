// ============================================================================
// SynthCap — seeded PRNG (Wichmann–Hill)
//
// WHY: SQF's `random` cannot be seeded, so scenes would never be reproducible.
// For a thesis you want: (terrain, sceneIndex, masterSeed) -> identical scene.
//
// WHY WICHMANN–HILL SPECIFICALLY: SQF numbers are 32-bit floats (~7 significant
// digits). A classic Park–Miller LCG needs exact 32-bit integer products
// (16807 * 2^31 territory) which float32 silently rounds — your "PRNG" becomes
// a non-deterministic mess. Wichmann–Hill was designed in 1982 for exactly
// this constraint: three small LCGs whose intermediate products stay below
// 2^24 (~16.7M), the float32 exact-integer limit. Max product here:
// 172 * 30306 ≈ 5.2M. Safe.
// ============================================================================

// --- seed the generator ---
// _seed call SC_fnc_srand;
SC_fnc_srand = {
    params ["_seed"];
    _seed = abs floor _seed;
    SC_rngS1 = 1 + (_seed mod 30268);
    SC_rngS2 = 1 + (floor (_seed / 30268) mod 30306);
    SC_rngS3 = 1 + (floor (_seed / 917101608) mod 30322);  // 30268*30306
};

// --- uniform [0,1) ---
// _r = call SC_fnc_rand;
SC_fnc_rand = {
    SC_rngS1 = (171 * SC_rngS1) mod 30269;
    SC_rngS2 = (172 * SC_rngS2) mod 30307;
    SC_rngS3 = (170 * SC_rngS3) mod 30323;
    (SC_rngS1 / 30269 + SC_rngS2 / 30307 + SC_rngS3 / 30323) mod 1
};

// --- uniform [a,b) ---
// _r = [_a, _b] call SC_fnc_randRange;
SC_fnc_randRange = {
    params ["_a", "_b"];
    _a + (call SC_fnc_rand) * (_b - _a)
};

// --- pick a random element of an array ---
// _el = _array call SC_fnc_pick;
SC_fnc_pick = {
    _this select floor ((call SC_fnc_rand) * count _this) min (count _this - 1)
};

// default-init so calling rand before srand doesn't error
[42] call SC_fnc_srand;


SC_fnc_shuffle = {
    private _a = +_this;
    for "_i" from ((count _a) - 1) to 1 step -1 do {
        private _j = floor ((call SC_fnc_rand) * (_i + 1));
        private _t = _a select _i;
        _a set [_i, _a select _j];
        _a set [_j, _t];
    };
    _a
};


