extends SceneTree

const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const EnvFixture = preload("res://scripts/research/ecology/synthetic_environment_fixture_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var traits := Traits.create_default()
	_check(bool(Traits.validate(traits)["success"]), "default traits validate")
	_check(Traits.TRAIT_NAMES.size() == 8, "initial development trait count is eight")
	_check(not traits.has("plant_type"), "no canonical plant_type")
	_check(not traits.has("mesh"), "no mesh in development traits")
	_check(not traits.has("renderer"), "no renderer in development traits")
	var original_hash := String(traits["checksum"])
	_check(original_hash.length() == 64, "traits checksum present")
	_check(original_hash == Traits.compute_checksum(traits), "traits checksum deterministic")

	for trait_name in Traits.TRAIT_NAMES:
		var bounds: Array = Traits.BOUNDS[trait_name]
		var lo = int(bounds[0]) if trait_name == "branching_depth" else float(bounds[0])
		var hi = int(bounds[1]) if trait_name == "branching_depth" else float(bounds[1])
		var lo_traits := Traits.with_trait(traits, trait_name, lo, "/lo")
		var hi_traits := Traits.with_trait(traits, trait_name, hi, "/hi")
		_check(bool(Traits.validate(lo_traits)["success"]), "%s lower bound valid" % trait_name)
		_check(bool(Traits.validate(hi_traits)["success"]), "%s upper bound valid" % trait_name)
		_check(String(lo_traits["checksum"]) != String(hi_traits["checksum"]), "%s changes development checksum" % trait_name)

	var genome := Genome.create_default()
	var genome_hash_before := String(genome["checksum"])
	var modified_traits := Traits.with_trait(traits, "branch_probability", 0.9, "/probe")
	_check(String(genome["checksum"]) == genome_hash_before, "development traits do not mutate accepted genome")
	_check(String(modified_traits["checksum"]) != original_hash, "development trait probe changes only development checksum")

	var env_a := EnvFixture.sample_at(125.0, -375.0, 2)
	var env_hash_a := String(env_a.get("checksum", ""))
	var env_b := EnvFixture.sample_at(125.0, -375.0, 2)
	_check(env_hash_a == String(env_b.get("checksum", "")), "environment truth independent of development traits")

	var seed0 := Contract.derive_individual_seed("lineage/A", "repro/7", 0, String(genome["version"]))
	var seed0_repeat := Contract.derive_individual_seed("lineage/A", "repro/7", 0, String(genome["version"]))
	var seed1 := Contract.derive_individual_seed("lineage/A", "repro/7", 1, String(genome["version"]))
	_check(seed0 >= 0, "individual seed is nonnegative")
	_check(seed0 == seed0_repeat, "individual seed deterministic")
	_check(seed0 != seed1, "seed_index changes individual seed")

	var envelope := Contract.create_seed_envelope(genome, traits, "lineage/A", "repro/7", 0, 1.25)
	_check(not envelope.is_empty(), "seed envelope created")
	_check(String(envelope["schema"]) == Contract.SEED_ENVELOPE_SCHEMA, "seed envelope schema")
	_check(String(envelope["genome_checksum"]) == genome_hash_before, "seed envelope carries inherited genome checksum")
	_check(String(envelope["development_traits_checksum"]) == original_hash, "seed envelope carries development traits checksum")
	_check(int(envelope["individual_seed"]) == seed0, "seed envelope carries deterministic individual seed")
	_check(String(envelope["checksum"]).length() == 64, "seed envelope checksum")

	var state := Contract.create_initial_development_state(envelope)
	_check(String(state["schema"]) == Contract.DEVELOPMENT_STATE_SCHEMA, "development state schema")
	_check(int(state["individual_seed"]) == seed0, "development state follows individual seed")
	_check(absf(float(state["reserve_energy"]) - 1.25) < 1e-12, "seed energy enters development state")
	_check(not state.has("genome_mutation"), "development state does not mutate genome")

	var graph := Contract.create_empty_growth_graph(seed0, original_hash)
	_check(String(graph["schema"]) == Contract.GROWTH_GRAPH_SCHEMA, "growth graph schema")
	_check(bool(graph["derived_representation"]), "growth graph explicitly derived representation")
	_check(Array(graph["segments"]).is_empty(), "empty growth graph starts without geometry")

	_test_source_boundaries()
	print("ECO.PH0 development_traits_hash=%s individual_seed=%d" % [original_hash, seed0])
	_finish()

func _test_source_boundaries() -> void:
	var traits_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_development_traits_v1.gd").to_lower()
	var contract_source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_development_contract_v1.gd").to_lower()
	for forbidden in ["plant_type", "treegenerator", "bushgenerator", "grassgenerator", "authority", "network", "persistence"]:
		_check(not traits_source.contains(forbidden), "traits source excludes %s" % forbidden)
	for forbidden in ["camera", "multimesh", "meshinstance", "authority", "network"]:
		_check(not contract_source.contains(forbidden), "contract source excludes %s" % forbidden)
	_check(contract_source.contains("derived_representation"), "growth graph boundary explicitly derived")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.PH0 Development Trait Contract: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.PH0 FAIL: %s" % failure)
	print("ECO.PH0 Development Trait Contract: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
