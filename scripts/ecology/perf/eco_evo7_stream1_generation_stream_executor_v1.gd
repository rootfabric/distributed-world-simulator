extends RefCounted

class_name EcoEvo7Stream1GenerationStreamExecutor

## ECO.EVO7 STREAM1 R1 — bounded deterministic generation stream proposal.
##
## This executor is deliberately NOT an authority. It receives immutable
## generation inputs, processes canonical parent chunks through the accepted
## pure candidate -> route -> recruitment kernels, and returns one immutable
## full-generation proposal. Chunk completion never mutates LS3.3 state.
##
## Authority rule:
##   chunks -> proposal -> LS3.3 validates base identity + every evidence hash
##   -> LS3.3 materializes recruits -> one atomic generation publication.
##
## R1 is semantics-first and in-process. It proves chunk-size invariance,
## bounded working sets, stale-base fencing, fail-closed behavior and the
## proposal/commit boundary. Replacing the chunk runner with remote S1 workers
## is a later transport/backend step and must not change proposal identity.

const CandidateKernel = preload("res://scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd")
const RouteKernel = preload("res://scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd")
const RecruitmentKernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo7_stream1_generation_proposal.v1"
const VERSION := "1.0.0"
const SOURCE := "STREAM1_BOUNDED_PROPOSAL"

const PIPELINE_LEGACY := "LEGACY_PER_CHUNK_CANONICALIZATION"
const PIPELINE_OPTIMIZED := "OPTIMIZED_GENERATION_BOUNDARY_CANONICALIZATION"
const PIPELINE_MODES: Array[String] = [PIPELINE_LEGACY, PIPELINE_OPTIMIZED]

const FAIL_INPUTS := "STREAM1_INPUT_MISMATCH"
const FAIL_CHUNK := "STREAM1_CHUNK_FAILURE"
const FAIL_ROUTE := "STREAM1_ROUTE_FAILURE"
const FAIL_RECRUITMENT := "STREAM1_RECRUITMENT_FAILURE"
const FAIL_AUDIT := "STREAM1_AUDIT_PARITY_FAILURE"
const FAIL_PROPOSAL := "STREAM1_PROPOSAL_INVALID"

const CONTEXT_FIELDS: Array[String] = [
	"schema", "version", "revision",
	"evolution_seed", "offspring_per_parent", "cell_size_m", "grid_size",
	"environment_seed", "environment_field_hash", "environment_cells",
	"base_generation", "base_population_hash",
]

const PROPOSAL_FIELDS: Array[String] = [
	"schema", "version", "generation", "base_generation", "base_population_hash",
	"parent_count", "candidate_count",
	"candidate_pool_hash", "dispersal_pool_hash", "recruitment_hash",
	"candidates", "routes", "recruitment", "proposal_hash",
]

const FAULT_KINDS := [
	"FORCE_CHUNK_FAILURE",
	"FORCE_AUDIT_MISMATCH",
	"FORCE_STALE_BASE",
	"FORCE_PARENT_BINDING_CORRUPTION",
	"FORCE_CANDIDATE_BUNDLE_CORRUPTION",
	"FORCE_PROPOSAL_HASH_CORRUPTION",
]

var _configured := false
var _parents_per_chunk := 64
var _audit_interval := 10
var _audit_generation_1 := true
var _pipeline_mode := PIPELINE_OPTIMIZED
var _fault_kind := ""
var _fault_params: Dictionary = {}

var stream_calls := 0
var chunks_processed := 0
var serial_audit_calls := 0
var oracle_elided_generations := 0
var max_parent_chunk_seen := 0
var max_candidate_chunk_seen := 0
var last_audit_generation := -1
var last_audit_pass := false

## PERF2.4 deterministic operation counters. These are side-channel only and
## never enter proposal identity.
var legacy_generation_calls := 0
var optimized_generation_calls := 0
var chunk_local_parent_sorts := 0
var chunk_local_candidate_sorts := 0
var chunk_local_route_sorts := 0
var chunk_local_recruitment_sorts := 0
var recruitment_context_builds := 0
var generation_boundary_sorts := 0

