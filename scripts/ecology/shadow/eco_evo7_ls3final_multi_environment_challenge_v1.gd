extends RefCounted

const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")

## ECO.EVO7 LS3.FINAL — same-flora multi-environment challenge.
##
## This layer owns no biology. It freezes three physical counterfactuals, runs the
## accepted LS3.6 public Workbench facade, and publishes read-only causal evidence.

const SCHEMA := "distributed_world_simulator.ecology.evo7_ls3_final_multi_environment_challenge.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS3.FINAL.1"
const MODE := "SHADOW_RAM_ONLY"
const MAX_GENERATIONS := 10
const INITIAL_RECORDS := 64

const CASES := [
    {
        "id": "WET_SURFACE",
        "world_seed": 362365,
        "environment_seed": Workbench.DEFAULT_ENVIRONMENT_SEED,
        "environment_recipe": "WATER_GRADIENT_STRONG",
    },
    {
        "id": "DRY_DRAINED",
        "world_seed": 361406,
        "environment_seed": Workbench.DEFAULT_ENVIRONMENT_SEED,
        "environment_recipe": "RELIEF_DRAINAGE_STRONG",
    },
    {
        "id": "BRIGHT_DRY",
        "world_seed": 358529,
        "environment_seed": Workbench.DEFAULT_ENVIRONMENT_SEED,
        "environment_recipe": "WATER_GRADIENT_STRONG",
    },
]

const ENVIRONMENT_METRICS: Array[String] = [
    "soil_moisture", "surface_water_fraction", "drainage_index",
    "incident_light", "rainfall_forcing", "temperature_c",
]
const TRAIT_METRICS: Array[String] = [
    "leaf_area_index_proxy", "realized_root_depth_m", "root_shoot_ratio",
    "realized_height_m", "water_satisfaction", "realized_resource_balance",
]
const AUTHORITY := {
    "world_write": false,
    "environment_write": false,
    "ecology_direct_write": false,
    "genome_edit": false,
    "mutation_authority": false,
    "desired_outcome_control": false,
    "classifier_to_ecology_edge": false,
    "persistence_write": false,
    "network_replication_write": false,
    "renderer_write": false,
}
const RESULT_FIELDS: Array[String] = [
    "schema", "version", "revision", "mode", "shadow_only",
    "max_generations", "founder_hereditary_pool_hash", "cases",
    "authorities", "challenge_hash",
]
const CASE_FIELDS: Array[String] = [
    "id", "world_seed", "environment_seed", "environment_recipe",
    "patch_hash", "environment_field_hash", "founder_hereditary_pool_hash",
    "initial_population", "terminal_generation", "terminal_outcome",
    "final_population", "final_ecology_state_hash", "final_hereditary_pool_hash",
    "classification_hash", "spatial_observatory_hash",
    "environment_means", "trait_moments", "class_counts", "case_hash",
]

func run(source) -> Dictionary:
    if source == null:
        return {}
    var evidence_cases: Array[Dictionary] = []
    var common_founder_hash := ""
    for case_spec_value in CASES:
        var case_spec: Dictionary = Dictionary(case_spec_value)
        var evidence := _run_case(source, case_spec)
        if evidence.is_empty():
            return {}
        var founder_hash := String(evidence["founder_hereditary_pool_hash"])
        if common_founder_hash.is_empty():
            common_founder_hash = founder_hash
        elif founder_hash != common_founder_hash:
            return {}
        evidence_cases.append(evidence)

    var result := {
        "schema": SCHEMA,
        "version": VERSION,
        "revision": REVISION,
        "mode": MODE,
        "shadow_only": true,
        "max_generations": MAX_GENERATIONS,
        "founder_hereditary_pool_hash": common_founder_hash,
        "cases": evidence_cases,
        "authorities": AUTHORITY.duplicate(true),
    }
    result["challenge_hash"] = _challenge_hash(result)
    return result if validate_result(result) else {}

