# EcologyWorkbench BatchRunner v1 (P11, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: headless batch experiment runner over the SAME ExperimentController
#   (no second simulation loop). A batch_plan expands deterministically into
#   variation x seed runs; EVERY run lands in the report — no filtering, no
#   "beautiful seed" selection (brief §22). Common scenarios are provided as
#   plan helpers; the report is canonical JSON (canonical_value_v1.encode,
#   stable key order, no wall-clock) so identical plans produce identical
#   report text.
# Layer: 2 (SIMULATION / ORCHESTRATION) for run driving; the report itself is
#   Layer 3 derived data (metrics summaries are read-only projections).
# DEVELOPMENT_BIAS profiles (SOFT / EARTH_LIKE / NMS_LIKE) are canonically
#   blocked (P9): such variations are KEPT in the report with status
#   BLOCKED_CANONICAL_EXTENSION_REQUIRED and never touch canonical state.
# Performance note: the A6 feedback advance is O(steps^2); the batch default
#   horizon is capped at DEFAULT_HORIZON (32). The cap is parameterized.
class_name EcoWorkbenchBatchRunnerV1
extends RefCounted

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const EnvironmentPatch = preload("res://scripts/ecology/workbench/environment_patch_v1.gd")
const PlacementPlan = preload("res://scripts/ecology/workbench/placement_plan_v1.gd")
const Profile = preload("res://scripts/ecology/workbench/organization_profile_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Metrics = preload("res://scripts/ecology/workbench/experiment_metrics_v1.gd")

const SCHEMA := "dws.ecology.workbench.batch-plan.v1"
const REPORT_SCHEMA := "dws.ecology.workbench.batch-report.v1"
const CHECKPOINT_SCHEMA := "dws.ecology.workbench.batch-checkpoint.v1"
const STATUS_COMPLETED := "COMPLETED"
const STATUS_FAILED := "FAILED"
const STATUS_BLOCKED := "BLOCKED_CANONICAL_EXTENSION_REQUIRED"
const DEFAULT_HORIZON := 32
const MAX_HORIZON := 512
const MAX_VARIATIONS := 4096
const MAX_SEEDS_PER_VARIATION := 4096

## Log a progress line every N completed variation-seed runs (0 disables).
var progress_every := 1

## Run a full batch plan. batch_plan :=
##   {"schema": SCHEMA, "base_manifest": <experiment-manifest v1>,
##    "variations": [{name, seed?, seed_range?: [from, to], env_patches?: [],
##                    placement_preset?, mutation_enabled?, feedback_enabled?,
##                    organization_profile?, founder_genomes?: {id: genome}},
##                   ...],
##    "horizon_ticks": int (default DEFAULT_HORIZON, capped MAX_HORIZON)}.
## Deterministic expansion: variations in plan order; seeds ascending
## (seed_range from..to inclusive; else variation.seed; else base seed).
## Returns {"success": true, "results": [...], "report_hash", "horizon_ticks",
##          "run_count"} — results include COMPLETED, FAILED and BLOCKED
## entries; NOTHING is filtered out.
func run_batch(batch_plan: Dictionary) -> Dictionary:
	var plan_error := validate_plan(batch_plan)
	if not plan_error.is_empty():
		return {"success": false, "error": plan_error}
	var base: Dictionary = batch_plan.base_manifest
	var horizon: int = int(batch_plan.get("horizon_ticks", DEFAULT_HORIZON))
	if not batch_plan.has("horizon_ticks"):
		horizon = mini(int(base.horizon_ticks), DEFAULT_HORIZON)
	var progress: int = int(batch_plan.get("progress_every", progress_every))
	var results: Array = []
	var runs_done := 0
	var total_runs := _total_run_count(batch_plan.variations, int(base.seed))
	for variation_index in batch_plan.variations.size():
		var variation: Dictionary = batch_plan.variations[variation_index]
		var variation_name := String(variation.name)
		for seed in _seed_list(variation, int(base.seed)):
			var result := _run_one(base, variation, variation_index, seed, horizon)
			results.append(result)
			runs_done += 1
			if progress > 0 and runs_done % progress == 0:
				print("BATCH_PROGRESS %d/%d variation=%s seed=%d status=%s error=%s" % [
					runs_done, total_runs, variation_name, seed, String(result.status), String(result.get("error", ""))])
	return {
		"success": true,
		"results": results,
		"report_hash": C.digest(results),
		"horizon_ticks": horizon,
		"run_count": results.size(),
	}

## Canonical deterministic report text (canonical_value_v1.encode; stable key
## order). Identical results -> identical text. "" on canonical encode failure.
func build_report(results: Array) -> String:
	return C.encode({
		"schema": REPORT_SCHEMA,
		"result_count": results.size(),
		"results": results,
	})

## Save the canonical batch report to `path` (user:// or absolute — the path
## is supplied by the caller). Returns {"success", "path", "text",
## "report_hash", "bytes"} or {"success": false, "error"}.
func save_batch_report(results: Array, path: String) -> Dictionary:
	if not path is String or path.is_empty():
		return {"success": false, "error": "BATCH_REPORT_PATH"}
	var text := build_report(results)
	if text.is_empty():
		return {"success": false, "error": "BATCH_REPORT_ENCODE"}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"success": false, "error": "BATCH_REPORT_OPEN:" + String(error_string(FileAccess.get_open_error()))}
	file.store_string(text)
	file.close()
	return {
		"success": true,
		"path": path,
		"text": text,
		"report_hash": text.sha256_text(),
		"bytes": text.to_utf8_buffer().size(),
	}

