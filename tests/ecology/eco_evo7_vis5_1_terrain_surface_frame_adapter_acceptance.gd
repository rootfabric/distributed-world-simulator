extends SceneTree

## ECO.EVO7 VIS5.1 — Terrain Surface Frame Adapter acceptance.
##
## Uses a deterministic fake ProceduralEarth-like source so the focused gate
## proves frame math and authority separation without mutating terrain/ecology.

const Adapter = preload("res://scripts/labs/ecology/eco_evo7_vis5_1_terrain_surface_frame_adapter.gd")

var assertions := 0
var failures: Array[String] = []


class FakeEarthWorld extends RefCounted:
	var radius_m := 1000.0
	var slope_gain_m := 0.0
	var state_call_count := 0
	var point_call_count := 0

	func _init(slope_gain_value: float = 0.0) -> void:
		slope_gain_m = slope_gain_value

	func get_planet_radius() -> float:
		return radius_m

	func get_surface_state(direction: Vector3, lod_level: int = 0) -> Dictionary:
		state_call_count += 1
		var d := direction.normalized()
		return {
			"elevation_m": slope_gain_m * d.x,
			"grass_density": 0.73,
			"rock_density": 0.21,
			"tree_density": 0.44,
			"water_kind": 0,
			"snow_mask": 0.0,
			"lod_level": lod_level,
		}

	func get_surface_point(direction: Vector3) -> Vector3:
		point_call_count += 1
		var d := direction.normalized()
		var elevation := slope_gain_m * d.x
		return d * (radius_m + elevation)


func _init() -> void:
	_m1_invalid_inputs_fail_closed()
	_m2_flat_surface_frame()
	_m3_sloped_surface_frame()
	_m4_determinism_and_seal()
	_m5_authority_and_source_boundary()
	_finish()


func _m1_invalid_inputs_fail_closed() -> void:
	var earth := FakeEarthWorld.new()
	_check(Adapter.build(null, Vector3.UP).is_empty(), "null earth rejected")
	_check(Adapter.build(earth, Vector3.ZERO).is_empty(), "zero direction rejected")
	_check(Adapter.build(earth, Vector3(INF, 0.0, 0.0)).is_empty(), "non-finite direction rejected")
	_check(Adapter.build(earth, Vector3.UP, 0.0).is_empty(), "zero sample distance rejected")
	_check(Adapter.build(earth, Vector3.UP, 1000.0).is_empty(), "oversized sample distance rejected")
	_check(Adapter.build(earth, Vector3.UP, 2.0, -1).is_empty(), "negative LOD rejected")


