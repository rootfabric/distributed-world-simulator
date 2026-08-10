class_name QuaterniusLayeredEquipmentLab
extends "res://scripts/characters/lab/quaternius_equipment_lab.gd"

const LayerDomain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const SelectiveFactory = preload("res://scripts/characters/equipment/selective_garment_scene_factory.gd")
const InflationFactory = preload("res://scripts/characters/equipment/garment_vertex_inflation_scene_factory.gd")
const PresentationCatalog = preload("res://scripts/characters/equipment/wearable_presentation_catalog.gd")
const CoverageCatalogType = preload("res://scripts/characters/equipment/wearable_body_coverage_catalog.gd")
const SuppressionCoordinatorType = preload("res://scripts/characters/equipment/layered_body_suppression_coordinator.gd")
const TopologyCatalogType = preload("res://scripts/characters/equipment/wearable_body_topology_catalog.gd")
const TopologyCoordinatorType = preload("res://scripts/characters/equipment/layered_body_topology_occlusion_coordinator.gd")
const LayeredRigAdapterType = preload("res://scripts/characters/equipment/quaternius_layered_body_suppression_adapter.gd")

const MALE_PEASANT_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"
const UPPER_ITEM_ID := "lab.item.layer.upper.001"
const LOWER_ITEM_ID := "lab.item.layer.lower.001"
const FEET_ITEM_ID := "lab.item.layer.feet.001"
const UPPER_PROFILE_ID := "equipment.layer.upper.peasant"
const LOWER_PROFILE_ID := "equipment.layer.lower.peasant"
const FEET_PROFILE_ID := "equipment.layer.feet.peasant"
const UPPER_PRESENTATION_ID := "wearable.layer.upper.peasant"
const LOWER_PRESENTATION_ID := "wearable.layer.lower.peasant"
const FEET_PRESENTATION_ID := "wearable.layer.feet.peasant"

const BODY_FIT_POLICY_BODY_VISIBLE_INFLATED_OVERLAY := "BODY_VISIBLE_INFLATED_OVERLAY"
const BODY_FIT_POLICY_TOPOLOGY_OCCLUSION := "TOPOLOGY_OCCLUSION"
const CLOTHING_MATERIAL_NAMES := ["MI_Peasant"]
const REGION_TORSO_CORE := "body.region.torso.core"
const LOWER_TOPOLOGY_THRESHOLD_M := 0.045
const FEET_TOPOLOGY_THRESHOLD_M := 0.045
const TOPOLOGY_BOUNDARY_PAD_M := 0.006
const FEET_TOPOLOGY_COVERAGE_MODE := "HIGH_BOOT"
const FEET_TOPOLOGY_UPPER_Y_PAD_M := 0.012
const FEET_TOPOLOGY_UPPER_BIAS_FRACTION := 0.52

# Base profile shapes remain the accepted fix9/fallback shapes. In the default
# body-visible mode they are scaled so their maximum equals the requested CLI
# tuning value. This preserves waist/cuff/shaft bias while allowing fast tuning.
const UPPER_INFLATION_PROFILE := [
	{"t": 0.00, "offset_m": 0.0040},
	{"t": 0.30, "offset_m": 0.0070},
	{"t": 0.70, "offset_m": 0.0080},
	{"t": 1.00, "offset_m": 0.0040},
]
const LOWER_INFLATION_PROFILE := [
	{"t": 0.00, "offset_m": 0.0060},
	{"t": 0.18, "offset_m": 0.0100},
	{"t": 0.45, "offset_m": 0.0140},
	{"t": 0.72, "offset_m": 0.0120},
	{"t": 1.00, "offset_m": 0.0060},
]
const FEET_INFLATION_PROFILE := [
	{"t": 0.00, "offset_m": 0.0050},
	{"t": 0.35, "offset_m": 0.0080},
	{"t": 0.65, "offset_m": 0.0120},
	{"t": 1.00, "offset_m": 0.0160},
]

const DEFAULT_UPPER_INFLATION_MAX_M := 0.032
const DEFAULT_LOWER_INFLATION_MAX_M := 0.038
const DEFAULT_FEET_INFLATION_MAX_M := 0.036
const DEFAULT_INFLATION_SCALE := 1.0
const MAX_TUNABLE_INFLATION_M := 0.080
const MIN_INFLATION_SCALE := 0.10
const MAX_INFLATION_SCALE := 2.00

