extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const EnvGradient = preload("res://scripts/research/ecology/plant_environmental_gradient_v1.gd")
const Seasonal = preload("res://scripts/research/ecology/plant_seasonal_world_v1.gd")
const Disturbance = preload("res://scripts/research/ecology/plant_disturbance_succession_v1.gd")
const Coexistence = preload("res://scripts/research/ecology/plant_multi_niche_coexistence_v1.gd")
const Persistence = preload("res://scripts/research/ecology/plant_ecosystem_persistence_v1.gd")
const RegionState = preload("res://scripts/ecology/production/ecology_region_state_v1.gd")
const EcologyClock = preload("res://scripts/ecology/production/ecology_clock_v1.gd")
const OfflineCatchup = preload("res://scripts/ecology/production/ecology_offline_catchup_v1.gd")
const ProductionPersistence = preload("res://scripts/ecology/production/ecology_region_persistence_v1.gd")

const EXPECTED_P3_8_INITIAL_STATE := "6070494e77828f4e25a00eed9695de9e87fdf94e472f5018d660a7c20b15d7fb"
const EXPECTED_CLOCK_HASH := "f62815a7be67d7db2aeaa809915924ba2eb0437521ef6c908239642ba6909899"
const EXPECTED_CATCHUP_HASH := "cc2a4815e1eae75b879ea52d8ba404880c69344928f953e8aaa38bd062b1ce3a"
const EXPECTED_REGION_HASH := "fbc2072e388b2c9b02ff5755815821391bcf23b97cab35a5a8b1452bc4e5999c"
const EXPECTED_SNAPSHOT_HASH := "c6ee61dc4250fcd22b762902ff35354957c884c8b1818aed8209fe4f6c829006"
const EXPECTED_AGGREGATE := "4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2"

var assertions := 0
var failed := false

