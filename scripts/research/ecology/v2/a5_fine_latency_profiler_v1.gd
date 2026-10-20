extends RefCounted
## ECO ARCH2 A14.6 R1: NONCANONICAL diagnostic sampling of accepted A5.
## Measures real existing staged operations without editing the A4 allocator,
## A5 semantics, A6 feedback, scheduling, seed, checkpoint or world owners.
## All speculative results are detached. No partial canonical state escapes.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const Frontier = preload("res://scripts/research/ecology/v2/a5_allocation_frontier_probe_v1.gd")
const Spatial = preload("res://scripts/research/ecology/v2/population_spatial_workset_plan_v1.gd")

const SCHEMA := "dws.ecology.a14-6-a5-fine-latency-profile.v1"
const MAX_CALLS := 129
const MAX_CURSOR_BYTES := 8388608
const PHASE_NAMES := ["PREPARE", "ALLOCATE", "ADVANCE"]

## The diagnostic runs on accepted FULL canonical input, deliberately
## executes the A4 allocator again on a detached field after PREPARE, and
## compares that independent A4 result to the real A5 ALLOCATE cursor.
## Returns only read-only evidence, not a new authoritative Runtime state.
static func profile_tick(state: Dictionary, options: Dictionary,
		max_members: int = 64, max_calls: int = MAX_CALLS) -> Dictionary:
	if not C.integer(max_members, 1, Spatial.MAX_MEMBERS) \
			or not C.integer(max_calls, 3, MAX_CALLS):
		return _fail("A14_6_INPUT_BOUNDS")
	var verify_start: int = Time.get_ticks_usec()
	var source_error: String = Runtime.validate(state)
	var verify_wall_us: int = maxi(0, Time.get_ticks_usec() - verify_start)
	if not source_error.is_empty():
		return _fail("A14_6_SOURCE:" + source_error)
	var source_bytes: String = C.encode(state)
	var options_bytes: String = C.encode(options)
	if source_bytes.is_empty() or options_bytes.is_empty():
		return _fail("A14_6_NONCANONICAL_INPUT")
	var original_hash: String = Runtime.state_hash(state)
	if original_hash.is_empty():
		return _fail("A14_6_SOURCE_HASH")

	var baseline_start: int = Time.get_ticks_usec()
	var baseline: Dictionary = Runtime.step_spatial_parallel_advance(
		state, options, 4, max_members, 4, 4)
	var baseline_us: int = maxi(0, Time.get_ticks_usec() - baseline_start)
	if not bool(baseline.get("success", false)):
		return _fail("A14_6_BASELINE:" + String(baseline.get("error", "?")))

	# Independent three-step composition isolates non-staged admission/A6
	# work. Its canonical hash must equal the full continuous reference.
	var lifecycle_start: int = Time.get_ticks_usec()
	var lifecycle: Dictionary = Runtime.step_lifecycle_spatial_parallel_advance(
		state, 4, max_members, 4, 4)
	var lifecycle_us: int = maxi(0, Time.get_ticks_usec() - lifecycle_start)
	if not bool(lifecycle.get("success", false)):
		return _fail("A14_6_LIFECYCLE:" + String(lifecycle.get("error", "?")))
	var admission_start: int = Time.get_ticks_usec()
	var admitted: Dictionary = Runtime.admit_propagules(lifecycle.state, options)
	var admission_us: int = maxi(0, Time.get_ticks_usec() - admission_start)
	if not bool(admitted.get("success", false)):
		return _fail("A14_6_ADMISSION:" + String(admitted.get("error", "?")))
	var feedback_start: int = Time.get_ticks_usec()
	var feedback: Dictionary = Runtime.step_feedback(admitted.state)
	var feedback_us: int = maxi(0, Time.get_ticks_usec() - feedback_start)
	if not bool(feedback.get("success", false)) \
			or C.encode(feedback.state) != C.encode(baseline.state):
		return _fail("A14_6_COMPOSITION_MISMATCH")

	var begin_started: int = Time.get_ticks_usec()
	var begun: Dictionary = Runtime.begin_staged_global_tick(
		state, options, 4, max_members)
	var begin_us: int = maxi(0, Time.get_ticks_usec() - begin_started)
	if not bool(begun.get("success", false)) or not begun.has("cursor"):
		return _fail("A14_6_BEGIN:" + String(begun.get("error", "?")))
	var cursor: Dictionary = begun.cursor
	var unit_count: int = cursor.lifecycle.units.size()
	if unit_count <= 0 or 2 * unit_count + 1 > max_calls:
		return _fail("A14_6_WORKSET_COUNT")
	var sample_rows: Array = []
	var sample_groups := {"PREPARE": [], "ALLOCATE": [], "ADVANCE": []}
	var max_cursor_bytes := 0
	var graph: Dictionary = {}
	var graph_us := -1
	var allocator_direct_us := -1
	var global_allocation_calls := 0
	var direct_state: Dictionary = {}
	var direct_intake: Dictionary = {}
	var demand_count := 0
	var completed: Dictionary = {}
	var grant_hash := ""
	for call_index in max_calls:
		var lifecycle_cursor: Dictionary = cursor.lifecycle
		var phase: String = String(lifecycle_cursor.phase)
		if not sample_groups.has(phase):
			return _fail("A14_6_PHASE:" + phase)
		var index: int = int(lifecycle_cursor.index)
		var member_count := 0
		var unit_index := -1
		if phase != "ALLOCATE":
			if index < 0 or index >= lifecycle_cursor.units.size():
				return _fail("A14_6_WORKSET_INDEX")
			var unit: Dictionary = lifecycle_cursor.units[index]
			member_count = unit.member_ids.size()
			unit_index = int(unit.index)
		else:
			# A4 sees every demand from all PREPARE worksets. The graph
			# is conservative over BOTH allocation passes, including
			# zero first-pass claims and residual pro-rata coupling.
			if global_allocation_calls != 0:
				return _fail("A14_6_DUPLICATE_GLOBAL_BARRIER")
			var prepared_demands: Array = lifecycle_cursor.demands
			demand_count = prepared_demands.size()
			var graph_start: int = Time.get_ticks_usec()
			var analyzed: Dictionary = Frontier.analyze(state.field, prepared_demands)
			graph_us = maxi(0, Time.get_ticks_usec() - graph_start)
			if not bool(analyzed.get("success", false)):
				return _fail("A14_6_FRONTIER:" + String(analyzed.get("error", "?")))
			graph = analyzed.plan
			if demand_count > 0:
				var alloc_start: int = Time.get_ticks_usec()
				var direct: Dictionary = Field.allocate_demands(
					state.field, prepared_demands, String(state.field.owner_token),
					int(state.field.owner_epoch), int(state.field.revision))
				allocator_direct_us = maxi(0, Time.get_ticks_usec() - alloc_start)
				if not bool(direct.get("success", false)):
					return _fail("A14_6_A4:" + String(direct.get("error", "?")))
				direct_state = direct.state
				grant_hash = C.digest(direct.grants)
				# Independently aggregate admitted grants by organism and
				# resource, matching the A5 ALL-population allocation barrier.
				for entry in lifecycle_cursor.entries:
					direct_intake[String(entry.state.individual_id)] = F.stock()
				for grant in direct.grants:
					var owner: String = String(grant.organism_id)
					var resource: String = String(grant.resource)
					if not direct_intake.has(owner):
						return _fail("A14_6_GRANT_UNKNOWN_ORGANISM")
					direct_intake[owner][resource] += int(grant.granted)
			else:
				allocator_direct_us = 0
				direct_state = state.field.duplicate(true)
				for entry in lifecycle_cursor.entries:
					direct_intake[String(entry.state.individual_id)] = F.stock()
				grant_hash = C.digest([])
		var source_cursor: String = C.encode(cursor)
		if source_cursor.is_empty():
			return _fail("A14_6_CURSOR_ENCODING")
		var bytes_before := source_cursor.to_utf8_buffer().size()
		if bytes_before > MAX_CURSOR_BYTES:
			return _fail("A14_6_CURSOR_BYTES")
		max_cursor_bytes = maxi(max_cursor_bytes, bytes_before)
		var wall_start: int = Time.get_ticks_usec()
		var progressed: Dictionary = Runtime.resume_staged_global_tick(
			state, options, cursor, 1)
		var elapsed: int = maxi(0, Time.get_ticks_usec() - wall_start)
		if not bool(progressed.get("success", false)):
			return _fail("A14_6_RESUME:" + String(progressed.get("error", "?")))
		sample_groups[phase].append(elapsed)
		if phase == "ALLOCATE":
			global_allocation_calls += 1
			# Before any ADVANCE outcome, compare the full global field
			# and every per-organism intake to independent A4 allocation.
			if bool(progressed.get("complete", false)) or not progressed.has("cursor"):
				return _fail("A14_6_MISSING_ALLOCATION_CURSOR")
			if C.encode(direct_state) != C.encode(progressed.cursor.lifecycle.allocated_field) \
					or C.encode(direct_intake) != C.encode(progressed.cursor.lifecycle.intake_by_id):
				return _fail("A14_6_GLOBAL_A4_PARITY")
		var bytes_after := 0
		if not bool(progressed.get("complete", false)):
			if progressed.has("state") or not progressed.has("cursor"):
				return _fail("A14_6_PARTIAL_STATE")
			var next_encoded: String = C.encode(progressed.cursor)
			if next_encoded.is_empty():
				return _fail("A14_6_NEXT_CURSOR_ENCODING")
			bytes_after = next_encoded.to_utf8_buffer().size()
			if bytes_after > MAX_CURSOR_BYTES:
				return _fail("A14_6_NEXT_CURSOR_BYTES")
			max_cursor_bytes = maxi(max_cursor_bytes, bytes_after)
			cursor = progressed.cursor
		else:
			if not progressed.has("state"):
				return _fail("A14_6_FINAL_STATE")
			completed = progressed.state
		sample_rows.append({
			"call_index": call_index, "phase": phase,
			"workset_index": unit_index, "member_count": member_count,
			"wall_us": elapsed, "cursor_bytes_before": bytes_before,
			"cursor_bytes_after": bytes_after,
		})
		if not completed.is_empty():
			break

	if completed.is_empty() or global_allocation_calls != 1 \
			or sample_groups.ALLOCATE.size() != 1 \
			or sample_groups.PREPARE.size() != unit_count \
			or sample_groups.ADVANCE.size() != unit_count:
		return _fail("A14_6_BARRIER_OR_PARTIAL_TICK")
	if C.encode(state) != source_bytes or C.encode(options) != options_bytes \
			or Runtime.state_hash(state) != original_hash:
		return _fail("A14_6_SOURCE_MUTATED")
	if C.encode(completed) != C.encode(baseline.state) \
			or Runtime.state_hash(completed) != Runtime.state_hash(baseline.state):
		return _fail("A14_6_CANONICAL_DRIFT")
	var anchor: String = C.digest({"schema": SCHEMA,
		"source_hash": original_hash, "options_hash": C.digest(options)})
	var cpA: Dictionary = Checkpoint.create(anchor, baseline.state)
	var cpB: Dictionary = Checkpoint.create(anchor, completed)
	if cpA.is_empty() or cpB.is_empty() \
			or Checkpoint.serialize(cpA) != Checkpoint.serialize(cpB):
		return _fail("A14_6_CHECKPOINT_DRIFT")
	var phase_summary := {}
	for key in PHASE_NAMES:
		phase_summary[key] = _stats(sample_groups[key])
	return {"success": true, "profile": {
		"schema": SCHEMA,
		"population": state.population.size(),
		"source_tick": int(state.tick), "committed_tick": int(completed.tick),
		"source_hash": original_hash,
		"canonical_hash": Runtime.state_hash(completed),
		"checkpoint_equal": true, "source_unchanged": true,
		"worksets": unit_count, "demands": demand_count,
		"global_allocation_calls": global_allocation_calls,
		"baseline_parallel_wall_us": baseline_us,
		"staged_begin_wall_us": begin_us,
		"source_validate_wall_us": verify_wall_us,
		"separate_lifecycle_wall_us": lifecycle_us,
		"separate_admission_wall_us": admission_us,
		"separate_feedback_wall_us": feedback_us,
		"allocation_topology_wall_us": graph_us,
		"independent_a4_allocate_wall_us": allocator_direct_us,
		"independent_a4_grants_hash": grant_hash,
		"max_cursor_bytes": max_cursor_bytes,
		"frontier_hash": C.digest(graph),
		"frontier_components": int(graph.component_count),
		"max_component_demands": int(graph.max_component_demands),
		"residual_buckets": int(graph.residual_bucket_count),
		"zero_primary_links": int(graph.zero_primary_links),
		"phase_stats": phase_summary,
		"phase_samples": sample_rows,
	}}

static func _stats(values: Array) -> Dictionary:
	var copy: Array = values.duplicate()
	copy.sort()
	var total := 0
	for x in copy:
		total += int(x)
	return {"calls": copy.size(),
		"p50_us": _percentile(copy, 0.50),
		"p95_us": _percentile(copy, 0.95),
		"p99_us": _percentile(copy, 0.99),
		"peak_us": int(copy.back()) if not copy.is_empty() else 0,
		"total_wall_us": total}

static func _percentile(sorted: Array, threshold: float) -> int:
	if sorted.is_empty():
		return 0
	return int(sorted[maxi(0, int(ceil(sorted.size() * threshold)) - 1)])

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
