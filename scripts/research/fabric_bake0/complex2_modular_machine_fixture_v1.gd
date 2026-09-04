extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Slice = preload("res://scripts/research/fabric_bake0/bridge2_source_slice_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge2_region_adapter_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/bridge2_mixed_runtime_v1.gd")
const Complex1A = preload("res://tests/research/fabric_bake0/fabric_bake_complex1a_fixture.gd")

const SCHEMA := "planet_simulator.fabric_complex2_modular_machine_r1.v1"
const PART_COUNT := 2000
const MODULE_COUNT := 25
const PARTS_PER_MODULE := 80
const MOVING_SUBSYSTEM_COUNT := 6
const CONTACT_ZONE_COUNT := 3
const FUNCTIONAL_PATH_COUNT := 2
const DT := 0.01

const REGION_STRUCTURAL := "region/complex2-structural"
const REGION_FULL := "region/complex2-full"
const REGION_CONTACT := "region/complex2-contact"
const REGION_DYNAMIC := "region/complex2-dynamic"
const REGION_HYBRID := "region/complex2-hybrid"

const STATE_STRUCTURAL := "state/complex2-structural"
const STATE_FULL := "state/complex2-full"
const STATE_CONTACT := "state/complex2-contact"
const STATE_DYNAMIC := "state/complex2-dynamic"
const STATE_HYBRID := "state/complex2-hybrid"

const DETACH_MODULE_ID := "module/complex2-24"
const DETACH_SUPPORT_ID := "support/complex2-23-24"
const SECOND_SUPPORT_ID := "support/complex2-10-11"
const EVENT_DETACH := "event/complex2-detach-module-24"
const EVENT_SECOND := "event/complex2-break-drive-support"
const EVENT_SWAP := "event/complex2-stabilized-representation-swap"

static func build() -> Dictionary:
	var modules := _modules()
	var supports := _supports()
	var parts := _parts(modules)
	var movers := _moving_subsystems()
	var contacts := _contact_zones()
	var functional_subject := _functional_subject()
	var master := _master_source({})
	if master.is_empty():
		return _failure("COMPLEX2_MASTER_SOURCE_FAILED")
	var registry := _registry(master)
	if registry.is_empty():
		return _failure("COMPLEX2_MIXED_REGISTRY_FAILED")
	var subject := {
		"success": true,
		"schema": SCHEMA,
		"revision": 100,
		"parts": parts,
		"modules": modules,
		"supports": supports,
		"moving_subsystems": movers,
		"contact_zones": contacts,
		"functional_subject": functional_subject,
		"applied_event_ids": [],
		"master": master,
		"registry": registry,
		"initial_state": _initial_state(),
	}
	subject["machine_hash"] = _machine_hash(subject)
	return subject