func _m2_flat_surface_frame() -> void:
	var earth := FakeEarthWorld.new(0.0)
	var frame := Adapter.build(earth, Vector3.UP, 2.0, 0)
	_check(not frame.is_empty(), "flat surface frame builds")
	if frame.is_empty():
		return
	_check(Adapter.validate(frame), "flat surface frame validates")
	_check(String(frame.get("schema", "")) == Adapter.SCHEMA, "frame schema exact")
	_check(String(frame.get("version", "")) == Adapter.VERSION, "frame version exact")
	_check(String(frame.get("revision", "")) == Adapter.REVISION, "frame revision exact")
	_check(bool(frame.get("presentation_only", false)), "frame is presentation-only")
	_check(bool(frame.get("surface_point_is_canonical", false)), "surface point explicitly canonical")
	_check(bool(frame.get("terrain_normal_is_derived_presentation", false)), "terrain normal explicitly derived")
	_check(not bool(frame.get("canonical_ecology_position_changed", true)), "adapter does not change canonical ecology position")
	_check(not bool(frame.get("growth_graph_changed", true)), "adapter does not change GrowthGraph")

	var canonical_direction := Vector3(frame.get("canonical_direction", Vector3.ZERO))
	var surface_point := Vector3(frame.get("surface_point_world", Vector3.ZERO))
	var radial_up := Vector3(frame.get("radial_up", Vector3.ZERO))
	var terrain_normal := Vector3(frame.get("terrain_normal", Vector3.ZERO))
	var radial_basis := Basis(frame.get("radial_basis", Basis.IDENTITY))
	var terrain_basis := Basis(frame.get("terrain_basis", Basis.IDENTITY))
	_check(canonical_direction.is_equal_approx(Vector3.UP), "canonical direction preserved")
	_check(surface_point.is_equal_approx(earth.get_surface_point(Vector3.UP)), "surface point matches exact terrain source")
	_check(radial_up.is_equal_approx(Vector3.UP), "radial up exact")
	_check(terrain_normal.dot(Vector3.UP) > 0.999999, "flat terrain normal matches radial up")
	_check(float(frame.get("slope_deg", -1.0)) < 0.001, "flat terrain slope approximately zero")
	_check(radial_basis.y.dot(radial_up) > 0.999999, "radial basis Y equals radial up")
	_check(terrain_basis.y.dot(terrain_normal) > 0.999999, "terrain basis Y equals terrain normal")
	_check(radial_basis.determinant() > 0.999999, "radial basis right-handed")
	_check(terrain_basis.determinant() > 0.999999, "terrain basis right-handed")
	_check(absf(radial_basis.x.dot(radial_basis.y)) < 0.000001, "radial basis X/Y orthogonal")
	_check(absf(terrain_basis.x.dot(terrain_basis.y)) < 0.000001, "terrain basis X/Y orthogonal")

	var state_value = frame.get("surface_state")
	_check(state_value is Dictionary, "surface state passed through")
	if state_value is Dictionary:
		var state: Dictionary = state_value
		_check(is_equal_approx(float(state.get("grass_density", -1.0)), 0.73), "ground-cover density remains source data")
		_check(int(state.get("lod_level", -1)) == 0, "surface state uses requested LOD")
	_check(is_equal_approx(float(frame.get("elevation_m", NAN)), 0.0), "flat elevation exact")
	_check(String(frame.get("frame_hash", "")).length() == 64, "frame seal is SHA-256")
	_check(earth.state_call_count >= 1, "adapter samples surface state")
	_check(earth.point_call_count >= 5, "adapter samples center plus four geometric neighbors")


func _m3_sloped_surface_frame() -> void:
	var earth := FakeEarthWorld.new(100.0)
	var frame := Adapter.build(earth, Vector3.UP, 2.0, 0)
	_check(not frame.is_empty(), "sloped surface frame builds")
	if frame.is_empty():
		return
	_check(Adapter.validate(frame), "sloped surface frame validates")
	var radial_up := Vector3(frame.get("radial_up", Vector3.ZERO))
	var terrain_normal := Vector3(frame.get("terrain_normal", Vector3.ZERO))
	var slope_deg := float(frame.get("slope_deg", 0.0))
	_check(terrain_normal.dot(radial_up) < 0.999, "sloped terrain normal differs from radial up")
	_check(terrain_normal.dot(radial_up) > 0.95, "sloped terrain normal still points outward")
	_check(slope_deg > 3.0, "derived slope is materially non-zero")
	_check(slope_deg < 12.0, "derived slope remains physically bounded for fixture")

	var radial_basis := Basis(frame.get("radial_basis", Basis.IDENTITY))
	var terrain_basis := Basis(frame.get("terrain_basis", Basis.IDENTITY))
	_check(radial_basis.y.dot(radial_up) > 0.999999, "macro-plant radial frame stays radial on slope")
	_check(terrain_basis.y.dot(terrain_normal) > 0.999999, "ground-cover frame follows terrain normal on slope")
	_check(radial_basis.y.dot(terrain_basis.y) < 0.999, "radial and terrain frames remain explicitly distinct")
	_check(Vector3(frame.get("surface_point_world", Vector3.ZERO)).is_equal_approx(earth.get_surface_point(Vector3.UP)), "slope frame preserves canonical center point")