## PERF2.4 R5 optimized-only cache. EnvironmentSample is a pure immutable
## projection of one environment cell plus the frozen field identity, so it
## can be reused across generations while that identity is unchanged.
## The cache is hard-bounded by the fixed environment cell count.
var _optimized_environment_sample_cache: Dictionary = {}
var _optimized_environment_cache_identity := ""

var _last_report: Dictionary = {}

func setup(config: Dictionary) -> bool:
	_configured = false
	stream_calls = 0
	chunks_processed = 0
	serial_audit_calls = 0
	oracle_elided_generations = 0
	max_parent_chunk_seen = 0
	max_candidate_chunk_seen = 0
	last_audit_generation = -1
	last_audit_pass = false
	legacy_generation_calls = 0
	optimized_generation_calls = 0
	chunk_local_parent_sorts = 0
	chunk_local_candidate_sorts = 0
	chunk_local_route_sorts = 0
	chunk_local_recruitment_sorts = 0
	recruitment_context_builds = 0
	generation_boundary_sorts = 0
	_optimized_environment_sample_cache = {}
	_optimized_environment_cache_identity = ""
	_last_report = {}
	_parents_per_chunk = int(config.get("parents_per_chunk", 64))
	_audit_interval = int(config.get("audit_interval", 10))
	_audit_generation_1 = bool(config.get("audit_generation_1", true))
	_pipeline_mode = String(config.get("pipeline_mode", PIPELINE_OPTIMIZED))
	if _parents_per_chunk < 1 or _audit_interval < 1:
		return false
	if _pipeline_mode not in PIPELINE_MODES:
		return false
	_configured = true
	return true

func get_telemetry() -> Dictionary:
	return {
		"parents_per_chunk": _parents_per_chunk,
		"stream_calls": stream_calls,
		"chunks_processed": chunks_processed,
		"serial_audit_calls": serial_audit_calls,
		"oracle_elided_generations": oracle_elided_generations,
		"max_parent_chunk_seen": max_parent_chunk_seen,
		"max_candidate_chunk_seen": max_candidate_chunk_seen,
		"last_audit_generation": last_audit_generation,
		"last_audit_pass": last_audit_pass,
		"pipeline_mode": _pipeline_mode,
		"legacy_generation_calls": legacy_generation_calls,
		"optimized_generation_calls": optimized_generation_calls,
		"chunk_local_parent_sorts": chunk_local_parent_sorts,
		"chunk_local_candidate_sorts": chunk_local_candidate_sorts,
		"chunk_local_route_sorts": chunk_local_route_sorts,
		"chunk_local_recruitment_sorts": chunk_local_recruitment_sorts,
		"recruitment_context_builds": recruitment_context_builds,
		"generation_boundary_sorts": generation_boundary_sorts,
	}

func get_last_report() -> Dictionary:
	return _last_report.duplicate(true)

func set_test_fault_injection(kind: String, params: Dictionary = {}) -> void:
	if kind.is_empty():
		_fault_kind = ""
		_fault_params = {}
		return
	if not kind in FAULT_KINDS:
		push_error("STREAM1 executor: unknown fault injection kind %s" % kind)
		return
	_fault_kind = kind
	_fault_params = params.duplicate(true)

func is_audit_generation(generation: int) -> bool:
	if generation <= 0:
		return false
	if _audit_generation_1 and generation == 1:
		return true
	return _audit_interval > 0 and generation % _audit_interval == 0