static func run_experiment() -> Dictionary:
	var subject := build()
	if not bool(subject.get("success", false)):
		return subject
	var registry: Dictionary = subject["registry"]
	var started := Runtime.start(registry, subject["initial_state"])
	if not bool(started.get("success", false)):
		return _failure("COMPLEX2_SESSION_START_FAILED", started)
	var session: Dictionary = started["details"]["session"]
	var reference: Dictionary = subject["initial_state"].duplicate(true)
	var max_full_delta := 0.0

	var normal := _run_mixed_reference(
		session,
		registry,
		reference,
		8,
		{REGION_DYNAMIC: 0.32, REGION_HYBRID: -0.08}
	)
	if not bool(normal.get("success", false)):
		return normal
	session = normal["session"]
	reference = normal["reference"]
	max_full_delta = maxf(max_full_delta, float(normal["max_delta"]))
	var normal_state := Dictionary(session["state_values"]).duplicate(true)

	var contact_input := {REGION_CONTACT: 0.90}
	var contact := _run_mixed_reference(session, registry, reference, 1, contact_input)
	if not bool(contact.get("success", false)):
		return contact
	session = contact["session"]
	reference = contact["reference"]
	max_full_delta = maxf(max_full_delta, float(contact["max_delta"]))
	var contact_state := Dictionary(session["state_values"]).duplicate(true)
	var contact_state_delta := absf(float(contact_state[STATE_CONTACT]) - float(normal_state[STATE_CONTACT]))

	var power_before := Complex1A.solve(subject["functional_subject"])
	if not bool(power_before.get("success", false)):
		return _failure("COMPLEX2_POWER_BASELINE_FAILED", power_before)

	var detached := _apply_support_break(subject, DETACH_SUPPORT_ID, EVENT_DETACH)
	if not bool(detached.get("success", false)):
		return detached
	subject = detached["subject"]
	var components_after_detach := _module_components(subject)
	var detached_component := _component_containing(components_after_detach, DETACH_MODULE_ID)
	if detached_component != [DETACH_MODULE_ID]:
		return _failure("COMPLEX2_DETACH_COMPONENT_MISMATCH", {"component": detached_component})

	var power_detach := Complex1A.apply_structural_break(
		subject["functional_subject"], DETACH_SUPPORT_ID, EVENT_DETACH
	)
	if not bool(power_detach.get("success", false)):
		return _failure("COMPLEX2_DETACH_FUNCTIONAL_MUTATION_FAILED", power_detach)
	subject["functional_subject"] = power_detach["subject"]
	var power_after_detach := Complex1A.solve(subject["functional_subject"])
	if not bool(power_after_detach.get("success", false)):
		return _failure("COMPLEX2_POWER_AFTER_DETACH_FAILED", power_after_detach)

	var master_after_detach := _master_source({REGION_HYBRID: 1})
	var invalidated_detach := Runtime.apply_master_update(
		session,
		registry,
		master_after_detach["frontier"],
		master_after_detach["authority"],
		2100
	)
	if not bool(invalidated_detach.get("success", false)):
		return _failure("COMPLEX2_DETACH_INVALIDATION_FAILED", invalidated_detach)
	session = invalidated_detach["details"]["session"]
	var detach_affected: Array = Array(invalidated_detach["details"]["affected_regions"]).duplicate()
	var blocked_detach := Runtime.step(session, registry, {}, DT)
	if bool(blocked_detach.get("success", false)):
		return _failure("COMPLEX2_STALE_DETACH_REGION_EXECUTED", blocked_detach)
	var rebuilt_hybrid := _rebuild_one(session, registry, REGION_HYBRID, 2)
	if not bool(rebuilt_hybrid.get("success", false)):
		return rebuilt_hybrid
	session = rebuilt_hybrid["session"]
	registry = rebuilt_hybrid["registry"]

	var stabilize := _run_mixed_reference(session, registry, reference, 6, {})
	if not bool(stabilize.get("success", false)):
		return stabilize
	session = stabilize["session"]
	reference = stabilize["reference"]
	max_full_delta = maxf(max_full_delta, float(stabilize["max_delta"]))

	var full_region := Registry.region_by_id(registry, REGION_FULL)
	var hybrid_region := Registry.region_by_id(registry, REGION_HYBRID)
	var full_to_hybrid := Adapter.create(
		REGION_FULL,
		"HYBRID_BAKE",
		String(full_region["state_id"]),
		full_region["adapter"]["source_slice"],
		_backend_hash("HYBRID_BAKE"),
		float(full_region["adapter"]["storage"]),
		float(full_region["adapter"]["damping"]),
		2
	)
	var hybrid_to_full := Adapter.create(
		REGION_HYBRID,
		"FULL",
		String(hybrid_region["state_id"]),
		hybrid_region["adapter"]["source_slice"],
		_backend_hash("FULL"),
		float(hybrid_region["adapter"]["storage"]),
		float(hybrid_region["adapter"]["damping"]),
		2
	)
	if full_to_hybrid.is_empty() or hybrid_to_full.is_empty():
		return _failure("COMPLEX2_SWAP_ADAPTER_BUILD_FAILED")
	var swap_event := {
		"event_id": EVENT_SWAP,
		"time": float(session["time_s"]),
		"transitions": [{"kind": "STABILIZED_REPRESENTATION_SWAP"}],
	}
	var swapped := Runtime.consume_representation_swap_event(
		session,
		registry,
		swap_event,
		REGION_FULL,
		full_to_hybrid,
		REGION_HYBRID,
		hybrid_to_full
	)
	if not bool(swapped.get("success", false)):
		return _failure("COMPLEX2_REPRESENTATION_SWAP_FAILED", swapped)
	session = swapped["details"]["session"]
	registry = swapped["details"]["registry"]

	var after_swap := _run_mixed_reference(session, registry, reference, 5, {REGION_DYNAMIC: 0.16})
	if not bool(after_swap.get("success", false)):
		return after_swap
	session = after_swap["session"]
	reference = after_swap["reference"]
	max_full_delta = maxf(max_full_delta, float(after_swap["max_delta"]))

	var second_break := _apply_support_break(subject, SECOND_SUPPORT_ID, EVENT_SECOND)
	if not bool(second_break.get("success", false)):
		return second_break
	subject = second_break["subject"]
	var second_power_break := Complex1A.apply_structural_break(
		subject["functional_subject"], SECOND_SUPPORT_ID, EVENT_SECOND
	)
	if not bool(second_power_break.get("success", false)):
		return _failure("COMPLEX2_SECOND_FUNCTIONAL_MUTATION_FAILED", second_power_break)
	subject["functional_subject"] = second_power_break["subject"]
	var power_after_second := Complex1A.solve(subject["functional_subject"])
	if not bool(power_after_second.get("success", false)):
		return _failure("COMPLEX2_POWER_AFTER_SECOND_FAILED", power_after_second)

	var master_after_second := _master_source({REGION_HYBRID: 1, REGION_DYNAMIC: 1})
	var invalidated_second := Runtime.apply_master_update(
		session,
		registry,
		master_after_second["frontier"],
		master_after_second["authority"],
		2200
	)
	if not bool(invalidated_second.get("success", false)):
		return _failure("COMPLEX2_SECOND_INVALIDATION_FAILED", invalidated_second)
	session = invalidated_second["details"]["session"]
	var second_affected: Array = Array(invalidated_second["details"]["affected_regions"]).duplicate()
	var blocked_second := Runtime.step(session, registry, {}, DT)
	if bool(blocked_second.get("success", false)):
		return _failure("COMPLEX2_SECOND_STALE_REGION_EXECUTED", blocked_second)
	var rebuilt_dynamic := _rebuild_one(session, registry, REGION_DYNAMIC, 2)
	if not bool(rebuilt_dynamic.get("success", false)):
		return rebuilt_dynamic
	session = rebuilt_dynamic["session"]
	registry = rebuilt_dynamic["registry"]

	var final_run := _run_mixed_reference(session, registry, reference, 5, {})
	if not bool(final_run.get("success", false)):
		return final_run
	session = final_run["session"]
	reference = final_run["reference"]
	max_full_delta = maxf(max_full_delta, float(final_run["max_delta"]))

	var kinds: Array = []
	for region in registry["regions"]:
		kinds.append(String(region["representation_kind"]))
	kinds.sort()
	var event_handoff_max := 0.0
	for handoff in swapped["details"]["handoffs"]:
		event_handoff_max = maxf(event_handoff_max, absf(float(handoff["state_error"])))

	var result := {
		"success": true,
		"schema": SCHEMA,
		"part_count": subject["parts"].size(),
		"module_count": subject["modules"].size(),
		"moving_subsystem_count": subject["moving_subsystems"].size(),
		"contact_zone_count": subject["contact_zones"].size(),
		"functional_path_count": FUNCTIONAL_PATH_COUNT,
		"module_revision": int(subject["revision"]),
		"module_components_after_detach": components_after_detach,
		"detached_component": detached_component,
		"detach_event_id": EVENT_DETACH,
		"second_event_id": EVENT_SECOND,
		"applied_event_ids": Array(subject["applied_event_ids"]).duplicate(),
		"detach_affected_regions": detach_affected,
		"second_affected_regions": second_affected,
		"detach_stale_error": String(blocked_detach.get("error_code", "")),
		"second_stale_error": String(blocked_second.get("error_code", "")),
		"detach_rebuild_handoff_error": float(rebuilt_hybrid["state_handoff_error"]),
		"second_rebuild_handoff_error": float(rebuilt_dynamic["state_handoff_error"]),
		"representation_swap_handoff_error": event_handoff_max,
		"representation_kinds_after_swap": kinds,
		"representation_event_ledger_size": session["event_ledger"].size(),
		"normal_state": normal_state,
		"contact_state": contact_state,
		"contact_state_delta": contact_state_delta,
		"contact_external_flow_keys": [REGION_CONTACT],
		"mixed_full_max_state_delta": max_full_delta,
		"power_before": _power_summary(power_before),
		"power_after_detach": _power_summary(power_after_detach),
		"power_after_second": _power_summary(power_after_second),
		"detach_functional_mutations": Array(power_detach["functional_topology_mutations"]).duplicate(true),
		"second_functional_mutations": Array(second_power_break["functional_topology_mutations"]).duplicate(true),
		"machine_hash": _machine_hash(subject),
		"final_state_hash": Utils.canonical_hash(session["state_values"]),
	}
	result["experiment_hash"] = Utils.canonical_hash({
		"machine_hash": result["machine_hash"],
		"final_state_hash": result["final_state_hash"],
		"applied_event_ids": result["applied_event_ids"],
		"representation_kinds_after_swap": result["representation_kinds_after_swap"],
		"power_after_second": result["power_after_second"],
	})
	return result

