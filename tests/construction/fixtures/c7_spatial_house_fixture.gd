extends RefCounted

const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const SectionScript = preload("res://scripts/construction/spatial/construction_spatial_section_definition.gd")
const OpeningScript = preload("res://scripts/construction/spatial/construction_spatial_opening_definition.gd")
const SpaceScript = preload("res://scripts/construction/spatial/construction_spatial_space_definition.gd")
const UtilityScript = preload("res://scripts/construction/spatial/construction_spatial_utility_definition.gd")

static func house_snapshot(instance_key: String = "house-a", part_conditions: Dictionary = {}, access_states: Dictionary = {}, bond_states: Dictionary = {}, revision: int = 0, build_state: String = "") -> Dictionary:
	var resolved_build_state := build_state
	if resolved_build_state.is_empty():
		resolved_build_state = "DAMAGED" if _has_damage(part_conditions, bond_states) else "OPERATIONAL"
	return SnapshotScript.create(
		"construct/spatial/%s" % instance_key,
		"item/spatial/%s/root" % instance_key,
		revision,
		resolved_build_state,
		_parts(instance_key, part_conditions, access_states),
		_bonds(instance_key, bond_states),
		{
			"operational": resolved_build_state == "OPERATIONAL",
			"capabilities": [],
			"spatial_sections": _sections(instance_key),
			"spatial_openings": _openings(instance_key),
			"spatial_spaces": _spaces(),
			"spatial_utilities": _utilities(instance_key),
			"spatial_construct_kind": "SMALL_HOUSE",
		}
	)

static func door_open(instance_key: String = "house-a", revision: int = 1) -> Dictionary:
	return house_snapshot(instance_key, {}, {"door": "OPEN"}, {}, revision, "OPERATIONAL")
static func wall_lost(instance_key: String = "house-a", revision: int = 1) -> Dictionary:
	return house_snapshot(instance_key, {"wall-east": "DESTROYED"}, {}, {}, revision, "DAMAGED")
static func window_lost(instance_key: String = "house-a", revision: int = 1) -> Dictionary:
	return house_snapshot(instance_key, {"window": "DESTROYED"}, {}, {}, revision, "DAMAGED")
static func power_lost(instance_key: String = "house-a", revision: int = 1) -> Dictionary:
	return house_snapshot(instance_key, {"power-panel": "DESTROYED"}, {}, {}, revision, "DAMAGED")
static func data_lost(instance_key: String = "house-a", revision: int = 1) -> Dictionary:
	return house_snapshot(instance_key, {"data-router": "DESTROYED"}, {}, {}, revision, "DAMAGED")
static func roof_degraded(instance_key: String = "house-a", revision: int = 1) -> Dictionary:
	return house_snapshot(instance_key, {"roof": "DEGRADED"}, {}, {}, revision, "DAMAGED")
static func door_bond_broken(instance_key: String = "house-a", revision: int = 1) -> Dictionary:
	return house_snapshot(instance_key, {}, {}, {"door": "BROKEN"}, revision, "DAMAGED")
static func repaired(instance_key: String = "house-a", revision: int = 2) -> Dictionary:
	return house_snapshot(instance_key, {}, {}, {}, revision, "OPERATIONAL")
static func partial(instance_key: String = "house-a", revision: int = 0) -> Dictionary:
	return house_snapshot(instance_key, {}, {}, {}, revision, "PARTIAL")

static func _parts(instance_key: String, conditions: Dictionary, access_states: Dictionary) -> Array:
	var specs: Array = [
		["data-router", "DATA_ROUTER", "utility", 4.0, [0.8, 1.2, -1.4]],
		["door", "DOOR_PANEL", "closure", 35.0, [0.0, 1.0, 2.0]],
		["door-frame", "DOOR_FRAME", "opening-frame", 40.0, [0.0, 1.0, 2.0]],
		["floor", "FLOOR_PANEL", "floor", 280.0, [0.0, 0.1, 0.0]],
		["foundation", "FOUNDATION", "foundation", 900.0, [0.0, -0.4, 0.0]],
		["power-panel", "POWER_PANEL", "utility", 18.0, [-0.8, 1.1, -1.4]],
		["roof", "ROOF_PANEL", "roof", 220.0, [0.0, 2.6, 0.0]],
		["wall-east", "WALL_PANEL", "wall", 180.0, [2.0, 1.3, 0.0]],
		["wall-north", "WALL_PANEL", "wall", 180.0, [0.0, 1.3, -2.0]],
		["wall-south", "WALL_PANEL", "wall", 145.0, [0.0, 1.3, 2.0]],
		["wall-west", "WALL_PANEL", "wall", 180.0, [-2.0, 1.3, 0.0]],
		["window", "WINDOW_PANEL", "closure", 18.0, [2.0, 1.4, 0.0]],
		["window-frame", "WINDOW_FRAME", "opening-frame", 22.0, [2.0, 1.4, 0.0]],
	]
	var result: Array = []
	for spec in specs:
		var key := String(spec[0])
		var metadata := {"condition": String(conditions.get(key, "INTACT")), "spatial_component": true}
		if key in ["door", "window"]:
			metadata["access_state"] = String(access_states.get(key, "CLOSED"))
		result.append(PartScript.create("part/spatial/%s/%s" % [instance_key, key], "item/spatial/%s/%s" % [instance_key, key], String(spec[1]), String(spec[2]), float(spec[3]), Array(spec[4]), metadata))
	return result

