// ============================================================================
// SynthCap — 2D bounding box extraction (the core)
//
// Chain per object:
//   boundingBoxReal (model space, optional LOD)
//     -> 8 corners + 12 edge midpoints + centre  (21 sample points)
//     -> modelToWorldVisual                       (model -> world AGL)
//     -> behind-camera cull (dot product with camera dir)
//     -> worldToScreen                            (world AGL -> UI coords)
//     -> safe-zone affine transform               (UI coords -> PIXELS)
//     -> min/max over surviving points, clamp to image rectangle
//
// WHY THE *VISUAL* VARIANTS: the engine keeps separate simulation and render
// states; on moving objects modelToWorld (sim state) + worldToScreen (render
// state) disagree by a velocity-dependent error. Our scenes are frozen at
// capture time, which kills the issue, but we use Visual variants anyway.
//
// WHY EDGE MIDPOINTS: worldToScreen gives us nothing useful for points that
// fall outside the view. If a truck pokes into the frame but all 8 box
// corners are outside it, corners alone would report "offscreen" and drop a
// clearly visible object. 12 extra midpoints make partially-visible objects
// degrade gracefully (the box tightens toward the visible part — a slight
// under-box at frame edges, which we mark with truncated=1).
//
// WHY THE SAFE-ZONE TRANSFORM: worldToScreen returns Arma UI coordinates,
// which are defined relative to the SAFE ZONE, not the screen edges. UI x=0
// is NOT the left edge of your PNG. This is the single most common source of
// "all my boxes are shifted/scaled" in this exact use case. Pixel mapping:
//   px = (ui_x - safeZoneX) / safeZoneW * imageWidth
//   py = (ui_y - safeZoneY) / safeZoneH * imageHeight
// (Single monitor assumed. Triple-head setups need the *Abs variants.)
// ============================================================================

// Edge index pairs for the 8-corner box (order produced by SC_fnc_boxPointsModel)
SC_boxEdges = [
    [0,1],[1,3],[3,2],[2,0],      // bottom face
    [4,5],[5,7],[7,6],[6,4],      // top face
    [0,4],[1,5],[2,6],[3,7]       // verticals
];

// ----------------------------------------------------------------------------
// [_obj, _lod] call SC_fnc_boxPointsModel
// -> [cornersArray(8), allSamplePoints(21)]   (both in MODEL space)
// ----------------------------------------------------------------------------
SC_fnc_boxPointsModel = {
    params ["_obj", ["_lod", ""]];

    private _bb = if (_lod isEqualTo "") then {
        boundingBoxReal _obj
    } else {
        boundingBoxReal [_obj, _lod]
    };
    // Newer engine versions append a bounding-sphere radius as a 3rd element;
    // we only take min/max.
    (_bb select 0) params ["_x0", "_y0", "_z0"];
    (_bb select 1) params ["_x1", "_y1", "_z1"];

    private _corners = [
        [_x0,_y0,_z0], [_x1,_y0,_z0], [_x0,_y1,_z0], [_x1,_y1,_z0],
        [_x0,_y0,_z1], [_x1,_y0,_z1], [_x0,_y1,_z1], [_x1,_y1,_z1]
    ];

    private _pts = + _corners;                       // copy
    {                                                // 12 edge midpoints
        _x params ["_i", "_j"];
        private _a = _corners select _i;
        private _b = _corners select _j;
        _pts pushBack (( _a vectorAdd _b ) vectorMultiply 0.5);
    } forEach SC_boxEdges;
    _pts pushBack [ (_x0+_x1)/2, (_y0+_y1)/2, (_z0+_z1)/2 ];   // centre

    [_corners, _pts]
};

// ----------------------------------------------------------------------------
// _uiPos call SC_fnc_uiToPx  -> [px, py]
// ----------------------------------------------------------------------------
SC_fnc_uiToPx = {
    params ["_ux", "_uy"];
    [
        (_ux - safeZoneX) / safeZoneW * SC_imgW,
        (_uy - safeZoneY) / safeZoneH * SC_imgH
    ]
};