static func _modules() -> Array:
	var modules: Array = []
	for index in range(MODULE_COUNT):
		var region_id := REGION_STRUCTURAL
		var role := "FRAME"
		if index >= 8 and index <= 11:
			region_id = REGION_DYNAMIC
			role = "MOVING_DRIVE"
		elif index >= 12 and index <= 14:
			region_id = REGION_FULL
			role = "ARTICULATED_IMPACT"
		elif index >= 15 and index <= 18:
			region_id = REGION_CONTACT
			role = "CONTACT_TOOLING"
		elif index >= 19:
			region_id = REGION_HYBRID
			role = "COMPLIANT_DETACHABLE"
		modules.append({
			"module_id": "module/complex2-%02d" % index,
			"index": index,
			"region_id": region_id,
			"role": role,
			"part_start": index * PARTS_PER_MODULE,
			"part_count": PARTS_PER_MODULE,
		})
	return modules

static func _parts(modules: Array) -> Array:
	var parts: Array = []
	for module in modules:
		for local_index in range(PARTS_PER_MODULE):
			var global_index := int(module["part_start"]) + local_index
			parts.append({
				"part_id": "part/complex2-%04d" % global_index,
				"module_id": String(module["module_id"]),
				"region_id": String(module["region_id"]),
			})
	return parts

