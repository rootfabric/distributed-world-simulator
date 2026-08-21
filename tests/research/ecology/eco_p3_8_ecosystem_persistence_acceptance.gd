extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const EnvGradient = preload("res://scripts/research/ecology/plant_environmental_gradient_v1.gd")
const Seasonal = preload("res://scripts/research/ecology/plant_seasonal_world_v1.gd")
const Disturbance = preload("res://scripts/research/ecology/plant_disturbance_succession_v1.gd")
const Coexistence = preload("res://scripts/research/ecology/plant_multi_niche_coexistence_v1.gd")
const Persistence = preload("res://scripts/research/ecology/plant_ecosystem_persistence_v1.gd")

const TOTAL_STEPS := 12
const CUT_STEPS := 5

var assertions := 0
var failed := false

func _init() -> void:
	var mode := OS.get_environment("ECO_P3_8_MODE")
	if mode == "write_cut":
		_run_write_cut()
		return
	if mode == "resume_cut":
		_run_resume_cut()
		return
	_run_full()

func _run_full() -> void:
	var initial_result := _initial_p3_7_result()
	_check(bool(Coexistence.validate_result(initial_result).get("success", false)), "P3.7 source validates")
	var source_before := initial_result.duplicate(true)
	var state := Persistence.initialize(initial_result)
	_check(bool(Persistence.validate_state(state).get("success", false)), "P3.8 initial state validates")
	_check(initial_result == source_before, "P3.8 initialize does not mutate P3.7 source")
	_check(int(state["generation"]) == 0, "initial generation is zero")
	_check(String(state["root_p3_7_result_hash"]) == String(initial_result["result_hash"]), "root P3.7 result hash pinned")
	_check(String(state["current_p3_7_result_hash"]) == String(initial_result["result_hash"]), "current P3.7 result hash pinned")
	_check(String(state["parent_p3_7_candidate_aggregate"]) == Persistence.PARENT_P3_7_CANDIDATE_AGGREGATE, "P3.7 candidate aggregate pinned")

	var bytes_a := Persistence.serialize_state(state)
	var bytes_b := Persistence.serialize_state(state)
	_check(not bytes_a.is_empty(), "checkpoint serialization produces bytes")
	_check(bytes_a == bytes_b, "checkpoint serialization is byte deterministic")
	var restored := Persistence.deserialize_state(bytes_a)
	_check(bool(Persistence.validate_state(restored).get("success", false)), "checkpoint deserializes to valid state")
	_check(restored == state, "serialized checkpoint round-trips exact typed state")
	_check(Persistence.serialize_state(restored) == bytes_a, "restored checkpoint reserializes byte-identically")

	var uninterrupted := Persistence.advance(state, TOTAL_STEPS)
	_check(bool(Persistence.validate_state(uninterrupted).get("success", false)), "uninterrupted final state validates")
	_check(int(uninterrupted["generation"]) == TOTAL_STEPS, "uninterrupted generation advances")
	var cut := Persistence.advance(state, CUT_STEPS)
	_check(bool(Persistence.validate_state(cut).get("success", false)), "cut state validates")
	var cut_bytes := Persistence.serialize_state(cut)
	var cut_restored := Persistence.deserialize_state(cut_bytes)
	_check(cut_restored == cut, "cut checkpoint round-trips exactly")
	var resumed := Persistence.advance(cut_restored, TOTAL_STEPS - CUT_STEPS)
	_check(bool(Persistence.validate_state(resumed).get("success", false)), "resumed final state validates")
	_check(String(resumed["state_hash"]) == String(uninterrupted["state_hash"]), "save/restart final state hash equals uninterrupted")
	_check(String(resumed["current_p3_7_result_hash"]) == String(uninterrupted["current_p3_7_result_hash"]), "save/restart P3.7 result hash equals uninterrupted")
	_check(Dictionary(resumed["current_p3_7_result"])["next_community"] == Dictionary(uninterrupted["current_p3_7_result"])["next_community"], "save/restart community equals uninterrupted")

	var cut_9 := Persistence.advance(state, 9)
	var resumed_9 := Persistence.advance(Persistence.deserialize_state(Persistence.serialize_state(cut_9)), 3)
	_check(String(resumed_9["state_hash"]) == String(uninterrupted["state_hash"]), "different checkpoint cut converges to same final state")

	var zero_step := Persistence.advance(state, 0)
	_check(String(zero_step["state_hash"]) == String(state["state_hash"]), "zero-step advance preserves semantic state")
	_check(zero_step == state, "zero-step advance reconstructs exact state")

	var path := "user://eco_p3_8_acceptance_checkpoint.bin"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var save_info := Persistence.save_file(path, cut)
	_check(bool(save_info.get("success", false)), "actual FileAccess checkpoint save succeeds")
	_check(int(save_info.get("bytes", 0)) == cut_bytes.size(), "saved file byte count exact")
	_check(String(save_info.get("file_sha256", "")) == _sha(cut_bytes), "saved file SHA-256 exact")
	var loaded := Persistence.load_file(path)
	_check(loaded == cut, "actual FileAccess checkpoint load restores exact state")
	_check(String(Persistence.advance(loaded, 7)["state_hash"]) == String(uninterrupted["state_hash"]), "disk-loaded state resumes to uninterrupted final")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var current: Dictionary = uninterrupted["current_p3_7_result"]
	var disturbance: Dictionary = current["disturbance_result"]
	var seasonal: Dictionary = disturbance["seasonal_result"]
	var environment: Dictionary = seasonal["environment_result"]
	var spatial: Dictionary = environment["spatial_result"]
	_check(String(current["schema"]) == Coexistence.SCHEMA, "checkpoint contains P3.7 coexistence state")
	_check(String(disturbance["schema"]) == Disturbance.SCHEMA, "checkpoint contains P3.6 disturbance state")
	_check(String(seasonal["schema"]) == Seasonal.SCHEMA, "checkpoint contains P3.5 seasonal state")
	_check(String(environment["schema"]) == EnvGradient.SCHEMA, "checkpoint contains P3.4 environmental state")
	_check(String(spatial["schema"]) == Dispersal.SCHEMA, "checkpoint contains P3.3 spatial state")
	_check(String(spatial["parent_p3_2_accepted_aggregate"]) == Dispersal.PARENT_P3_2_ACCEPTED_AGGREGATE, "checkpoint retains accepted P3.2 ancestry")

	seed(24680)
	var rng_before := [randi(), randi(), randi()]
	seed(24680)
	Persistence.advance(Persistence.deserialize_state(Persistence.serialize_state(state)), 3)
	var rng_after := [randi(), randi(), randi()]
	_check(rng_before == rng_after, "P3.8 checkpoint and replay consume no global RNG")

	var tampered := state.duplicate(true)
	tampered["state_hash"] = "0".repeat(64)
	_check(not bool(Persistence.validate_state(tampered).get("success", false)), "tampered state hash rejected")
	_check(Persistence.serialize_state(tampered).is_empty(), "tampered state cannot serialize")
	tampered = state.duplicate(true)
	tampered["current_p3_7_result"]["summary"]["active_lineages_next"] = 1
	_check(not bool(Persistence.validate_state(tampered).get("success", false)), "tampered nested P3.7 result rejected")
	tampered = state.duplicate(true)
	tampered["generation"] = -1
	_check(not bool(Persistence.validate_state(tampered).get("success", false)), "negative generation rejected")
	tampered = state.duplicate(true)
	tampered["generation"] = 0.0
	_check(not bool(Persistence.validate_state(tampered).get("success", false)), "non-integer generation rejected")
	tampered = state.duplicate(true)
	tampered["parent_p3_7_candidate_aggregate"] = "0".repeat(64)
	_check(not bool(Persistence.validate_state(tampered).get("success", false)), "wrong P3.7 parent aggregate rejected")
	tampered = state.duplicate(true)
	tampered["root_p3_7_result_hash"] = "bad"
	_check(not bool(Persistence.validate_state(tampered).get("success", false)), "malformed root hash rejected")
	_check(Persistence.advance(state, -1).is_empty(), "negative step count fails closed")
	_check(Persistence.advance(state, Persistence.MAX_ADVANCE_STEPS + 1).is_empty(), "excessive step count fails closed")
	_check(Persistence.advance(state, 1.0).is_empty(), "non-integer step count fails closed")

	var bad_header := bytes_a.duplicate()
	var header_end := _separator(bad_header)
	_check(header_end > 0, "checkpoint envelope separator found")
	if header_end > 0:
		var header := bad_header.slice(0, header_end).get_string_from_utf8()
		var lines := header.split("\n", false)
		lines[1] = "payload_sha256=" + "0".repeat(64)
		var rewritten := ("\n".join(lines) + "\n\n").to_utf8_buffer()
		rewritten.append_array(bad_header.slice(header_end + 2))
		_check(Persistence.deserialize_state(rewritten).is_empty(), "payload digest tamper rejected before decode")
	var truncated := bytes_a.slice(0, bytes_a.size() - 1)
	_check(Persistence.deserialize_state(truncated).is_empty(), "truncated checkpoint rejected")
	var extended := bytes_a.duplicate()
	extended.append(0)
	_check(Persistence.deserialize_state(extended).is_empty(), "checkpoint with trailing bytes rejected")

	var empty_result := _empty_p3_7_result()
	var empty_state := Persistence.initialize(empty_result)
	_check(bool(Persistence.validate_state(empty_state).get("success", false)), "empty ecosystem persistence state valid")
	var empty_restored := Persistence.deserialize_state(Persistence.serialize_state(empty_state))
	_check(empty_restored == empty_state, "empty ecosystem checkpoint round-trips")
	var empty_advanced := Persistence.advance(empty_restored, 2)
	_check(bool(Persistence.validate_state(empty_advanced).get("success", false)), "empty ecosystem resumes deterministically")

	var checkpoint_sha := _sha(cut_bytes)
	var aggregate := (
		String(state["state_hash"]) + "\n" +
		String(cut["state_hash"]) + "\n" +
		String(uninterrupted["state_hash"]) + "\n" +
		checkpoint_sha + "\n" +
		String(empty_state["state_hash"])
	).sha256_text()
	if failed:
		quit(1)
		return
	print("ECO.P3.8 Deterministic Ecosystem Persistence: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate)
	print("initial_state_hash=" + String(state["state_hash"]))
	print("cut_state_hash=" + String(cut["state_hash"]))
	print("final_state_hash=" + String(uninterrupted["state_hash"]))
	print("checkpoint_sha256=" + checkpoint_sha)
	print("final_p3_7_result_hash=" + String(uninterrupted["current_p3_7_result_hash"]))
	print("parent_p3_7=" + Persistence.PARENT_P3_7_CANDIDATE_AGGREGATE)
	print("source_p3_7=" + String(initial_result["result_hash"]))
	quit(0)

func _run_write_cut() -> void:
	var path := OS.get_environment("ECO_P3_8_CHECKPOINT_PATH")
	if path.is_empty():
		push_error("ECO_P3_8_CHECKPOINT_PATH missing")
		quit(1)
		return
	var state := Persistence.initialize(_initial_p3_7_result())
	var cut := Persistence.advance(state, CUT_STEPS)
	var expected := Persistence.advance(state, TOTAL_STEPS)
	var info := Persistence.save_file(path, cut)
	if not bool(info.get("success", false)):
		push_error("P3.8 writer save failed")
		quit(1)
		return
	print("ECO.P3.8 Cross-Process Writer: PASS")
	print("cut_generation=%d" % int(cut["generation"]))
	print("cut_state_hash=" + String(cut["state_hash"]))
	print("checkpoint_sha256=" + String(info["file_sha256"]))
	print("expected_final_state_hash=" + String(expected["state_hash"]))
	quit(0)

func _run_resume_cut() -> void:
	var path := OS.get_environment("ECO_P3_8_CHECKPOINT_PATH")
	if path.is_empty():
		push_error("ECO_P3_8_CHECKPOINT_PATH missing")
		quit(1)
		return
	var loaded := Persistence.load_file(path)
	if not bool(Persistence.validate_state(loaded).get("success", false)) or int(loaded.get("generation", -1)) != CUT_STEPS:
		push_error("P3.8 resume checkpoint invalid")
		quit(1)
		return
	var resumed := Persistence.advance(loaded, TOTAL_STEPS - CUT_STEPS)
	var baseline := Persistence.advance(Persistence.initialize(_initial_p3_7_result()), TOTAL_STEPS)
	if String(resumed.get("state_hash", "")) != String(baseline.get("state_hash", "")):
		push_error("P3.8 resumed state differs from uninterrupted baseline")
		quit(1)
		return
	print("ECO.P3.8 Cross-Process Resume: PASS")
	print("loaded_generation=%d" % int(loaded["generation"]))
	print("final_generation=%d" % int(resumed["generation"]))
	print("final_state_hash=" + String(resumed["state_hash"]))
	print("final_p3_7_result_hash=" + String(resumed["current_p3_7_result_hash"]))
	quit(0)

func _initial_p3_7_result() -> Dictionary:
	var parent := _disturbance_result()
	var niches := _niches()
	var community := Coexistence.community_from_parent(parent, niches)
	var skewed := _skew_community(community, 0.05, 0.95)
	return Coexistence.step(parent, skewed, niches, {"stabilization_fraction": 0.5})

func _empty_p3_7_result() -> Dictionary:
	var parent := _empty_disturbance()
	return Coexistence.step(parent, [], [], {"stabilization_fraction": 0.5})

func _niches() -> Array:
	return [
		{"id":"alpha","temperature_optimum_c":10.0,"temperature_breadth_c":12.0,"moisture_optimum":0.8,"moisture_breadth":0.5,"light_optimum":0.5,"light_breadth":0.5,"nutrients_optimum":0.9,"nutrients_breadth":0.7},
		{"id":"beta","temperature_optimum_c":15.0,"temperature_breadth_c":12.0,"moisture_optimum":0.65,"moisture_breadth":0.5,"light_optimum":0.85,"light_breadth":0.5,"nutrients_optimum":0.4,"nutrients_breadth":0.7},
	]

func _skew_community(base: Array, alpha_share: float, beta_share: float) -> Array:
	var out := []
	for patch_value in base:
		var patch: Dictionary = patch_value
		var total := 0.0
		for plant_value in patch["plants"]:
			total += float(plant_value["biomass_kg"])
		out.append({"id":String(patch["id"]),"plant_order":PackedStringArray(["alpha","beta"]),"plants":[{"id":"alpha","biomass_kg":total*alpha_share},{"id":"beta","biomass_kg":total*beta_share}]})
	return out

func _disturbance_result() -> Dictionary:
	return Disturbance.apply(_seasonal(0.0), _disturbance(0.8, 1.0, 0.0, 0.0), _traits(), 2.0)

func _empty_disturbance() -> Dictionary:
	var spatial := Dispersal.disperse([], [], {"dispersal_fraction":0.2})
	var env := EnvGradient.apply(spatial, [], _environment_config())
	var season := Seasonal.evaluate(env, 0.0, _season_config())
	return Disturbance.apply(season, _disturbance(0.8,1.0,1.0,1.0), [], 2.0)

func _traits() -> Array:
	return [
		{"id":"alpha","heat_resistance":0.9,"flood_resistance":0.2,"drought_resistance":0.2,"recovery_rate":0.4,"pioneer_capacity":0.2},
		{"id":"beta","heat_resistance":0.2,"flood_resistance":0.8,"drought_resistance":0.8,"recovery_rate":0.9,"pioneer_capacity":0.9},
	]

func _disturbance(s: float, h: float, f: float, d: float) -> Dictionary:
	return {"severity":s,"heat_pressure":h,"flood_pressure":f,"drought_pressure":d,"recovery_time_scale_years":2.0}

func _seasonal(t: float) -> Dictionary:
	return Seasonal.evaluate(_environment(), t, _season_config())

func _season_config() -> Dictionary:
	return {"cycle":{"period_years":1.0,"epoch_year":0.0,"phase_x_slope":0.0,"phase_y_slope":0.125,"phase_altitude_slope":0.0},"temperature_c":{"amplitude":10.0,"phase_offset":0.0},"moisture":{"amplitude":0.2,"phase_offset":0.25},"light":{"amplitude":0.1,"phase_offset":0.5},"nutrients":{"amplitude":0.15,"phase_offset":0.75}}

func _environment() -> Dictionary:
	return EnvGradient.apply(_spatial(0.2), [{"id":"C","x":4.0,"y":2.0,"altitude":200.0},{"id":"A","x":0.0,"y":0.0,"altitude":0.0},{"id":"B","x":2.0,"y":0.0,"altitude":100.0}], _environment_config())

func _environment_config() -> Dictionary:
	return {"origin":{"x":0.0,"y":0.0,"altitude":0.0},"temperature_c":_channel(20.0,-1.0,0.5,-0.01,-50.0,50.0),"moisture":_channel(0.8,-0.05,0.025,-0.001,0.0,1.0),"light":_channel(0.4,0.05,0.025,0.001,0.0,1.0),"nutrients":_channel(0.9,-0.05,-0.025,-0.0005,0.0,1.0)}

func _channel(b: float, x: float, y: float, z: float, mn: float, mx: float) -> Dictionary:
	return {"base":b,"x_slope":x,"y_slope":y,"altitude_slope":z,"min":mn,"max":mx}

func _spatial(fraction: float) -> Dictionary:
	var a := _density([{"id":"alpha","biomass_kg":6.0},{"id":"beta","biomass_kg":4.0}],10.0)
	var b := _density([{"id":"beta","biomass_kg":2.0}],2.0)
	var c := _density([],10.0)
	return Dispersal.disperse([{"id":"C","density_result":c,"boundary_export_fraction":0.0},{"id":"A","density_result":a,"boundary_export_fraction":0.25},{"id":"B","density_result":b,"boundary_export_fraction":0.0}],[{"from":"A","to":"C","weight":1.0},{"from":"A","to":"B","weight":3.0}],{"dispersal_fraction":fraction})

func _density(plants: Array, capacity: float) -> Dictionary:
	var competitors := []
	for plant in plants:
		competitors.append({"id":String(plant["id"]),"demand":_resources(1.0),"capture_efficiency":_resources(1.0)})
	return Density.step(Competition.compete(_resources(100.0), competitors), {"area_m2":capacity,"reference_capacity_kg_m2":1.0,"minimum_capacity_fraction":0.25,"max_recovery_fraction":0.25,"max_decline_fraction":0.6}, plants)

func _resources(value: float) -> Dictionary:
	return {"light":value,"water":value,"nutrients":value}

func _separator(bytes: PackedByteArray) -> int:
	for index in range(bytes.size() - 1):
		if bytes[index] == 10 and bytes[index + 1] == 10:
			return index
	return -1

func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL: " + message)
		return
	assertions += 1