const CLI_UPPER_PREFIX := "--ch8c-upper-inflation="
const CLI_LOWER_PREFIX := "--ch8c-lower-inflation="
const CLI_FEET_PREFIX := "--ch8c-feet-inflation="
const CLI_SCALE_PREFIX := "--ch8c-inflation-scale="

@export_enum("BODY_VISIBLE_INFLATED_OVERLAY", "TOPOLOGY_OCCLUSION") var body_fit_policy: String = BODY_FIT_POLICY_BODY_VISIBLE_INFLATED_OVERLAY

var layered_rig_adapter
var body_coverage_catalog
var body_suppression_coordinator
var body_topology_catalog
var body_topology_coordinator
var layered_setup_result: Dictionary = {}
var inflation_reports: Dictionary = {}

var upper_inflation_max_m: float = DEFAULT_UPPER_INFLATION_MAX_M
var lower_inflation_max_m: float = DEFAULT_LOWER_INFLATION_MAX_M
var feet_inflation_max_m: float = DEFAULT_FEET_INFLATION_MAX_M
var inflation_scale: float = DEFAULT_INFLATION_SCALE
var cli_inflation_override_active: bool = false

func _ready() -> void:
	_apply_cli_inflation_overrides()
	super._ready()
	_setup_layered_equipment()
	_refresh_status()

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_U:
			_toggle_layer(UPPER_ITEM_ID, UPPER_PROFILE_ID)
		elif event.keycode == KEY_L:
			_toggle_layer(LOWER_ITEM_ID, LOWER_PROFILE_ID)
		elif event.keycode == KEY_K:
			_toggle_layer(FEET_ITEM_ID, FEET_PROFILE_ID)

func _apply_cli_inflation_overrides() -> void:
	for raw_argument in OS.get_cmdline_user_args():
		var argument := String(raw_argument)
		if argument.begins_with(CLI_UPPER_PREFIX):
			var parsed_upper: Dictionary = _parse_cli_float(argument, CLI_UPPER_PREFIX, 0.0, MAX_TUNABLE_INFLATION_M)
			if bool(parsed_upper.get("success", false)):
				upper_inflation_max_m = float(parsed_upper.get("value", upper_inflation_max_m))
				cli_inflation_override_active = true
		elif argument.begins_with(CLI_LOWER_PREFIX):
			var parsed_lower: Dictionary = _parse_cli_float(argument, CLI_LOWER_PREFIX, 0.0, MAX_TUNABLE_INFLATION_M)
			if bool(parsed_lower.get("success", false)):
				lower_inflation_max_m = float(parsed_lower.get("value", lower_inflation_max_m))
				cli_inflation_override_active = true
		elif argument.begins_with(CLI_FEET_PREFIX):
			var parsed_feet: Dictionary = _parse_cli_float(argument, CLI_FEET_PREFIX, 0.0, MAX_TUNABLE_INFLATION_M)
			if bool(parsed_feet.get("success", false)):
				feet_inflation_max_m = float(parsed_feet.get("value", feet_inflation_max_m))
				cli_inflation_override_active = true
		elif argument.begins_with(CLI_SCALE_PREFIX):
			var parsed_scale: Dictionary = _parse_cli_float(argument, CLI_SCALE_PREFIX, MIN_INFLATION_SCALE, MAX_INFLATION_SCALE)
			if bool(parsed_scale.get("success", false)):
				inflation_scale = float(parsed_scale.get("value", inflation_scale))
				cli_inflation_override_active = true
	if cli_inflation_override_active:
		print("CH8C CLI inflation override: upper=%.4f lower=%.4f feet=%.4f scale=%.3f" % [upper_inflation_max_m, lower_inflation_max_m, feet_inflation_max_m, inflation_scale])

func _parse_cli_float(argument: String, prefix: String, min_value: float, max_value: float) -> Dictionary:
	var raw_value: String = argument.substr(prefix.length()).strip_edges()
	if raw_value.is_empty() or not raw_value.is_valid_float():
		push_warning("CH8C ignored invalid CLI value: %s" % argument)
		return {"success": false}
	var value: float = raw_value.to_float()
	if not is_finite(value) or value < min_value or value > max_value:
		push_warning("CH8C ignored out-of-range CLI value: %s (allowed %.3f..%.3f)" % [argument, min_value, max_value])
		return {"success": false}
	return {"success": true, "value": value}