static func _supports() -> Array:
	var supports: Array = []
	for index in range(MODULE_COUNT - 1):
		supports.append({
			"support_id": "support/complex2-%02d-%02d" % [index, index + 1],
			"module_a": "module/complex2-%02d" % index,
			"module_b": "module/complex2-%02d" % (index + 1),
			"active": true,
		})
	for pair in [[0, 4], [4, 8], [8, 12], [12, 16], [16, 20]]:
		supports.append({
			"support_id": "brace/complex2-%02d-%02d" % [pair[0], pair[1]],
			"module_a": "module/complex2-%02d" % pair[0],
			"module_b": "module/complex2-%02d" % pair[1],
			"active": true,
		})
	return supports

static func _moving_subsystems() -> Array:
	return [
		{"subsystem_id": "moving/arm-shoulder", "module_id": "module/complex2-08", "kind": "ARTICULATED"},
		{"subsystem_id": "moving/arm-elbow", "module_id": "module/complex2-09", "kind": "ARTICULATED"},
		{"subsystem_id": "moving/shaft", "module_id": "module/complex2-10", "kind": "ROTATING"},
		{"subsystem_id": "moving/drive-carriage", "module_id": "module/complex2-11", "kind": "TRANSLATING"},
		{"subsystem_id": "moving/compliant-carriage", "module_id": "module/complex2-20", "kind": "COMPLIANT"},
		{"subsystem_id": "moving/detachable-head", "module_id": DETACH_MODULE_ID, "kind": "DETACHABLE"},
	]