## Validate a batch plan. Returns "" when valid.
func validate_plan(batch_plan: Dictionary) -> String:
	var required := ["schema", "base_manifest", "variations"]
	if not batch_plan.has_all(required) or String(batch_plan.schema) != SCHEMA:
		return "BATCH_PLAN_SCHEMA"
	for key in batch_plan.keys():
		if not key in required + ["horizon_ticks", "progress_every"]:
			return "BATCH_PLAN_FIELD:" + String(key)
	var base_error := Manifest.validate(batch_plan.base_manifest)
	if not base_error.is_empty():
		return "BATCH_PLAN_BASE_MANIFEST:" + base_error
	var variations: Variant = batch_plan.variations
	if not variations is Array or variations.is_empty() or variations.size() > MAX_VARIATIONS:
		return "BATCH_PLAN_VARIATIONS"
	var seen_names := {}
	for variation in variations:
		if not variation is Dictionary or not variation.has("name"):
			return "BATCH_VARIATION"
		var name := String(variation.name)
		if name.is_empty() or name.length() > 128:
			return "BATCH_VARIATION_NAME"
		if seen_names.has(name):
			return "BATCH_VARIATION_DUPLICATE_NAME:" + name
		seen_names[name] = true
		for field in variation.keys():
			if not field in ["name", "seed", "seed_range", "env_patches", "placement_preset", "mutation_enabled", "feedback_enabled", "organization_profile", "founder_genomes"]:
				return "BATCH_VARIATION_FIELD:" + String(field)
		if variation.has("seed") and not C.integer(variation.seed, 0, C.MAX_INT):
			return "BATCH_VARIATION_SEED"
		if variation.has("seed_range"):
			var range_value: Variant = variation.seed_range
			if not range_value is Array or range_value.size() != 2 \
					or not C.integer(range_value[0], 0, C.MAX_INT) \
					or not C.integer(range_value[1], 0, C.MAX_INT) \
					or int(range_value[0]) > int(range_value[1]) \
					or int(range_value[1]) - int(range_value[0]) + 1 > MAX_SEEDS_PER_VARIATION:
				return "BATCH_VARIATION_SEED_RANGE"
		if variation.has("env_patches") and not variation.env_patches is Array:
			return "BATCH_VARIATION_ENV_PATCHES"
		if variation.has("placement_preset") and (not variation.placement_preset is String or not String(variation.placement_preset) in PlacementPlan.PRESETS):
			return "BATCH_VARIATION_PLACEMENT_PRESET"
		if variation.has("mutation_enabled") and not variation.mutation_enabled is bool:
			return "BATCH_VARIATION_MUTATION_ENABLED"
		if variation.has("feedback_enabled") and not variation.feedback_enabled is bool:
			return "BATCH_VARIATION_FEEDBACK_ENABLED"
		if variation.has("organization_profile") and (not variation.organization_profile is String or not String(variation.organization_profile) in Profile.MODES):
			return "BATCH_VARIATION_PROFILE"
		if variation.has("founder_genomes") and not variation.founder_genomes is Dictionary:
			return "BATCH_VARIATION_FOUNDER_GENOMES"
	if batch_plan.has("horizon_ticks") and not C.integer(batch_plan.horizon_ticks, 1, MAX_HORIZON):
		return "BATCH_PLAN_HORIZON"
	if batch_plan.has("progress_every") and not C.integer(batch_plan.progress_every, 0, C.MAX_INT):
		return "BATCH_PLAN_PROGRESS_EVERY"
	return ""