func execute_generation(parents: Array, generation: int, immutable_context: Dictionary) -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	if not _configured:
		return _failure(FAIL_INPUTS, "executor not configured", generation)
	if parents.is_empty() or not _validate_context(immutable_context, generation):
		return _failure(FAIL_INPUTS, "parents/context invalid", generation)

	var ordered: Array[Dictionary] = CandidateKernel.ordered_parents(parents)
	if ordered.size() != parents.size():
		return _failure(FAIL_INPUTS, "parent records invalid", generation)

	var all_candidates: Array[Dictionary] = []
	var all_routes: Array[Dictionary] = []
	var all_recruitment: Array[Dictionary] = []
	var chunk_count := 0
	var candidate_build_ms := 0.0
	var route_build_ms := 0.0
	var recruitment_eval_ms := 0.0

	var optimized_recruitment_context: Dictionary = {}
	if _pipeline_mode == PIPELINE_OPTIMIZED:
		optimized_generation_calls += 1
		var environment_cache_identity := "%s|%d|%s" % [
			String(immutable_context["revision"]),
			int(immutable_context["environment_seed"]),
			String(immutable_context["environment_field_hash"]),
		]
		if _optimized_environment_cache_identity != environment_cache_identity:
			_optimized_environment_sample_cache.clear()
			_optimized_environment_cache_identity = environment_cache_identity
		if _optimized_environment_sample_cache.size() > Array(immutable_context["environment_cells"]).size():
			return _failure(FAIL_RECRUITMENT, "optimized environment cache bound exceeded", generation)
		optimized_recruitment_context = RecruitmentKernel.build_context(
			String(immutable_context["schema"]), String(immutable_context["version"]),
			String(immutable_context["revision"]), int(immutable_context["environment_seed"]),
			String(immutable_context["environment_field_hash"]), Array(immutable_context["environment_cells"]))
		optimized_recruitment_context["environment_sample_cache"] = _optimized_environment_sample_cache
		recruitment_context_builds += 1
		if optimized_recruitment_context.is_empty():
			return _failure(FAIL_RECRUITMENT, "optimized recruitment context failed", generation)
	else:
		legacy_generation_calls += 1

	var cursor := 0
	while cursor < ordered.size():
		var end := mini(cursor + _parents_per_chunk, ordered.size())
		var chunk: Array = ordered.slice(cursor, end)
		var chunk_index := chunk_count
		chunk_count += 1
		if _fault_kind == "FORCE_CHUNK_FAILURE" and int(_fault_params.get("chunk_index", 0)) == chunk_index:
			return _failure(FAIL_CHUNK, "forced chunk failure (test)", generation)

		max_parent_chunk_seen = maxi(max_parent_chunk_seen, chunk.size())

		var phase_started := Time.get_ticks_usec()
		var candidates: Array[Dictionary] = []
		if _pipeline_mode == PIPELINE_OPTIMIZED:
			candidates = CandidateKernel.build_presorted_unsorted(
				chunk, generation,
				String(immutable_context["schema"]), String(immutable_context["version"]),
				int(immutable_context["evolution_seed"]), int(immutable_context["offspring_per_parent"]))
		else:
			candidates = CandidateKernel.build_all(
				chunk, generation,
				String(immutable_context["schema"]), String(immutable_context["version"]),
				int(immutable_context["evolution_seed"]), int(immutable_context["offspring_per_parent"]))
			chunk_local_parent_sorts += 1
			chunk_local_candidate_sorts += 1
		candidate_build_ms += _elapsed_ms(phase_started)
		if candidates.size() != chunk.size() * int(immutable_context["offspring_per_parent"]):
			return _failure(FAIL_CHUNK, "candidate chunk count mismatch", generation)
		max_candidate_chunk_seen = maxi(max_candidate_chunk_seen, candidates.size())

		phase_started = Time.get_ticks_usec()
		var routes: Array[Dictionary] = []
		if _pipeline_mode == PIPELINE_OPTIMIZED:
			routes = RouteKernel.build_in_input_order(
				candidates, generation,
				String(immutable_context["schema"]), String(immutable_context["version"]),
				int(immutable_context["evolution_seed"]), float(immutable_context["cell_size_m"]),
				int(immutable_context["grid_size"]))
		else:
			routes = RouteKernel.build_all(
				candidates, generation,
				String(immutable_context["schema"]), String(immutable_context["version"]),
				int(immutable_context["evolution_seed"]), float(immutable_context["cell_size_m"]),
				int(immutable_context["grid_size"]))
			chunk_local_route_sorts += 1
		route_build_ms += _elapsed_ms(phase_started)
		if routes.size() != candidates.size():
			return _failure(FAIL_ROUTE, "route chunk count mismatch", generation)

		phase_started = Time.get_ticks_usec()
		var recruitment: Array[Dictionary] = []
		if _pipeline_mode == PIPELINE_OPTIMIZED:
			recruitment = _evaluate_recruitment_chunk_input_order(
				candidates, routes, optimized_recruitment_context, immutable_context)
		else:
			recruitment = _evaluate_recruitment_chunk_legacy(candidates, routes, immutable_context)
			recruitment_context_builds += 1
			chunk_local_recruitment_sorts += 1
		recruitment_eval_ms += _elapsed_ms(phase_started)
		if recruitment.size() != candidates.size():
			return _failure(FAIL_RECRUITMENT, "recruitment chunk count mismatch", generation)

		all_candidates.append_array(candidates)
		all_routes.append_array(routes)
		all_recruitment.append_array(recruitment)
		chunks_processed += 1
		cursor = end

	CandidateKernel.sort_candidates(all_candidates)
	generation_boundary_sorts += 1
	all_routes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate_hash"]) < String(b["candidate_hash"])
	)
	generation_boundary_sorts += 1
	all_recruitment.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate_hash"]) < String(b["candidate_hash"])
	)
	generation_boundary_sorts += 1

	if all_candidates.size() != ordered.size() * int(immutable_context["offspring_per_parent"]):
		return _failure(FAIL_PROPOSAL, "global candidate count mismatch", generation)
	if all_routes.size() != all_candidates.size() or all_recruitment.size() != all_candidates.size():
		return _failure(FAIL_PROPOSAL, "global stage count mismatch", generation)

	var candidate_pool_hash := CandidateKernel.candidate_pool_hash(
		all_candidates, String(immutable_context["schema"]), String(immutable_context["version"]))
	var dispersal_pool_hash := RouteKernel.route_pool_hash(
		all_routes, String(immutable_context["schema"]), String(immutable_context["version"]))
	var recruitment_hash := RecruitmentKernel.recruitment_pool_hash(
		all_recruitment, String(immutable_context["schema"]), String(immutable_context["version"]))
	if candidate_pool_hash.is_empty() or dispersal_pool_hash.is_empty() or recruitment_hash.is_empty():
		return _failure(FAIL_PROPOSAL, "proposal pool hash failed", generation)

	var audited := is_audit_generation(generation)
	var audit_ms := 0.0
	if audited:
		var audit_started := Time.get_ticks_usec()
		var oracle := _monolithic_oracle(ordered, generation, immutable_context)
		audit_ms = _elapsed_ms(audit_started)
		serial_audit_calls += 1
		if oracle.is_empty():
			return _failure(FAIL_AUDIT, "monolithic oracle failed", generation)
		if _fault_kind == "FORCE_AUDIT_MISMATCH":
			oracle["candidate_pool_hash"] = _flip_hash(String(oracle["candidate_pool_hash"]))
		if String(oracle["candidate_pool_hash"]) != candidate_pool_hash \
		or String(oracle["dispersal_pool_hash"]) != dispersal_pool_hash \
		or String(oracle["recruitment_hash"]) != recruitment_hash \
		or Array(oracle["candidates"]) != all_candidates \
		or Array(oracle["routes"]) != all_routes \
		or Array(oracle["recruitment"]) != all_recruitment:
			last_audit_generation = generation
			last_audit_pass = false
			return _failure(FAIL_AUDIT, "chunked proposal diverged from monolithic oracle", generation)
		last_audit_generation = generation
		last_audit_pass = true
	else:
		oracle_elided_generations += 1

	var proposal := {
		"schema": SCHEMA,
		"version": VERSION,
		"generation": generation,
		"base_generation": int(immutable_context["base_generation"]),
		"base_population_hash": String(immutable_context["base_population_hash"]),
		"parent_count": ordered.size(),
		"candidate_count": all_candidates.size(),
		"candidate_pool_hash": candidate_pool_hash,
		"dispersal_pool_hash": dispersal_pool_hash,
		"recruitment_hash": recruitment_hash,
		"candidates": all_candidates,
		"routes": all_routes,
		"recruitment": all_recruitment,
	}
	if _fault_kind == "FORCE_STALE_BASE":
		proposal["base_population_hash"] = _flip_hash(String(proposal["base_population_hash"]))
	if _fault_kind == "FORCE_PARENT_BINDING_CORRUPTION" and not all_candidates.is_empty():
		## candidate_hash intentionally does not include parent_record_id.
		## This fault therefore stays internally hash-consistent and proves
		## that LS3.3 authority validates the live parent binding explicitly.
		var altered_parent_candidate: Dictionary = all_candidates[0].duplicate(true)
		altered_parent_candidate["parent_record_id"] = "stream1/forged-parent"
		all_candidates[0] = altered_parent_candidate
		proposal["candidates"] = all_candidates
	if _fault_kind == "FORCE_CANDIDATE_BUNDLE_CORRUPTION" and not all_candidates.is_empty():
		## candidate_hash contains the declared bundle checksum, not every
		## nested field. Remove one required field while retaining that
		## checksum so only full hereditary-bundle validation can catch it.
		var altered_bundle_candidate: Dictionary = all_candidates[0].duplicate(true)
		var altered_bundle: Dictionary = Dictionary(altered_bundle_candidate["child_bundle"]).duplicate(true)
		altered_bundle.erase("dev_traits")
		altered_bundle_candidate["child_bundle"] = altered_bundle
		all_candidates[0] = altered_bundle_candidate
		proposal["candidates"] = all_candidates
	proposal["proposal_hash"] = proposal_hash(proposal)
	if _fault_kind == "FORCE_PROPOSAL_HASH_CORRUPTION":
		proposal["proposal_hash"] = _flip_hash(String(proposal["proposal_hash"]))
	if not validate_proposal_shape(proposal):
		return _failure(FAIL_PROPOSAL, "proposal shape/hash invalid before return", generation)

	stream_calls += 1
	_last_report = {
		"schema": SCHEMA,
		"version": VERSION,
		"source": SOURCE,
		"generation": generation,
		"parent_count": ordered.size(),
		"candidate_count": all_candidates.size(),
		"parents_per_chunk": _parents_per_chunk,
		"chunk_count": chunk_count,
		"max_parent_chunk": mini(_parents_per_chunk, ordered.size()),
		"max_candidate_chunk": mini(_parents_per_chunk, ordered.size()) * int(immutable_context["offspring_per_parent"]),
		"audited": audited,
		"pipeline_mode": _pipeline_mode,
		"proposal_hash": String(proposal["proposal_hash"]),
		"optimization": {
			"chunk_local_parent_sorts": chunk_count if _pipeline_mode == PIPELINE_LEGACY else 0,
			"chunk_local_candidate_sorts": chunk_count if _pipeline_mode == PIPELINE_LEGACY else 0,
			"chunk_local_route_sorts": chunk_count if _pipeline_mode == PIPELINE_LEGACY else 0,
			"chunk_local_recruitment_sorts": chunk_count if _pipeline_mode == PIPELINE_LEGACY else 0,
			"recruitment_context_builds": chunk_count if _pipeline_mode == PIPELINE_LEGACY else 1,
			"generation_boundary_sorts": 3,
		},
		"timings_ms": {
			"candidate_build_ms": candidate_build_ms,
			"route_build_ms": route_build_ms,
			"recruitment_eval_ms": recruitment_eval_ms,
			"audit_ms": audit_ms,
			"total_ms": _elapsed_ms(started_usec),
		},
	}
	return {
		"success": true,
		"source": SOURCE,
		"proposal": proposal,
		"report": _last_report.duplicate(true),
		"failure_code": "",
	}

