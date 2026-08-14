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
const Ownership = preload("res://scripts/ecology/production/ecology_region_ownership_v1.gd")

const EXPECTED_P4_4_AGGREGATE := "4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2"
const EXPECTED_SNAPSHOT_HASH := "c6ee61dc4250fcd22b762902ff35354957c884c8b1818aed8209fe4f6c829006"
const EXPECTED_SOURCE_OWNERSHIP := "f89f476285a40fdf0fe0f79557001f536fff4df2c8da9085cd5ecffce314d1de"
const EXPECTED_HANDOFF := "3d9e94ffddc7f9cf3f6e765c08b620a2bf3436b751fbadcedb694fe5c9e2624c"
const EXPECTED_TARGET_OWNERSHIP := "b7d0edb5c943dbe0f1ba62066dd94c5a5d84eff82177897174ba37f984b734c4"
const EXPECTED_AGGREGATE := "c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419"

var assertions := 0
var failed := false

func _init() -> void:
	var completed := _completed_catchup()
	_check(bool(OfflineCatchup.validate_state(completed).get("success", false)), "P4.3 fixture validates")
	var snapshot := ProductionPersistence.create_snapshot(completed)
	_check(bool(ProductionPersistence.validate_snapshot(snapshot).get("success", false)), "P4.4 snapshot validates")
	_check(String(snapshot.get("snapshot_hash", "")) == EXPECTED_SNAPSHOT_HASH, "P4.4 frozen snapshot exact")
	_check(Ownership.PARENT_P4_4_AGGREGATE == EXPECTED_P4_4_AGGREGATE, "P4.4 aggregate pinned")

	var source := Ownership.create_ownership(snapshot, "server-a", 0)
	_check(bool(Ownership.validate_ownership(source).get("success", false)), "initial ownership validates")
	_check(String(source["region_id"]) == "planet-01:region_0007", "region id derived")
	_check(String(source["owner_server_id"]) == "server-a", "source owner exact")
	_check(int(source["ownership_epoch"]) == 0, "initial fencing epoch exact")
	_check(String(source["snapshot_hash"]) == EXPECTED_SNAPSHOT_HASH, "snapshot identity pinned")
	_check(String(source["ownership_hash"]) == EXPECTED_SOURCE_OWNERSHIP, "frozen source ownership exact")
	_check(Ownership.authorize(source, "server-a", 0, String(source["ownership_hash"]), EXPECTED_SNAPSHOT_HASH), "exact owner claim authorized")
	_check(not Ownership.authorize(source, "server-b", 0, String(source["ownership_hash"]), EXPECTED_SNAPSHOT_HASH), "wrong server rejected")
	_check(not Ownership.authorize(source, "server-a", 1, String(source["ownership_hash"]), EXPECTED_SNAPSHOT_HASH), "wrong epoch rejected")
	_check(not Ownership.authorize(source, "server-a", 0, "0".repeat(64), EXPECTED_SNAPSHOT_HASH), "wrong ownership hash rejected")

	var snapshot_before := snapshot.duplicate(true)
	Dictionary(source["snapshot"])["snapshot_hash"] = EXPECTED_SNAPSHOT_HASH
	_check(snapshot == snapshot_before, "ownership does not mutate source snapshot")
	var extracted := Ownership.extract_snapshot(source)
	extracted["snapshot_hash"] = "0".repeat(64)
	_check(String(Dictionary(source["snapshot"])["snapshot_hash"]) == EXPECTED_SNAPSHOT_HASH, "extracted snapshot isolated")

	var handoff := Ownership.prepare_handoff(source, "server-b")
	_check(bool(Ownership.validate_handoff(handoff, source).get("success", false)), "handoff validates")
	_check(String(handoff["handoff_hash"]) == EXPECTED_HANDOFF, "frozen handoff exact")
	_check(String(handoff["source_owner_server_id"]) == "server-a", "source encoded")
	_check(String(handoff["target_owner_server_id"]) == "server-b", "target encoded")
	_check(int(handoff["source_epoch"]) == 0 and int(handoff["target_epoch"]) == 1, "handoff increments epoch exactly once")
	_check(String(handoff["snapshot_hash"]) == EXPECTED_SNAPSHOT_HASH, "handoff carries exact snapshot")
	_check(Ownership.prepare_handoff(source, "server-b") == handoff, "handoff package deterministic")
	_check(String(source["owner_server_id"]) == "server-a" and int(source["ownership_epoch"]) == 0, "prepare is read-only")

	var target := Ownership.accept_handoff(source, handoff, "server-b")
	_check(bool(Ownership.validate_ownership(target).get("success", false)), "target ownership validates")
	_check(String(target["owner_server_id"]) == "server-b", "target becomes owner")
	_check(int(target["ownership_epoch"]) == 1, "target gets next fencing epoch")
	_check(String(target["snapshot_hash"]) == EXPECTED_SNAPSHOT_HASH, "handoff preserves canonical snapshot")
	_check(String(target["ownership_hash"]) == EXPECTED_TARGET_OWNERSHIP, "frozen target ownership exact")
	_check(Ownership.authorize(target, "server-b", 1, String(target["ownership_hash"]), EXPECTED_SNAPSHOT_HASH), "target authority valid")
	_check(not Ownership.authorize(target, "server-a", 0, String(source["ownership_hash"]), EXPECTED_SNAPSHOT_HASH), "old source fenced")
	_check(Ownership.accept_handoff(target, handoff, "server-b").is_empty(), "duplicate/replayed handoff rejected")
	_check(Ownership.accept_handoff(source, handoff, "server-c").is_empty(), "wrong target acceptor rejected")
	_check(Ownership.prepare_handoff(source, "server-a").is_empty(), "self-handoff rejected")

	var future_catchup := OfflineCatchup.extend_elapsed(completed, 2.0)
	future_catchup = OfflineCatchup.advance_batch(future_catchup, 10)
	_check(bool(OfflineCatchup.validate_state(future_catchup).get("success", false)), "future catch-up validates")
	var future_snapshot := ProductionPersistence.create_snapshot(future_catchup)
	_check(bool(ProductionPersistence.validate_snapshot(future_snapshot).get("success", false)), "future snapshot validates")
	_check(String(future_snapshot["snapshot_hash"]) != EXPECTED_SNAPSHOT_HASH, "future snapshot identity changes")

	var source_advanced := Ownership.commit_snapshot(source, "server-a", 0, String(source["ownership_hash"]), future_snapshot)
	_check(bool(Ownership.validate_ownership(source_advanced).get("success", false)), "source owner can commit future snapshot")
	_check(int(source_advanced["ownership_epoch"]) == 0, "snapshot mutation keeps fencing epoch")
	_check(String(source_advanced["ownership_hash"]) != String(source["ownership_hash"]), "snapshot mutation rotates CAS ownership hash")
	_check(Ownership.accept_handoff(source_advanced, handoff, "server-b").is_empty(), "handoff prepared before mutation is stale")
	_check(Ownership.commit_snapshot(source_advanced, "server-a", 0, String(source["ownership_hash"]), snapshot).is_empty(), "stale CAS hash cannot mutate")
	_check(Ownership.commit_snapshot(source, "server-b", 0, String(source["ownership_hash"]), future_snapshot).is_empty(), "non-owner cannot mutate")

	var after_advance_handoff := Ownership.accept_handoff(source_advanced, Ownership.prepare_handoff(source_advanced, "server-b"), "server-b")
	var target_advanced := Ownership.commit_snapshot(target, "server-b", 1, String(target["ownership_hash"]), future_snapshot)
	_check(bool(Ownership.validate_ownership(after_advance_handoff).get("success", false)), "advance then handoff valid")
	_check(bool(Ownership.validate_ownership(target_advanced).get("success", false)), "handoff then advance valid")
	_check(String(after_advance_handoff["ownership_hash"]) == String(target_advanced["ownership_hash"]), "same canonical future snapshot converges across handoff boundary")

	var handoff_bc := Ownership.prepare_handoff(target_advanced, "server-c")
	var owner_c := Ownership.accept_handoff(target_advanced, handoff_bc, "server-c")
	_check(String(owner_c["owner_server_id"]) == "server-c", "second handoff owner exact")
	_check(int(owner_c["ownership_epoch"]) == 2, "second handoff increments epoch")
	_check(String(owner_c["snapshot_hash"]) == String(future_snapshot["snapshot_hash"]), "second handoff preserves latest snapshot")

	var tampered := handoff.duplicate(true)
	tampered["handoff_hash"] = "0".repeat(64)
	_check(not bool(Ownership.validate_handoff(tampered, source).get("success", false)), "handoff hash tamper rejected")
	tampered = handoff.duplicate(true)
	tampered["target_epoch"] = 2
	_check(not bool(Ownership.validate_handoff(tampered, source).get("success", false)), "epoch skip rejected")
	tampered = handoff.duplicate(true)
	tampered["snapshot_hash"] = "0".repeat(64)
	_check(not bool(Ownership.validate_handoff(tampered, source).get("success", false)), "snapshot hash tamper rejected")
	tampered = handoff.duplicate(true)
	tampered["unexpected"] = true
	_check(not bool(Ownership.validate_handoff(tampered, source).get("success", false)), "extra handoff field rejected")
	var tampered_owner := source.duplicate(true)
	tampered_owner["ownership_hash"] = "0".repeat(64)
	_check(not bool(Ownership.validate_ownership(tampered_owner).get("success", false)), "ownership hash tamper rejected")
	_check(Ownership.create_ownership(snapshot, " bad", 0).is_empty(), "bad server id rejected")
	_check(Ownership.create_ownership(snapshot, "server-a", -1).is_empty(), "negative epoch rejected")
	var max_owner := Ownership.create_ownership(snapshot, "server-a", Ownership.MAX_EXACT_EPOCH)
	_check(not max_owner.is_empty(), "max epoch representable")
	_check(Ownership.prepare_handoff(max_owner, "server-b").is_empty(), "epoch overflow handoff rejected")

	seed(741852)
	var rng_before := [randi(), randi(), randi()]
	seed(741852)
	var rng_owner := Ownership.create_ownership(snapshot, "server-a", 0)
	var rng_handoff := Ownership.prepare_handoff(rng_owner, "server-b")
	Ownership.accept_handoff(rng_owner, rng_handoff, "server-b")
	var rng_after := [randi(), randi(), randi()]
	_check(rng_before == rng_after, "P4.5 consumes no global RNG")

	var aggregate := (String(source["ownership_hash"]) + "\n" + String(handoff["handoff_hash"]) + "\n" + String(target["ownership_hash"]) + "\n" + Ownership.PARENT_P4_4_AGGREGATE).sha256_text()
	_check(aggregate == EXPECTED_AGGREGATE, "frozen P4.5 aggregate exact")

	if failed:
		quit(1)
		return
	print("ECO.P4.5 Region Ownership / Server Handoff: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate)
	print("source_ownership_hash=" + String(source["ownership_hash"]))
	print("handoff_hash=" + String(handoff["handoff_hash"]))
	print("target_ownership_hash=" + String(target["ownership_hash"]))
	print("parent_p4_4=" + Ownership.PARENT_P4_4_AGGREGATE)
	quit(0)

func _completed_catchup() -> Dictionary:
	var p3_initial := Persistence.initialize(_initial_p3_7_result())
	var region := RegionState.create_region_state("planet-01:region_0007", 42.5, p3_initial)
	var clock := EcologyClock.create_clock(region, 1.0)
	var catchup := OfflineCatchup.create(region, 47.9, clock)
	return OfflineCatchup.advance_batch(catchup, 5)

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
	push_error("ECO.P4.5 FAIL: " + message)
