// ============================================================================
// SynthCap — configuration
// In stage 3+ the Python orchestrator overwrites this file per run.
// ============================================================================

// --- Reproducibility ---
SC_masterSeed = 1337;

// --- Image geometry ------------------------------------------------------
// CRITICAL: these MUST equal the true pixel size of the PNGs `screenshot`
// produces, i.e. (window resolution) x (sampling %). If you run the game at
// 1920x1080 with 100% sampling, this is 1920x1080. With 200% sampling it is
// 3840x2160. The offline visualizer cross-checks this against the real PNG
// header and will yell at you if it disagrees. Getting this wrong scales
// every box by a constant factor.
SC_imgW = 1280;
SC_imgH = 720;

// --- Camera ---------------------------------------------------------------
SC_hfovDeg = 60;      // horizontal field of view, degrees (demo default)
// NOTE on camSetFov: Arma's fov value is (to good approximation) the tangent
// of the half horizontal FOV — the vanilla default 0.75 corresponds to ~74°.
// The calibration scene (stage-1 validation step 2) verifies this empirically
// on YOUR build/aspect ratio; do not skip it.



// --- Labeling policy ------------------------------------------------------
SC_minVis   = 0.15;   // drop objects with visibility fraction below this
SC_minBoxPx = 8;      // drop boxes whose SHORT side is under this many pixels
// Everything kept gets `visibility` + `truncated` attributes recorded, so you
// can filter harder at training time without re-rendering.

// --- Bounding box LOD -----------------------------------------------------
// "" = default boundingBoxReal (often loose: includes rotor discs, antennas,
// sometimes clan-sign geometry). "Geometry" or "FireGeometry" usually hug the
// hull much better BUT support varies per model — some addon models return a
// degenerate/huge box for a named LOD. The wireframe overlay is your audit
// tool: cycle this setting and look. We may end up with a per-class override
// table in stage 2.
SC_boxLOD = "Geometry";

// --- Vehicle table: classname -> category ---------------------------------
// SINGLE SOURCE OF TRUTH. Adding a row here adds the class to the spawn pool
// AND gives it a label. There is no way to spawn something unlabelled.
/* SC_vehicleTable = [
    ["B_MRAP_01_F",             "mrap"],
    ["O_MRAP_02_F",             "mrap"],
    ["B_APC_Tracked_01_rcws_F", "ifv"],
    ["O_MBT_02_cannon_F",       "tank"],
    ["B_Truck_01_covered_F",    "truck"],
    ["C_Offroad_01_F",          "car"],
    ["C_Offroad_01_red_F",      "car"],
    ["C_Hatchback_01_F",        "car"],
    ["C_Quadbike_01_black_F",   "quad"]
]; */

