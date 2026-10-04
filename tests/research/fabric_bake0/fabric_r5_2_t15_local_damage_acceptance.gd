extends SceneTree
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t15_local_damage_runtime_v1.gd")
const Families = preload("res://scripts/research/fabric_bake0/r5_t13_5_shared_families_runtime_v1.gd")
const FF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t13_5_family_fixture.gd")
const DF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t15_local_damage_fixture.gd")
const F = preload("res://tests/research/fabric_bake0/fabric_r5_2_t12_ship_fixture.gd")

const INSTANCE_COUNT := 100
const TARGET_INDEX := 57
const TARGET_PATH := "root/bank/unit03/cannon/emitter"
const DAMAGE_FAMILY := "family-b-instance-058-damage-1"
const REPAIR_FAMILY := "family-b-instance-058-repair-2"
const DAMAGE_EVENT := "damage/t15-instance-058/emitter-cell-009/1"
const REPAIR_EVENT := "repair/t15-instance-058/emitter-cell-009/2"
const DT := 0.002
const AMBIENT_K := 294.0

var checks := 0
var failures: Array = []

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("T15: " + label + " " + JSON.stringify(details))

func iid(index: int) -> String:
	return "t15-instance-%03d" % (index + 1)

func family_for(index: int) -> String:
	if index < 40: return "family-a"
	if index < 70: return "family-b"
	if index < 90: return "family-c"
	return "family-d"

func commands_for(index: int) -> Dictionary:
	var laser := 190.0 + 12.0 * float(index % 5)
	var position := -0.08 + 0.04 * float(index % 5)
	return F.commands(3, laser, position)

func add_metrics(result: Dictionary, metrics: Dictionary) -> void:
	if not result.success:
		return
	var m: Dictionary = result.details.physical.metrics
	metrics.runtime_steps += 1
	metrics.evaluations += int(m.evaluations)
	metrics.boundary_calls += int(m.boundary_calls)
	metrics.compiled_group_visits += int(m.compiled_group_visits)
	metrics.leaf_traversals += int(m.leaf_traversals)