func validate_result(result: Dictionary) -> bool:
    if not _exact_keys(result, RESULT_FIELDS):
        return false
    if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION or String(result.get("revision", "")) != REVISION or String(result.get("mode", "")) != MODE:
        return false
    if not bool(result.get("shadow_only", false)) or int(result.get("max_generations", -1)) != MAX_GENERATIONS:
        return false
    if String(result.get("founder_hereditary_pool_hash", "")).length() != 64 or not _valid_authorities(result.get("authorities")):
        return false
    var cases_value = result.get("cases")
    if not cases_value is Array or Array(cases_value).size() != CASES.size():
        return false

    var patch_hashes := {}
    var environment_hashes := {}
    var final_state_hashes := {}
    var final_heredity_hashes := {}
    var populations := {}
    for index in CASES.size():
        var value = Array(cases_value)[index]
        if not value is Dictionary:
            return false
        var evidence: Dictionary = value
        var expected: Dictionary = Dictionary(CASES[index])
        if not _validate_case(evidence, expected, String(result["founder_hereditary_pool_hash"])):
            return false
        patch_hashes[String(evidence["patch_hash"])] = true
        environment_hashes[String(evidence["environment_field_hash"])] = true
        final_state_hashes[String(evidence["final_ecology_state_hash"])] = true
        final_heredity_hashes[String(evidence["final_hereditary_pool_hash"])] = true
        populations[String(evidence["id"])] = int(evidence["final_population"])

    if patch_hashes.size() != CASES.size() or environment_hashes.size() != CASES.size():
        return false
    if final_state_hashes.size() != CASES.size() or final_heredity_hashes.size() != CASES.size():
        return false
    if int(populations.get("BRIGHT_DRY", -1)) - int(populations.get("DRY_DRAINED", -1)) < 40:
        return false
    return String(result.get("challenge_hash", "")) == _challenge_hash(result)

func _run_case(source, case_spec: Dictionary) -> Dictionary:
    var spec := Workbench.default_spec()
    spec["world_seed"] = int(case_spec["world_seed"])
    spec["environment_seed"] = int(case_spec["environment_seed"])
    spec["environment_recipe"] = String(case_spec["environment_recipe"])
    var workbench = Workbench.new()
    if not workbench.setup(source, spec):
        return {}

    var initial := workbench.get_workbench_snapshot()
    var initial_ecology := workbench.get_ecology_snapshot()
    var environment := workbench.get_environment_field()
    var environment_means := _environment_means(environment)
    if initial.is_empty() or initial_ecology.is_empty() or environment_means.is_empty():
        return {}
    if int(initial_ecology.get("record_count", -1)) != INITIAL_RECORDS:
        return {}

    var terminal_generation := 0
    var terminal_outcome := "SURVIVED"
    for _step in MAX_GENERATIONS:
        var stepped := workbench.advance_generations(1)
        if stepped.is_empty():
            return {}
        terminal_generation = int(stepped["generation"])
        var latest_step: Dictionary = workbench.get_spatial_history()[-1]
        if int(latest_step.get("population_count", -1)) == 0:
            terminal_outcome = "EXTINCT"
            break

    var final_snapshot := workbench.get_workbench_snapshot()
    var latest: Dictionary = workbench.get_spatial_history()[-1]
    var classification := workbench.get_classification()
    if final_snapshot.is_empty() or latest.is_empty() or classification.is_empty():
        return {}
    var evidence := {
        "id": String(case_spec["id"]),
        "world_seed": int(case_spec["world_seed"]),
        "environment_seed": int(case_spec["environment_seed"]),
        "environment_recipe": String(case_spec["environment_recipe"]),
        "patch_hash": String(initial["patch_hash"]),
        "environment_field_hash": String(initial["environment_field_hash"]),
        "founder_hereditary_pool_hash": String(initial["hereditary_pool_hash"]),
        "initial_population": int(initial_ecology["record_count"]),
        "terminal_generation": terminal_generation,
        "terminal_outcome": terminal_outcome,
        "final_population": int(latest["population_count"]),
        "final_ecology_state_hash": String(final_snapshot["ecology_state_hash"]),
        "final_hereditary_pool_hash": String(final_snapshot["hereditary_pool_hash"]),
        "classification_hash": String(final_snapshot["classification_hash"]),
        "spatial_observatory_hash": String(final_snapshot["spatial_observatory_hash"]),
        "environment_means": environment_means,
        "trait_moments": Dictionary(latest["trait_moments"]).duplicate(true),
        "class_counts": Dictionary(latest["class_counts"]).duplicate(true),
    }
    evidence["case_hash"] = _case_hash(evidence)
    return evidence