SC_vehicleTable = [
    ["B_MBT_01_arty_F", "artillery"],   // vanilla,
    ["B_MBT_01_mlrs_F", "artillery"],   // vanilla,
    ["CUP_B_M1129_MC_MK19_Desert", "artillery"],   // 541888371,
    ["CUP_B_M270_HE_HIL", "artillery"],   // 541888371,
    ["CUP_B_RM70_CZ", "artillery"],   // 541888371,
    ["CUP_O_BM21_RU", "artillery"],   // 541888371,
    ["I_Truck_02_MRL_F", "artillery"],   // vanilla,
    ["O_MBT_02_arty_F", "artillery"],   // vanilla,
    ["ffp_122h63", "artillery"],   // 917042703,
    ["ffp_rsrakh06", "artillery"],   // 917042703,
    ["sfp_grkpbv90120", "artillery"],   // 826911897,
    ["sfp_robotbil15", "artillery"],   // 826911897,
    ["CUP_B_M1030_USA", "bike"],   // 541888371,
    ["CUP_C_TT650_RU", "bike"],   // 541888371,
    ["sfp_cykel42", "bike"],   // 826911897,
    ["B_G_Offroad_01_repair_F", "car"],   // vanilla,
    ["B_LSV_01_AT_F", "car"],   // expansion,
    ["B_MRAP_01_hmg_F", "car"],   // vanilla,
    ["B_Truck_01_box_F", "car"],   // vanilla,
    ["B_Truck_01_cargo_F", "car"],   // enoch,
    ["B_Truck_01_transport_F", "car"],   // vanilla,
    ["CUP_B_Dingo_CZ_Des", "car"],   // 541888371,
    ["CUP_B_Mastiff_GMG_GB_D", "car"],   // 541888371,
    ["CUP_B_nM1151_ogpk_m2_AFU", "car"],   // 541888371,
    ["CUP_I_Hilux_armored_AGS30_TK", "car"],   // 541888371,
    ["CUP_I_Hilux_zu23_TK", "car"],   // 541888371,
    ["CUP_I_UAZ_AGS30_UN", "car"],   // 541888371,
    ["CUP_I_nM1025_Unarmed_ION", "car"],   // 541888371,
    ["CUP_O_Tigr_M_233114_RU", "car"],   // 541888371,
    ["C_Kart_01_F", "car"],   // kart,
    ["C_SUV_01_F", "car"],   // vanilla,
    ["C_Truck_02_fuel_F", "car"],   // vanilla,
    ["C_Van_02_service_F", "car"],   // orange,
    ["Flex_CUP_POL_RG31E_M2", "car"],   // 3459905206,
    ["LIB_Kfz1_Hood", "car"],   // 2648308937,
    ["LIB_OpelBlitz_Ammo", "car"],   // 2648308937,
    ["LIB_OpelBlitz_Parm", "car"],   // 2648308937,
    ["LIB_Scout_M3_FFV", "car"],   // 2648308937,
    ["LIB_US_GMC_Fuel", "car"],   // 2648308937,
    ["LIB_Willys_MB_Hood", "car"],   // 2648308937,
    ["LIB_Zis5v_Fuel", "car"],   // 2648308937,
    ["LIB_Zis5v_Med", "car"],   // 2648308937,
    ["O_LSV_02_AT_F", "car"],  // expansion,
    ["O_Truck_03_ammo_F", "car"],   // vanilla,
    ["O_Truck_03_covered_F", "car"],   // vanilla,
    ["ffp_bv206", "car"],   // 917042703,
    ["ffp_rg32m", "car"],   // 917042703,
    ["ffp_susi8x8_ammo", "car"],   // 917042703,
    ["sfp_tent12_base", "car"],   // 826911897,
    ["sfp_tgb1111", "car"],   // 826911897,
    ["sfp_tgb1314", "car"],   // 826911897,
    ["sfp_tgb13_ksp58", "car"],   // 826911897,
    ["sfp_tgb16_ksp58", "car"],   // 826911897,
    ["sfp_tgb20", "car"],   // 826911897,
    ["sfp_wheelchair", "car"],   // 826911897,
    ["B_Heli_Attack_01_dynamicLoadout_F", "heli"],   // vanilla,
    ["B_Heli_Light_01_F", "heli"],   // vanilla,
    ["B_Heli_Transport_01_F", "heli"],   // vanilla,
    ["B_Heli_Transport_03_F", "heli"],   // heli,
    ["B_T_UAV_03_dynamicLoadout_F", "heli"],   // expansion,
    ["B_UAV_01_F", "heli"],   // vanilla,
    ["B_UAV_06_F", "heli"],  // orange,
    ["CUP_B_CH47F_VIV_GB", "heli"],   // 541888371,
    ["CUP_B_UH1Y_UNA_USMC", "heli"],   // 541888371,
    ["CUP_I_AH1Z_Dynamic_AAF", "heli"],  // 541888371,
    ["CUP_I_Mi17_UN", "heli"],   // 541888371,
    ["CUP_I_Wildcat_Green_AAF", "heli"],   // 541888371,
    ["CUP_MH60S_Unarmed_USN", "heli"],   // 541888371,
    ["CUP_O_Ka50_DL_RU", "heli"],   // 541888371,
    ["CUP_O_Mi8_RU", "heli"],   // 541888371,
    ["EC635", "heli"],   // 909320014,
    ["EC635_SAR", "heli"],   // 909320014,
    ["EC635_Unarmed_Cargo", "heli"],   // 909320014,
    ["Flex_CUP_NOR_Bell412_Armed", "heli"],   // 3333292879,
    ["Flex_CUP_POL_Mi24_D", "heli"],   // 3459905206,
    ["Flex_CUP_POL_Mi24_D_MEV", "heli"],   // 3459905206,
    ["I_Heli_light_03_dynamicLoadout_F", "heli"],   // vanilla,
    ["I_Heli_light_03_unarmed_F", "heli"],   // vanilla,
    ["NH90Armed", "heli"],   // 909320014,
    ["NH90Marine", "heli"],  // 909320014,
    ["O_Heli_Attack_02_dynamicLoadout_F", "heli"],   // vanilla,
    ["O_Heli_Light_02_unarmed_F", "heli"],   // vanilla,
    ["O_Heli_Transport_04_F", "heli"],   // heli,
    ["O_Heli_Transport_04_ammo_F", "heli"],   // heli,
    ["O_Heli_Transport_04_bench_F", "heli"],   // heli,
    ["O_Heli_Transport_04_box_F", "heli"] ,  // heli,
    ["O_Heli_Transport_04_fuel_F", "heli"] ,  // heli,
    ["O_Heli_Transport_04_medevac_F", "heli"] ,  // heli,
    ["O_Heli_Transport_04_repair_F", "heli"],   // heli,
    ["UH60_wreck_EP1", "heli"] ,  // 2648308937,
    ["ffp_md500", "heli"]  , // 917042703,
    ["sfp_hkp16", "heli"] ,  // 826911897,
    ["sfp_hkp16_ffv", "heli"] ,  // 826911897,
    ["sfp_hkp4", "heli"] ,  // 826911897,
    ["sfp_hkp9", "heli"] ,  // 826911897,
    ["B_AFV_Wheeled_01_cannon_F", "ifv"] ,  // tank,
    ["B_AFV_Wheeled_01_up_cannon_F", "ifv"],   // tank,
    ["B_APC_Tracked_01_CRV_F", "ifv"],   // vanilla,
    ["B_APC_Tracked_01_rcws_F", "ifv"],   // vanilla,
    ["B_APC_Wheeled_01_cannon_F", "ifv"],   // vanilla,
    ["CUP_B_BMP2_AMB_CZ", "ifv"],   // 541888371,
    ["CUP_B_BMP2_CZ", "ifv"],  // 541888371,
    ["CUP_B_FV432_Bulldog_GB_D_RWS", "ifv"],   // 541888371,
    ["CUP_B_LAV25M240_USMC", "ifv"] ,  // 541888371,
    ["CUP_I_M113A3_UN", "ifv"] ,  // 541888371,
    ["CUP_O_BMP1_TKA", "ifv"] ,  // 541888371,
    ["CUP_O_GAZ_Vodnik_AGS_RU", "ifv"],   // 541888371,
    ["CUP_O_GAZ_Vodnik_PK_RU", "ifv"] ,  // 541888371,
    ["I_APC_Wheeled_03_cannon_F", "ifv"],   // vanilla,
    ["I_APC_tracked_03_cannon_F", "ifv"],  // vanilla,
    ["LIB_PzKpfwV_no_lods_DLV", "ifv"],   // 2648308937,
    ["LIB_SdKfz251", "ifv"],   // 2648308937,
    ["LIB_SdKfz251_FFV", "ifv"] ,  // 2648308937,
    ["LIB_SdKfz_7", "ifv"] ,  // 2648308937,
    ["LIB_SdKfz_7_AA", "ifv"] ,  // 2648308937,
    ["LIB_UK_M3_Halftrack", "ifv"],   // 2648308937,
    ["LIB_UniversalCarrier", "ifv"],   // 2648308937,
    ["O_APC_Tracked_02_cannon_F", "ifv"] ,  // vanilla,
    ["O_APC_Wheeled_02_rcws_v2_F", "ifv"] ,  // vanilla,
    ["ffp_bmp2", "ifv"],   // 917042703,
    ["ffp_cv9030", "ifv"] ,  // 917042703,
    ["sfp_patgb360", "ifv"] ,  // 826911897,
    ["sfp_pbv302", "ifv"],   // 826911897,
    ["CUP_B_M1126_ICV_M2_Desert", "mrap"] ,  // 541888371,
    ["CUP_B_M1128_MGS_Desert", "mrap"]  , // 541888371,
    ["CUP_B_M1135_ATGMV_Desert", "mrap"] ,  // 541888371,
    ["CUP_B_RG31_M2_GC_USA", "mrap"] ,  // 541888371,
    ["CUP_M1240_AFU", "mrap"] ,  // 541888371,
    ["CUP_M1240_OGPK_Mk19_AFU", "mrap"] ,  // 541888371,
    ["CUP_M1245_CROWS_M134_AFU", "mrap"],   // 541888371,
    ["CUP_M1277_M134_AFU", "mrap"],   // 541888371,
    ["B_Plane_CAS_01_dynamicLoadout_F", "plane"],   // vanilla,
    ["B_Plane_Fighter_01_F", "plane"] ,  // jets,
    ["B_T_VTOL_01_armed_F", "plane"] ,  // expansion,
    ["B_T_VTOL_01_vehicle_F", "plane"] ,  // expansion,
    ["B_UAV_02_dynamicLoadout_F", "plane"]  , // vanilla,
    ["B_UAV_05_F", "plane"],   // jets,
    ["CUP_B_A10_DYN_USA", "plane"] ,  // 541888371,
    ["CUP_B_C130J_Cargo_GB", "plane"] ,  // 541888371,
    ["CUP_B_C130J_GB", "plane"],   // 541888371,
    ["CUP_B_C47_USA", "plane"] ,  // 541888371,
    ["CUP_B_L39_CZ", "plane"] ,  // 541888371,
    ["CUP_B_MV22_VIV_USMC", "plane"] ,  // 541888371,
    ["CUP_C_B737_CIV", "plane"] ,  // 541888371,
    ["CUP_O_Pchela1T_RU", "plane"],  // 541888371,
    ["I_Plane_Fighter_03_dynamicLoadout_F", "plane"] ,  // vanilla,
    ["LIB_CG4_WACO", "plane"],   // 2648308937,
    ["LIB_FW190F8", "plane"] ,  // 2648308937,
    ["LIB_HORSA", "plane"] ,  // 2648308937,
    ["LIB_Ju87", "plane"] ,  // 2648308937,
    ["LIB_Li2", "plane"]  , // 2648308937,
    ["LIB_P39", "plane"]  , // 2648308937,
    ["LIB_P47", "plane"]  , // 2648308937,
    ["LIB_Pe2", "plane"]  , // 2648308937,
    ["O_Plane_CAS_02_dynamicLoadout_F", "plane"],  // vanilla,
    ["O_Plane_Fighter_02_F", "plane"] ,  // jets,
    ["O_T_UAV_04_CAS_F", "plane"] ,  // expansion,
    ["O_T_VTOL_02_vehicle_dynamicLoadout_F", "plane"],   // expansion,
    ["ffp_jas39e", "plane"],   // 917042703,
    ["ffp_orbiter", "plane"],   // 917042703,
    ["sfp_jas39", "plane"] ,  // 826911897,
    ["sfp_s100b", "plane"] ,  // 826911897,
    ["sfp_tp84_2015", "plane"] ,  // 826911897,
    ["sfp_uav01", "plane"],   // 826911897,
    ["sfp_uav03", "plane"] ,  // 826911897,
    ["B_GMG_01_high_F", "static"],   // vanilla,
    ["B_Mortar_01_F", "static"] ,  // vanilla,
    ["B_Radar_System_01_F", "static"],   // jets,
    ["B_SAM_System_03_F", "static"] ,  // jets,
    ["B_Static_Designator_01_F", "static"] ,  // mark,
    ["CBA_B_InvisibleTargetAir", "static"] ,  // 450814997,
    ["CUP_B_L134A1_TriPod_BAF_MPT", "static"]  , // 497661914,
    ["CUP_B_M134_A_GB", "static"],   // 497660133,
    ["CUP_B_M163_Vulcan_USA", "static"],   // 541888371,
    ["CUP_B_M2StaticMG_US", "static"] ,  // 497661914,
    ["CUP_B_MK19_TriPod_US", "static"] ,  // 497661914,
    ["CUP_B_SPG9_AFU", "static"] ,  // 497661914,
    ["CUP_B_Type072_Turret", "static"]  , // 541888371,
    ["CUP_B_nM1097_AVENGER_AFU", "static"] ,  // 541888371,
    ["CUP_I_AGS_UN", "static"],   // 497661914,
    ["CUP_I_Datsun_AA", "static"] ,  // 541888371,
    ["CUP_I_KORD_high_UN", "static"] , // 497661914,
    ["CUP_O_D30_RU", "static"] ,  // 497661914,
    ["CUP_O_Metis_RU", "static"] ,  // 497661914,
    ["CUP_O_ZSU23_Afghan_TK", "static"] ,  // 541888371,
    ["CUP_WV_B_CRAM", "static"] ,  // 541888371,
    ["Flex_CUP_FIN_SearchLight", "static"],  // 3465921651,
    ["I_HMG_02_F", "static"],   // vanilla,
    ["LIB_61k", "static"] ,  // 2648308937,
    ["LIB_FlaK_30", "static"] ,  // 2648308937,
    ["LIB_Flakvierling_38", "static"] ,  // 2648308937,
    ["LIB_M2_60", "static"],   // 2648308937,
    ["LIB_Zis3", "static"] ,  // 2648308937,
    ["LIB_leFH18", "static"]  , // 2648308937,
    ["Land_Pod_Heli_Transport_04_medevac_F", "static"],   // heli,
    ["O_Radar_System_02_F", "static"],   // jets,
    ["O_SAM_System_04_F", "static"],   // jets,
    ["O_Static_Designator_02_F", "static"],   // mark,
    ["sfp_75mm_m57", "static"] ,  // 826911897,
    ["sfp_fh77", "static"] ,  // 826911897,
    ["sfp_grsp", "static"] ,  // 826911897,
    ["sfp_ksp88", "static"] ,  // 826911897,
    ["sfp_lvkv90c", "static"] ,  // 826911897,
    ["sfp_rbs17", "static"],   // 826911897,
    ["sfp_rbs56", "static"] ,  // 826911897,
    ["B_MBT_01_TUSK_F", "tank"] ,  // vanilla,
    ["B_MBT_01_cannon_F", "tank"] ,  // vanilla,
    ["B_UGV_02_Science_F", "tank"] ,  // enoch,
    ["CUP_B_Leopard2A6_UA", "tank"] ,  // 541888371,
    ["CUP_B_M1A2C_LDF", "tank"],   // 541888371,
    ["CUP_B_M1A2SEP_NATO", "tank"]  , // 541888371,
    ["CUP_B_M1A2SEP_RACS", "tank"] ,  // 541888371,
    ["CUP_B_M60A3_USMC", "tank"] ,  // 541888371,
    ["CUP_B_T72_CZ", "tank"],   // 541888371,
    ["CUP_O_T72_RU", "tank"]  , // 541888371,
    ["CUP_O_T90M_RU", "tank"] ,  // 541888371,
    ["I_LT_01_AT_F", "tank"] ,  // tank,
    ["I_LT_01_cannon_F", "tank"] ,  // tank,
    ["I_LT_01_scout_F", "tank"] ,  // tank,
    ["I_MBT_03_cannon_F", "tank"],   // vanilla,
    ["LIB_Churchill_Mk7_AVRE", "tank"] ,  // 2648308937,
    ["LIB_Cromwell_Mk4", "tank"],   // 2648308937,
    ["LIB_JS2_43", "tank"] ,  // 2648308937,
    ["LIB_M4A3_75", "tank"] , // 2648308937,
    ["LIB_M4A3_76", "tank"] ,  // 2648308937,
    ["LIB_PzKpfwV", "tank"] ,  // 2648308937,
    ["LIB_SdKfz124", "tank"] ,  // 2648308937,
    ["LIB_T34_76", "tank"]  , // 2648308937,
    ["O_MBT_02_cannon_F", "tank"] ,  // vanilla,
    ["O_MBT_02_railgun_F", "tank"],   // vanilla,
    ["O_MBT_04_cannon_F", "tank"] ,  // tank,
    ["O_MBT_04_command_F", "tank"],   // tank,
    ["sfp_ikv91", "tank"] , // 826911897,
    ["sfp_missile_trolley", "tank"] ,  // 826911897,
    ["sfp_strv102", "tank"]   ,// 826911897,
    ["sfp_strv103b", "tank"] ,  // 826911897,
    ["sfp_strv121", "tank"] ,  // 826911897,
    ["sfp_strv122", "tank"]   // 826911897
];