# --- one variation-seed run ----------------------------------------------------

func _run_one(base: Dictionary, variation: Dictionary, variation_index: int, seed: int, horizon: int) -> Dictionary:
	var derived := _derive_manifest(base, variation, seed, horizon)
	var variation_name := String(variation.name)
	if not bool(derived.get("success", false)):
		# Keep the failure in the report (never filtered out).
		return _failed_result(variation_name, variation_index, seed, "BATCH_DERIVE:" + String(derived.get("error", "?")))
	var manifest: Dictionary = derived.manifest
	var manifest_hash := Manifest.canonical_hash(manifest)
	var result := _result_shell(variation_name, variation_index, seed, manifest)
	result["manifest_hash"] = manifest_hash
	# DEVELOPMENT_BIAS profiles are canonically blocked (P9): record the
	# blocked status and never touch canonical state.
	var profile := Profile.preset(String(manifest.organization_profile))
	if String(profile.rule_class) == "DEVELOPMENT_BIAS":
		var blocked := Profile.apply_development_bias(profile)
		result["status"] = STATUS_BLOCKED
		result["required_hook"] = String(blocked.get("required_hook", Profile.REQUIRED_HOOK))
		return result
	var ctl := Controller.new()
	var init_result: Dictionary = ctl.initialize(manifest)
	if not bool(init_result.get("success", false)):
		result["status"] = STATUS_FAILED
		result["error"] = "BATCH_INIT:" + String(init_result.get("error", "?"))
		return result
	var accumulator := Metrics.new()
	accumulator.begin(manifest)
	var snapshot0: Dictionary = ctl.get_snapshot()
	if not bool(snapshot0.get("success", false)):
		result["status"] = STATUS_FAILED
		result["error"] = "BATCH_SNAPSHOT0:" + String(snapshot0.get("error", "?"))
		return result
	result["initial_state_hash"] = String(snapshot0.canonical_state_hash)
	accumulator.observe(ctl)
	var interval := int(manifest.checkpoint.interval_ticks)
	var checkpoint_ref := {}
	var run_failed := false
	for _tick in horizon:
		var step: Dictionary = ctl.step()
		if not bool(step.get("success", false)):
			run_failed = true
			result["error"] = "BATCH_TICK:" + String(step.get("error", "?"))
			break
		accumulator.observe(ctl)
		if interval > 0 and int(step.tick) % interval == 0:
			checkpoint_ref = _checkpoint_ref(ctl, manifest_hash)
	result["status"] = STATUS_FAILED if run_failed else STATUS_COMPLETED
	result["ticks_run"] = _ticks_of(ctl)
	var final_snapshot: Dictionary = ctl.get_snapshot()
	if bool(final_snapshot.get("success", false)):
		result["final_state_hash"] = String(final_snapshot.canonical_state_hash)
	var summary := accumulator.summary(String(result.final_state_hash))
	result["metrics"] = summary
	result["events"] = summary.event_counts.duplicate()
	result["checkpoint_ref"] = checkpoint_ref
	return result