func _init() -> void:
	var p3_initial := Persistence.initialize(_initial_p3_7_result())
	_check(bool(Persistence.validate_state(p3_initial).get("success", false)), "P3.8 initial fixture validates")
	_check(String(p3_initial.get("state_hash", "")) == EXPECTED_P3_8_INITIAL_STATE, "P3.8 initial identity exact")
	var region := RegionState.create_region_state("planet-01:region_0007", 42.5, p3_initial)
	_check(bool(RegionState.validate_region_state(region).get("success", false)), "P4.1 region validates")
	var clock := EcologyClock.create_clock(region, 1.0)
	_check(bool(EcologyClock.validate_clock(clock).get("success", false)), "P4.2 clock validates")
	_check(String(clock.get("clock_hash", "")) == EXPECTED_CLOCK_HASH, "P4.2 clock identity exact")

	var initial := OfflineCatchup.create(region, 47.9, clock)
	_check(bool(OfflineCatchup.validate_state(initial).get("success", false)), "P4.3 catch-up validates")
	var completed := OfflineCatchup.advance_batch(initial, 5)
	_check(bool(OfflineCatchup.validate_state(completed).get("success", false)), "completed P4.3 catch-up validates")
	_check(bool(completed.get("fully_caught_up", false)), "completed P4.3 state fully caught up")
	_check(String(completed.get("catchup_hash", "")) == EXPECTED_CATCHUP_HASH, "accepted P4.3 catch-up identity exact")
	_check(String(Dictionary(completed.get("region_state", {})).get("region_state_hash", "")) == EXPECTED_REGION_HASH, "accepted region identity exact")

	var snapshot := ProductionPersistence.create_snapshot(completed)
	_check(bool(ProductionPersistence.validate_snapshot(snapshot).get("success", false)), "P4.4 production snapshot validates")
	_check(String(snapshot.get("parent_p4_3_accepted_aggregate", "")) == ProductionPersistence.PARENT_P4_3_ACCEPTED_AGGREGATE, "accepted P4.3 aggregate pinned")
	_check(String(snapshot.get("snapshot_hash", "")) == EXPECTED_SNAPSHOT_HASH, "frozen production snapshot identity exact")
	_check(String(snapshot.get("region_id", "")) == "planet-01:region_0007", "region id projected exactly")
	_check(int(snapshot.get("ecology_generation", -1)) == 5, "generation projected exactly")
	_check(float(snapshot.get("observed_target_world_time", NAN)) == 47.9, "offline observation horizon persisted exactly")
	_check(String(snapshot.get("clock_hash", "")) == EXPECTED_CLOCK_HASH, "clock identity persisted exactly")
	_check(String(snapshot.get("catchup_hash", "")) == EXPECTED_CATCHUP_HASH, "catch-up identity persisted exactly")
	_check(String(snapshot.get("region_state_hash", "")) == EXPECTED_REGION_HASH, "region identity persisted exactly")

	var bytes_a := ProductionPersistence.serialize_snapshot(snapshot)
	var bytes_b := ProductionPersistence.serialize_snapshot(snapshot)
	_check(not bytes_a.is_empty(), "production serialization produces bytes")
	_check(bytes_a == bytes_b, "production serialization is byte deterministic")
	var file_sha := ProductionPersistence.serialized_sha256(snapshot)
	_check(file_sha.length() == 64, "serialized production snapshot has SHA-256 identity")
	var decoded := ProductionPersistence.deserialize_snapshot(bytes_a)
	_check(bool(ProductionPersistence.validate_snapshot(decoded).get("success", false)), "production bytes deserialize to valid snapshot")
	_check(decoded == snapshot, "production snapshot round-trip is typed exact")
	_check(ProductionPersistence.serialize_snapshot(decoded) == bytes_a, "decoded snapshot reserializes byte-identically")
	_check(ProductionPersistence.restore_catchup_state(decoded) == completed, "completed catch-up restores exactly")

	var pending := OfflineCatchup.advance_batch(initial, 2)
	_check(int(pending.get("remaining_due_steps", -1)) == 3, "pending snapshot fixture has explicit debt")
	var pending_snapshot := ProductionPersistence.create_snapshot(pending)
	_check(bool(ProductionPersistence.validate_snapshot(pending_snapshot).get("success", false)), "pending catch-up snapshot validates")
	var pending_bytes := ProductionPersistence.serialize_snapshot(pending_snapshot)
	var pending_restored := ProductionPersistence.restore_catchup_state(ProductionPersistence.deserialize_snapshot(pending_bytes))
	_check(bool(OfflineCatchup.validate_state(pending_restored).get("success", false)), "pending catch-up restores valid")
	_check(int(pending_restored.get("remaining_due_steps", -1)) == 3, "pending backlog survives restart exactly")
	_check(float(pending_restored.get("observed_target_world_time", NAN)) == 47.9, "fractional horizon survives restart")
	var resumed := OfflineCatchup.advance_batch(pending_restored, 10)
	_check(String(resumed.get("catchup_hash", "")) == EXPECTED_CATCHUP_HASH, "restart resume converges to accepted catch-up identity")
	_check(String(Dictionary(resumed.get("region_state", {})).get("region_state_hash", "")) == EXPECTED_REGION_HASH, "restart resume converges to accepted region identity")

	var path := "user://eco_p4_4_acceptance_snapshot.bin"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var save_info := ProductionPersistence.save_file(path, pending_snapshot)
	_check(bool(save_info.get("success", false)), "production FileAccess save succeeds")
	_check(String(save_info.get("file_sha256", "")) == ProductionPersistence.serialized_sha256(pending_snapshot), "saved file SHA exact")
	var disk_snapshot := ProductionPersistence.load_file(path)
	_check(disk_snapshot == pending_snapshot, "production FileAccess load restores exact pending snapshot")
	var disk_resumed := OfflineCatchup.advance_batch(ProductionPersistence.restore_catchup_state(disk_snapshot), 10)
	_check(String(disk_resumed.get("catchup_hash", "")) == EXPECTED_CATCHUP_HASH, "disk restart converges to accepted catch-up identity")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_check(ProductionPersistence.migrate_to_current(snapshot) == snapshot, "current production format migration is exact identity")
	var unsupported := snapshot.duplicate(true)
	unsupported["format_version"] = 0
	_check(ProductionPersistence.migrate_to_current(unsupported).is_empty(), "pre-P4.4 pseudo-format rejected; no invented legacy migration")
	unsupported = snapshot.duplicate(true)
	unsupported["format_version"] = 2
	_check(ProductionPersistence.migrate_to_current(unsupported).is_empty(), "future production format rejected until explicit migration exists")

	var tampered := snapshot.duplicate(true)
	tampered["snapshot_hash"] = "0".repeat(64)
	_check(not bool(ProductionPersistence.validate_snapshot(tampered).get("success", false)), "snapshot hash tamper rejected")
	tampered = snapshot.duplicate(true)
	tampered["region_state_hash"] = "0".repeat(64)
	_check(not bool(ProductionPersistence.validate_snapshot(tampered).get("success", false)), "derived region hash tamper rejected")
	tampered = snapshot.duplicate(true)
	tampered["parent_p4_3_accepted_aggregate"] = "0".repeat(64)
	_check(not bool(ProductionPersistence.validate_snapshot(tampered).get("success", false)), "wrong P4.3 parent rejected")
	tampered = snapshot.duplicate(true)
	Dictionary(tampered["catchup_state"])["catchup_hash"] = "0".repeat(64)
	_check(not bool(ProductionPersistence.validate_snapshot(tampered).get("success", false)), "nested catch-up tamper rejected")
	tampered = snapshot.duplicate(true)
	tampered["unexpected"] = true
	_check(not bool(ProductionPersistence.validate_snapshot(tampered).get("success", false)), "extra snapshot field rejected")

	var payload_tamper := bytes_a.duplicate()
	payload_tamper[payload_tamper.size() - 1] = int(payload_tamper[payload_tamper.size() - 1]) ^ 1
	_check(ProductionPersistence.deserialize_snapshot(payload_tamper).is_empty(), "payload checksum tamper rejected")
	_check(ProductionPersistence.deserialize_snapshot(bytes_a.slice(0, bytes_a.size() - 1)).is_empty(), "truncated snapshot rejected")
	var trailing := bytes_a.duplicate()
	trailing.append(0)
	_check(ProductionPersistence.deserialize_snapshot(trailing).is_empty(), "trailing bytes rejected")
	var wrong_magic := bytes_a.duplicate()
	wrong_magic[0] = 88
	_check(ProductionPersistence.deserialize_snapshot(wrong_magic).is_empty(), "wrong production storage magic rejected")
	var p3_research_header := "DWS_ECO_P3_8_CHECKPOINT_V1\npayload_sha256=%s\npayload_bytes=0\nstate_hash=%s\n\n" % ["0".repeat(64), "0".repeat(64)]
	_check(ProductionPersistence.deserialize_snapshot(p3_research_header.to_utf8_buffer()).is_empty(), "P3.8 research checkpoint is not accepted as P4.4 production storage")

	seed(86431)
	var rng_before := [randi(), randi(), randi()]
	seed(86431)
	var rng_snapshot := ProductionPersistence.create_snapshot(completed)
	var rng_bytes := ProductionPersistence.serialize_snapshot(rng_snapshot)
	ProductionPersistence.deserialize_snapshot(rng_bytes)
	ProductionPersistence.restore_catchup_state(rng_snapshot)
	var rng_after := [randi(), randi(), randi()]
	_check(rng_before == rng_after, "P4.4 production persistence consumes no global RNG")

	var aggregate_hash := (String(snapshot["snapshot_hash"]) + "\n" + String(completed["catchup_hash"]) + "\n" + ProductionPersistence.PARENT_P4_3_ACCEPTED_AGGREGATE).sha256_text()
	_check(aggregate_hash == EXPECTED_AGGREGATE, "frozen P4.4 semantic aggregate exact")

	if failed:
		quit(1)
		return
	print("ECO.P4.4 Production Persistence: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate_hash)
	print("snapshot_hash=" + String(snapshot["snapshot_hash"]))
	print("file_sha256=" + file_sha)
	print("resumed_catchup_hash=" + String(resumed["catchup_hash"]))
	print("parent_p4_3=" + ProductionPersistence.PARENT_P4_3_ACCEPTED_AGGREGATE)
	quit(0)

func _initial_p3_7_result() -> Dictionary:
	var parent := _disturbance_result()
	var niches := _niches()
	var community := Coexistence.community_from_parent(parent, niches)
	var skewed := _skew_community(community, 0.05, 0.95)
	return Coexistence.step(parent, skewed, niches, {"stabilization_fraction": 0.5})

func _niches() -> Array:
	return [{"id":"alpha","temperature_optimum_c":10.0,"temperature_breadth_c":12.0,"moisture_optimum":0.8,"moisture_breadth":0.5,"light_optimum":0.5,"light_breadth":0.5,"nutrients_optimum":0.9,"nutrients_breadth":0.7},{"id":"beta","temperature_optimum_c":15.0,"temperature_breadth_c":12.0,"moisture_optimum":0.65,"moisture_breadth":0.5,"light_optimum":0.85,"light_breadth":0.5,"nutrients_optimum":0.4,"nutrients_breadth":0.7}]

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

func _traits() -> Array:
	return [{"id":"alpha","heat_resistance":0.9,"flood_resistance":0.2,"drought_resistance":0.2,"recovery_rate":0.4,"pioneer_capacity":0.2},{"id":"beta","heat_resistance":0.2,"flood_resistance":0.8,"drought_resistance":0.8,"recovery_rate":0.9,"pioneer_capacity":0.9}]

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

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		return
	failed = true
	push_error("ECO.P4.4 FAIL: " + message)