func _scaled_profile(base_profile: Array, requested_max_m: float) -> Array:
	var base_max_m: float = 0.0
	for raw_point in base_profile:
		if raw_point is Dictionary:
			base_max_m = maxf(base_max_m, float((raw_point as Dictionary).get("offset_m", 0.0)))
	if base_max_m <= 0.0:
		return base_profile.duplicate(true)
	var effective_max_m: float = minf(requested_max_m * inflation_scale, MAX_TUNABLE_INFLATION_M)
	var multiplier: float = effective_max_m / base_max_m
	var scaled: Array = []
	for raw_point in base_profile:
		var point: Dictionary = (raw_point as Dictionary).duplicate(true)
		point["offset_m"] = float(point.get("offset_m", 0.0)) * multiplier
		scaled.append(point)
	return scaled

func _setup_layered_equipment() -> void:
	var loaded = load(MALE_PEASANT_PATH)
	if not loaded is PackedScene:
		layered_setup_result = {"success": false, "code": "MALE_PEASANT_SCENE_MISSING", "details": {}}
		push_error("CH8C layered lab Male_Peasant source is unavailable")
		return
	var source_scene := loaded as PackedScene
	if body_fit_policy != BODY_FIT_POLICY_BODY_VISIBLE_INFLATED_OVERLAY and body_fit_policy != BODY_FIT_POLICY_TOPOLOGY_OCCLUSION:
		layered_setup_result = {"success": false, "code": "UNSUPPORTED_BODY_FIT_POLICY", "details": {"policy": body_fit_policy}}
		push_error("CH8C unsupported body fit policy: %s" % body_fit_policy)
		return

	layered_rig_adapter = LayeredRigAdapterType.new()
	layered_setup_result = layered_rig_adapter.bind_presenter(avatar)
	if not bool(layered_setup_result.get("success", false)):
		push_error("CH8C layered rig adapter bind failed: %s" % JSON.stringify(layered_setup_result))
		return
	body_coverage_catalog = CoverageCatalogType.new()
	body_suppression_coordinator = SuppressionCoordinatorType.new()
	layered_setup_result = body_suppression_coordinator.setup(avatar, layered_rig_adapter, body_coverage_catalog)
	if not bool(layered_setup_result.get("success", false)):
		push_error("CH8C suppression coordinator setup failed: %s" % JSON.stringify(layered_setup_result))
		return
	body_topology_catalog = TopologyCatalogType.new()
	body_topology_coordinator = TopologyCoordinatorType.new()
	layered_setup_result = body_topology_coordinator.setup(avatar, layered_rig_adapter, body_topology_catalog)
	if not bool(layered_setup_result.get("success", false)):
		push_error("CH8C topology coordinator setup failed: %s" % JSON.stringify(layered_setup_result))
		return

	var use_body_occlusion := body_fit_policy == BODY_FIT_POLICY_TOPOLOGY_OCCLUSION
	var clothing_filter: Array = [] if use_body_occlusion else CLOTHING_MATERIAL_NAMES
	var upper_profile: Array = [] if use_body_occlusion else _scaled_profile(UPPER_INFLATION_PROFILE, upper_inflation_max_m)
	var lower_profile: Array = LOWER_INFLATION_PROFILE if use_body_occlusion else _scaled_profile(LOWER_INFLATION_PROFILE, lower_inflation_max_m)
	var feet_profile: Array = FEET_INFLATION_PROFILE if use_body_occlusion else _scaled_profile(FEET_INFLATION_PROFILE, feet_inflation_max_m)
	inflation_reports.clear()
	var definitions := [
		{
			"profile": UPPER_PROFILE_ID,
			"presentation": UPPER_PRESENTATION_ID,
			"channels": ["body.torso.outer", "body.arms.outer"],
			"meshes": ["Male_Peasant_Body", "Male_Peasant_Arms"],
			"regions": [REGION_TORSO_CORE] if use_body_occlusion else [],
			"inflation_profile": upper_profile,
			"topology_threshold_m": 0.0,
			"topology_coverage_mode": "ROBUST",
			"topology_upper_y_pad_m": 0.0,
			"topology_upper_bias_fraction": 1.0,
		},
		{
			"profile": LOWER_PROFILE_ID,
			"presentation": LOWER_PRESENTATION_ID,
			"channels": ["body.legs.outer"],
			"meshes": ["Male_Peasant_Legs"],
			"regions": [],
			"inflation_profile": lower_profile,
			"topology_threshold_m": LOWER_TOPOLOGY_THRESHOLD_M if use_body_occlusion else 0.0,
			"topology_coverage_mode": "ROBUST",
			"topology_upper_y_pad_m": 0.0,
			"topology_upper_bias_fraction": 1.0,
		},
		{
			"profile": FEET_PROFILE_ID,
			"presentation": FEET_PRESENTATION_ID,
			"channels": ["body.feet"],
			"meshes": ["Male_Peasant_Feet"],
			"regions": [],
			"inflation_profile": feet_profile,
			"topology_threshold_m": FEET_TOPOLOGY_THRESHOLD_M if use_body_occlusion else 0.0,
			"topology_coverage_mode": FEET_TOPOLOGY_COVERAGE_MODE,
			"topology_upper_y_pad_m": FEET_TOPOLOGY_UPPER_Y_PAD_M,
			"topology_upper_bias_fraction": FEET_TOPOLOGY_UPPER_BIAS_FRACTION,
		}
	]

	for definition in definitions:
		var profile := LayerDomain.Profile.new(String(definition["profile"]), String(definition["presentation"]), "body.root", definition["channels"], [], [], ["equipment.clothing"])
		layered_setup_result = equipment_source.register_profile(profile)
		if not bool(layered_setup_result.get("success", false)):
			push_error("CH8C layered profile registration failed: %s" % JSON.stringify(layered_setup_result))
			return
		var selected: Dictionary = SelectiveFactory.create(source_scene, definition["meshes"])
		if not bool(selected.get("success", false)):
			layered_setup_result = selected
			push_error("CH8C selective scene creation failed: %s" % JSON.stringify(selected))
			return
		var selected_scene = selected.get("details", {}).get("scene")
		if not selected_scene is PackedScene:
			layered_setup_result = {"success": false, "code": "SELECTED_SCENE_NOT_PACKED", "details": {}}
			return
		var presentation_scene := selected_scene as PackedScene
		var inflation_profile: Array = definition.get("inflation_profile", [])
		if not inflation_profile.is_empty():
			var inflation_result: Dictionary = InflationFactory.create(presentation_scene, inflation_profile, clothing_filter)
			if not bool(inflation_result.get("success", false)):
				layered_setup_result = inflation_result
				push_error("CH8C garment vertex inflation failed: %s" % JSON.stringify(inflation_result))
				return
			var inflated_scene = inflation_result.get("details", {}).get("scene")
			if not inflated_scene is PackedScene:
				layered_setup_result = {"success": false, "code": "INFLATED_SCENE_NOT_PACKED", "details": {}}
				return
			presentation_scene = inflated_scene as PackedScene
			inflation_reports[String(definition["presentation"])] = inflation_result.get("details", {}).duplicate(true)

		layered_setup_result = wearable_catalog.register_scene(String(definition["presentation"]), equipment_rig_adapter.rig_profile_id, PresentationCatalog.STRATEGY_SKINNED_GARMENT, presentation_scene)
		if not bool(layered_setup_result.get("success", false)):
			push_error("CH8C layered presentation registration failed: %s" % JSON.stringify(layered_setup_result))
			return
		layered_setup_result = body_coverage_catalog.register_coverage(String(definition["presentation"]), layered_rig_adapter.rig_profile_id, definition["regions"])
		if not bool(layered_setup_result.get("success", false)):
			push_error("CH8C coverage registration failed: %s" % JSON.stringify(layered_setup_result))
			return
		var topology_threshold_m := float(definition.get("topology_threshold_m", 0.0))
		if topology_threshold_m > 0.0:
			layered_setup_result = body_topology_catalog.register_surface_occlusion(String(definition["presentation"]), layered_rig_adapter.rig_profile_id, presentation_scene, topology_threshold_m, TOPOLOGY_BOUNDARY_PAD_M, String(definition.get("topology_coverage_mode", "ROBUST")), float(definition.get("topology_upper_y_pad_m", 0.0)), float(definition.get("topology_upper_bias_fraction", 1.0)))
			if not bool(layered_setup_result.get("success", false)):
				push_error("CH8C topology registration failed: %s" % JSON.stringify(layered_setup_result))
				return

	layered_setup_result = body_suppression_coordinator.apply_snapshot(equipment_source.get_snapshot())
	if not bool(layered_setup_result.get("success", false)):
		return
	layered_setup_result = body_topology_coordinator.apply_snapshot(equipment_source.get_snapshot())