static func _bonds(instance_key: String, states: Dictionary) -> Array:
	var keys := ["data-router", "door", "door-frame", "floor", "power-panel", "roof", "wall-east", "wall-north", "wall-south", "wall-west", "window", "window-frame"]
	var result: Array = []
	for key in keys:
		result.append(BondScript.create("bond/spatial/%s/%s" % [instance_key, key], "part/spatial/%s/foundation" % instance_key, "part/spatial/%s/%s" % [instance_key, key], "STRUCTURAL", 25000.0, String(states.get(key, "INTACT")), {"spatial_component": key}))
	return result

static func _sections(instance_key: String) -> Array:
	var p := "part/spatial/%s/" % instance_key
	var b := "bond/spatial/%s/" % instance_key
	return [
		SectionScript.create("spatial-section/door-frame", "DOOR_FRAME", [p + "door-frame"], [b + "door-frame"]),
		SectionScript.create("spatial-section/floor", "FLOOR", [p + "floor"], [b + "floor"], 1, {"area_m2": 16.0}),
		SectionScript.create("spatial-section/foundation", "FOUNDATION", [p + "foundation"], [], 1, {"load_capacity_kg": 10000.0}),
		SectionScript.create("spatial-section/roof", "ROOF", [p + "roof"], [b + "roof"], 1, {"weather_resistance": 1.0}),
		SectionScript.create("spatial-section/wall-east", "WALL", [p + "wall-east"], [b + "wall-east"]),
		SectionScript.create("spatial-section/wall-north", "WALL", [p + "wall-north"], [b + "wall-north"]),
		SectionScript.create("spatial-section/wall-south", "WALL", [p + "wall-south"], [b + "wall-south"]),
		SectionScript.create("spatial-section/wall-west", "WALL", [p + "wall-west"], [b + "wall-west"]),
		SectionScript.create("spatial-section/window-frame", "WINDOW_FRAME", [p + "window-frame"], [b + "window-frame"]),
	]

static func _openings(instance_key: String) -> Array:
	var p := "part/spatial/%s/" % instance_key
	var b := "bond/spatial/%s/" % instance_key
	return [
		OpeningScript.create("spatial-opening/main-door", "DOOR", "space/house/main", "space/exterior", "spatial-section/door-frame", p + "door", [b + "door"], true, {"width_m": 0.9, "height_m": 2.0}),
		OpeningScript.create("spatial-opening/main-window", "WINDOW", "space/house/main", "space/exterior", "spatial-section/window-frame", p + "window", [b + "window"], true, {"width_m": 1.2, "height_m": 1.0}),
	]

static func _spaces() -> Array:
	return [SpaceScript.create("space/house/main", ["spatial-section/floor", "spatial-section/roof", "spatial-section/wall-east", "spatial-section/wall-north", "spatial-section/wall-south", "spatial-section/wall-west"], ["spatial-opening/main-door", "spatial-opening/main-window"], ["spatial-utility/data", "spatial-utility/power"], 6, {"volume_m3": 40.0, "occupancy_limit": 4, "space_kind": "WORKROOM"})]

static func _utilities(instance_key: String) -> Array:
	var p := "part/spatial/%s/" % instance_key
	var b := "bond/spatial/%s/" % instance_key
	return [
		UtilityScript.create("spatial-utility/data", "DATA", [p + "data-router"], [b + "data-router"], ["spatial-utility/power"], 1, {"bandwidth_mbps": 1000.0}),
		UtilityScript.create("spatial-utility/power", "POWER", [p + "power-panel"], [b + "power-panel"], [], 1, {"capacity_kw": 12.0, "lighting": true}),
	]

static func _has_damage(part_conditions: Dictionary, bond_states: Dictionary) -> bool:
	for value in part_conditions.values():
		if String(value) != "INTACT": return true
	for value in bond_states.values():
		if String(value) != "INTACT": return true
	return false
