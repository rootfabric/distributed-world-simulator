extends SceneTree
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Families = preload("res://scripts/research/fabric_bake0/r5_t13_5_shared_families_runtime_v1.gd")
const FF = preload("res://tests/research/fabric_bake0/fabric_r5_2_t13_5_family_fixture.gd")
const F = preload("res://tests/research/fabric_bake0/fabric_r5_2_t12_ship_fixture.gd")

const INSTANCE_COUNT := 100
const DAMAGE_INDEX := 57
const DT := 0.002
const AMBIENT_K := 294.0

var checks := 0
var failures: Array = []

func check(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("T13.5: " + label + " " + JSON.stringify(details))

func iid(index: int) -> String:
	return "family-instance-%03d" % (index + 1)

func family_for(index: int) -> String:
	if index < 40:
		return "family-a"
	if index < 70:
		return "family-b"
	if index < 90:
		return "family-c"
	return "family-d"

func commands_for(index: int) -> Dictionary:
	var laser := 170.0 + 15.0 * float(index % 6)
	var position := -0.10 + 0.05 * float(index % 5)
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

func same_path(registry, families: Array, path: String) -> bool:
	var first: String = registry.family_subtree_hash(String(families[0]), path)
	if first.is_empty():
		return false
	for i in range(1, families.size()):
		if registry.family_subtree_hash(String(families[i]), path) != first:
			return false
	return true

func _initialize() -> void:
	var built: Dictionary = FF.build_families()
	check(built.success, "build four structural families", built)
	if not built.success:
		quit(1)
		return
	var bundles: Dictionary = built.details
	check(FF.compile_events == 42, "selective family compile work is exactly 42 events", FF.compile_events)
	var full_family_baseline_compile_events := 4 * 30
	check(full_family_baseline_compile_events - FF.compile_events == 78, "cross-family subtree reuse avoids 78 compile events")
	for id in ["family-a", "family-b", "family-c", "family-d"]:
		check(bundles.has(id), "family bundle exists " + id)
		check(int(bundles[id].capsule.source_component_count) == 4275, "family retains 4275 source components " + id)

	var registry = Families.new()
	for id in ["family-a", "family-b", "family-c", "family-d"]:
		var registered: Dictionary = registry.register_family(id, bundles[id], bundles[id].capsule.checksum)
		check(registered.success, "register " + id, registered)
		check(not bool(registered.details.get("deduplicated", true)), "unique family prepared once " + id)
		check(int(registered.details.get("unique_model_prepares", -1)) >= 1, "prepare accounting available " + id)

	var alias: Dictionary = registry.register_family("family-a-copy", bundles["family-a"], bundles["family-a"].capsule.checksum)
	check(alias.success, "register exact duplicate family alias", alias)
	check(bool(alias.details.get("deduplicated", false)), "exact duplicate family does not prepare again")
	check(alias.details.get("owner_family_id") == "family-a", "duplicate family routes to canonical owner")

	var reuse: Dictionary = registry.reuse_stats()
	check(int(reuse.family_registrations) == 5, "five family registrations including alias")
	check(int(reuse.alias_registrations) == 1, "one exact family alias")
	check(int(reuse.unique_model_prepares) == 4, "four unique full family prepares")
	check(int(reuse.subtree_occurrences) == 120, "four 30-node family manifests")
	check(int(reuse.unique_subtree_hashes) == 42, "42 unique compiled subtree identities")
	check(int(reuse.subtree_intern_events) == 42, "subtree pool interns each unique identity once")
	check(int(reuse.subtree_reuse_hits) == 78, "78 subtree occurrences reuse pooled identities")
	check(int(reuse.shared_subtree_hashes) == 29, "29 subtree identities shared by multiple families")
	check(int(reuse.max_family_reuse) == 4, "unchanged subtrees reused across all four families")

	# Structural-family relations: selective deltas rebuild only the affected path and ancestors.
	check(same_path(registry, ["family-a", "family-b", "family-d"], "root/battery"), "LFP battery reused by A/B/D")
	check(registry.family_subtree_hash("family-a", "root/battery") != registry.family_subtree_hash("family-c", "root/battery"), "NMC battery creates distinct subtree")
	check(same_path(registry, ["family-a", "family-c"], "root/bank"), "battery-only variant reuses complete bank")
	check(registry.family_subtree_hash("family-a", "root/bank") != registry.family_subtree_hash("family-b", "root/bank"), "cooling delta rebuilds bank ancestor")
	check(registry.family_subtree_hash("family-a", "root/bank") != registry.family_subtree_hash("family-d", "root/bank"), "emitter delta rebuilds bank ancestor")
	check(same_path(registry, ["family-a", "family-b", "family-c", "family-d"], "root/bank/unit01"), "unit01 reused across all families")
	check(same_path(registry, ["family-a", "family-b", "family-c", "family-d"], "root/bank/unit02"), "unit02 reused across all families")
	check(same_path(registry, ["family-a", "family-b", "family-c", "family-d"], "root/bank/unit03/cannon/power"), "unit03 cannon power reused across all families")
	check(same_path(registry, ["family-a", "family-b", "family-c"], "root/bank/unit03/cannon/emitter"), "GAAS emitter reused by A/B/C")
	check(registry.family_subtree_hash("family-a", "root/bank/unit03/cannon/emitter") != registry.family_subtree_hash("family-d", "root/bank/unit03/cannon/emitter"), "GAN emitter is distinct")
	check(same_path(registry, ["family-a", "family-c", "family-d"], "root/bank/unit03/cannon/cooling"), "water cooling reused by A/C/D")
	check(registry.family_subtree_hash("family-a", "root/bank/unit03/cannon/cooling") != registry.family_subtree_hash("family-b", "root/bank/unit03/cannon/cooling"), "glycol cooling is distinct")
	check(same_path(registry, ["family-a", "family-b", "family-c", "family-d"], "root/bank/unit03/servo"), "unit03 servo reused across all families")
	check(same_path(registry, ["family-a", "family-b", "family-c", "family-d"], "root/bank/unit03/drive"), "unit03 drive reused across all families")

	var root_hashes := {}
	for id in ["family-a", "family-b", "family-c", "family-d"]:
		var root_hash: String = registry.family_subtree_hash(id, "root")
		check(U.is_lower_hex_64(root_hash), "family root hash valid " + id)
		check(not root_hashes.has(root_hash), "family root model unique " + id)
		root_hashes[root_hash] = true
	check(root_hashes.size() == 4, "four distinct family root models")
	check(registry.all_models_intact(), "all prepared family models intact before instances")

	var instances := {}
	var family_counts := {"family-a":0, "family-b":0, "family-c":0, "family-d":0}
	for i in range(INSTANCE_COUNT):
		var family_id := family_for(i)
		var created: Dictionary = registry.create_instance(
			family_id,
			iid(i),
			"world/family-slot-%03d" % (i + 1),
			0.76 + 0.00025 * float(i % 20),
			300.0 + 0.02 * float(i % 5)
		)
		check(created.success, "create family instance " + iid(i), created)
		if created.success:
			check(registry.instance_valid(created.details), "family instance valid " + iid(i))
			instances[iid(i)] = created.details
			family_counts[family_id] += 1

	check(instances.size() == 100, "100 heterogeneous family instances created")
	check(family_counts == {"family-a":40, "family-b":30, "family-c":20, "family-d":10}, "family population 40/30/20/10")
	reuse = registry.reuse_stats()
	check(int(reuse.instance_count) == 100, "registry counts 100 instances")
	check(int(reuse.unique_model_prepares) == 4, "100 instances add zero family prepares")
	check(FF.compile_events == 42, "100 instances add zero compile events")

	var crossed: Dictionary = instances[iid(0)].duplicate(true)
	crossed.family_id = "family-b"
	check(not registry.instance_valid(crossed), "instance state cannot cross structural family")

	var damaged_id := iid(DAMAGE_INDEX)
	check(family_for(DAMAGE_INDEX) == "family-b", "damage target belongs to cooling variant family")
	var damaged: Dictionary = registry.apply_damage(instances[damaged_id], true)
	check(damaged.success, "damage one family instance", damaged)
	var damaged_instance: Dictionary = damaged.details.next_instance if damaged.success else {}
	if damaged.success:
		check(int(damaged_instance.state.damage_revision) == 1 and bool(damaged_instance.state.disabled), "damage remains instance-local")
		check(int(damaged.details.instance_compile_events) == 0, "damage causes no compile")

	var metrics := {"runtime_steps":0, "evaluations":0, "boundary_calls":0, "compiled_group_visits":0, "leaf_traversals":0}
	var healthy_equivalent := 0
	var damaged_diverged := false
	for i in range(INSTANCE_COUNT):
		var id := iid(i)
		var control: Dictionary = registry.execute(instances[id], commands_for(i), AMBIENT_K, DT)
		var candidate_input: Dictionary = damaged_instance if i == DAMAGE_INDEX else instances[id]
		var candidate: Dictionary = registry.execute(candidate_input, commands_for(i), AMBIENT_K, DT)
		check(control.success and candidate.success, "family control/candidate execute " + id, {"control":control, "candidate":candidate})
		if not control.success or not candidate.success:
			continue
		add_metrics(control, metrics)
		add_metrics(candidate, metrics)
		check(control.details.family_id == family_for(i) and candidate.details.family_id == family_for(i), "execution routed to expected family " + id)
		check(int(control.details.instance_compile_events) == 0 and int(candidate.details.instance_compile_events) == 0, "instance execution never compiles " + id)
		check(int(control.details.prepare_count) == 4 and int(candidate.details.prepare_count) == 4, "family prepare count stable " + id)
		if i == DAMAGE_INDEX:
			damaged_diverged = candidate.details.next_instance.state != control.details.next_instance.state
			check(damaged_diverged, "damaged family instance diverges")
		else:
			var same: bool = candidate.details.next_instance == control.details.next_instance and candidate.details.physical == control.details.physical
			if same:
				healthy_equivalent += 1
			check(same, "other family instance exact-equivalent " + id)

	check(healthy_equivalent == 99, "one damage leaves other 99 exact-equivalent", healthy_equivalent)
	check(damaged_diverged, "damage target behavior diverged")
	check(int(metrics.runtime_steps) == 200, "200 control/candidate runtime steps")
	check(int(metrics.leaf_traversals) == 0, "all heterogeneous instances stay on compact execution")
	check(int(metrics.compiled_group_visits) == 12 * int(metrics.evaluations), "battery group accounting exact")
	check(int(metrics.boundary_calls) == 19 * int(metrics.evaluations), "boundary accounting exact")
	check(FF.compile_events == 42, "runtime and damage do not add compile work")
	check(registry.all_models_intact(), "all shared family models intact after execution")

	reuse = registry.reuse_stats()
	var deterministic := {
		"schema":"fabric.t13_5.result.v1",
		"failures":failures,
		"checks":checks,
		"instances":instances.size(),
		"family_counts":family_counts,
		"family_registrations":int(reuse.family_registrations),
		"family_aliases":int(reuse.alias_registrations),
		"unique_family_models":int(reuse.unique_model_prepares),
		"compile_events":FF.compile_events,
		"full_family_baseline_compile_events":full_family_baseline_compile_events,
		"cross_family_compile_events_avoided":full_family_baseline_compile_events - FF.compile_events,
		"no_cache_instance_compile_events":INSTANCE_COUNT * 30,
		"combined_no_cache_events_avoided":INSTANCE_COUNT * 30 - FF.compile_events,
		"subtree_occurrences":int(reuse.subtree_occurrences),
		"unique_subtree_hashes":int(reuse.unique_subtree_hashes),
		"shared_subtree_hashes":int(reuse.shared_subtree_hashes),
		"subtree_intern_events":int(reuse.subtree_intern_events),
		"subtree_reuse_hits":int(reuse.subtree_reuse_hits),
		"max_family_reuse":int(reuse.max_family_reuse),
		"runtime_steps":int(metrics.runtime_steps),
		"evaluations":int(metrics.evaluations),
		"boundary_calls":int(metrics.boundary_calls),
		"compiled_group_visits":int(metrics.compiled_group_visits),
		"leaf_traversals":int(metrics.leaf_traversals),
		"damaged_instance":damaged_id,
		"damaged_family":"family-b",
		"damage_revision":int(damaged_instance.get("state", {}).get("damage_revision", -1)),
		"healthy_equivalent_after_damage":healthy_equivalent,
		"damaged_diverged":damaged_diverged,
		"all_models_intact":registry.all_models_intact(),
	}
	print("FABRIC_R5_2_T13_5_RESULT=" + JSON.stringify(deterministic, "", true, true))
	print("FABRIC R5.2 T13.5 SHARED FAMILIES: " + ("PASS" if failures.is_empty() else "FAIL") + " (%d assertions)" % checks)
	quit(0 if failures.is_empty() else 1)