func _validate_case(evidence: Dictionary, expected: Dictionary, common_founder_hash: String) -> bool:
    if not _exact_keys(evidence, CASE_FIELDS):
        return false
    if String(evidence.get("id", "")) != String(expected["id"]) or int(evidence.get("world_seed", 0)) != int(expected["world_seed"]) or int(evidence.get("environment_seed", 0)) != int(expected["environment_seed"]) or String(evidence.get("environment_recipe", "")) != String(expected["environment_recipe"]):
        return false
    for hash_name in ["patch_hash", "environment_field_hash", "founder_hereditary_pool_hash", "final_ecology_state_hash", "final_hereditary_pool_hash", "classification_hash", "spatial_observatory_hash", "case_hash"]:
        if String(evidence.get(hash_name, "")).length() != 64:
            return false
    if String(evidence["founder_hereditary_pool_hash"]) != common_founder_hash or int(evidence.get("initial_population", -1)) != INITIAL_RECORDS:
        return false
    var terminal_generation := int(evidence.get("terminal_generation", -1))
    var final_population := int(evidence.get("final_population", -1))
    var terminal_outcome := String(evidence.get("terminal_outcome", ""))
    if terminal_generation < 1 or terminal_generation > MAX_GENERATIONS or final_population < 0:
        return false
    if terminal_outcome == "EXTINCT":
        if final_population != 0:
            return false
    elif terminal_outcome == "SURVIVED":
        if terminal_generation != MAX_GENERATIONS or final_population <= 0:
            return false
    else:
        return false
    if not _valid_environment_means(evidence.get("environment_means")) or not _valid_trait_moments(evidence.get("trait_moments")):
        return false
    if not evidence.get("class_counts") is Dictionary or Dictionary(evidence["class_counts"]).is_empty():
        return false
    if not _semantic_envelope(evidence):
        return false
    return String(evidence.get("case_hash", "")) == _case_hash(evidence)

func _semantic_envelope(evidence: Dictionary) -> bool:
    var means: Dictionary = evidence["environment_means"]
    match String(evidence["id"]):
        "WET_SURFACE":
            return float(means["surface_water_fraction"]) >= 0.95 \
                and float(means["soil_moisture"]) >= 0.75 \
                and String(evidence["terminal_outcome"]) == "EXTINCT" \
                and int(evidence["terminal_generation"]) == 1
        "DRY_DRAINED":
            return float(means["surface_water_fraction"]) <= 0.01 \
                and float(means["soil_moisture"]) <= 0.40 \
                and float(means["drainage_index"]) >= 0.70 \
                and String(evidence["terminal_outcome"]) == "SURVIVED" \
                and int(evidence["final_population"]) < INITIAL_RECORDS
        "BRIGHT_DRY":
            return float(means["surface_water_fraction"]) <= 0.01 \
                and float(means["incident_light"]) >= 0.85 \
                and String(evidence["terminal_outcome"]) == "SURVIVED" \
                and int(evidence["final_population"]) > INITIAL_RECORDS
    return false

func _environment_means(environment: Dictionary) -> Dictionary:
    var cells_value = environment.get("cells")
    if not cells_value is Array or Array(cells_value).size() != 1024:
        return {}
    var out := {}
    for metric in ENVIRONMENT_METRICS:
        var total := 0.0
        for value in Array(cells_value):
            if not value is Dictionary:
                return {}
            var number := float(Dictionary(value).get(metric, NAN))
            if not is_finite(number):
                return {}
            total += number
        out[metric] = snappedf(total / 1024.0, 1e-9)
    return out