SC_vehiclePool = SC_vehicleTable apply { _x select 0 };
SC_categoryMap = createHashMapFromArray SC_vehicleTable;

// Canonical ordered class list — pin this on the Python side instead of
// deriving catToIdx from whatever happened to spawn.
SC_categories = [];
{
    private _c = _x select 1;
    if !(_c in SC_categories) then { SC_categories pushBack _c };
} forEach SC_vehicleTable;
SC_categories sort true;


// --- Small scraped vehicle pool ----------------------------------------------------
// Vanilla classes so the demo runs before CUP finishes downloading.
// Swap in CUP classnames later, e.g. "CUP_O_T72_RU", "CUP_B_HMMWV_M2_USA",
// "CUP_O_Ural_RU", "CUP_O_BMP2_RU", ...
SC_CUP_vehiclePool = [
    "CUP_I_412_Military_Armed_PMC",
    "CUP_I_412_Military_Armed_AT_PMC",
    "CUP_I_412_Mil_Utility_PMC",
    "CUP_I_412_Military_Radar_PMC",
    "CUP_I_412_dynamicLoadout_PMC",
    "CUP_I_412_Military_Armed_AAF",
    "CUP_I_412_Military_Armed_AT_AAF",
    "CUP_I_412_Mil_Utility_AAF",
    "CUP_I_412_Military_Radar_AAF",
    "CUP_I_412_dynamicLoadout_AAF",
    "CUP_I_412_Mil_Transport_PMC",
    "CUP_I_412_Mil_Transport_AAF",
    "CUP_I_LCU1600_RACS",
    "CUP_I_LCVP_RACS",
    "CUP_I_LCVP_VIV_RACS",
    "CUP_I_ZUBR_AAF",
    "CUP_I_ZUBR_UN",
    "CUP_I_M151_SYND",
    "CUP_I_M151_M2_SYND",
    "CUP_I_T810_Unarmed_LDF",
    "CUP_I_T810_Refuel_LDF",
    "CUP_I_T810_Reammo_LDF",
    "CUP_I_T810_Repair_LDF",
    "CUP_I_MTLB_pk_SYNDIKAT",
    "CUP_I_MTLB_pk_UN",
    "CUP_I_MTLB_pk_NAPA",
    "CUP_I_Type072_Rack_Right",
    "CUP_I_Type072_Rack_Left",
    "CUP_I_Type072_Turret",
    "CUP_I_Hilux_unarmed_TK",
    "CUP_I_Hilux_armored_unarmed_TK",
    "CUP_I_Hilux_SPG9_TK",
    "CUP_I_Hilux_armored_SPG9_TK",
    "CUP_I_Hilux_igla_TK",
    "CUP_I_Hilux_armored_igla_TK",
    "CUP_I_Hilux_metis_TK",
    "CUP_I_Hilux_armored_metis_TK",
    "CUP_I_Hilux_MLRS_TK",
    "CUP_I_Hilux_armored_MLRS_TK",
    "CUP_I_Hilux_zu23_TK",
    "CUP_I_Hilux_armored_zu23_TK",
    "CUP_I_Hilux_btr60_TK",
    "CUP_I_Hilux_BMP1_TK",
    "CUP_I_Hilux_armored_BMP1_TK",
    "CUP_I_Hilux_AGS30_TK",
    "CUP_I_Hilux_armored_AGS30_TK",
    "CUP_I_Hilux_M2_TK",
    "CUP_I_Hilux_armored_M2_TK",
    "CUP_I_Hilux_UB32_TK"
];