static func validate_proposal_shape(proposal: Dictionary) -> bool:
	if proposal.size() != PROPOSAL_FIELDS.size():
		return false
	for key in PROPOSAL_FIELDS:
		if not proposal.has(key):
			return false
	if String(proposal.get("schema", "")) != SCHEMA or String(proposal.get("version", "")) != VERSION:
		return false
	if int(proposal.get("generation", -1)) < 1 or int(proposal.get("base_generation", -1)) < 0:
		return false
	if int(proposal.get("generation", -1)) != int(proposal.get("base_generation", -1)) + 1:
		return false
	if not _is_hash(String(proposal.get("base_population_hash", ""))):
		return false
	if typeof(proposal.get("parent_count")) != TYPE_INT or typeof(proposal.get("candidate_count")) != TYPE_INT:
		return false
	var candidates_value = proposal.get("candidates")
	var routes_value = proposal.get("routes")
	var recruitment_value = proposal.get("recruitment")
	if not candidates_value is Array or not routes_value is Array or not recruitment_value is Array:
		return false
	var candidates: Array = candidates_value
	var routes: Array = routes_value
	var recruitment: Array = recruitment_value
	if int(proposal["parent_count"]) < 1 or int(proposal["candidate_count"]) < 1:
		return false
	if candidates.size() != int(proposal["candidate_count"]) or routes.size() != candidates.size() or recruitment.size() != candidates.size():
		return false
	if not _is_hash(String(proposal.get("candidate_pool_hash", ""))) \
	or not _is_hash(String(proposal.get("dispersal_pool_hash", ""))) \
	or not _is_hash(String(proposal.get("recruitment_hash", ""))):
		return false
	var expected := proposal_hash(proposal)
	return _is_hash(expected) and String(proposal.get("proposal_hash", "")) == expected