func _ticks_of(ctl: Object) -> int:
	var snapshot: Dictionary = ctl.get_snapshot()
	return int(snapshot.get("tick", 0)) if bool(snapshot.get("success", false)) else -1

func _checkpoint_ref(ctl: Object, manifest_hash: String) -> Dictionary:
	var serialized: Dictionary = ctl.serialize_state()
	if not bool(serialized.get("success", false)):
		return {}
	var tick := int(serialized.tick)
	var state_hash := String(serialized.state_hash)
	return {
		"schema": CHECKPOINT_SCHEMA,
		"tick": tick,
		"state_hash": state_hash,
		"manifest_hash": manifest_hash,
		"checkpoint_id": C.digest({
			"schema": CHECKPOINT_SCHEMA,
			"manifest_hash": manifest_hash,
			"tick": tick,
			"state_hash": state_hash,
		}),
	}

func _result_shell(variation_name: String, variation_index: int, seed: int, manifest: Dictionary) -> Dictionary:
	return {
		"schema": REPORT_SCHEMA + ".result",
		"variation_name": variation_name,
		"variation_index": variation_index,
		"seed": seed,
		"experiment_id": String(manifest.experiment_id),
		"manifest_hash": "",
		"status": STATUS_FAILED,
		"initial_state_hash": "",
		"final_state_hash": "",
		"ticks_run": 0,
		"metrics": {},
		"events": {},
		"checkpoint_ref": {},
		"error": "",
	}

func _failed_result(variation_name: String, variation_index: int, seed: int, error: String) -> Dictionary:
	var result := _result_shell(variation_name, variation_index, seed, {"experiment_id": ""})
	result["error"] = error
	return result

# --- manifest derivation (immutable, deterministic) -----------------------------

## Public derivation access (for equivalence harnesses): the exact manifest a
## variation+seed run initializes from, WITHOUT running anything.
func derive_manifest(base: Dictionary, variation: Dictionary, seed: int, horizon: int) -> Dictionary:
	return _derive_manifest(base, variation, seed, horizon)

func _derive_manifest(base: Dictionary, variation: Dictionary, seed: int, horizon: int) -> Dictionary:
	var manifest := base.duplicate(true)
	manifest.experiment_id = "%s/%s/s%d" % [String(base.experiment_id), _sanitize_name(String(variation.name)), seed]
	if String(manifest.experiment_id).length() > 128:
		manifest.experiment_id = manifest.experiment_id.substr(0, 128)
	manifest.seed = seed
	manifest.horizon_ticks = horizon
	if variation.has("mutation_enabled"):
		manifest.mutation.mutations_enabled = bool(variation.mutation_enabled)
	if variation.has("feedback_enabled"):
		manifest.feedback.enabled = bool(variation.feedback_enabled)
	if variation.has("organization_profile"):
		manifest.organization_profile = String(variation.organization_profile)
	if variation.has("founder_genomes"):
		var swaps: Dictionary = variation.founder_genomes
		for founder in manifest.founders:
			if swaps.has(String(founder.founder_id)):
				founder.genome = swaps[String(founder.founder_id)]
				founder.biological_hash = null
	if variation.has("env_patches"):
		for patch in variation.env_patches:
			var applied: Dictionary = EnvironmentPatch.apply_patch(manifest, patch)
			if not bool(applied.get("success", false)):
				return {"success": false, "error": "PATCH:" + String(applied.get("error", "?"))}
			manifest = applied.manifest
	if variation.has("placement_preset"):
		var generated: Dictionary = PlacementPlan.generate(manifest, String(variation.placement_preset))
		if not bool(generated.get("success", false)):
			return {"success": false, "error": "PLACEMENT:" + String(generated.get("error", "?"))}
		manifest.placement.entries = generated.entries
	var manifest_error := Manifest.validate(manifest)
	if not manifest_error.is_empty():
		return {"success": false, "error": "MANIFEST:" + manifest_error}
	return {"success": true, "manifest": manifest}