// --- Randomiser parameters -----------------------------------------------------------

SC_vehicleCountRange_min = 1;
SC_vehicleCountRange_max = 8;
SC_vehicleSpawnRad_min = 60;
SC_vehicleSpawnRad_max_max = 1000;
SC_vehicleDestroyed_max = 40;

// altitude settings and angle for the camera for capture
/* SC_poses = [
    [150, 90,   0, 8],
    [300, 60, 120, 4],
    [400, 80, 200, 3],
    [600, 90,  45, 2],
    [800, 45, 250, 1]
]; */

// [altMin, altMax, pitchMin, pitchMax, nPts]
SC_poseBands = [
    [120, 200, 70, 90, 8],
    [240, 340, 50, 80, 4],
    [340, 470, 55, 85, 3],
    [520, 700, 65, 90, 2],
    [700, 900, 40, 65, 1]
];

    // Worst-case horizontal camera backoff, derived from the bands themselves.
    // Current bands: 900 / tan 40 ≈ 1072 m.
    SC_camReach = 0;
    {
        _x params ["", "_aMax", "_pMin"];
        SC_camReach = SC_camReach max (_aMax / tan _pMin);
    } forEach SC_poseBands;


SC_fnc_samplePose = {
    params ["_band"];
    _band params ["_aMin", "_aMax", "_pMin", "_pMax"];
    [
        [_aMin, _aMax] call SC_fnc_randRange,
        [_pMin, _pMax] call SC_fnc_randRange,
        360 * (call SC_fnc_rand)
    ]
};