func _valid_environment_means(value) -> bool:
    if not value is Dictionary:
        return false
    var means: Dictionary = value
    if not _exact_keys(means, ENVIRONMENT_METRICS):
        return false
    for metric in ENVIRONMENT_METRICS:
        if not is_finite(float(means.get(metric, NAN))):
            return false
    for bounded in ["soil_moisture", "surface_water_fraction", "drainage_index", "incident_light", "rainfall_forcing"]:
        var number := float(means[bounded])
        if number < 0.0 or number > 1.0:
            return false
    return true

func _valid_trait_moments(value) -> bool:
    if not value is Dictionary:
        return false
    var moments: Dictionary = value
    if not _exact_keys(moments, TRAIT_METRICS):
        return false
    for metric in TRAIT_METRICS:
        var item_value = moments.get(metric)
        if not item_value is Dictionary:
            return false
        var item: Dictionary = item_value
        if item.keys().size() != 2 or not item.has("mean") or not item.has("variance"):
            return false
        if not is_finite(float(item["mean"])) or not is_finite(float(item["variance"])) or float(item["variance"]) < 0.0:
            return false
    return true

func _valid_authorities(value) -> bool:
    if not value is Dictionary:
        return false
    var authorities: Dictionary = value
    if authorities.keys().size() != AUTHORITY.keys().size():
        return false
    for key in AUTHORITY.keys():
        if not authorities.has(key) or typeof(authorities[key]) != TYPE_BOOL or bool(authorities[key]) != bool(AUTHORITY[key]):
            return false
    return true

func _case_hash(evidence: Dictionary) -> String:
    var tokens := PackedStringArray([
        SCHEMA, VERSION, REVISION, String(evidence.get("id", "")),
        str(int(evidence.get("world_seed", 0))), str(int(evidence.get("environment_seed", 0))), String(evidence.get("environment_recipe", "")),
        String(evidence.get("patch_hash", "")), String(evidence.get("environment_field_hash", "")), String(evidence.get("founder_hereditary_pool_hash", "")),
        str(int(evidence.get("initial_population", -1))), str(int(evidence.get("terminal_generation", -1))), String(evidence.get("terminal_outcome", "")),
        str(int(evidence.get("final_population", -1))), String(evidence.get("final_ecology_state_hash", "")), String(evidence.get("final_hereditary_pool_hash", "")),
        String(evidence.get("classification_hash", "")), String(evidence.get("spatial_observatory_hash", "")),
    ])
    var means: Dictionary = evidence.get("environment_means", {})
    for metric in ENVIRONMENT_METRICS:
        tokens.append("env:%s:%s" % [metric, _f(float(means.get(metric, 0.0)))])
    var moments: Dictionary = evidence.get("trait_moments", {})
    for metric in TRAIT_METRICS:
        var item: Dictionary = moments.get(metric, {})
        tokens.append("trait:%s:%s:%s" % [metric, _f(float(item.get("mean", 0.0))), _f(float(item.get("variance", 0.0)))])
    var class_counts: Dictionary = evidence.get("class_counts", {})
    var class_keys: Array = class_counts.keys(); class_keys.sort()
    for key in class_keys:
        tokens.append("class:%s:%d" % [String(key), int(class_counts[key])])
    return "|".join(tokens).sha256_text()

func _challenge_hash(result: Dictionary) -> String:
    var tokens := PackedStringArray([
        SCHEMA, VERSION, REVISION, MODE, str(MAX_GENERATIONS),
        String(result.get("founder_hereditary_pool_hash", "")), _authority_hash(),
    ])
    for value in Array(result.get("cases", [])):
        if value is Dictionary:
            tokens.append(String(Dictionary(value).get("case_hash", "")))
    return "|".join(tokens).sha256_text()

func _authority_hash() -> String:
    var tokens := PackedStringArray([SCHEMA, VERSION, "authority"])
    var keys: Array = AUTHORITY.keys(); keys.sort()
    for key in keys:
        tokens.append("%s=%s" % [String(key), "1" if bool(AUTHORITY[key]) else "0"])
    return "|".join(tokens).sha256_text()

func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
    if value.keys().size() != expected.size():
        return false
    for key in expected:
        if not value.has(key):
            return false
    return true

func _f(value: float) -> String:
    return "%.12f" % value