static func proposal_hash(proposal: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA, VERSION,
		str(int(proposal.get("generation", -1))),
		str(int(proposal.get("base_generation", -1))),
		String(proposal.get("base_population_hash", "")),
		str(int(proposal.get("parent_count", -1))),
		str(int(proposal.get("candidate_count", -1))),
		String(proposal.get("candidate_pool_hash", "")),
		String(proposal.get("dispersal_pool_hash", "")),
		String(proposal.get("recruitment_hash", "")),
	])).sha256_text()

func _validate_context(context: Dictionary, generation: int) -> bool:
	if context.size() != CONTEXT_FIELDS.size():
		return false
	for key in CONTEXT_FIELDS:
		if not context.has(key):
			return false
	if String(context["schema"]).is_empty() or String(context["version"]).is_empty() or String(context["revision"]).is_empty():
		return false
	if int(context["base_generation"]) != generation - 1:
		return false
	if not _is_hash(String(context["base_population_hash"])) or not _is_hash(String(context["environment_field_hash"])):
		return false
	if int(context["offspring_per_parent"]) < 1 or int(context["grid_size"]) < 1:
		return false
	if not is_finite(float(context["cell_size_m"])) or float(context["cell_size_m"]) <= 0.0:
		return false
	var cells_value = context["environment_cells"]
	if not cells_value is Array or Array(cells_value).size() != int(context["grid_size"]) * int(context["grid_size"]):
		return false
	return true