mapSize   = worldSize;              // edge length in metres (Altis 30720, Tanoa 15360, Stratis 8192)
mapRange  = [0, mapSize];             // valid x / y range
mapCenter = [mapSize / 2, mapSize / 2, 0];

SC_auditMode = false;
SC_captureMode = true;


// weather presets -------------------------------------------------
// [name, hour, overcast, fog, rain, windStr]
/* SC_weatherPresets = [
    ["clear_noon",     12, 0.00, 0.00, 0.0, 0.1],
    ["clear_morning",   7, 0.10, 0.05, 0.0, 0.2],
    ["hazy_pm",        15, 0.30, 0.25, 0.0, 0.3],
    ["overcast",       11, 0.70, 0.10, 0.0, 0.5],
    ["rain",           14, 0.90, 0.20, 0.7, 0.8],
    ["rain_morning",    7, 0.85, 0.20, 0.75, 0.6],
    ["rain_dusk",      19, 0.90, 0.20, 0.65, 0.7],
    ["fog_dawn",        6, 0.40, 0.45, 0.0, 0.1],
    ["dusk",           19, 0.20, 0.10, 0.0, 0.2]
];

 */

// --- Time of day ----------------------------------------------------------
// [label, hour, weight, aperture]
SC_timeStates = [
    ["dawn",       6, 0.10, 35],  
    ["morning",    9, 0.25, 70],  
    ["noon",      12, 0.30, 80],   
    ["afternoon", 15, 0.25, 72], 
    ["dusk",      19, 0.10, 35]    
];