static func _contact_zones() -> Array:
	return [
		{"zone_id": "contact/complex2-tool-a", "module_ids": ["module/complex2-15", "module/complex2-16"], "region_id": REGION_CONTACT},
		{"zone_id": "contact/complex2-tool-b", "module_ids": ["module/complex2-17"], "region_id": REGION_CONTACT},
		{"zone_id": "contact/complex2-impact", "module_ids": ["module/complex2-13", "module/complex2-14"], "region_id": REGION_FULL},
	]

static func _functional_subject() -> Dictionary:
	var subject := Complex1A.two_loads()
	var remapped: Dictionary = {}
	for raw_id in subject["structural_bonds"].keys():
		var old_id := String(raw_id)
		var new_id := old_id
		if old_id == "support/branch-a":
			new_id = DETACH_SUPPORT_ID
		elif old_id == "support/branch-b":
			new_id = SECOND_SUPPORT_ID
		remapped[new_id] = bool(subject["structural_bonds"][raw_id])
	subject["structural_bonds"] = remapped
	for index in range(subject["functional_links"].size()):
		var link: Dictionary = subject["functional_links"][index]
		var support_ids: Array = []
		for raw_support in link["support_bond_ids"]:
			var support_id := String(raw_support)
			if support_id == "support/branch-a":
				support_id = DETACH_SUPPORT_ID
			elif support_id == "support/branch-b":
				support_id = SECOND_SUPPORT_ID
			support_ids.append(support_id)
		link["support_bond_ids"] = support_ids
		subject["functional_links"][index] = link
	return subject

static func _apply_support_break(subject: Dictionary, support_id: String, event_id: String) -> Dictionary:
	if event_id.is_empty():
		return _failure("COMPLEX2_EVENT_ID_REQUIRED")
	if subject["applied_event_ids"].has(event_id):
		return _failure("COMPLEX2_EVENT_ALREADY_APPLIED", {"event_id": event_id})
	var found := false
	var next := subject.duplicate(true)
	for index in range(next["supports"].size()):
		var support: Dictionary = next["supports"][index]
		if String(support["support_id"]) != support_id:
			continue
		found = true
		if not bool(support["active"]):
			return _failure("COMPLEX2_SUPPORT_ALREADY_BROKEN", {"support_id": support_id})
		support["active"] = false
		next["supports"][index] = support
		break
	if not found:
		return _failure("COMPLEX2_SUPPORT_NOT_FOUND", {"support_id": support_id})
	next["revision"] = int(next["revision"]) + 1
	next["applied_event_ids"].append(event_id)
	next["applied_event_ids"].sort()
	next["machine_hash"] = _machine_hash(next)
	return {
		"success": true,
		"subject": next,
		"event_id": event_id,
		"support_id": support_id,
	}

static func _module_components(subject: Dictionary) -> Array:
	var adjacency: Dictionary = {}
	for module in subject["modules"]:
		adjacency[String(module["module_id"])] = []
	for support in subject["supports"]:
		if not bool(support["active"]):
			continue
		var a := String(support["module_a"])
		var b := String(support["module_b"])
		adjacency[a].append(b)
		adjacency[b].append(a)
	var visited: Dictionary = {}
	var components: Array = []
	var ids: Array = adjacency.keys()
	ids.sort()
	for module_id in ids:
		if visited.has(module_id):
			continue
		var queue: Array = [module_id]
		visited[module_id] = true
		var component: Array = []
		while not queue.is_empty():
			var current := String(queue.pop_front())
			component.append(current)
			var neighbors: Array = Array(adjacency[current]).duplicate()
			neighbors.sort()
			for neighbor in neighbors:
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				queue.append(neighbor)
		component.sort()
		components.append(component)
	components.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
	return components

static func _component_containing(components: Array, module_id: String) -> Array:
	for component in components:
		if component.has(module_id):
			return Array(component).duplicate()
	return []