func _evaluate_recruitment_chunk_legacy(
	candidates: Array[Dictionary],
	routes: Array[Dictionary],
	context: Dictionary
) -> Array[Dictionary]:
	var candidate_by_hash := {}
	for candidate in candidates:
		candidate_by_hash[String(candidate["candidate_hash"])] = candidate
	var recruitment_context := RecruitmentKernel.build_context(
		String(context["schema"]), String(context["version"]), String(context["revision"]),
		int(context["environment_seed"]), String(context["environment_field_hash"]),
		Array(context["environment_cells"]))
	var out: Array[Dictionary] = []
	for route in routes:
		var candidate_hash := String(route.get("candidate_hash", ""))
		if not candidate_by_hash.has(candidate_hash):
			return []
		var event := RecruitmentKernel.evaluate_recruitment_event(
			candidate_by_hash[candidate_hash], route, recruitment_context)
		if event.is_empty():
			return []
		event["recruitment_event_hash"] = RecruitmentKernel.recruitment_event_hash(
			event, String(context["schema"]), String(context["version"]))
		out.append(event)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate_hash"]) < String(b["candidate_hash"])
	)
	return out

## PERF2.4 optimized recruitment seam. Candidate and route arrays are produced
## in the exact same chunk-local input order, so hash-map reconstruction and
## chunk-local sorting are unnecessary. Full canonical sorting still occurs
## once at the generation proposal boundary.
func _evaluate_recruitment_chunk_input_order(
	candidates: Array[Dictionary],
	routes: Array[Dictionary],
	recruitment_context: Dictionary,
	context: Dictionary
) -> Array[Dictionary]:
	if candidates.size() != routes.size() or recruitment_context.is_empty():
		return []
	var out: Array[Dictionary] = []
	for index in range(candidates.size()):
		var candidate: Dictionary = candidates[index]
		var route: Dictionary = routes[index]
		if String(candidate.get("candidate_hash", "")) != String(route.get("candidate_hash", "")):
			return []
		var event: Dictionary = RecruitmentKernel.evaluate_recruitment_event(
			candidate, route, recruitment_context)
		if event.is_empty():
			return []
		event["recruitment_event_hash"] = RecruitmentKernel.recruitment_event_hash(
			event, String(context["schema"]), String(context["version"]))
		out.append(event)
	return out

