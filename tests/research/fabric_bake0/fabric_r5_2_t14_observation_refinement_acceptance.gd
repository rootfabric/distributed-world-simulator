extends SceneTree
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const T14 = preload("res://scripts/research/fabric_bake0/r5_t14_observation_refinement_runtime_v1.gd")
const FF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t13_5_family_fixture.gd")
const F = preload("res://tests/research/fabric_bake0/fabric_r5_2_t12_ship_fixture.gd")

const INSTANCE_COUNT := 100
const OBSERVED_INDEX := 57
const OBSERVATION_ID := "observation/t14-instance-058-cannon"
const REFINED_PATH := "root/bank/unit03/cannon"
const DT := 0.002
const AMBIENT_K := 294.0

var checks := 0
var failures: Array = []

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("T14: " + label + " " + JSON.stringify(details))

func iid(index: int) -> String:
	return "t14-instance-%03d" % (index + 1)

func family_for(index: int) -> String:
	if index < 40:
		return "family-a"
	if index < 70:
		return "family-b"
	if index < 90:
		return "family-c"
	return "family-d"

func commands_for(index: int) -> Dictionary:
	var laser := 175.0 + 12.5 * float(index % 6)
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

func model_identities(runtime, ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[String(id)] = runtime.family_identity(String(id))
	return out

func _initialize() -> void:
	var built: Dictionary = FF.build_families()
	check(built.success, "build T13.5 structural families", built)
	if not built.success:
		quit(1)
		return
	check(FF.compile_events == 42, "T14 starts from T13.5 selective compile baseline", FF.compile_events)
	var bundles: Dictionary = built.details

	var runtime = T14.new()
	for family_id in ["family-a", "family-b", "family-c", "family-d"]:
		var registered: Dictionary = runtime.register_family(family_id, bundles[family_id], bundles[family_id].capsule.checksum)
		check(registered.success, "register family " + family_id, registered)
		check(not bool(registered.details.get("deduplicated", true)), "unique family prepared " + family_id)
	check(int(runtime.family_stats().unique_model_prepares) == 4, "four unique family models prepared")
	check(runtime.all_models_intact(), "family models intact before observation")

	var instances := {}
	var family_counts := {"family-a":0, "family-b":0, "family-c":0, "family-d":0}
	for i in range(INSTANCE_COUNT):
		var family_id := family_for(i)
		var created: Dictionary = runtime.create_instance(
			family_id,
			iid(i),
			"world/t14-slot-%03d" % (i + 1),
			0.77 + 0.0002 * float(i % 20),
			300.0 + 0.015 * float(i % 7)
		)
		check(created.success, "create T14 instance " + iid(i), created)
		if created.success:
			check(runtime.instance_valid(created.details), "validate T14 instance " + iid(i))
			instances[iid(i)] = created.details
			family_counts[family_id] += 1

	check(instances.size() == 100, "100 instances created")
	check(family_counts == {"family-a":40, "family-b":30, "family-c":20, "family-d":10}, "family population 40/30/20/10")
	check(FF.compile_events == 42, "instance creation adds zero compile events")
	var caller_instances_hash_before := U.canonical_hash(instances)
	check(U.is_lower_hex_64(caller_instances_hash_before), "caller instance baseline hash valid")
	var model_ids_before := model_identities(runtime, ["family-a", "family-b", "family-c", "family-d"])
	var model_ids_hash_before := U.canonical_hash(model_ids_before)
	check(U.is_lower_hex_64(model_ids_hash_before), "model identity baseline hash valid")

	var initial_summary: Dictionary = runtime.resolution_summary(instances)
	check(int(initial_summary.refined_instances) == 0, "all instances initially compact")
	check(int(initial_summary.compact_instances) == 100, "100 compact before observation")
	check(int(initial_summary.active_refinements) == 0, "no active refinement before observation")

	var target_id := iid(OBSERVED_INDEX)
	var target: Dictionary = instances[target_id]
	check(String(target.family_id) == "family-b", "observed instance belongs to cooling variant family")
	check(runtime.path_resolution(target, REFINED_PATH) == "COMPACT", "selected path initially compact")
	check(runtime.family_subtree_hash("family-b", REFINED_PATH) != runtime.family_subtree_hash("family-a", REFINED_PATH), "selected cannon anchored to family-b variant")

	var root_reject: Dictionary = runtime.request_refinement(target, "root", "observation/root-forbidden")
	check(not root_reject.success and root_reject.error_code == "T14_ROOT_REFINEMENT_FORBIDDEN", "whole-root refinement rejected")
	var unknown_reject: Dictionary = runtime.request_refinement(target, "root/bank/unit99", "observation/unknown")
	check(not unknown_reject.success and unknown_reject.error_code == "T14_REFINEMENT_PATH_UNKNOWN", "unknown refinement path rejected")
	check(int(runtime.stats().active_refinements) == 0, "invalid requests do not create overlays")

	# Establish compact controls before the observation overlay exists.
	var controls := {}
	var metrics := {"runtime_steps":0, "evaluations":0, "boundary_calls":0, "compiled_group_visits":0, "leaf_traversals":0}
	for i in range(INSTANCE_COUNT):
		var id := iid(i)
		var before: Dictionary = instances[id].duplicate(true)
		var step: Dictionary = runtime.execute(instances[id], commands_for(i), AMBIENT_K, DT)
		check(step.success, "compact control execute " + id, step)
		if step.success:
			controls[id] = step.details
			add_metrics(step, metrics)
			check(String(step.details.active_refinement_path).is_empty(), "control has no active refinement " + id)
		check(instances[id] == before, "control execution leaves caller instance unchanged " + id)
	check(controls.size() == 100, "100 compact controls captured")

	var refined: Dictionary = runtime.request_refinement(target, REFINED_PATH, OBSERVATION_ID)
	check(refined.success, "request one observation-driven refinement", refined)
	if not refined.success:
		quit(1)
		return
	var metadata: Dictionary = refined.details.refinement
	var detail: Array = refined.details.detail
	check(metadata.schema == T14.REFINEMENT_SCHEMA, "refinement schema")
	check(metadata.observation_id == OBSERVATION_ID, "observation id bound")
	check(metadata.instance_id == target_id, "refinement bound to selected instance")
	check(metadata.family_id == "family-b", "refinement bound to selected family")
	check(metadata.path == REFINED_PATH, "refinement bound to selected path")
	check(metadata.subtree_hash == runtime.family_subtree_hash("family-b", REFINED_PATH), "refinement anchored to family subtree")
	check(U.is_lower_hex_64(String(metadata.compiled_model_hash)), "refinement model hash valid")
	check(U.is_lower_hex_64(String(metadata.detail_manifest_hash)), "detail manifest hash valid")
	check(int(metadata.detail_node_count) == 4, "cannon refinement materializes four compiled nodes")
	check(int(metadata.detail_leaf_count) == 3, "cannon refinement has three compiled leaves")
	check(detail.size() == 4, "detail manifest contains four nodes")
	var detail_paths := []
	var detail_kinds := []
	for row in detail:
		detail_paths.append(String(row.path))
		detail_kinds.append(String(row.kind))
		check(U.is_lower_hex_64(String(row.subtree_hash)), "detail subtree hash valid " + String(row.path))
		check(U.is_lower_hex_64(String(row.capsule_checksum)), "detail capsule checksum valid " + String(row.path))
	check(detail_paths == [
		"root/bank/unit03/cannon",
		"root/bank/unit03/cannon/cooling",
		"root/bank/unit03/cannon/emitter",
		"root/bank/unit03/cannon/power",
	], "detail paths are exactly selected cannon subtree")
	detail_kinds.sort()
	check(detail_kinds == ["COOLING_LOOP", "LASER_CANNON", "LASER_EMITTER", "POWER_STAGE"], "detail kinds cover cannon compiled components")
	check(int(refined.details.source_leaf_traversals) == 0, "observation performs zero source-leaf traversal")
	check(int(refined.details.recompile_events) == 0, "observation performs zero recompile")
	check(int(refined.details.unique_model_prepares) == 4, "observation performs zero model prepare")
	check(FF.compile_events == 42, "observation adds zero compile events")

	var summary: Dictionary = runtime.resolution_summary(instances)
	check(int(summary.refined_instances) == 1, "exactly one refined instance")
	check(int(summary.compact_instances) == 99, "other 99 instances remain compact")
	check(int(summary.active_refinements) == 1, "exactly one active refinement")
	check(runtime.path_resolution(target, REFINED_PATH) == "DETAILED", "selected cannon is detailed")
	check(runtime.path_resolution(target, REFINED_PATH + "/cooling") == "DETAILED", "selected subtree descendants are detailed")
	check(runtime.path_resolution(target, "root/bank/unit03") == "MIXED", "selected subtree ancestor is mixed")
	var sibling_paths := [
		"root/battery",
		"root/bank/unit01",
		"root/bank/unit02",
		"root/bank/unit03/servo",
		"root/bank/unit03/drive",
	]
	var compact_siblings := 0
	for path in sibling_paths:
		var compact := runtime.path_resolution(target, path) == "COMPACT"
		if compact:
			compact_siblings += 1
		check(compact, "same-instance sibling remains compact " + path)
	check(compact_siblings == 5, "all five same-instance sibling regions remain compact")

	var other_compact := 0
	for i in range(INSTANCE_COUNT):
		if i == OBSERVED_INDEX:
			continue
		var compact := runtime.path_resolution(instances[iid(i)], REFINED_PATH) == "COMPACT"
		if compact:
			other_compact += 1
		check(compact, "other instance remains compact " + iid(i))
	check(other_compact == 99, "all other 99 instances remain compact")

	# Returned detail is caller-owned; mutating it cannot corrupt the active overlay.
	var returned_detail: Array = refined.details.detail
	returned_detail[0].path = "caller/mutated"
	var stored_info: Dictionary = runtime.refinement_info(target)
	check(String(stored_info.detail[0].path) == REFINED_PATH, "caller detail mutation cannot alter stored refinement")
	check(U.canonical_hash(stored_info.detail) == String(metadata.detail_manifest_hash), "stored detail manifest remains intact")

	var second_request: Dictionary = runtime.request_refinement(target, "root/bank/unit03/servo", "observation/second")
	check(not second_request.success and second_request.error_code == "T14_INSTANCE_ALREADY_REFINED", "second concurrent refinement on same instance rejected")

	# Observation overlay must not affect physics for the selected instance or any sibling.
	var physics_equivalent := 0
	for i in range(INSTANCE_COUNT):
		var id := iid(i)
		var before: Dictionary = instances[id].duplicate(true)
		var candidate: Dictionary = runtime.execute(instances[id], commands_for(i), AMBIENT_K, DT)
		check(candidate.success, "observed candidate execute " + id, candidate)
		if candidate.success and controls.has(id):
			add_metrics(candidate, metrics)
			var same: bool = candidate.details.next_instance == controls[id].next_instance and candidate.details.physical == controls[id].physical
			if same:
				physics_equivalent += 1
			check(same, "observation leaves physics exact-equivalent " + id)
			var expected_path := REFINED_PATH if i == OBSERVED_INDEX else ""
			check(candidate.details.active_refinement_path == expected_path, "execution reports only selected overlay " + id)
			check(int(candidate.details.instance_compile_events) == 0 and int(candidate.details.recompile_events) == 0, "execution never compiles after observation " + id)
		check(instances[id] == before, "candidate execution leaves caller instance unchanged " + id)
	check(physics_equivalent == 100, "all 100 physics results exact-equivalent after observation")

	check(U.canonical_hash(instances) == caller_instances_hash_before, "observation leaves all caller instance state unchanged")
	check(U.canonical_hash(model_identities(runtime, ["family-a", "family-b", "family-c", "family-d"])) == model_ids_hash_before, "observation leaves family model identities unchanged")
	check(runtime.all_models_intact(), "all family models intact during observation")
	check(FF.compile_events == 42, "runtime observation path still adds zero compile work")
	check(int(metrics.runtime_steps) == 200, "200 compact/observed execution steps")
	check(int(metrics.leaf_traversals) == 0, "physics execution remains compact with zero source leaf traversal")
	check(int(metrics.compiled_group_visits) == 12 * int(metrics.evaluations), "compiled group accounting exact")
	check(int(metrics.boundary_calls) == 19 * int(metrics.evaluations), "boundary accounting exact")

	# Snapshot/restore re-materializes the same detail from the frozen family model.
	var snap: Dictionary = runtime.snapshot_refinement(target)
	check(snap.success, "snapshot active refinement", snap)
	check(U.is_lower_hex_64(String(snap.details.sha256)), "refinement snapshot hash valid")
	var wrong_release: Dictionary = runtime.release_refinement(target, "observation/wrong")
	check(not wrong_release.success and wrong_release.error_code == "T14_OBSERVATION_ID_MISMATCH", "wrong observation id cannot release refinement")
	var released: Dictionary = runtime.release_refinement(target, OBSERVATION_ID)
	check(released.success and int(released.details.active_refinements) == 0, "release selected refinement")
	summary = runtime.resolution_summary(instances)
	check(int(summary.refined_instances) == 0 and int(summary.compact_instances) == 100, "release returns all 100 instances to compact")
	check(runtime.path_resolution(target, REFINED_PATH) == "COMPACT", "selected path compact after release")
	var no_snapshot: Dictionary = runtime.snapshot_refinement(target)
	check(not no_snapshot.success and no_snapshot.error_code == "T14_REFINEMENT_NOT_ACTIVE", "cannot snapshot inactive refinement")

	var cross_instance: Dictionary = instances[iid(OBSERVED_INDEX + 1)]
	var cross_restore: Dictionary = runtime.restore_refinement(cross_instance, snap.details.text, snap.details.sha256)
	check(not cross_restore.success and cross_restore.error_code == "T14_SNAPSHOT_INSTANCE_MISMATCH", "snapshot cannot restore onto another instance")
	var tampered_text := String(snap.details.text) + " "
	var tampered_restore: Dictionary = runtime.restore_refinement(target, tampered_text, snap.details.sha256)
	check(not tampered_restore.success and tampered_restore.error_code == "T14_SNAPSHOT_ANCHOR_MISMATCH", "snapshot byte tamper rejected")

	var restored: Dictionary = runtime.restore_refinement(target, snap.details.text, snap.details.sha256)
	check(restored.success, "restore observation refinement", restored)
	if restored.success:
		check(restored.details.refinement == metadata, "restored refinement metadata exact")
		check(U.canonical_hash(restored.details.detail) == String(metadata.detail_manifest_hash), "restored detail manifest exact")
		check(runtime.path_resolution(target, REFINED_PATH) == "DETAILED", "restored selected path detailed")
		check(int(restored.details.recompile_events) == 0 and int(restored.details.source_leaf_traversals) == 0, "restore neither recompiles nor traverses source leaves")
	var final_release: Dictionary = runtime.release_refinement(target, OBSERVATION_ID)
	check(final_release.success, "release restored refinement")
	summary = runtime.resolution_summary(instances)
	check(int(summary.refined_instances) == 0 and int(summary.compact_instances) == 100, "final state returns all instances compact")

	var stats: Dictionary = runtime.stats()
	check(int(stats.successful_requests) == 1, "one successful observation request")
	check(int(stats.restore_count) == 1, "one successful restore")
	check(int(stats.release_count) == 2, "two successful releases")
	check(int(stats.materialization_count) == 2, "request plus restore materialize twice")
	check(int(stats.compiled_nodes_visited) == 8, "only four-node subtree visited twice")
	check(int(stats.source_leaf_traversals) == 0, "T14 observation never traverses source leaves")
	check(int(stats.recompile_events) == 0, "T14 observation never recompiles")
	check(int(stats.active_refinements) == 0, "no refinement leak after release")
	check(int(stats.unique_model_prepares) == 4, "T14 observation adds zero family prepare")
	check(FF.compile_events == 42, "T14 final compile count unchanged")
	check(U.canonical_hash(instances) == caller_instances_hash_before, "T14 final caller state byte-equivalent")
	check(runtime.all_models_intact(), "T14 final family models intact")

	var result := {
		"schema":"fabric.t14.result.v1",
		"failures":failures,
		"checks":checks,
		"instances":instances.size(),
		"family_counts":family_counts,
		"compile_events":FF.compile_events,
		"unique_family_models":int(runtime.family_stats().unique_model_prepares),
		"observed_instance":target_id,
		"observed_family":"family-b",
		"refined_path":REFINED_PATH,
		"detail_node_count":int(metadata.detail_node_count),
		"detail_leaf_count":int(metadata.detail_leaf_count),
		"selected_subtree_hash":String(metadata.subtree_hash),
		"detail_manifest_hash":String(metadata.detail_manifest_hash),
		"refined_instances_during_observation":1,
		"compact_instances_during_observation":99,
		"same_instance_compact_siblings":compact_siblings,
		"other_compact_instances":other_compact,
		"physics_equivalent_after_refinement":physics_equivalent,
		"snapshot_roundtrip":restored.success,
		"successful_requests":int(stats.successful_requests),
		"restore_count":int(stats.restore_count),
		"release_count":int(stats.release_count),
		"materialization_count":int(stats.materialization_count),
		"compiled_nodes_visited":int(stats.compiled_nodes_visited),
		"source_leaf_traversals":int(stats.source_leaf_traversals),
		"recompile_events":int(stats.recompile_events),
		"active_refinements_final":int(stats.active_refinements),
		"runtime_steps":int(metrics.runtime_steps),
		"evaluations":int(metrics.evaluations),
		"boundary_calls":int(metrics.boundary_calls),
		"compiled_group_visits":int(metrics.compiled_group_visits),
		"physics_leaf_traversals":int(metrics.leaf_traversals),
		"caller_instances_unchanged":U.canonical_hash(instances) == caller_instances_hash_before,
		"model_identities_unchanged":U.canonical_hash(model_identities(runtime, ["family-a", "family-b", "family-c", "family-d"])) == model_ids_hash_before,
		"all_models_intact":runtime.all_models_intact(),
	}
	print("FABRIC_R5_2_T14_RESULT=" + JSON.stringify(result, "", true, true))
	print("FABRIC R5.2 T14 OBSERVATION REFINEMENT: " + ("PASS" if failures.is_empty() else "FAIL") + " (%d assertions)" % checks)
	quit(0 if failures.is_empty() else 1)