static func _master_source(revisions: Dictionary) -> Dictionary:
	var dependency_hash := Utils.canonical_hash({"complex2": "MODULAR_MACHINE_R1"})
	var sources: Array = []
	var records: Array = []
	var mutable: Array = []
	for spec in _region_specs():
		var region_id := String(spec[0])
		var source_id := _source_id(region_id)
		var revision_offset := int(revisions.get(region_id, 0))
		var source := SourceRevision.create(
			"CONSTRUCTION",
			source_id,
			41,
			100 + revision_offset,
			Utils.canonical_hash({
				"machine": "COMPLEX2",
				"region_id": region_id,
				"revision_offset": revision_offset,
			}),
			dependency_hash
		)
		if source.is_empty():
			return {}
		sources.append(source)
		records.append({
			"source_domain": "CONSTRUCTION",
			"source_id": source_id,
			"authority_epoch": 41,
			"owner_id": "server/complex2",
		})
		mutable.append(Utils.source_key("CONSTRUCTION", source_id))
	var frontier := Frontier.create(sources)
	var authority := AuthorityEnvelope.create("server/complex2", records, mutable)
	if frontier.is_empty() or authority.is_empty():
		return {}
	return {"frontier": frontier, "authority": authority}

static func _registry(master: Dictionary) -> Dictionary:
	var regions: Array = []
	for spec in _region_specs():
		var region_id := String(spec[0])
		var kind := String(spec[1])
		var state_id := String(spec[2])
		var source_key := Utils.source_key("CONSTRUCTION", _source_id(region_id))
		var slice := Slice.create(region_id, master["frontier"], master["authority"], [source_key])
		if slice.is_empty():
			return {}
		var adapter := Adapter.create(
			region_id,
			kind,
			state_id,
			slice,
			_backend_hash(kind),
			float(spec[3]),
			float(spec[4]),
			1
		)
		if adapter.is_empty():
			return {}
		regions.append({
			"region_id": region_id,
			"representation_kind": kind,
			"state_id": state_id,
			"adapter": adapter,
		})
	var interfaces := [
		_interface("interface/complex2-contact-full", REGION_CONTACT, REGION_FULL, 0.31),
		_interface("interface/complex2-dynamic-structural", REGION_DYNAMIC, REGION_STRUCTURAL, 0.28),
		_interface("interface/complex2-full-dynamic", REGION_FULL, REGION_DYNAMIC, 0.35),
		_interface("interface/complex2-structural-hybrid", REGION_STRUCTURAL, REGION_HYBRID, 0.26),
	]
	return Registry.create(master["frontier"], master["authority"], regions, interfaces)

static func _rebuild_one(session: Dictionary, registry: Dictionary, region_id: String, generation: int) -> Dictionary:
	var old := Registry.region_by_id(registry, region_id)
	if old.is_empty():
		return _failure("COMPLEX2_REBUILD_REGION_MISSING", {"region_id": region_id})
	var fresh_slice := Slice.refreshed(
		old["adapter"]["source_slice"],
		session["live_master_frontier"],
		session["live_master_authority"]
	)
	if fresh_slice.is_empty():
		return _failure("COMPLEX2_REBUILD_SLICE_FAILED", {"region_id": region_id})
	var adapter := Adapter.create(
		region_id,
		String(old["representation_kind"]),
		String(old["state_id"]),
		fresh_slice,
		String(old["adapter"]["backend_contract_hash"]),
		float(old["adapter"]["storage"]),
		float(old["adapter"]["damping"]),
		generation
	)
	if adapter.is_empty():
		return _failure("COMPLEX2_REBUILD_ADAPTER_FAILED", {"region_id": region_id})
	var rebuilt := Runtime.rebuild_region(session, registry, adapter)
	if not bool(rebuilt.get("success", false)):
		return _failure("COMPLEX2_REGION_REBUILD_FAILED", rebuilt)
	return {
		"success": true,
		"session": rebuilt["details"]["session"],
		"registry": rebuilt["details"]["registry"],
		"state_handoff_error": float(rebuilt["details"]["state_handoff_error"]),
	}