// --- Sky condition --------------------------------------------------------
// [label, overcast, fog, rain, wind, weight, apertureMod]
SC_skyStates = [
    ["clear",    0.00, 0.00, 0.00, 0.1, 0.35,   0],
    ["hazy",     0.30, 0.25, 0.00, 0.3, 0.20,  -3],
    ["overcast", 0.70, 0.10, 0.00, 0.5, 0.25,  -8],
    ["rain",     0.90, 0.20, 0.70, 0.8, 0.12, -12],
    ["fog",      0.40, 0.45, 0.00, 0.1, 0.08,  -6]
];


/* // worldName -> aperture offset (positive = darker)
SC_terrainApertureMod = createHashMapFromArray [

    // --- snow, ~0.7-0.85 albedo -------------------------------------------
    ["tem_suursaariw",          25],
    
    ["tem_raatteentiew",        25],
    ["mcn_neaville_plr_bulge",  25],   // Ardennes, winter

    // --- sand / beach, bright ---------------------------------------------
    ["i44_omaha_v2",            10],   // beach + sea glare

    // --- Mediterranean, dry scrub and tan soil ----------------------------
    ["malden",                   8],
    ["stratis",                  8],
    ["altis",                    6],

    // --- temperate farmland, green but open -------------------------------
    ["i44_merderet_v2",          3],   // Normandy bocage + pasture
    ["i44_merderet_koth",        3],

    // --- boreal summer, dark conifer ~0.08 albedo -------------------------
    ["tem_suursaari",            0],
   
    ["tem_karelia",              0],
    ["tem_vinjesvingen",         0],
    ["tem_olhava",               0]
];
 */


