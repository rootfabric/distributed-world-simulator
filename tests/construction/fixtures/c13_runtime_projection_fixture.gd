extends RefCounted

const RequestScript = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const C10Fixture = preload("res://tests/construction/fixtures/c10_parametric_members_fixture.gd")
const C11Fixture = preload("res://tests/construction/fixtures/c11_local_geometry_editing_fixture.gd")
const GeometryCompilerScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_compiler.gd")
const GeometryPlannerScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_transaction_planner.gd")
const C6Fixture = preload("res://tests/construction/fixtures/c6_mobile_rover_fixture.gd")
const MobileCompilerScript = preload("res://scripts/construction/mobile/construction_mobile_compiler.gd")
const C7Fixture = preload("res://tests/construction/fixtures/c7_spatial_house_fixture.gd")
const SpatialCompilerScript = preload("res://scripts/construction/spatial/construction_spatial_compiler.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")

static func beam_request(key: String = "beam-a", revision: int = 0, length_m: float = 4.0, origin: Array = [0.0, 0.0, 0.0]) -> Dictionary:
	var graph := C11Fixture.graph(key, length_m)
	var snapshot: Dictionary = graph["snapshot"]
	if revision != int(snapshot["state_revision"]): snapshot = SnapshotScript.create(String(snapshot["construct_id"]), String(snapshot["root_item_instance_id"]), revision, String(snapshot["build_state"]), snapshot["parts"], snapshot["bonds"], snapshot["compiled_facets"])
	return RequestScript.create(snapshot, [graph["projection"]], {}, {}, origin)

static func edited_beam_request(key: String = "beam-a", origin: Array = [0.0, 0.0, 0.0]) -> Dictionary:
	var graph := C11Fixture.graph(key, 4.0)
	var request := C11Fixture.request(key, graph, [C11Fixture.insert_mid(0, "geometry-point/corner", "geometry-point/start", [2.0, 0.0, 0.0]), C11Fixture.move_end(1, [2.0, 3.0, 0.0])], [C11Fixture.min_segment(0.25), C11Fixture.orthogonal()], 1)
	var compiled := GeometryCompilerScript.compile(graph["instance"], C10Fixture.beam_definition(), C10Fixture.materials(), request)
	var planned := GeometryPlannerScript.plan("plan/c13/geometry/%s" % key, request, graph["projection"], graph["snapshot"], compiled)
	return RequestScript.create(planned["after_snapshot"], [planned["after_projection"]], {}, {}, origin)

static func two_beam_request(key: String = "pair-a", changed_second: bool = false) -> Dictionary:
	var first_graph := C11Fixture.graph("%s-first" % key, 4.0)
	var second_graph := C11Fixture.graph("%s-second" % key, 3.0 if changed_second else 2.0)
	var construct_id := "construct/runtime/pair/%s" % key
	var root_id := "item/runtime/pair/%s/root" % key
	var first_part: Dictionary = first_graph["snapshot"]["parts"][0].duplicate(true)
	var second_part: Dictionary = second_graph["snapshot"]["parts"][0].duplicate(true)
	first_part["part_id"] = "part/runtime/pair/%s/first" % key; first_part["local_position_m"] = [-2.0, 0.0, 0.0]
	second_part["part_id"] = "part/runtime/pair/%s/second" % key; second_part["local_position_m"] = [2.0, 0.0, 0.0]
	var revision := 1 if changed_second else 0
	var snapshot := SnapshotScript.create(construct_id, root_id, revision, "OPERATIONAL", [first_part, second_part], [], {"operational": true, "capabilities": []})
	return RequestScript.create(snapshot, [first_graph["projection"], second_graph["projection"]])

static func rover_request(key: String = "rover-a", state: String = "healthy", origin: Array = [0.0, 0.0, 0.0]) -> Dictionary:
	var snapshot: Dictionary
	match state:
		"immobile": snapshot = C6Fixture.three_wheels_lost(key, 2)
		"degraded": snapshot = C6Fixture.one_wheel_lost(key, 1)
		_: snapshot = C6Fixture.rover_snapshot(key)
	var compiled := MobileCompilerScript.compile(snapshot)
	return RequestScript.create(snapshot, [], compiled["profile"], {}, origin)

static func house_request(key: String = "house-a", door_open: bool = false, origin: Array = [0.0, 0.0, 0.0]) -> Dictionary:
	var snapshot := C7Fixture.door_open(key, 1) if door_open else C7Fixture.house_snapshot(key)
	var compiled := SpatialCompilerScript.compile(snapshot)
	return RequestScript.create(snapshot, [], {}, compiled["profile"], origin)

static func split_world_before(key: String = "split-a") -> Array:
	return [RequestScript.create(_split_source_snapshot(key, false), [])]

static func split_world_after(key: String = "split-a") -> Array:
	return [RequestScript.create(_split_source_snapshot(key, true), []), RequestScript.create(_split_child_snapshot(key), [], {}, {}, [3.0, 0.0, 0.0])]

static func _split_source_snapshot(key: String, after_split: bool) -> Dictionary:
	var anchor := PartScript.create("part/runtime/split/%s/anchor" % key, "item/runtime/split/%s/anchor" % key, "FRAME", "anchor", 20.0, [0.0, 0.0, 0.0], {"condition": "INTACT"})
	var arm := PartScript.create("part/runtime/split/%s/arm" % key, "item/runtime/split/%s/arm" % key, "BEAM", "member", 10.0, [1.5, 0.0, 0.0], {"condition": "INTACT", "geometry": {"bounding_box_m": [3.0, 0.2, 0.2]}})
	var parts: Array = [anchor] if after_split else [anchor, arm]
	var bonds: Array = [] if after_split else [BondScript.create("bond/runtime/split/%s/arm" % key, String(anchor["part_id"]), String(arm["part_id"]), "MECHANICAL", 1000.0, "INTACT", {})]
	return SnapshotScript.create("construct/runtime/split/%s/source" % key, "item/runtime/split/%s/source-root" % key, 1 if after_split else 0, "OPERATIONAL", parts, bonds, {"operational": true, "split": after_split})

static func _split_child_snapshot(key: String) -> Dictionary:
	var arm := PartScript.create("part/runtime/split/%s/arm" % key, "item/runtime/split/%s/arm" % key, "BEAM", "member", 10.0, [0.0, 0.0, 0.0], {"condition": "INTACT", "geometry": {"bounding_box_m": [3.0, 0.2, 0.2]}})
	return SnapshotScript.create("construct/runtime/split/%s/child" % key, "item/runtime/split/%s/child-root" % key, 0, "OPERATIONAL", [arm], [], {"operational": true, "split_parent": "construct/runtime/split/%s/source" % key})