static func _run_mixed_reference(
	session: Dictionary,
	registry: Dictionary,
	reference: Dictionary,
	steps: int,
	external_flows: Dictionary
) -> Dictionary:
	var live_session := session
	var live_reference := reference.duplicate(true)
	var max_delta := 0.0
	for step_index in range(steps):
		var mixed := Runtime.step(live_session, registry, external_flows, DT)
		if not bool(mixed.get("success", false)):
			return _failure("COMPLEX2_MIXED_STEP_FAILED", {"step": step_index, "result": mixed})
		var full := Runtime.full_reference_step(registry, live_reference, external_flows, DT)
		if not bool(full.get("success", false)):
			return _failure("COMPLEX2_FULL_REFERENCE_STEP_FAILED", {"step": step_index, "result": full})
		live_session = mixed["details"]["session"]
		live_reference = full["details"]["state_values"]
		max_delta = maxf(max_delta, _state_error(live_session["state_values"], live_reference))
	return {
		"success": true,
		"session": live_session,
		"reference": live_reference,
		"max_delta": max_delta,
	}

static func _power_summary(solved: Dictionary) -> Dictionary:
	return {
		"active_functional_bond_ids": Array(solved["active_functional_bond_ids"]).duplicate(),
		"load_a": Dictionary(solved["loads"]["load/lamp-a"]).duplicate(true),
		"load_b": Dictionary(solved["loads"]["load/lamp-b"]).duplicate(true),
		"max_balance_residual": float(solved["max_balance_residual"]),
		"max_power_residual": float(solved["max_power_residual"]),
	}

static func _region_specs() -> Array:
	return [
		[REGION_CONTACT, "CONTACT_BAKE", STATE_CONTACT, 0.90, 0.10],
		[REGION_DYNAMIC, "DYNAMIC_ROM", STATE_DYNAMIC, 1.25, 0.06],
		[REGION_FULL, "FULL", STATE_FULL, 1.15, 0.07],
		[REGION_HYBRID, "HYBRID_BAKE", STATE_HYBRID, 1.05, 0.09],
		[REGION_STRUCTURAL, "STRUCTURAL_BAKE", STATE_STRUCTURAL, 1.00, 0.08],
	]

static func _initial_state() -> Dictionary:
	return {
		STATE_STRUCTURAL: 1.0,
		STATE_FULL: 0.72,
		STATE_CONTACT: 0.44,
		STATE_DYNAMIC: 0.21,
		STATE_HYBRID: -0.08,
	}

static func _source_id(region_id: String) -> String:
	return "construct/%s" % region_id.replace("region/", "")

static func _backend_hash(kind: String) -> String:
	match kind:
		"STRUCTURAL_BAKE":
			return Utils.canonical_hash({"bridge1_exact": "e128cf9d49f84691b8a5428c97ab7acd53b92d90"})
		"CONTACT_BAKE":
			return Utils.canonical_hash({"b0_3_closure": "9575a63d6aeb4c455f8beade7588505e600c12d6"})
		"DYNAMIC_ROM":
			return Utils.canonical_hash({"b0_4_exact": "e33ac10ac94d8b70f1387d442a3ae9d3801bb08a"})
		"HYBRID_BAKE":
			return Utils.canonical_hash({"b0_5_a_exact": "d819fffa0dc86cc09cda0000f20c310aec23c799"})
		_:
			return Utils.canonical_hash({"fabric0_18_exact": "e079565b4b9cd0dae530ff5042f057ce8fa0d0cc"})

static func _interface(interface_id: String, a: String, b: String, conductance: float) -> Dictionary:
	return {
		"interface_id": interface_id,
		"region_a": a,
		"region_b": b,
		"port_a": Adapter.port_id(a, "right"),
		"port_b": Adapter.port_id(b, "left"),
		"conductance": conductance,
	}

static func _machine_hash(subject: Dictionary) -> String:
	var support_state: Array = []
	for support in subject["supports"]:
		support_state.append({
			"support_id": String(support["support_id"]),
			"active": bool(support["active"]),
		})
	return Utils.canonical_hash({
		"schema": SCHEMA,
		"revision": int(subject["revision"]),
		"module_count": subject["modules"].size(),
		"support_state": support_state,
		"applied_event_ids": Array(subject["applied_event_ids"]).duplicate(),
	})

static func _state_error(a: Dictionary, b: Dictionary) -> float:
	var error := 0.0
	for key in a.keys():
		error = maxf(error, absf(float(a[key]) - float(b[key])))
	return error

static func _failure(error_code: String, details = null) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details,
	}