func identities(runtime, ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[id] = runtime.family_identity(String(id))
	return out

func atomic_snapshot(runtime) -> Dictionary:
	return {
		"family_stats": runtime.family_stats().duplicate(true),
		"runtime_stats": runtime.stats().duplicate(true),
		"all_models_intact": runtime.all_models_intact(),
	}

func _initialize() -> void:
	var built: Dictionary = FF.build_families()
	check(built.success, "build T13.5 family baseline", built)
	if not built.success:
		quit(1)
		return
	var bundles: Dictionary = built.details
	check(FF.compile_events == 42, "T13.5 selective compile baseline remains 42", FF.compile_events)
	DF.reset()

	var runtime = Runtime.new()
	for family_id in ["family-a", "family-b", "family-c", "family-d"]:
		var registered: Dictionary = runtime.register_family(family_id, bundles[family_id], bundles[family_id].capsule.checksum)
		check(registered.success, "register baseline " + family_id, registered)
	check(int(runtime.family_stats().unique_model_prepares) == 4, "four baseline family models prepared")
	check(int(runtime.family_stats().unique_subtree_hashes) == 42, "baseline subtree pool has 42 identities")
	check(runtime.all_models_intact(), "baseline models intact")

	var instances := {}
	var family_counts := {"family-a":0, "family-b":0, "family-c":0, "family-d":0}
	for i in range(INSTANCE_COUNT):
		var family_id := family_for(i)
		var created: Dictionary = runtime.create_instance(
			family_id,
			iid(i),
			"world/t15-slot-%03d" % (i + 1),
			0.76 + 0.00025 * float(i % 20),
			300.0 + 0.02 * float(i % 5)
		)
		check(created.success, "create instance " + iid(i), created)
		if created.success:
			instances[iid(i)] = created.details
			family_counts[family_id] += 1
	check(instances.size() == 100, "100 instances created")
	check(family_counts == {"family-a":40,"family-b":30,"family-c":20,"family-d":10}, "family population 40/30/20/10")
	check(int(runtime.family_stats().unique_model_prepares) == 4, "instances add no prepares")
	check(FF.compile_events == 42, "instances add no compiler work")

	var target_id := iid(TARGET_INDEX)
	var target: Dictionary = instances[target_id]
	check(family_for(TARGET_INDEX) == "family-b" and target.family_id == "family-b", "target is family-b instance 058")
	var original_model_ids := identities(runtime, ["family-a", "family-b", "family-c", "family-d"])
	var original_model_hash := U.canonical_hash(original_model_ids)
	var original_target_physical_hash := U.canonical_hash(target.state.physical)
	var original_emitter_hash := runtime.family_subtree_hash("family-b", TARGET_PATH)
	check(U.is_lower_hex_64(original_emitter_hash), "original emitter subtree anchored")

	# Healthy controls are captured before any structural fork. Runtime execution is caller-owned/pure.
	var controls := {}
	var control_metrics := {"runtime_steps":0,"evaluations":0,"boundary_calls":0,"compiled_group_visits":0,"leaf_traversals":0}
	for i in range(INSTANCE_COUNT):
		var id := iid(i)
		var control: Dictionary = runtime.execute(instances[id], commands_for(i), AMBIENT_K, DT)
		check(control.success, "healthy control execute " + id, control)
		if control.success:
			controls[id] = control.details
			add_metrics(control, control_metrics)
	check(int(control_metrics.runtime_steps) == 100, "100 healthy control steps")
	check(int(control_metrics.leaf_traversals) == 0, "healthy controls stay compact")

	# Source-side local UNBAKE/rebuild: one T9 emitter's 128 source gain cells only.
	var damaged_built: Dictionary = DF.rebuild_family_b_emitter(bundles["family-b"], false, true, 3)
	check(damaged_built.success, "build one-cell-disabled local successor", damaged_built)
	if not damaged_built.success:
		quit(1)
		return
	var damaged_bundle: Dictionary = damaged_built.details
	check(DF.compile_events == 5, "damage rebuild compiles leaf plus four ancestors only", DF.compile_events)
	check(DF.source_leaf_traversals == 128, "damage source traversal bounded to 128-cell emitter", DF.source_leaf_traversals)
	check(DF.source_anchor_checks == 1, "damage UNBAKE source graph anchored to compiled emitter")
	check(int(damaged_bundle.capsule.source_component_count) == 4275, "damaged ship keeps 4275 physical source components")

	# Transactional adversarial gate: a candidate can be structurally valid but
	# unable to accept the caller-owned physical state. Rejection must leave the
	# live registry byte/logically unchanged and the same family/event IDs reusable.
	var unsafe_built: Dictionary = DF.make_projection_unsafe_motor_candidate(bundles["family-b"])
	check(unsafe_built.success, "build valid projection-unsafe successor candidate", unsafe_built)
	if not unsafe_built.success:
		quit(1)
		return
	var unsafe_bundle: Dictionary = unsafe_built.details
	var old_servo_max := float(bundles["family-b"].children.bank.children.unit03.children.servo.descriptor.max_abs_motor_omega_rad_s)
	var new_servo_max := float(unsafe_bundle.children.bank.children.unit03.children.servo.descriptor.max_abs_motor_omega_rad_s)
	check(new_servo_max < old_servo_max, "adversarial successor tightens valid servo state envelope", {"old":old_servo_max,"new":new_servo_max})

	var atomic = Runtime.new()
	var atomic_registered: Dictionary = atomic.register_family("family-b", bundles["family-b"], bundles["family-b"].capsule.checksum)
	check(atomic_registered.success, "atomic probe registers baseline family", atomic_registered)
	var atomic_a_created: Dictionary = atomic.create_instance("family-b", "t15-atomic-a", "world/atomic-a", 0.8, 300.0)
	var atomic_b_created: Dictionary = atomic.create_instance("family-b", "t15-atomic-b", "world/atomic-b", 0.8, 300.0)
	check(atomic_a_created.success and atomic_b_created.success, "atomic probe creates two baseline instances", {"a":atomic_a_created,"b":atomic_b_created})
	var atomic_a: Dictionary = atomic_a_created.details
	var atomic_b: Dictionary = atomic_b_created.details
	var high_omega: Dictionary = atomic_a.duplicate(true)
	high_omega.state.physical.bank.unit03.servo.motor_angular_velocity_rad_s = 0.5 * (old_servo_max + new_servo_max)
	check(atomic.instance_valid(high_omega), "high-omega caller state remains valid in old family")
	var rejected_before := atomic_snapshot(atomic)
	var rejected: Dictionary = atomic.fork_instance(
		high_omega, "family-b-atomic-tight", unsafe_bundle, unsafe_bundle.capsule.checksum,
		"root/bank/unit03/servo/motor", "damage/t15-atomic-projection/1", "DAMAGE"
	)
	check(not rejected.success and rejected.error_code == "T15_STATE_PROJECTION_UNSAFE", "unsafe projection fails before live commit", rejected)
	var unsafe_reject_clean: bool = atomic_snapshot(atomic) == rejected_before
	check(unsafe_reject_clean, "unsafe projection rejection is transactionally side-effect free")
	check(atomic.family_identity("family-b-atomic-tight").is_empty(), "rejected successor family is not visible")
	check(atomic.instance_valid(high_omega) and atomic.instance_valid(atomic_b), "rejected fork keeps old bindings current")

	# Retry the exact same family/event after correcting only caller state. If the
	# rejected attempt leaked a route/event, this cannot succeed.
	var retry: Dictionary = atomic.fork_instance(
		atomic_a, "family-b-atomic-tight", unsafe_bundle, unsafe_bundle.capsule.checksum,
		"root/bank/unit03/servo/motor", "damage/t15-atomic-projection/1", "DAMAGE"
	)
	var retry_same_ids: bool = bool(retry.success)
	check(retry_same_ids, "same family/event IDs succeed after corrected retry", retry)
	check(not atomic.family_identity("family-b-atomic-tight").is_empty(), "successful retry commits successor family")

	# Alias and occupied-family rejects are also preflight-only. Neither may add a
	# route/model/receipt nor disturb the still-current second baseline instance.
	var alias_before := atomic_snapshot(atomic)
	var alias_reject: Dictionary = atomic.fork_instance(
		atomic_b, "family-b-atomic-alias", unsafe_bundle, unsafe_bundle.capsule.checksum,
		"root/bank/unit03/servo/motor", "damage/t15-atomic-alias/1", "DAMAGE"
	)
	check(not alias_reject.success and alias_reject.error_code == "T15_DIVERGENT_FAMILY_UNEXPECTEDLY_ALIASED", "existing model alias rejected before live mutation", alias_reject)
	var alias_reject_clean: bool = atomic_snapshot(atomic) == alias_before and atomic.family_identity("family-b-atomic-alias").is_empty()
	check(alias_reject_clean, "alias rejection leaks no family/accounting state")
	var occupied_reject: Dictionary = atomic.fork_instance(
		atomic_b, "family-b-atomic-tight", unsafe_bundle, unsafe_bundle.capsule.checksum,
		"root/bank/unit03/servo/motor", "damage/t15-atomic-occupied/1", "DAMAGE"
	)
	check(not occupied_reject.success and occupied_reject.error_code == "T15_FAMILY_ID_ALREADY_REGISTERED", "occupied successor family id rejected before live mutation", occupied_reject)
	var occupied_reject_clean: bool = atomic_snapshot(atomic) == alias_before and atomic.instance_valid(atomic_b)
	check(occupied_reject_clean, "occupied-id rejection leaves live state unchanged")

	# T14 observation and T15 structural mutation cannot coexist on the same old binding.
	var observed: Dictionary = runtime.request_observation(target, "root/bank/unit03/cannon", "observation/t15-pre-damage")
	check(observed.success, "T14 observation can inspect target before damage", observed)
	var blocked: Dictionary = runtime.fork_instance(target, DAMAGE_FAMILY, damaged_bundle, damaged_bundle.capsule.checksum, TARGET_PATH, DAMAGE_EVENT, "DAMAGE")
	check(not blocked.success and blocked.error_code == "T15_ACTIVE_OBSERVATION_MUST_RELEASE", "active observation must release before structural fork")
	var released: Dictionary = runtime.release_observation(target, "observation/t15-pre-damage")
	check(released.success, "release pre-damage observation")

	# Negative divergence anchors fail before family registration.
	var wrong_path: Dictionary = runtime.fork_instance(
		target, "family-b-bad-path", damaged_bundle, damaged_bundle.capsule.checksum,
		"root/bank/unit03/cannon/power", "damage/t15-bad-path", "DAMAGE"
	)
	check(not wrong_path.success and wrong_path.error_code == "T15_DIVERGENCE_NOT_LOCAL_TO_SELECTED_CHAIN", "wrong selected path rejected")
	var topology_tamper: Dictionary = damaged_bundle.duplicate(true)
	topology_tamper.children.bank.children.erase("unit02")
	var bad_shape: Dictionary = runtime.fork_instance(
		target, "family-b-bad-shape", topology_tamper, String(topology_tamper.capsule.checksum),
		TARGET_PATH, "damage/t15-bad-shape", "DAMAGE"
	)
	check(not bad_shape.success and bad_shape.error_code == "T15_TOPOLOGY_SHAPE_CHANGED", "unexpected topology shape change rejected before fork")
	check(int(runtime.family_stats().unique_model_prepares) == 4, "failed fork attempts prepare nothing")

	var damage: Dictionary = runtime.fork_instance(
		target, DAMAGE_FAMILY, damaged_bundle, damaged_bundle.capsule.checksum,
		TARGET_PATH, DAMAGE_EVENT, "DAMAGE"
	)
	check(damage.success, "fork only target instance onto damaged family", damage)
	if not damage.success:
		quit(1)
		return
	var damaged_instance: Dictionary = damage.details.next_instance
	var damage_receipt: Dictionary = damage.details.receipt
	var expected_paths := [
		"root",
		"root/bank",
		"root/bank/unit03",
		"root/bank/unit03/cannon",
		TARGET_PATH,
	]
	check(damage_receipt.changed_paths == expected_paths, "damage changes exactly leaf plus four ancestors", damage_receipt.changed_paths)
	check(int(damage_receipt.unchanged_paths) == 25, "other 25 compiled subtrees remain byte-identical")
	check(damage_receipt.old_family_id == "family-b" and damage_receipt.new_family_id == DAMAGE_FAMILY, "damage receipt records instance family fork")
	check(damage_receipt.old_binding_checksum != damage_receipt.new_binding_checksum, "fork creates a new binding identity")
	check(damage_receipt.physical_state_hash_before == damage_receipt.physical_state_hash_after, "fork projects physical state byte-exact")
	check(U.validate_checksum(damage_receipt).success, "damage receipt checksum valid")
	check(damaged_instance.binding.instance_id == target.binding.instance_id and damaged_instance.binding.world_slot == target.binding.world_slot, "semantic instance/world slot preserved")
	check(int(damaged_instance.state.state_revision) == int(target.state.state_revision) + 1, "damage projection advances state revision once")
	check(int(damaged_instance.state.damage_revision) == int(target.state.damage_revision) + 1, "damage projection advances damage revision once")
	check(U.canonical_hash(damaged_instance.state.physical) == original_target_physical_hash, "damage projection does not invent physical state")
	check(runtime.instance_valid(damaged_instance), "damaged fork is current and valid")
	check(not runtime.instance_valid(target), "old target binding is superseded")
	var stale_execute: Dictionary = runtime.execute(target, commands_for(TARGET_INDEX), AMBIENT_K, DT)
	check(not stale_execute.success and stale_execute.error_code == "T15_INSTANCE_SUPERSEDED", "superseded pre-damage binding cannot execute")
	var duplicate_event: Dictionary = runtime.fork_instance(
		damaged_instance, "family-b-duplicate-event", damaged_bundle, damaged_bundle.capsule.checksum,
		TARGET_PATH, DAMAGE_EVENT, "DAMAGE"
	)
	check(not duplicate_event.success and duplicate_event.error_code == "T15_EVENT_ALREADY_APPLIED", "damage event is idempotently fenced")

	var damage_stats: Dictionary = runtime.family_stats()
	check(int(damage_stats.unique_model_prepares) == 5, "one divergent instance adds one prepared family model")
	check(int(damage_stats.subtree_occurrences) == 150, "fifth family adds one 30-node manifest")
	check(int(damage_stats.unique_subtree_hashes) == 47, "damage introduces exactly five new subtree identities")
	check(int(damage_stats.subtree_reuse_hits) == 103, "damage reuses other 25 subtrees")
	check(runtime.family_subtree_hash(DAMAGE_FAMILY, TARGET_PATH) != original_emitter_hash, "damaged emitter subtree identity diverges")
	check(U.canonical_hash(identities(runtime, ["family-a","family-b","family-c","family-d"])) == original_model_hash, "four original family model identities unchanged after fork")
	check(runtime.all_models_intact(), "all family models intact after damage fork")

	# Only the selected instance changes physical behavior; the other 99 remain exact.
	var healthy_equivalent := 0
	var damaged_diverged := false
	var damage_metrics := {"runtime_steps":0,"evaluations":0,"boundary_calls":0,"compiled_group_visits":0,"leaf_traversals":0}
	var damaged_step: Dictionary = {}
	for i in range(INSTANCE_COUNT):
		var id := iid(i)
		var candidate_input: Dictionary = damaged_instance if i == TARGET_INDEX else instances[id]
		var candidate: Dictionary = runtime.execute(candidate_input, commands_for(i), AMBIENT_K, DT)
		check(candidate.success, "post-damage execute " + id, candidate)
		if not candidate.success:
			continue
		add_metrics(candidate, damage_metrics)
		if i == TARGET_INDEX:
			damaged_step = candidate
			damaged_diverged = candidate.details.physical != controls[id].physical
			check(damaged_diverged, "one-cell emitter damage changes target physical output")
			check(candidate.details.family_id == DAMAGE_FAMILY, "target executes fork family")
		else:
			var same: bool = candidate.details.next_instance == controls[id].next_instance and candidate.details.physical == controls[id].physical
			if same: healthy_equivalent += 1
			check(same, "unaffected instance remains exact " + id)
	check(healthy_equivalent == 99, "damage leaves other 99 instances exact-equivalent", healthy_equivalent)
	check(damaged_diverged, "damage target diverges")
	check(int(damage_metrics.runtime_steps) == 100 and int(damage_metrics.leaf_traversals) == 0, "post-damage steady execution stays compact")
	check(DF.compile_events == 5 and DF.source_leaf_traversals == 128, "steady execution adds no source rebuild work")
	check(FF.compile_events == 42, "baseline family compiler count remains frozen")

	# Advance the damaged state once more as a counterfactual before repair.
	check(damaged_step.success, "damaged target step available for repair continuation")
	var damaged_after_step: Dictionary = damaged_step.details.next_instance if damaged_step.success else damaged_instance
	var damaged_followup: Dictionary = runtime.execute(damaged_after_step, commands_for(TARGET_INDEX), AMBIENT_K, DT)
	check(damaged_followup.success, "damaged follow-up reference executes")

	# Repair the same source cell at a later canonical revision; again only five compiles / 128 leaves.
	var repaired_built: Dictionary = DF.rebuild_family_b_emitter(damaged_bundle, true, false, 4)
	check(repaired_built.success, "build repaired local successor", repaired_built)
	if not repaired_built.success:
		quit(1)
		return
	var repaired_bundle: Dictionary = repaired_built.details
	check(DF.compile_events == 10, "damage plus repair use ten selective compile events total")
	check(DF.source_leaf_traversals == 256, "damage plus repair traverse only two 128-cell emitter sources")
	check(DF.source_anchor_checks == 2, "damage and repair both anchor detailed source to current compiled leaf")
	var repair: Dictionary = runtime.fork_instance(
		damaged_after_step, REPAIR_FAMILY, repaired_bundle, repaired_bundle.capsule.checksum,
		TARGET_PATH, REPAIR_EVENT, "REPAIR"
	)
	check(repair.success, "repair forks target onto repaired family", repair)
	if not repair.success:
		quit(1)
		return
	var repaired_instance: Dictionary = repair.details.next_instance
	var repair_receipt: Dictionary = repair.details.receipt
	check(repair_receipt.changed_paths == expected_paths and int(repair_receipt.unchanged_paths) == 25, "repair changes the same bounded chain only")
	check(repair_receipt.physical_state_hash_before == repair_receipt.physical_state_hash_after, "repair projection preserves evolved physical state")
	check(int(repaired_instance.state.damage_revision) == 2, "damage plus repair produce two structural mutation revisions")
	check(U.canonical_hash(repaired_instance.state.physical) == U.canonical_hash(damaged_after_step.state.physical), "repair starts from damaged evolved state without reset")
	check(not runtime.instance_valid(damaged_after_step), "damaged binding superseded by repair")
	var stale_damaged: Dictionary = runtime.execute(damaged_after_step, commands_for(TARGET_INDEX), AMBIENT_K, DT)
	check(not stale_damaged.success and stale_damaged.error_code == "T15_INSTANCE_SUPERSEDED", "superseded damaged binding cannot execute after repair")

	var repair_stats: Dictionary = runtime.family_stats()
	check(int(repair_stats.unique_model_prepares) == 6, "repair adds one more prepared successor model")
	check(int(repair_stats.subtree_occurrences) == 180, "six families expose 180 subtree occurrences")
	check(int(repair_stats.unique_subtree_hashes) == 52, "repair adds exactly five revision-sensitive subtree identities")
	check(int(repair_stats.subtree_reuse_hits) == 128, "repair reuses another 25 unchanged subtrees")
	check(U.canonical_hash(identities(runtime, ["family-a","family-b","family-c","family-d"])) == original_model_hash, "original shared families remain immutable after repair")
	check(runtime.all_models_intact(), "all models intact after repair fork")

	# Independent healthy-family runtime: same physical state + repaired enabled emitter
	# must recover healthy boundary behavior despite different canonical revision/model identity.
	var reference_registry = Families.new()
	var ref_registered: Dictionary = reference_registry.register_family("family-b-ref", bundles["family-b"], bundles["family-b"].capsule.checksum)
	check(ref_registered.success, "prepare independent healthy family reference", ref_registered)
	var ref_created: Dictionary = reference_registry.create_instance("family-b-ref", "t15-repair-reference", "world/reference", 0.8, 300.0)
	check(ref_created.success, "create independent repair reference", ref_created)
	var reference_instance: Dictionary = ref_created.details if ref_created.success else {}
	if ref_created.success:
		reference_instance.state.physical = repaired_instance.state.physical.duplicate(true)
		reference_instance.state.state_revision = int(repaired_instance.state.state_revision)
		reference_instance.state.damage_revision = int(repaired_instance.state.damage_revision)
		check(reference_registry.instance_valid(reference_instance), "transplanted physical state valid in original healthy family")
	var repaired_step: Dictionary = runtime.execute(repaired_instance, commands_for(TARGET_INDEX), AMBIENT_K, DT)
	var healthy_reference_step: Dictionary = reference_registry.execute(reference_instance, commands_for(TARGET_INDEX), AMBIENT_K, DT)
	check(repaired_step.success and healthy_reference_step.success, "repaired and independent healthy reference execute", {"repair":repaired_step,"reference":healthy_reference_step})
	var repair_restored_behavior := false
	var repair_differs_from_damaged := false
	if repaired_step.success and healthy_reference_step.success:
		repair_restored_behavior = repaired_step.details.physical == healthy_reference_step.details.physical
		repair_differs_from_damaged = damaged_followup.success and repaired_step.details.physical != damaged_followup.details.physical
		check(repair_restored_behavior, "repair restores healthy boundary physics from preserved state")
		check(repair_differs_from_damaged, "repair physically differs from continuing damaged emitter")
		check(int(repaired_step.details.physical.metrics.leaf_traversals) == 0, "repaired steady execution is compact")

	var runtime_stats: Dictionary = runtime.stats()
	check(int(runtime_stats.fork_events) == 2, "exactly damage and repair commit two forks")
	check(int(runtime_stats.state_projection_events) == 2, "two state projections")
	check(int(runtime_stats.superseded_rejections) >= 2, "superseded bindings are actively fenced")
	check(int(runtime_stats.event_receipts) == 2, "two durable-style derived receipts held")
	check(int(runtime_stats.current_instances) == 100, "semantic instance population remains 100")
	check(int(runtime_stats.unique_model_prepares) == 6, "six unique prepared models final")
	check(FF.compile_events == 42 and DF.compile_events == 10, "compile accounting separates baseline 42 from two local 5-event rebuilds")
	check(DF.source_leaf_traversals == 256, "source traversal occurs only during two local rebuilds")
	check(runtime.all_models_intact(), "T15 final all model identities intact")

	var result := {
		"schema":"fabric.t15.result.v1",
		"failures":failures,
		"checks":checks,
		"instances":instances.size(),
		"family_counts":family_counts,
		"target_instance":target_id,
		"target_original_family":"family-b",
		"selected_path":TARGET_PATH,
		"baseline_compile_events":FF.compile_events,
		"damage_compile_events":5,
		"repair_compile_events":5,
		"local_compile_events_total":DF.compile_events,
		"source_leaf_traversals_rebuild":DF.source_leaf_traversals,
		"source_anchor_checks":DF.source_anchor_checks,
		"source_components_per_ship":int(bundles["family-b"].capsule.source_component_count),
		"changed_paths_per_mutation":expected_paths.size(),
		"unchanged_subtrees_per_mutation":25,
		"original_family_models":4,
		"final_family_models":int(repair_stats.unique_model_prepares),
		"final_unique_subtree_hashes":int(repair_stats.unique_subtree_hashes),
		"final_subtree_occurrences":int(repair_stats.subtree_occurrences),
		"final_subtree_reuse_hits":int(repair_stats.subtree_reuse_hits),
		"healthy_equivalent_after_damage":healthy_equivalent,
		"damaged_target_diverged":damaged_diverged,
		"repair_restored_healthy_behavior":repair_restored_behavior,
		"repair_differs_from_damaged_continuation":repair_differs_from_damaged,
		"physical_state_preserved_on_damage":damage_receipt.physical_state_hash_before == damage_receipt.physical_state_hash_after,
		"physical_state_preserved_on_repair":repair_receipt.physical_state_hash_before == repair_receipt.physical_state_hash_after,
		"final_damage_revision":int(repaired_instance.state.damage_revision),
		"steady_leaf_traversals_after_damage":int(damage_metrics.leaf_traversals),
		"fork_events":int(runtime_stats.fork_events),
		"state_projection_events":int(runtime_stats.state_projection_events),
		"superseded_rejections":int(runtime_stats.superseded_rejections),
		"event_receipts":int(runtime_stats.event_receipts),
		"current_instances":int(runtime_stats.current_instances),
		"original_models_intact":U.canonical_hash(identities(runtime, ["family-a","family-b","family-c","family-d"])) == original_model_hash,
		"all_models_intact":runtime.all_models_intact(),
		"atomicity_unsafe_reject_clean":unsafe_reject_clean,
		"atomicity_retry_same_ids":retry_same_ids,
		"atomicity_alias_reject_clean":alias_reject_clean,
		"atomicity_occupied_id_reject_clean":occupied_reject_clean,
	}
	print("FABRIC_R5_2_T15_RESULT=" + JSON.stringify(result, "", true, true))
	print("FABRIC R5.2 T15 LOCAL DAMAGE UNBAKE REBAKE: " + ("PASS" if failures.is_empty() else "FAIL") + " (%d assertions)" % checks)
	quit(0 if failures.is_empty() else 1)