// ----------------------------------------------------------------------------
// _objectsArray call SC_fnc_cacheBoxPoints
//
// The scene is FROZEN at capture time, so model->world is constant for the
// whole run. Everything that doesn't depend on the camera is hoisted out of
// the per-frame path and stashed on the object.
// Call AFTER SC_fnc_freeze, and again if anything moves.
// ----------------------------------------------------------------------------
SC_fnc_cacheBoxPoints = {
    {
        private _obj = _x;
        if (isNull _obj) then { continue };

        // --- LOD validation: some models return a degenerate or absurd box
        //     for a named LOD. Detect once here, not silently every frame.
        private _lod = SC_boxLOD;
        private _bb  = if (_lod isEqualTo "") then { boundingBoxReal _obj }
                       else { boundingBoxReal [_obj, _lod] };
        (_bb select 0) params ["_x0","_y0","_z0"];
        (_bb select 1) params ["_x1","_y1","_z1"];
        private _dx = _x1 - _x0; private _dy = _y1 - _y0; private _dz = _z1 - _z0;

        if (_dx < 0.5 || _dy < 0.5 || _dz < 0.5 || _dx > 60 || _dy > 60 || _dz > 60) then {
            diag_log text format ["SYNTHCAP|WARN|LOD '%1' degenerate on %2 (%3x%4x%5) — falling back to default",
                _lod, typeOf _obj, _dx toFixed 1, _dy toFixed 1, _dz toFixed 1];
            _lod = "";
        };

        ([_obj, _lod] call SC_fnc_boxPointsModel) params ["_cModel", "_ptsModel"];

        private _ptsAGL = _ptsModel apply { _obj modelToWorldVisual _x };
        private _ptsASL = _ptsAGL  apply { AGLToASL _x };

        // visibility samples: 8 corners + centre (centre is the last point)
        private _visASL = (_ptsASL select [0, 8]) + [_ptsASL select ((count _ptsASL) - 1)];

        // conservative cull radius from the box diagonal
        private _radius = 0.5 * sqrt (_dx*_dx + _dy*_dy + _dz*_dz);
        private _centreASL = _ptsASL select ((count _ptsASL) - 1);

        _obj setVariable ["SC_boxCache", [_ptsAGL, _ptsASL, _visASL, _centreASL, _radius, _lod], false];
    } forEach _this;

    diag_log text format ["SYNTHCAP|CACHE|%1 objects, lod='%2'", count _this, SC_boxLOD];
};


// ----------------------------------------------------------------------------
// _obj call SC_fnc_projectObject
//
// -> []  if the object contributes no usable box (fully offscreen / behind)
// -> [xMinPx, yMinPx, wPx, hPx, truncated, nProjected, nTotal]
//    truncated: 1 if the raw box exceeded the image rectangle or any sample
//               point was offscreen/behind-camera, else 0
// ----------------------------------------------------------------------------
SC_fnc_projectObject = {
    private _obj = _this;

    private _cache = _obj getVariable ["SC_boxCache", []];
    if (_cache isEqualTo []) exitWith {
        diag_log text format ["SYNTHCAP|WARN|no box cache for %1 — call SC_fnc_cacheBoxPoints", typeOf _obj];
        []
    };
    _cache params ["_ptsAGL", "_ptsASL", "", "_centreASL", "_radius"];

    private _camPosASL = getPosASL SC_cam;
    private _camDir    = vectorDir SC_cam;

    // --- cheap rejects before the 21-point projection --------------------
    private _toObj = _centreASL vectorDiff _camPosASL;
    private _dist  = vectorMagnitude _toObj;

    // entirely behind the camera (radius-tolerant)
    if ((_toObj vectorDotProduct _camDir) < -_radius) exitWith { [] };

    // beyond what the engine is drawing — a label here has no pixels
    if (_dist > SC_maxLabelRange) exitWith { [] };

    // outside the cone: half-angle padded by the object's angular size
    private _cosAng = (_toObj vectorDotProduct _camDir) / (_dist max 0.01);
    if (_cosAng < SC_cullCos && {_dist > _radius * 4}) exitWith { [] };

    private _xMin =  1e9; private _yMin =  1e9;
    private _xMax = -1e9; private _yMax = -1e9;
    private _nProj = 0;
    private _anyLost = false;

    {
        // Behind-camera cull: worldToScreen behaviour for behind-plane points
        // has varied across engine versions (empty vs. mirrored garbage);
        // an explicit dot-product test is version-proof.
        private _rel = (_ptsASL select _forEachIndex) vectorDiff _camPosASL;
        if ((_rel vectorDotProduct _camDir) <= 0.01) then {
            _anyLost = true;
        } else {
            private _scr = worldToScreen _x;
            if (count _scr < 2) then {
                _anyLost = true;                             // offscreen
            } else {
                (_scr call SC_fnc_uiToPx) params ["_px", "_py"];
                if (_px < 0 || _py < 0 || _px > SC_imgW || _py > SC_imgH) then {
                    _anyLost = true;
                };
                if (_px < _xMin) then { _xMin = _px };
                if (_py < _yMin) then { _yMin = _py };
                if (_px > _xMax) then { _xMax = _px };
                if (_py > _yMax) then { _yMax = _py };
                _nProj = _nProj + 1;
            };
        };
    } forEach _ptsAGL;

    if (_nProj == 0) exitWith { [] };                        // fully offscreen

    private _cxMin = _xMin max 0;
    private _cyMin = _yMin max 0;
    private _cxMax = _xMax min SC_imgW;
    private _cyMax = _yMax min SC_imgH;
    private _w = _cxMax - _cxMin;
    private _h = _cyMax - _cyMin;
    if (_w <= 0 || _h <= 0) exitWith { [] };                 // degenerate

    private _truncated = _anyLost
        || _xMin < 0 || _yMin < 0 || _xMax > SC_imgW || _yMax > SC_imgH;

    [_cxMin, _cyMin, _w, _h, parseNumber _truncated, _nProj, count _ptsAGL]
};