func _m4_determinism_and_seal() -> void:
	var earth_a := FakeEarthWorld.new(80.0)
	var first := Adapter.build(earth_a, Vector3(0.2, 0.97, -0.1).normalized(), 3.0, 1)
	var second := Adapter.build(earth_a, Vector3(0.2, 0.97, -0.1).normalized(), 3.0, 1)
	_check(not first.is_empty() and not second.is_empty(), "determinism fixtures build")
	if first.is_empty() or second.is_empty():
		return
	_check(String(first.get("frame_hash", "")) == String(second.get("frame_hash", "")), "same source and sampling produce same frame hash")
	_check(Vector3(first.get("terrain_normal", Vector3.ZERO)).is_equal_approx(Vector3(second.get("terrain_normal", Vector3.ZERO))), "same source produces same terrain normal")
	_check(is_equal_approx(float(first.get("slope_deg", -1.0)), float(second.get("slope_deg", -2.0))), "same source produces same slope")
	_check(int(Dictionary(first.get("surface_state", {})).get("lod_level", -1)) == 1, "requested LOD reaches surface state")

	var changed_distance := Adapter.build(earth_a, Vector3(0.2, 0.97, -0.1).normalized(), 4.0, 1)
	_check(not changed_distance.is_empty(), "alternate sampling distance builds")
	if not changed_distance.is_empty():
		_check(String(first.get("frame_hash", "")) != String(changed_distance.get("frame_hash", "")), "sampling distance participates in frame identity")

	var tampered := first.duplicate(true)
	tampered["slope_deg"] = float(tampered["slope_deg"]) + 1.0
	_check(not Adapter.validate(tampered), "tampered slope rejected")

	tampered = first.duplicate(true)
	tampered["canonical_ecology_position_changed"] = true
	_check(not Adapter.validate(tampered), "canonical position mutation claim rejected")

	tampered = first.duplicate(true)
	tampered["frame_hash"] = "0".repeat(64)
	_check(not Adapter.validate(tampered), "tampered seal rejected")


func _m5_authority_and_source_boundary() -> void:
	var adapter_source := _source("res://scripts/labs/ecology/eco_evo7_vis5_1_terrain_surface_frame_adapter.gd")
	var earth_source := _source("res://scripts/world/earth/procedural_earth_world.gd")
	var vis4_source := _source("res://scripts/labs/ecology/eco_evo7_vis4_4_play0_ph5_renderer.gd")

	_check(adapter_source.contains("PRESENTATION_ONLY := true"), "adapter source declares presentation-only authority")
	_check(adapter_source.contains("get_surface_point"), "adapter consumes canonical terrain point API")
	_check(adapter_source.contains("get_surface_state"), "adapter consumes canonical terrain state API")
	_check(adapter_source.contains("get_planet_radius"), "adapter derives angular sampling from canonical planet radius")
	_check(not adapter_source.contains("DescriptorV2"), "adapter does not depend on ecology Descriptor V2")
	_check(not adapter_source.contains("GrowthGraph"), "adapter does not rebuild GrowthGraph")
	_check(not adapter_source.contains("mutation"), "adapter owns no mutation path")
	_check(not adapter_source.contains("population"), "adapter owns no population path")
	_check(not adapter_source.contains("generation_write"), "adapter owns no generation write path")

	_check(earth_source.contains("func get_surface_point(direction_value: Vector3) -> Vector3:"), "ProceduralEarthWorld remains canonical surface-point owner")
	_check(earth_source.contains("func get_surface_state(direction: Vector3, lod_level: int = 0) -> Dictionary:"), "ProceduralEarthWorld remains surface-state owner")
	_check(vis4_source.contains("var base_world: Vector3 = earth_world.get_surface_point(up)"), "VIS4 macro-plant canonical placement remains unchanged")
	_check(not vis4_source.contains("eco_evo7_vis5_1_terrain_surface_frame_adapter.gd"), "VIS5.1 does not silently change accepted VIS4 macro-plant placement")


func _source(path: String) -> String:
	var source := FileAccess.get_file_as_string(path)
	_check(not source.is_empty(), "source exists: %s" % path)
	return source


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 VIS5.1 Terrain Surface Frame Adapter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 VIS5.1 FAIL: %s" % failure)
	print(
		"ECO.EVO7 VIS5.1 Terrain Surface Frame Adapter: FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)