func _monolithic_oracle(
	ordered: Array[Dictionary],
	generation: int,
	context: Dictionary
) -> Dictionary:
	var candidates := CandidateKernel.build_all(
		ordered, generation, String(context["schema"]), String(context["version"]),
		int(context["evolution_seed"]), int(context["offspring_per_parent"]))
	if candidates.is_empty():
		return {}
	var routes := RouteKernel.build_all(
		candidates, generation, String(context["schema"]), String(context["version"]),
		int(context["evolution_seed"]), float(context["cell_size_m"]), int(context["grid_size"]))
	if routes.size() != candidates.size():
		return {}
	var recruitment: Array[Dictionary] = _evaluate_recruitment_chunk_legacy(candidates, routes, context)
	if recruitment.size() != candidates.size():
		return {}
	return {
		"candidates": candidates,
		"routes": routes,
		"recruitment": recruitment,
		"candidate_pool_hash": CandidateKernel.candidate_pool_hash(candidates, String(context["schema"]), String(context["version"])),
		"dispersal_pool_hash": RouteKernel.route_pool_hash(routes, String(context["schema"]), String(context["version"])),
		"recruitment_hash": RecruitmentKernel.recruitment_pool_hash(recruitment, String(context["schema"]), String(context["version"])),
	}

func _failure(code: String, detail: String, generation: int) -> Dictionary:
	_last_report = {
		"schema": SCHEMA,
		"version": VERSION,
		"generation": generation,
		"failure_code": code,
		"failure_detail": detail,
	}
	return {
		"success": false,
		"failure_code": code,
		"failure_detail": detail,
		"generation": generation,
		"source": "",
	}

static func _is_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true

static func _flip_hash(value: String) -> String:
	if not _is_hash(value):
		return "0".repeat(64)
	var last := value.substr(value.length() - 1, 1)
	return value.substr(0, value.length() - 1) + ("0" if last != "0" else "1")

func _elapsed_ms(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000.0