// worldName (lowercase) -> aperture offset. Positive = stop down = darker.
// Keyed via `toLower worldName` — CfgWorlds casing is inconsistent across mods.
SC_terrainApertureMod = createHashMapFromArray [

    // --- snow, ~0.7-0.85 albedo -------------------------------------------
    ["tem_suursaariw",            25],
    ["raateroadw",                25],
    ["tem_talvivaara",            25],   // talvi = winter
    ["i44_merderet_winter",       25],
    ["mcn_neaville_winter",       25],
    ["swu_ardennes_1944_winter",  25],

    // --- Mediterranean / dry scrub ----------------------------------------
    ["stratis",                    8],
    ["malden",                     8],
    ["altis",                      6],
    ["swu_greece_pella_region",    6],

    // --- temperate farmland and built-up, green but open ------------------
    ["i44_merderet_v2",            3],   // Normandy bocage + pasture
    ["i44_merderet_koth",          3],
    ["swu_ardennes_1940",          3],
    ["swu_aachen_outskirts",       3],

    // --- boreal summer, dark conifer ~0.08 albedo -------------------------
    ["tem_suursaari",              0],
    ["tem_karelia",                0],
    ["tem_vinjesvingen",           0],
    ["tem_olhava",                 0],
    ["tem_chernarusd",             0]    // unverified — see note
];

// Weather samples drawn per scene (see SC_fnc_pickWeather)
SC_weatherPerScene = 5;

// Fog is capped against the tallest pose so vehicles stay visible.
// Above this camera-to-target range, fog is scaled down.
SC_fogMaxRange = 900;
SC_emptyFrac = 0.15;   
SC_seasonDate = [2035, 6, 24];   // month drives sun path — pin it for repeatability

// Weighted pick from [..., weight] rows — weight must be the LAST element.
SC_fnc_pickWeighted = {
    params ["_table"];
    private _total = 0;
    { _total = _total + (_x select ((count _x) - 1)) } forEach _table;

    private _r = _total * (call SC_fnc_rand);
    private _acc = 0;
    private _hit = _table select ((count _table) - 1);   // fallback
    {
        _acc = _acc + (_x select ((count _x) - 1));
        if (_r <= _acc) exitWith { _hit = _x };
    } forEach _table;
    _hit
};

// Returns [timeRow, skyRow] — call once per scene, per weather slot.
SC_fnc_pickWeather = {
    [
        [SC_timeStates] call SC_fnc_pickWeighted,
        [SC_skyStates]  call SC_fnc_pickWeighted
    ]
};

// [[_timeRow, _skyRow]] call SC_fnc_applyWeather  ->  "noon_overcast"
SC_fnc_applyWeather = {
    params ["_combo"];
    _combo params ["_timeRow", "_skyRow"];
    _timeRow params ["_tName", "_hour"];
    _skyRow  params ["_sName", "_oc", "_fog", "_rain", "_wind"];

    SC_seasonDate params ["_yr", "_mo", "_dy"];
    private _minute = floor (60 * (call SC_fnc_rand));   // jitter the sun angle
    setDate [_yr, _mo, _dy, _hour, _minute];

    // rain needs cloud cover or it renders as nothing
    private _ocEff = _oc;
    if (_rain > 0 && _ocEff < 0.7) then { _ocEff = 0.7 };

    // cap fog so the tallest pose can still see the target
    private _maxAlt = 0;
    { _maxAlt = _maxAlt max (_x select 1) } forEach SC_poseBands;
    private _fogEff = _fog;
    if (_maxAlt > SC_fogMaxRange) then {
        _fogEff = _fog * (SC_fogMaxRange / _maxAlt);
    };

    private _terrMod = SC_terrainApertureMod getOrDefault [worldName, 0];
    private _ap = (((_timeRow select 3) + (_skyRow select 6) + _terrMod) max 8) min 100;
    SC_apertureNow = _ap;
    setAperture _ap;



    0 setOvercast _ocEff;
    0 setFog _fogEff;
    0 setRain _rain;
    setWind [_wind, _wind, true];
    forceWeatherChange;

    // wait for the transition to actually land, don't guess
    private _t0 = time;
    waitUntil {
        sleep 0.1;
        ((abs (overcast - _ocEff)) < 0.02 && (abs (fog - _fogEff)) < 0.02)
        || (time > _t0 + 5)
    };
    
/*     // exposure follows the light, not a global constant
    private _ap = ((_timeRow select 3) + (_skyRow select 6)) max 8;
    SC_apertureNow = _ap;
    setAperture _ap;
    uiSleep 0.2;          // must be applied after mission start to take effect
 */
    private _label = format ["%1_%2", _tName, _sName];
    diag_log text format [
        "SYNTHCAP|WEATHER|%1|%2|%3|%4:%5|oc=%6|fog=%7|rain=%8|sun=%9",
        _label, _tName, _sName, _hour, _minute,
        _ocEff toFixed 2, _fogEff toFixed 2, _rain toFixed 2, sunOrMoon toFixed 3
    ];
    _label
};

