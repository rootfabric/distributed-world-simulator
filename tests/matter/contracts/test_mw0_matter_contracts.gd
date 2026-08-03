extends SceneTree

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const MaterialScript = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const SampleScript = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const BrickAddressScript = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const BrickSnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const MutationRequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const MutationResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const MassLedgerScript = preload("res://scripts/simulation/matter/contracts/matter_mass_ledger.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const CellAddressScript = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_manifest()
	_test_utils()
	_test_material_definition()
	_test_default_material_catalog()
	_test_composition()
	_test_sample()
	_test_body_definition()
	_test_brick_address()
	_test_brick_snapshot()
	_test_mass_ledger()
	_test_mutation_request()
	_test_mutation_result()
	_test_checksum_and_runtime_rejection()
	_test_composition_properties()
	_test_mass_ledger_properties()
	_finish()


func _test_manifest() -> void:
	var path: String = "res://config/matter/mw0-matter-contracts.v1.json"
	_assert(FileAccess.file_exists(path), "MW0 manifest is missing")
	var file := FileAccess.open(path, FileAccess.READ)
	_assert(file != null, "MW0 manifest could not be opened")
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	_assert(typeof(parsed) == TYPE_DICTIONARY, "MW0 manifest is not a JSON object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var manifest: Dictionary = parsed
	_assert(String(manifest.get("schema", "")) == "planet_simulator.mw0_matter_contracts_manifest.v1", "MW0 manifest schema changed")
	_assert(String(manifest.get("checkpoint", "")) == "v17.0.0-simulation-mw0-matter-contracts", "MW0 checkpoint changed")
	_assert(String(manifest.get("recommended_branch", "")) == "feature/mw0-matter-contracts", "MW0 branch changed")
	_assert(not bool(manifest.get("runtime_worlds_changed", true)), "MW0 unexpectedly changes runtime worlds")
	_assert(not bool(manifest.get("moon_runtime_changed", true)), "MW0 unexpectedly changes Moon runtime")
	var fixture = manifest.get("asteroid_fixture")
	_assert(typeof(fixture) == TYPE_DICTIONARY, "MW0 asteroid fixture is missing")
	if typeof(fixture) == TYPE_DICTIONARY:
		_assert(int(fixture.get("generator_seed", 0)) == 2026073101, "MW0 asteroid fixture seed changed")
		_assert(absf(float(fixture.get("reference_radius_m", 0.0)) - 1000.0) < 0.000000001, "MW0 asteroid fixture radius changed")
	var catalog: Dictionary = MaterialCatalogScript.default_catalog()
	_assert(Array(manifest.get("material_ids", [])) == _material_ids(catalog), "MW0 manifest material IDs diverged from catalog")


func _material_ids(catalog: Dictionary) -> Array:
	var result: Array = []
	for material in catalog.get("materials", []):
		result.append(String(material.get("material_id", "")))
	return result


func _test_utils() -> void:
	_assert(MatterUtilsScript.is_semantic_version("1.0.0"), "Semantic version 1.0.0 rejected")
	_assert(MatterUtilsScript.is_semantic_version("1.2.3-alpha.1+build.7"), "Semantic prerelease rejected")
	for invalid_version in ["1.0", "01.0.0", "1..0", "1.0.0-", " 1.0.0"]:
		_assert(not MatterUtilsScript.is_semantic_version(invalid_version), "Invalid semantic version accepted: %s" % invalid_version)
	_assert(MatterUtilsScript.is_ratio(0.0), "Zero ratio rejected")
	_assert(MatterUtilsScript.is_ratio(1.0), "One ratio rejected")
	_assert(not MatterUtilsScript.is_ratio(-0.1), "Negative ratio accepted")
	_assert(not MatterUtilsScript.is_ratio(1.1), "Ratio above one accepted")
	_assert(not MatterUtilsScript.is_finite_number(NAN), "NaN accepted as finite")
	_assert(not MatterUtilsScript.is_finite_number(INF), "INF accepted as finite")
	_assert(MatterUtilsScript.is_canonical_id("matter/basalt", 2), "Canonical matter ID rejected")
	_assert(not MatterUtilsScript.is_canonical_id("Matter/Basalt", 2), "Uppercase matter ID accepted")


func _test_material_definition() -> void:
	var material: Dictionary = _basalt_material()
	_assert_ok(MaterialScript.validate(material), "Valid basalt material rejected")
	_assert(MaterialScript.normalize(material) == material, "Material normalization changed canonical value")
	var extra: Dictionary = material.duplicate(true)
	extra["presentation_material"] = "res://materials/basalt.tres"
	_assert_fail(MaterialScript.validate(extra), "Presentation field accepted by material definition")
	var negative_density: Dictionary = material.duplicate(true)
	negative_density["density_kg_m3"] = -1.0
	negative_density["checksum"] = MatterUtilsScript.compute_checksum(negative_density)
	_assert_fail(MaterialScript.validate(negative_density), "Negative density accepted")
	var nan_hardness: Dictionary = material.duplicate(true)
	nan_hardness["hardness_pa"] = NAN
	nan_hardness["checksum"] = MatterUtilsScript.compute_checksum(nan_hardness)
	_assert_fail(MaterialScript.validate(nan_hardness), "NaN hardness accepted")
	var invalid_temperature: Dictionary = material.duplicate(true)
	invalid_temperature["vaporization_temperature_k"] = invalid_temperature["melting_temperature_k"]
	invalid_temperature["checksum"] = MatterUtilsScript.compute_checksum(invalid_temperature)
	_assert_fail(MaterialScript.validate(invalid_temperature), "Non-increasing phase temperatures accepted")
	var duplicate_tags: Dictionary = material.duplicate(true)
	duplicate_tags["tags"] = ["matter-tag/bonded", "matter-tag/bonded"]
	duplicate_tags["checksum"] = MatterUtilsScript.compute_checksum(duplicate_tags)
	_assert_fail(MaterialScript.validate(duplicate_tags), "Duplicate material tags accepted")


func _test_default_material_catalog() -> void:
	var catalog: Dictionary = MaterialCatalogScript.default_catalog()
	_assert_ok(MaterialCatalogScript.validate(catalog), "Default material catalog rejected")
	_assert(catalog["materials"].size() == 7, "Default material catalog size changed")
	var expected_ids: Array[String] = [
		"matter/basalt",
		"matter/fractured-basalt",
		"matter/iron-nickel-ore",
		"matter/regolith-compacted",
		"matter/regolith-loose",
		"matter/silicate-waste",
		"matter/water-ice",
	]
	var actual_ids: Array[String] = []
	for material in catalog["materials"]:
		actual_ids.append(String(material["material_id"]))
	_assert(actual_ids == expected_ids, "Default material catalog IDs changed")
	_assert(not MaterialCatalogScript.material_by_id(catalog, "matter/water-ice").is_empty(), "Water ice missing from catalog")
	_assert(MaterialCatalogScript.material_by_id(catalog, "matter/missing").is_empty(), "Unknown catalog material resolved")
	var mutated: Dictionary = catalog.duplicate(true)
	mutated["materials"][0]["density_kg_m3"] = 1.0
	_assert_fail(MaterialCatalogScript.validate(mutated), "Catalog mutation passed nested checksum")
	var duplicate: Dictionary = catalog.duplicate(true)
	duplicate["materials"].insert(1, duplicate["materials"][0].duplicate(true))
	duplicate["catalog_hash"] = MatterUtilsScript.payload_hash(duplicate["materials"])
	duplicate["checksum"] = MatterUtilsScript.compute_checksum(duplicate)
	_assert_fail(MaterialCatalogScript.validate(duplicate), "Duplicate catalog material accepted")


func _test_composition() -> void:
	var composition: Dictionary = CompositionScript.create([
		{"material_id": "matter/iron-nickel-ore", "mass_fraction": 0.2},
		{"material_id": "matter/basalt", "mass_fraction": 0.8},
	])
	_assert_ok(CompositionScript.validate(composition), "Valid composition rejected")
	_assert(String(composition["components"][0]["material_id"]) == "matter/basalt", "Composition was not canonicalized by material ID")
	_assert(absf(CompositionScript.fraction_for(composition, "matter/iron-nickel-ore") - 0.2) < 0.000000001, "Composition fraction lookup failed")
	_assert_ok(CompositionScript.validate(CompositionScript.empty()), "Empty vacuum composition rejected")
	var from_weights: Dictionary = CompositionScript.from_weights({
		"matter/basalt": 4.0,
		"matter/iron-nickel-ore": 1.0,
	})
	_assert_ok(CompositionScript.validate(from_weights), "Composition weights failed to normalize")
	_assert(absf(CompositionScript.fraction_for(from_weights, "matter/basalt") - 0.8) < 0.000000001, "Weight normalization produced wrong fraction")
	_assert(CompositionScript.from_weights({"matter/basalt": 0.0}).is_empty(), "Zero composition weight accepted")
	var invalid_sum: Dictionary = composition.duplicate(true)
	invalid_sum["components"][0]["mass_fraction"] = 0.7
	invalid_sum["checksum"] = MatterUtilsScript.compute_checksum(invalid_sum)
	_assert_fail(CompositionScript.validate(invalid_sum), "Non-normalized composition accepted")
	var duplicate: Dictionary = CompositionScript.create([
		{"material_id": "matter/basalt", "mass_fraction": 0.5},
		{"material_id": "matter/basalt", "mass_fraction": 0.5},
	])
	_assert_fail(CompositionScript.validate(duplicate), "Duplicate composition component accepted")


func _test_sample() -> void:
	var composition: Dictionary = _basalt_composition()
	var occupied: Dictionary = SampleScript.create(
		-1.25,
		1.0,
		2900.0,
		composition,
		0.9,
		220.0,
		0.05,
		["matter-state/bonded"]
	)
	_assert_ok(SampleScript.validate(occupied), "Valid occupied matter sample rejected")
	var vacuum: Dictionary = SampleScript.vacuum(2.0, 3.0)
	_assert_ok(SampleScript.validate(vacuum), "Valid vacuum sample rejected")
	var outside_matter: Dictionary = occupied.duplicate(true)
	outside_matter["signed_distance_m"] = 2.0
	outside_matter["checksum"] = MatterUtilsScript.compute_checksum(outside_matter)
	_assert_fail(SampleScript.validate(outside_matter), "Occupied sample outside SDF surface accepted")
	var vacuum_with_density: Dictionary = vacuum.duplicate(true)
	vacuum_with_density["density_kg_m3"] = 1.0
	vacuum_with_density["checksum"] = MatterUtilsScript.compute_checksum(vacuum_with_density)
	_assert_fail(SampleScript.validate(vacuum_with_density), "Vacuum sample with density accepted")
	var occupied_without_composition: Dictionary = occupied.duplicate(true)
	occupied_without_composition["composition"] = CompositionScript.empty()
	occupied_without_composition["checksum"] = MatterUtilsScript.compute_checksum(occupied_without_composition)
	_assert_fail(SampleScript.validate(occupied_without_composition), "Occupied sample without composition accepted")


func _test_body_definition() -> void:
	var body: Dictionary = _body_definition()
	_assert_ok(BodyScript.validate(body), "Valid matter body definition rejected")
	var normalized_body: Dictionary = BodyScript.normalize(body)
	_assert(
		normalized_body == body and typeof(normalized_body["reference_radius_m"]) == TYPE_FLOAT,
		"Body definition normalization changed canonical value or numeric type"
	)
	_assert(int(body["generator_seed"]) == 2026073101, "Fixed asteroid seed changed")
	_assert(absf(float(body["reference_radius_m"]) - 1000.0) < 0.000000001, "Fixed asteroid radius changed")
	var bad_frame: Dictionary = body.duplicate(true)
	bad_frame["body_frame_id"] = "body/Asteroid/fixed"
	bad_frame["checksum"] = MatterUtilsScript.compute_checksum(bad_frame)
	_assert_fail(BodyScript.validate(bad_frame), "Uppercase body frame accepted")
	var runtime_metadata: Dictionary = body.duplicate(true)
	runtime_metadata["metadata"]["node"] = RefCounted.new()
	runtime_metadata["checksum"] = MatterUtilsScript.compute_checksum(runtime_metadata)
	_assert_fail(BodyScript.validate(runtime_metadata), "Runtime object accepted in body metadata")
	var bad_version: Dictionary = body.duplicate(true)
	bad_version["generator_version"] = "1.0"
	bad_version["checksum"] = MatterUtilsScript.compute_checksum(bad_version)
	_assert_fail(BodyScript.validate(bad_version), "Invalid body generator version accepted")


func _test_brick_address() -> void:
	var address: Dictionary = _brick_address(0, 0, 0)
	_assert_ok(BrickAddressScript.validate(address), "Valid matter brick address rejected")
	_assert(String(address["address_id"]).contains(String(address["cell_address"]["cell_id"])), "Brick address did not preserve cell identity")
	var tampered: Dictionary = address.duplicate(true)
	tampered["address_id"] += "/tampered"
	_assert_fail(BrickAddressScript.validate(tampered), "Tampered brick address ID accepted")
	var bad_cell: Dictionary = address.duplicate(true)
	bad_cell["cell_address"]["universe_id"] = "other"
	_assert_fail(BrickAddressScript.validate(bad_cell), "Brick address accepted invalid nested cell checksum/identity")
	var out_of_range: Dictionary = BrickAddressScript.create(address["cell_address"], 0, 1048576, 0, 0)
	_assert_fail(BrickAddressScript.validate(out_of_range), "Out-of-range brick coordinate accepted")


func _test_brick_snapshot() -> void:
	var address: Dictionary = _brick_address(0, 0, 0)
	var samples: Array = [
		SampleScript.vacuum(1.0, 3.0),
		SampleScript.create(-0.5, 1.0, 2900.0, _basalt_composition(), 1.0, 220.0, 0.05, ["matter-state/bonded"]),
		SampleScript.create(-1.0, 1.0, 3000.0, CompositionScript.from_weights({"matter/basalt": 0.8, "matter/iron-nickel-ore": 0.2}), 0.8, 230.0, 0.04, ["matter-state/bonded"]),
		SampleScript.vacuum(2.0, 3.0),
	]
	var snapshot: Dictionary = BrickSnapshotScript.create(
		"matter-snapshot/asteroid-lab-0",
		address,
		_body_definition()["checksum"],
		"1.0.0",
		2026073101,
		0,
		samples
	)
	_assert_ok(BrickSnapshotScript.validate(snapshot), "Valid matter brick snapshot rejected")
	_assert(int(snapshot["sample_count"]) == 4, "Matter brick sample count changed")
	_assert(snapshot["composition_channel"]["palette"].size() == 3, "Composition palette did not deduplicate samples")
	for index in range(samples.size()):
		var reconstructed: Dictionary = BrickSnapshotScript.sample_at(snapshot, index)
		_assert_ok(SampleScript.validate(reconstructed), "Reconstructed sample rejected at %d" % index)
		_assert(MatterUtilsScript.canonical_json(reconstructed) == MatterUtilsScript.canonical_json(samples[index]), "Snapshot sample roundtrip changed sample %d" % index)
	var bad_size: Dictionary = snapshot.duplicate(true)
	bad_size["geometry_channel"]["signed_distance_m"].pop_back()
	bad_size["checksum"] = MatterUtilsScript.compute_checksum(bad_size)
	_assert_fail(BrickSnapshotScript.validate(bad_size), "Mismatched geometry channel size accepted")
	var bad_index: Dictionary = snapshot.duplicate(true)
	bad_index["composition_channel"]["palette_indices"][0] = 99
	bad_index["checksum"] = MatterUtilsScript.compute_checksum(bad_index)
	_assert_fail(BrickSnapshotScript.validate(bad_index), "Out-of-range composition palette index accepted")
	var bad_sample: Dictionary = snapshot.duplicate(true)
	bad_sample["property_channel"]["density_kg_m3"][0] = 10.0
	bad_sample["checksum"] = MatterUtilsScript.compute_checksum(bad_sample)
	_assert_fail(BrickSnapshotScript.validate(bad_sample), "Invalid cross-channel vacuum sample accepted")
	var runtime_property: Dictionary = snapshot.duplicate(true)
	runtime_property["property_channel"]["density_kg_m3"][0] = RefCounted.new()
	runtime_property["checksum"] = MatterUtilsScript.compute_checksum(runtime_property)
	_assert_fail(BrickSnapshotScript.validate(runtime_property), "Runtime value in property channel accepted")
	var invalid_flags: Dictionary = snapshot.duplicate(true)
	invalid_flags["property_channel"]["flags"][0] = "matter-state/vacuum"
	invalid_flags["checksum"] = MatterUtilsScript.compute_checksum(invalid_flags)
	_assert_fail(BrickSnapshotScript.validate(invalid_flags), "Non-array sample flags accepted")


func _test_mass_ledger() -> void:
	var ledger: Dictionary = _closed_ledger("matter-operation/excavate-1", 125.0)
	_assert_ok(MassLedgerScript.validate(ledger), "Valid closed mass ledger rejected")
	_assert(bool(ledger["closed"]), "Balanced mass ledger is not closed")
	_assert(absf(float(ledger["input_total_kg"]) - 125.0) < 0.000000001, "Mass ledger input total changed")
	_assert(absf(float(ledger["output_total_kg"]) - 125.0) < 0.000000001, "Mass ledger output total changed")
	var open_ledger: Dictionary = MassLedgerScript.create(
		"matter-operation/open-ledger",
		[{"account_id": "matter-account/terrain", "material_id": "matter/basalt", "mass_kg": 10.0}],
		[{"account_id": "matter-account/container", "material_id": "matter/basalt", "mass_kg": 9.0}],
		0.000001
	)
	_assert_ok(MassLedgerScript.validate(open_ledger), "Structurally valid open ledger rejected")
	_assert(not bool(open_ledger["closed"]), "Unbalanced mass ledger marked closed")
	var forged_closed: Dictionary = open_ledger.duplicate(true)
	forged_closed["closed"] = true
	forged_closed["checksum"] = MatterUtilsScript.compute_checksum(forged_closed)
	_assert_fail(MassLedgerScript.validate(forged_closed), "Forged ledger closure accepted")
	var wrong_material: Dictionary = MassLedgerScript.create(
		"matter-operation/transmutation",
		[{"account_id": "matter-account/terrain", "material_id": "matter/basalt", "mass_kg": 10.0}],
		[{"account_id": "matter-account/container", "material_id": "matter/iron-nickel-ore", "mass_kg": 10.0}],
		0.000001
	)
	_assert_ok(MassLedgerScript.validate(wrong_material), "Open material-specific ledger rejected structurally")
	_assert(not bool(wrong_material["closed"]), "Material substitution passed conservation")
	var duplicate_entries: Dictionary = MassLedgerScript.create(
		"matter-operation/duplicate-entries",
		[
			{"account_id": "matter-account/terrain", "material_id": "matter/basalt", "mass_kg": 5.0},
			{"account_id": "matter-account/terrain", "material_id": "matter/basalt", "mass_kg": 5.0},
		],
		[{"account_id": "matter-account/container", "material_id": "matter/basalt", "mass_kg": 10.0}]
	)
	_assert_fail(MassLedgerScript.validate(duplicate_entries), "Duplicate mass ledger entries accepted")


func _test_mutation_request() -> void:
	var address_a: Dictionary = _brick_address(0, 0, 0)
	var address_b: Dictionary = _brick_address(1, 0, 0)
	var expected: Dictionary = {
		String(address_a["address_id"]): 2,
		String(address_b["address_id"]): 7,
	}
	var request: Dictionary = MutationRequestScript.create({
		"operation_id": "matter-operation/excavate-1",
		"body_id": "body/asteroid-mw0",
		"actor_id": "actor/test-miner",
		"tool_id": "tool/test-drill",
		"operation_type": "EXCAVATE",
		"target_bricks": [address_b, address_a],
		"expected_revision_by_address": expected,
		"shape": MutationRequestScript.create_shape("CAPSULE", [0.0, 0.0, 0.0], [4.0, 0.0, 0.0], 0.5),
		"source_container_id": "",
		"destination_container_id": "container/test-hopper",
		"requested_mass_kg": 0.0,
		"energy_budget_j": 500000.0,
		"client_tick": 42,
	})
	_assert_ok(MutationRequestScript.validate(request), "Valid excavation request rejected")
	_assert(String(request["target_bricks"][0]["address_id"]) < String(request["target_bricks"][1]["address_id"]), "Mutation targets were not sorted")
	_assert(int(request["expected_revisions"][0]) == 2, "Expected revisions lost address association")
	var deposit_without_source: Dictionary = request.duplicate(true)
	deposit_without_source["operation_type"] = "DEPOSIT"
	deposit_without_source["requested_mass_kg"] = 10.0
	deposit_without_source["checksum"] = MatterUtilsScript.compute_checksum(deposit_without_source)
	_assert_fail(MutationRequestScript.validate(deposit_without_source), "Deposit without source container accepted")
	var bad_radius: Dictionary = request.duplicate(true)
	bad_radius["shape"]["radius_m"] = 0.0
	bad_radius["checksum"] = MatterUtilsScript.compute_checksum(bad_radius)
	_assert_fail(MutationRequestScript.validate(bad_radius), "Capsule with zero radius accepted")
	var stale_vector: Dictionary = request.duplicate(true)
	stale_vector["shape"]["start_position_m"] = [0.0, NAN, 0.0]
	stale_vector["checksum"] = MatterUtilsScript.compute_checksum(stale_vector)
	_assert_fail(MutationRequestScript.validate(stale_vector), "Mutation shape with NaN accepted")
	var revision_mismatch: Dictionary = request.duplicate(true)
	revision_mismatch["expected_revisions"].pop_back()
	revision_mismatch["checksum"] = MatterUtilsScript.compute_checksum(revision_mismatch)
	_assert_fail(MutationRequestScript.validate(revision_mismatch), "Mutation revision count mismatch accepted")


func _test_mutation_result() -> void:
	var address: Dictionary = _brick_address(0, 0, 0)
	var operation_id: String = "matter-operation/excavate-1"
	var ledger: Dictionary = _closed_ledger(operation_id, 125.0)
	var committed: Dictionary = MutationResultScript.create({
		"operation_id": operation_id,
		"status": "COMMITTED",
		"changed_bricks": [{
			"address": address,
			"previous_revision": 2,
			"new_revision": 3,
			"snapshot_checksum": _hash("snapshot-3"),
		}],
		"removed_mass_kg": 125.0,
		"deposited_mass_kg": 0.0,
		"extracted_composition": _basalt_composition(),
		"generated_heat_j": 2500.0,
		"consumed_energy_j": 500000.0,
		"created_aggregate_ids": ["material-batch/excavate-1"],
		"mass_ledger": ledger,
		"error_code": "",
	})
	_assert_ok(MutationResultScript.validate(committed), "Valid committed mutation result rejected")
	var non_monotonic: Dictionary = committed.duplicate(true)
	non_monotonic["changed_bricks"][0]["new_revision"] = 2
	non_monotonic["checksum"] = MatterUtilsScript.compute_checksum(non_monotonic)
	_assert_fail(MutationResultScript.validate(non_monotonic), "Non-monotonic brick revision accepted")
	var open_ledger: Dictionary = MassLedgerScript.create(
		operation_id,
		[{"account_id": "matter-account/terrain", "material_id": "matter/basalt", "mass_kg": 125.0}],
		[{"account_id": "matter-account/container", "material_id": "matter/basalt", "mass_kg": 124.0}]
	)
	var open_result: Dictionary = committed.duplicate(true)
	open_result["mass_ledger"] = open_ledger
	open_result["checksum"] = MatterUtilsScript.compute_checksum(open_result)
	_assert_fail(MutationResultScript.validate(open_result), "Committed result with open mass ledger accepted")
	var rejected_ledger: Dictionary = MassLedgerScript.create("matter-operation/rejected-1", [], [])
	var rejected: Dictionary = MutationResultScript.create({
		"operation_id": "matter-operation/rejected-1",
		"status": "REJECTED",
		"changed_bricks": [],
		"removed_mass_kg": 0.0,
		"deposited_mass_kg": 0.0,
		"extracted_composition": CompositionScript.empty(),
		"generated_heat_j": 0.0,
		"consumed_energy_j": 0.0,
		"created_aggregate_ids": [],
		"mass_ledger": rejected_ledger,
		"error_code": "STALE_REVISION",
	})
	_assert_ok(MutationResultScript.validate(rejected), "Valid rejected mutation result rejected")
	var rejected_with_effect: Dictionary = rejected.duplicate(true)
	rejected_with_effect["consumed_energy_j"] = 1.0
	rejected_with_effect["checksum"] = MatterUtilsScript.compute_checksum(rejected_with_effect)
	_assert_fail(MutationResultScript.validate(rejected_with_effect), "Rejected result with effects accepted")
	var rejected_with_output: Dictionary = rejected.duplicate(true)
	rejected_with_output["created_aggregate_ids"] = ["material-batch/rejected"]
	rejected_with_output["checksum"] = MatterUtilsScript.compute_checksum(rejected_with_output)
	_assert_fail(MutationResultScript.validate(rejected_with_output), "Rejected result with aggregate output accepted")


func _test_checksum_and_runtime_rejection() -> void:
	var material: Dictionary = _basalt_material()
	var wrong_checksum: Dictionary = material.duplicate(true)
	wrong_checksum["density_kg_m3"] = 1234.0
	_assert_fail(MaterialScript.validate(wrong_checksum), "Material checksum mutation not detected")
	var composition: Dictionary = _basalt_composition()
	var upper_checksum: Dictionary = composition.duplicate(true)
	upper_checksum["checksum"] = String(upper_checksum["checksum"]).to_upper()
	_assert_fail(CompositionScript.validate(upper_checksum), "Uppercase checksum accepted")
	var body: Dictionary = _body_definition()
	var runtime_value: Dictionary = body.duplicate(true)
	runtime_value["metadata"] = {"resource": Resource.new()}
	runtime_value["checksum"] = MatterUtilsScript.compute_checksum(runtime_value)
	_assert_fail(BodyScript.validate(runtime_value), "Resource accepted in canonical matter contract")
	var round_trip: String = MatterUtilsScript.canonical_json(body)
	_assert(not round_trip.is_empty(), "Canonical body JSON is empty")
	_assert(MatterUtilsScript.payload_hash(body) == MatterUtilsScript.payload_hash(BodyScript.normalize(body)), "Roundtrip changed canonical body hash")


func _test_composition_properties() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026073101
	var material_ids: Array[String] = [
		"matter/basalt",
		"matter/fractured-basalt",
		"matter/iron-nickel-ore",
		"matter/regolith-compacted",
		"matter/regolith-loose",
		"matter/silicate-waste",
		"matter/water-ice",
	]
	for iteration in range(300):
		var shuffled: Array[String] = material_ids.duplicate()
		for index in range(shuffled.size() - 1, 0, -1):
			var swap_index: int = rng.randi_range(0, index)
			var temporary: String = shuffled[index]
			shuffled[index] = shuffled[swap_index]
			shuffled[swap_index] = temporary
		var component_count: int = rng.randi_range(1, 5)
		var weights: Dictionary = {}
		for index in range(component_count):
			weights[shuffled[index]] = rng.randf_range(0.001, 1000.0)
		var composition: Dictionary = CompositionScript.from_weights(weights)
		_assert_ok(CompositionScript.validate(composition), "Property composition rejected at iteration %d" % iteration)
		var sum: float = 0.0
		for component in composition["components"]:
			sum += float(component["mass_fraction"])
		_assert(absf(sum - 1.0) <= CompositionScript.FRACTION_TOLERANCE, "Property composition sum drift at iteration %d" % iteration)
		var normalized_composition: Dictionary = CompositionScript.normalize(composition)
		var first_fraction_type: int = TYPE_NIL
		if not normalized_composition.is_empty():
			first_fraction_type = typeof(normalized_composition["components"][0]["mass_fraction"])
		_assert(
			normalized_composition == composition and first_fraction_type == TYPE_FLOAT,
			"Property composition normalization changed value or numeric type at iteration %d" % iteration
		)


func _test_mass_ledger_properties() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026073102
	var material_ids: Array[String] = ["matter/basalt", "matter/iron-nickel-ore", "matter/water-ice"]
	for iteration in range(300):
		var inputs: Array = []
		var outputs: Array = []
		for material_index in range(material_ids.size()):
			var material_id: String = material_ids[material_index]
			var mass: float = rng.randf_range(0.001, 1000000.0)
			var split: float = rng.randf_range(0.0, 1.0)
			inputs.append({
				"account_id": "matter-account/terrain-%d" % material_index,
				"material_id": material_id,
				"mass_kg": mass,
			})
			var first_mass: float = mass * split
			var second_mass: float = mass - first_mass
			if first_mass > 0.0:
				outputs.append({
					"account_id": "matter-account/container-%d" % material_index,
					"material_id": material_id,
					"mass_kg": first_mass,
				})
			if second_mass > 0.0:
				outputs.append({
					"account_id": "matter-account/world-%d" % material_index,
					"material_id": material_id,
					"mass_kg": second_mass,
				})
		var ledger: Dictionary = MassLedgerScript.create(
			"matter-operation/property-%d" % iteration,
			inputs,
			outputs,
			0.000001
		)
		_assert_ok(MassLedgerScript.validate(ledger), "Property ledger rejected at iteration %d" % iteration)
		_assert(bool(ledger["closed"]), "Balanced property ledger open at iteration %d" % iteration)
		var replay: Dictionary = MassLedgerScript.create(
			"matter-operation/property-%d" % iteration,
			inputs,
			outputs,
			0.000001
		)
		_assert(ledger == replay, "Mass ledger creation is non-deterministic at iteration %d" % iteration)
	for iteration in range(50):
		var input_mass: float = rng.randf_range(1.0, 1000.0)
		var missing_mass: float = rng.randf_range(0.01, 1.0)
		var ledger: Dictionary = MassLedgerScript.create(
			"matter-operation/open-property-%d" % iteration,
			[{"account_id": "matter-account/terrain", "material_id": "matter/basalt", "mass_kg": input_mass}],
			[{"account_id": "matter-account/container", "material_id": "matter/basalt", "mass_kg": input_mass - missing_mass}],
			0.000001
		)
		_assert_ok(MassLedgerScript.validate(ledger), "Open property ledger invalid at iteration %d" % iteration)
		_assert(not bool(ledger["closed"]), "Open property ledger closed at iteration %d" % iteration)


func _basalt_material() -> Dictionary:
	return MaterialCatalogScript.material_by_id(MaterialCatalogScript.default_catalog(), "matter/basalt")


func _basalt_composition() -> Dictionary:
	return CompositionScript.create([
		{"material_id": "matter/basalt", "mass_fraction": 1.0},
	])


func _body_definition() -> Dictionary:
	var catalog: Dictionary = MaterialCatalogScript.default_catalog()
	return BodyScript.create({
		"body_id": "body/asteroid-mw0",
		"body_kind": "ASTEROID",
		"body_frame_id": "body/asteroid-mw0/fixed",
		"generator_id": "matter-generator/fixed-seed-asteroid",
		"generator_version": "1.0.0",
		"generator_seed": 2026073101,
		"reference_radius_m": 1000.0,
		"default_material_id": "matter/basalt",
		"material_catalog_id": catalog["catalog_id"],
		"material_catalog_hash": catalog["catalog_hash"],
		"metadata": {
			"laboratory": true,
			"purpose": "mw0-contract-fixture",
		},
	})


func _cell_address() -> Dictionary:
	return CellAddressScript.create(
		"main",
		"mutable-worlds-lab",
		"asteroid-matter-space",
		"matter-octree",
		1,
		"asteroid-mw0",
		[0, 7]
	)


func _brick_address(x: int, y: int, z: int) -> Dictionary:
	return BrickAddressScript.create(_cell_address(), 0, x, y, z)


func _closed_ledger(operation_id: String, mass_kg: float) -> Dictionary:
	return MassLedgerScript.create(
		operation_id,
		[{"account_id": "matter-account/terrain", "material_id": "matter/basalt", "mass_kg": mass_kg}],
		[
			{"account_id": "matter-account/container", "material_id": "matter/basalt", "mass_kg": mass_kg * 0.8},
			{"account_id": "matter-account/world-debris", "material_id": "matter/basalt", "mass_kg": mass_kg * 0.2},
		],
		0.000001
	)


func _hash(text: String) -> String:
	return text.sha256_text()


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result.get("error_code", "")])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("MW0 matter contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MW0 matter contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