func _toggle_layer(item_id: String, profile_id: String) -> Dictionary:
	if body_suppression_coordinator == null or body_topology_coordinator == null:
		return {"success": false, "code": "CH8C_COORDINATOR_NOT_READY", "details": {}}
	var enabled: bool = not bool(equipment_source.has_item(item_id))
	var mutation_result: Dictionary = _set_item_equipped(item_id, profile_id, enabled)
	if not bool(mutation_result.get("success", false)):
		return mutation_result
	var snapshot = equipment_source.get_snapshot()
	var suppression_result: Dictionary = body_suppression_coordinator.apply_snapshot(snapshot)
	if not bool(suppression_result.get("success", false)):
		layered_setup_result = suppression_result
		push_error("CH8C layered suppression apply failed: %s" % JSON.stringify(suppression_result))
		_refresh_status()
		return suppression_result
	var topology_result: Dictionary = body_topology_coordinator.apply_snapshot(snapshot)
	if not bool(topology_result.get("success", false)):
		layered_setup_result = topology_result
		push_error("CH8C topology occlusion apply failed: %s" % JSON.stringify(topology_result))
		_refresh_status()
		return topology_result
	layered_setup_result = topology_result
	_refresh_equipment_view_policy()
	_refresh_status()
	return mutation_result