// vehicle damage presets -------------------------------------------------
SC_damageStates = ["intact", "damaged", "wrecked", "smoking"];

SC_fnc_applyDamage = {
    params ["_veh", "_state"];
    switch (_state) do {
        case "intact": { };

        case "damaged": {
            // visible but recognisable — wheels, engine, fuel
            {
                _veh setHitPointDamage [_x, 0.5 + 0.5 * (call SC_fnc_rand)];
            } forEach ["HitEngine", "HitFuel", "HitLFWheel", "HitRBWheel"];
        };

        case "wrecked": {
            _veh setDamage [1, false];          // burnt out, no active effects
        };

        case "smoking": {
            _veh setDamage [1, false];
            private _smoke = "test_EmptyObjectForSmoke" createVehicle (getPosATL _veh);
            _smoke attachTo [_veh, [0, 0, 0]];
            _veh setVariable ["SC_smokeObj", _smoke];
        };
    };
    _veh setVariable ["SC_damage", _state, false];   // for the label writer
};

// vehicle orientation presets -------------------------------------------------

SC_fnc_setRoll = {
    params ["_veh", "_h", "_roll"];
    private _dir = [sin _h, cos _h, 0];
    private _up  = [(cos _h) * (sin _roll), -(sin _h) * (sin _roll), cos _roll];
    _veh setVectorDirAndUp [_dir, _up];
};

SC_orientStates = ["upright", "tipped", "onside", "inverted"];

SC_fnc_applyOrientation = {
    params ["_veh", "_state"];
    private _h = 360 * (call SC_fnc_rand);
    private _roll = switch (_state) do {
        case "upright":  { 0 };
        case "tipped":   { 25 + 35 * (call SC_fnc_rand) };
        case "onside":   { 90 * ([1, -1] call SC_fnc_pick) };
        case "inverted": { 170 + 20 * (call SC_fnc_rand) };
        default { 0 };
    };
    [_veh, _h, _roll] call SC_fnc_setRoll;

    // Model-space box doesn't rotate, so after reorientation the vertical
    // extent may be ANY of the three axes. The diagonal bounds all of them.
    private _bb = boundingBoxReal _veh;
    (_bb select 0) params ["_x0","_y0","_z0"];
    (_bb select 1) params ["_x1","_y1","_z1"];
    private _diag = sqrt (((_x1-_x0)^2) + ((_y1-_y0)^2) + ((_z1-_z0)^2));

    private _p = getPosATL _veh;
    _veh setPosATL [_p select 0, _p select 1, _diag * 0.75];
    _veh setVelocity [0, 0, 0];

    _veh setVariable ["SC_orient", _state, false];
};


// --- Variance mixes (must each sum to 1.0) --------------------------------
SC_damageMix = [["intact", 0.45], ["damaged", 0.20], ["wrecked", 0.20], ["smoking", 0.15]];
SC_orientMix = [["upright", 0.70], ["tipped", 0.12], ["onside", 0.10], ["inverted", 0.08]];

// Label definitions
SC_maxLabelRange = 2500;
SC_cullCos = cos ((SC_hfovDeg / 2) * 1.4);


SC_anchorMargin = 150;   // hard terrain border to stay out of, metres

//  random anchor points 

SC_fnc_randAnchor = {
    private _lo = SC_anchorMargin;
    private _hi = mapSize - SC_anchorMargin;
    private _p = [];
    for "_i" from 1 to 200 do {
        private _c = [[_lo, _hi] call SC_fnc_randRange, [_lo, _hi] call SC_fnc_randRange, 0];
        if (!surfaceIsWater _c && {(getTerrainHeightASL _c) > 2}) exitWith { _p = _c };
    };
    _p
};


//  max range at which the smallest vehicle can still clear SC_minBoxPx
SC_labelRangePx = (5 * SC_imgW) / (SC_minBoxPx * 2 * tan (SC_hfovDeg / 2));

// add jitter to move the camera out of center 
SC_aimJitter = 0.5; 