static func _sanitize_name(name: String) -> String:
	var allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:/-"
	var out := PackedStringArray()
	for character in name:
		out.append(character if character in allowed else "-")
	return "".join(out)

static func _seed_list(variation: Dictionary, base_seed: int) -> Array:
	if variation.has("seed_range"):
		var from: int = int(variation.seed_range[0])
		var to: int = int(variation.seed_range[1])
		var seeds: Array = []
		for seed in range(from, to + 1):
			seeds.append(seed)
		return seeds
	if variation.has("seed"):
		return [int(variation.seed)]
	return [base_seed]

static func _total_run_count(variations: Array, base_seed: int) -> int:
	var total := 0
	for variation in variations:
		total += _seed_list(variation, base_seed).size()
	return total

# --- common-scenario plan helpers (brief §22) ------------------------------------
# Every helper returns a COMPLETE batch plan; all results are kept (no seed
# selection). SOFT/NMS_LIKE variations intentionally enter the report with
# status BLOCKED_CANONICAL_EXTENSION_REQUIRED.

static func plan(base_manifest: Dictionary, variations: Array, horizon_ticks: int = DEFAULT_HORIZON) -> Dictionary:
	return {
		"schema": SCHEMA,
		"base_manifest": base_manifest,
		"variations": variations,
		"horizon_ticks": horizon_ticks,
	}

## Same genome(s), different environments (env patches applied to the zones).
static func same_genome_different_environment(base_manifest: Dictionary, patch_a: Dictionary, patch_b: Dictionary, seed_range: Array = []) -> Dictionary:
	return plan(base_manifest, [
		_variation("env-a", {"env_patches": [patch_a]}, seed_range),
		_variation("env-b", {"env_patches": [patch_b]}, seed_range),
	])

## Different genomes, same environment: swap inline founder genomes by id.
static func different_genome_same_environment(base_manifest: Dictionary, genome_b_by_founder: Dictionary, seed_range: Array = []) -> Dictionary:
	return plan(base_manifest, [
		_variation("genome-a", {}, seed_range),
		_variation("genome-b", {"founder_genomes": genome_b_by_founder}, seed_range),
	])

## Mutation on vs off (same operator, same seed set).
static func mutation_on_off(base_manifest: Dictionary, seed_range: Array = []) -> Dictionary:
	return plan(base_manifest, [
		_variation("mutation-on", {"mutation_enabled": true}, seed_range),
		_variation("mutation-off", {"mutation_enabled": false}, seed_range),
	])

## Persistent environmental feedback on vs off.
static func feedback_on_off(base_manifest: Dictionary, seed_range: Array = []) -> Dictionary:
	return plan(base_manifest, [
		_variation("feedback-on", {"feedback_enabled": true}, seed_range),
		_variation("feedback-off", {"feedback_enabled": false}, seed_range),
	])

## FREE vs visual organization presets. SOFT/NMS_LIKE are DEVELOPMENT_BIAS:
## they stay in the report as BLOCKED_CANONICAL_EXTENSION_REQUIRED.
static func profile_free_vs_visual(base_manifest: Dictionary, seed_range: Array = []) -> Dictionary:
	return plan(base_manifest, [
		_variation("profile-free", {"organization_profile": "FREE"}, seed_range),
		_variation("profile-soft", {"organization_profile": "SOFT"}, seed_range),
		_variation("profile-nms-like", {"organization_profile": "NMS_LIKE"}, seed_range),
	])

## One variation over seeds 1..n (no selection — every seed is reported).
static func seeds_1_to_n(base_manifest: Dictionary, n: int) -> Dictionary:
	return plan(base_manifest, [
		_variation("seeds-1-to-n", {"seed_range": [1, maxi(1, n)]}, []),
	])

static func _variation(name: String, fields: Dictionary, seed_range: Array) -> Dictionary:
	var variation := {"name": name}
	for key in fields:
		variation[key] = fields[key]
	if not seed_range.is_empty():
		var from := int(seed_range[0])
		var to := from if seed_range.size() < 2 else int(seed_range[1])
		variation["seed_range"] = [from, maxi(from, to)]
	return variation