func _refresh_status() -> void:
	super._refresh_status()
	if status_label == null:
		return
	var upper_state := "ON" if equipment_source != null and equipment_source.has_item(UPPER_ITEM_ID) else "OFF"
	var lower_state := "ON" if equipment_source != null and equipment_source.has_item(LOWER_ITEM_ID) else "OFF"
	var feet_state := "ON" if equipment_source != null and equipment_source.has_item(FEET_ITEM_ID) else "OFF"
	var regions: Array = []
	if body_suppression_coordinator != null:
		regions = body_suppression_coordinator.create_report().get("active_regions", [])
	var topology_removed := 0
	var topology_active: Array = []
	if body_topology_coordinator != null:
		var topology_report: Dictionary = body_topology_coordinator.create_report()
		topology_removed = int(topology_report.get("removed_triangles", 0))
		topology_active = topology_report.get("active_presentations", [])
	var upper_inflation_max := 0.0
	var lower_inflation_max := 0.0
	var feet_inflation_max := 0.0
	if inflation_reports.has(UPPER_PRESENTATION_ID):
		upper_inflation_max = float((inflation_reports[UPPER_PRESENTATION_ID] as Dictionary).get("profile_max_offset_m", 0.0))
	if inflation_reports.has(LOWER_PRESENTATION_ID):
		lower_inflation_max = float((inflation_reports[LOWER_PRESENTATION_ID] as Dictionary).get("profile_max_offset_m", 0.0))
	if inflation_reports.has(FEET_PRESENTATION_ID):
		feet_inflation_max = float((inflation_reports[FEET_PRESENTATION_ID] as Dictionary).get("profile_max_offset_m", 0.0))
	var layered_status := (
		"\n\nCH8C — Layered Garments\n"
		+ "U — upper | L — lower | K — feet\n"
		+ "fit policy: %s\n"
		+ "inflation input: upper %.3f m | lower %.3f m | feet %.3f m | scale %.2f%s\n"
		+ "upper: %s | lower: %s | feet: %s\n"
		+ "material suppression: %s\n"
		+ "topology: %s | removed triangles: %d\n"
		+ "vertex inflation effective max: upper %.3f m | lower %.3f m | feet %.3f m"
	)
	var cli_marker := " | CLI" if cli_inflation_override_active else " | defaults"
	status_label.text += layered_status % [body_fit_policy, upper_inflation_max_m, lower_inflation_max_m, feet_inflation_max_m, inflation_scale, cli_marker, upper_state, lower_state, feet_state, ", ".join(regions), ", ".join(topology_active), topology_removed, upper_inflation_max, lower_inflation_max, feet_inflation_max]
