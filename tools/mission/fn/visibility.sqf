// ============================================================================
// SynthCap — occlusion / visibility scoring
//
// checkVisibility returns 0..1 per ray. Single-centre-point checks are
// worthless on vehicles (centre behind a wall, turret in plain view -> object
// wrongly dropped), so we average rays to 9 sample points: the 8 bounding-box
// corners + the centre.
//
// GOTCHAS handled here:
//  * SELF-OCCLUSION: a ray from the camera to the vehicle's FAR corners passes
//    through the vehicle's own near-side hull -> reported "occluded" even for
//    a vehicle sitting alone in a field. Fix: pass the object itself as the
//    ignored object in checkVisibility's left argument.
//  * The camera is a "camera" object with no geometry, so it never blocks rays.
//  * "VIEW" LOD is lenient about glass and some foliage. From a UAV nadir view
//    this partially mirrors reality (sparse canopy is see-through-ish), but
//    audit it visually on forested maps; if vegetation occlusion looks wrong
//    we can add lineIntersectsSurfaces sampling in stage 2.
//
// Returns: visibility fraction 0..1
// ============================================================================

SC_fnc_visibility = {
    private _obj = _this;
    private _cache = _obj getVariable ["SC_boxCache", []];
    if (_cache isEqualTo []) exitWith { 0 };
    _cache params ["", "", "_visASL"];

    private _camASL = getPosASL SC_cam;
    private _sum = 0;
    { _sum = _sum + ([_obj, "VIEW"] checkVisibility [_camASL, _x]) } forEach _visASL;
    _sum / (count _visASL)
};