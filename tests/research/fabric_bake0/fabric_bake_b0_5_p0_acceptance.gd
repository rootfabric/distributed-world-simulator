extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Fabric = preload("res://scripts/research/fabric0/fabric0_coupled_hybrid_dae_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ModeSignature = preload("res://scripts/research/fabric_bake0/hybrid_mode_signature_v1.gd")
const ModeDescriptor = preload("res://scripts/research/fabric_bake0/hybrid_bake_mode_descriptor_v1.gd")
const Transition = preload("res://scripts/research/fabric_bake0/hybrid_transition_descriptor_v1.gd")
const CacheEntry = preload("res://scripts/research/fabric_bake0/lazy_mode_cache_entry_v1.gd")
const Preflight = preload("res://scripts/research/fabric_bake0/hybrid_bake_preflight_v1.gd")

var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	_test_existing_fabric_hybrid_semantics()
	_test_mode_signature_determinism()
	_test_mode_descriptor_and_unresolved_b0_4()
	_test_transition_contract()
	_test_lazy_cache_and_invalidation()
	_test_unknown_mode_fail_closed()
	_test_bundle_preflight()
	_finish()

func _test_existing_fabric_hybrid_semantics() -> void:
	var system := Fabric.new_system()
	_check(Fabric.add_state(system, "q", 0.0, Fabric.dim_dimensionless(), 1.0), "FABRIC state accepted")
	_check(Fabric.add_parameter(system, "rate_a", 1.0, Fabric.dim_div(Fabric.dim_dimensionless(), Fabric.dim_time())), "FABRIC parameter A")
	_check(Fabric.add_parameter(system, "rate_b", -0.5, Fabric.dim_div(Fabric.dim_dimensionless(), Fabric.dim_time())), "FABRIC parameter B")
	_check(Fabric.add_mode(system, "stable_a", {"q": Fabric.expr_parameter("rate_a")}, []), "FABRIC FLOW mode A")
	_check(Fabric.add_mode(system, "stable_b", {"q": Fabric.expr_parameter("rate_b")}, []), "FABRIC FLOW mode B")
	_check(Fabric.set_initial_mode(system, "stable_a"), "FABRIC initial mode")
	var transition := {
		"id": "generic_release",
		"from_modes": ["stable_a"],
		"to_mode": "stable_b",
		"guard": {
			"expr": Fabric.expr_sub(Fabric.expr_state("q"), Fabric.expr_constant(0.25, Fabric.dim_dimensionless())),
			"nominal": 1.0,
			"direction": 1,
			"kind": "crossing",
		},
		"jump": {},
		"topology_ops": [],
		"priority": 0,
	}
	_check(Fabric.add_transition(system, transition), "existing FABRIC JUMP transition accepted")
	var advanced: Dictionary = Fabric.advance(system, 0.4)
	_check(bool(advanced.get("ok", false)), "existing FABRIC hybrid runtime advances")
	_check(Fabric.read_mode(system) == "stable_b", "existing FABRIC owns FLOW/JUMP semantics")

func _test_mode_signature_determinism() -> void:
	var deps_a := [
		{"dependency_id": "dependency/fabric/compiler", "version_hash": _h("fabric")},
		{"dependency_id": "dependency/physical/core", "version_hash": _h("physical")},
	]
	var deps_b := [deps_a[1].duplicate(true), deps_a[0].duplicate(true)]
	var relations_a := ["relation/spring/storage", "relation/contact/support"]
	var relations_b := ["relation/contact/support", "relation/spring/storage"]
	var sig_a := _signature("A", _h("frontier"), _h("topology-a"), deps_a, relations_a)
	var sig_b := _signature("A", _h("frontier"), _h("topology-a"), deps_b, relations_b)
	_check(not sig_a.is_empty(), "mode signature A created")
	_check(not sig_b.is_empty(), "mode signature reordered created")
	_check(String(sig_a["mode_hash"]) == String(sig_b["mode_hash"]), "mode signature order invariant")
	_check(String(sig_a["checksum"]) == String(sig_b["checksum"]), "mode signature checksum order invariant")
	_check(bool(ModeSignature.validate(sig_a).get("success", false)), "mode signature validates")

	var changed_topology := _signature("A", _h("frontier"), _h("topology-b"), deps_a, relations_a)
	_check(String(changed_topology["mode_hash"]) != String(sig_a["mode_hash"]), "topology changes mode identity")
	var changed_frontier := _signature("A", _h("frontier-2"), _h("topology-a"), deps_a, relations_a)
	_check(String(changed_frontier["mode_hash"]) != String(sig_a["mode_hash"]), "source frontier changes mode identity")
	var changed_dependency := [
		{"dependency_id": "dependency/fabric/compiler", "version_hash": _h("fabric-v2")},
		{"dependency_id": "dependency/physical/core", "version_hash": _h("physical")},
	]
	var changed_dep_sig := _signature("A", _h("frontier"), _h("topology-a"), changed_dependency, relations_a)
	_check(String(changed_dep_sig["mode_hash"]) != String(sig_a["mode_hash"]), "dependency version changes mode identity")

	var forbidden := ModeSignature.create(
		_h("frontier"),
		_h("topology"),
		["relation/motor/drive"],
		[],
		_h("boundary"),
		deps_a,
		"fabric-bake-b0.5-p0"
	)
	_check(forbidden.is_empty(), "device-specific MOTOR relation rejected from kernel mode identity")

func _test_mode_descriptor_and_unresolved_b0_4() -> void:
	var sig := _signature("A", _h("frontier"), _h("topology-a"), _deps(), ["relation/contact/support"])
	var domain := _domain(sig, "MODE_A")
	var unresolved := ModeDescriptor.unresolved_rom_binding()
	var descriptor := ModeDescriptor.create(
		"hybrid-mode/mode-a",
		sig,
		domain,
		unresolved,
		1
	)
	_check(not descriptor.is_empty(), "unresolved B0.4 mode descriptor created")
	_check(String(descriptor["execution_qualification"]) == "PREFLIGHT_ONLY", "unresolved B0.4 is preflight only")
	_check(bool(ModeDescriptor.validate(descriptor).get("success", false)), "unresolved descriptor validates")

	var illegal := descriptor.duplicate(true)
	illegal["execution_qualification"] = "B0_4_INTERFACE_BOUND"
	illegal["checksum"] = Utils.compute_checksum(illegal)
	var illegal_check: Dictionary = ModeDescriptor.validate(illegal)
	_check(not bool(illegal_check.get("success", false)), "unresolved interface cannot claim executable binding")
	_check(String(illegal_check.get("error_code", "")) == "UNRESOLVED_B0_4_INTERFACE_EXECUTION_FORBIDDEN", "unresolved execution rejection exact")

	var resolved := _resolved_descriptor(sig, domain, "artifact-a")
	_check(not resolved.is_empty(), "resolved B0.4 interface descriptor created")
	_check(String(resolved["execution_qualification"]) == "B0_4_INTERFACE_BOUND", "resolved descriptor explicitly bound")
	_check(bool(ModeDescriptor.validate(resolved).get("success", false)), "resolved descriptor validates")

func _test_transition_contract() -> void:
	var sig_a := _signature("A", _h("frontier"), _h("topology-a"), _deps(), ["relation/contact/support"])
	var sig_b := _signature("B", _h("frontier"), _h("topology-b"), _deps(), ["relation/contact/released"])
	var guard := {
		"guard_id": "guard/hybrid/release",
		"kind": "CROSSING",
		"direction": 1,
		"observed_quantity_id": "quantity/generalized/coordinate",
		"dimension": [0, 0, 0, 0, 0, 0, 0],
		"nominal": 1.0,
		"threshold": 0.25,
		"mapped_source_region": "region/hybrid/interface",
	}
	var handoff := Transition.unresolved_handoff(_h("conservation"))
	var ownership := Transition.exactly_once_event_ownership()
	var transition := Transition.create(
		"transition/hybrid/release",
		_h("frontier"),
		String(sig_a["mode_hash"]),
		String(sig_b["mode_hash"]),
		guard,
		handoff,
		"NONE",
		ownership,
		0
	)
	_check(not transition.is_empty(), "generic hybrid transition created")
	_check(bool(Transition.validate(transition).get("success", false)), "generic transition validates")
	_check(String(transition["execution_qualification"]) == "PREFLIGHT_ONLY", "transition remains preflight only")
	_check(String(transition["event_ownership"]["semantics"]) == "EXACTLY_ONCE", "exactly-once event ownership explicit")
	_check(String(transition["event_ownership"]["canonical_revision_policy"]) == "EXTERNAL_AUTHORITY_ONLY", "reset cannot advance canonical revision")
	_check(String(transition["reset_handoff"]["contract_kind"]) == "B0_4_STATE_HANDOFF_INTERFACE", "reset/handoff explicitly B0.4-compatible")

	var bad_owner := transition.duplicate(true)
	bad_owner["event_ownership"]["owner"] = "BAKED_CACHE"
	bad_owner["transition_hash"] = Transition.identity_hash(bad_owner)
	bad_owner["checksum"] = Utils.compute_checksum(bad_owner)
	var bad_owner_check: Dictionary = Transition.validate(bad_owner)
	_check(not bool(bad_owner_check.get("success", false)), "cache cannot own physical event")
	_check(String(bad_owner_check.get("error_code", "")) == "HYBRID_EVENT_OWNER_MUST_BE_PHYSICAL", "event owner rejection exact")

	var bad_revision := transition.duplicate(true)
	bad_revision["event_ownership"]["canonical_revision_policy"] = "ADVANCE_ON_RESET"
	bad_revision["transition_hash"] = Transition.identity_hash(bad_revision)
	bad_revision["checksum"] = Utils.compute_checksum(bad_revision)
	var bad_revision_check: Dictionary = Transition.validate(bad_revision)
	_check(not bool(bad_revision_check.get("success", false)), "reset cannot mutate canonical revision")
	_check(String(bad_revision_check.get("error_code", "")) == "HYBRID_RESET_MUST_NOT_ADVANCE_CANONICAL_REVISION", "revision owner rejection exact")

func _test_lazy_cache_and_invalidation() -> void:
	var sig := _signature("A", _h("frontier"), _h("topology-a"), _deps(), ["relation/contact/support"])
	var domain := _domain(sig, "MODE_A")
	var descriptor := _resolved_descriptor(sig, domain, "artifact-a")
	var entry := CacheEntry.create(descriptor)
	_check(not entry.is_empty(), "resolved lazy cache entry created")
	_check(String(entry["validity_state"]) == "VALID", "resolved cache initially valid")
	_check(bool(entry["derived_only"]), "cache explicitly derived-only")
	_check(bool(CacheEntry.validate_against(entry, sig, descriptor).get("success", false)), "exact cache binding validates")

	var lookup: Dictionary = Preflight.lookup_mode(sig, descriptor, [entry], "FULL")
	_check(bool(lookup.get("success", false)), "exact cache lookup succeeds")
	_check(String(lookup["details"]["action"]) == "CACHE_ENTRY_MATCH", "exact cache match only")
	_check(not bool(lookup["details"]["execution_authorized"]), "P0 cache match does not authorize execution")

	var changed_source_sig := _signature("A", _h("frontier-v2"), _h("topology-a"), _deps(), ["relation/contact/support"])
	var changed_source_desc := _resolved_descriptor(changed_source_sig, _domain(changed_source_sig, "MODE_A"), "artifact-a")
	var source_reconcile: Dictionary = Preflight.reconcile_cache(entry, changed_source_sig, changed_source_desc)
	_check(bool(source_reconcile.get("success", false)), "source cache reconcile succeeds")
	_check(String(source_reconcile["details"]["reason"]) == "SOURCE_FRONTIER_CHANGED", "source change invalidates cache")
	_check(String(source_reconcile["details"]["entry"]["validity_state"]) == "STALE", "source-changed cache becomes stale")

	var changed_topology_sig := _signature("A", _h("frontier"), _h("topology-v2"), _deps(), ["relation/contact/support"])
	var changed_topology_desc := _resolved_descriptor(changed_topology_sig, _domain(changed_topology_sig, "MODE_A"), "artifact-a")
	var topology_reconcile: Dictionary = Preflight.reconcile_cache(entry, changed_topology_sig, changed_topology_desc)
	_check(String(topology_reconcile["details"]["reason"]) == "TOPOLOGY_CHANGED", "topology change invalidates cache")

	var changed_deps := [
		{"dependency_id": "dependency/fabric/compiler", "version_hash": _h("fabric-v2")},
		{"dependency_id": "dependency/physical/core", "version_hash": _h("physical")},
	]
	var changed_dep_sig := _signature("A", _h("frontier"), _h("topology-a"), changed_deps, ["relation/contact/support"])
	var changed_dep_desc := _resolved_descriptor(changed_dep_sig, _domain(changed_dep_sig, "MODE_A"), "artifact-a")
	var dep_reconcile: Dictionary = Preflight.reconcile_cache(entry, changed_dep_sig, changed_dep_desc)
	_check(String(dep_reconcile["details"]["reason"]) == "DEPENDENCY_CHANGED", "dependency change invalidates cache")

	var changed_interface_desc := _resolved_descriptor(sig, domain, "artifact-b")
	var interface_reconcile: Dictionary = Preflight.reconcile_cache(entry, sig, changed_interface_desc)
	_check(String(interface_reconcile["details"]["reason"]) == "B0_4_INTERFACE_CHANGED", "B0.4 interface change invalidates cache")

func _test_unknown_mode_fail_closed() -> void:
	var sig_a := _signature("A", _h("frontier"), _h("topology-a"), _deps(), ["relation/contact/support"])
	var desc_a := _resolved_descriptor(sig_a, _domain(sig_a, "MODE_A"), "artifact-a")
	var entry_a := CacheEntry.create(desc_a)
	var sig_unknown := _signature("C", _h("frontier"), _h("topology-c"), _deps(), ["relation/contact/unknown"])

	var full: Dictionary = Preflight.unknown_mode_fallback(sig_unknown, [entry_a], "FULL")
	_check(bool(full.get("success", false)), "unknown mode FULL fallback accepted")
	_check(String(full["details"]["action"]) == "FALLBACK", "unknown mode never nearest-match executes")
	_check(String(full["details"]["fallback"]) == "FULL", "unknown mode falls back FULL")
	_check(not bool(full["details"]["nearest_mode_reuse"]), "nearest cached mode reuse forbidden")

	var no_safe: Dictionary = Preflight.unknown_mode_fallback(sig_unknown, [entry_a], "NO_SAFE_BAKE")
	_check(String(no_safe["details"]["fallback"]) == "NO_SAFE_BAKE", "unknown mode may fail closed NO_SAFE_BAKE")

	var unresolved_desc := ModeDescriptor.create(
		"hybrid-mode/mode-c",
		sig_unknown,
		_domain(sig_unknown, "MODE_C"),
		ModeDescriptor.unresolved_rom_binding(),
		1
	)
	var unresolved_lookup: Dictionary = Preflight.lookup_mode(sig_unknown, unresolved_desc, [], "FULL")
	_check(String(unresolved_lookup["details"]["action"]) == "FALLBACK", "unresolved B0.4 interface cannot compile/execute")
	_check(String(unresolved_lookup["details"]["reason"]) == "B0_4_INTERFACE_UNRESOLVED", "unresolved B0.4 fallback reason exact")

func _test_bundle_preflight() -> void:
	var sig_a := _signature("A", _h("frontier"), _h("topology-a"), _deps(), ["relation/contact/support"])
	var sig_b := _signature("B", _h("frontier"), _h("topology-b"), _deps(), ["relation/contact/released"])
	var desc_a := _resolved_descriptor(sig_a, _domain(sig_a, "MODE_A"), "artifact-a")
	var desc_b := _resolved_descriptor(sig_b, _domain(sig_b, "MODE_B"), "artifact-b")
	var guard := {
		"guard_id": "guard/hybrid/release",
		"kind": "CROSSING",
		"direction": 1,
		"observed_quantity_id": "quantity/generalized/coordinate",
		"dimension": [0, 0, 0, 0, 0, 0, 0],
		"nominal": 1.0,
		"threshold": 0.25,
		"mapped_source_region": "region/hybrid/interface",
	}
	var transition := Transition.create(
		"transition/hybrid/release",
		_h("frontier"),
		String(sig_a["mode_hash"]),
		String(sig_b["mode_hash"]),
		guard,
		Transition.unresolved_handoff(_h("conservation")),
		"FABRIC_TOPOLOGY_TRANSACTION",
		Transition.exactly_once_event_ownership(),
		0
	)
	var entry_a := CacheEntry.create(desc_a)
	var entry_b := CacheEntry.create(desc_b)
	var bundle: Dictionary = Preflight.validate_bundle([desc_b, desc_a], [transition], [entry_b, entry_a])
	_check(bool(bundle.get("success", false)), "B0.5 P0 bundle validates")
	_check(int(bundle["details"]["mode_count"]) == 2, "bundle mode count")
	_check(int(bundle["details"]["transition_count"]) == 1, "bundle transition count")
	_check(int(bundle["details"]["cache_entry_count"]) == 2, "bundle cache count")
	_check(not bool(bundle["details"]["execution_authorized"]), "bundle does not authorize B0.5 executable runtime")

	var duplicate: Dictionary = Preflight.validate_bundle([desc_a, desc_b], [transition, transition], [entry_a, entry_b])
	_check(not bool(duplicate.get("success", false)), "duplicate transition ownership rejected")
	_check(String(duplicate.get("error_code", "")) in ["DUPLICATE_B0_5_TRANSITION_ID", "DUPLICATE_B0_5_TRANSITION_HASH"], "duplicate transition rejection exact")

func _signature(
	label: String,
	frontier_hash: String,
	topology_hash: String,
	dependencies: Array,
	relations: Array
) -> Dictionary:
	return ModeSignature.create(
		frontier_hash,
		topology_hash,
		relations,
		["active-set/contact/%s" % label.to_lower()],
		_h("boundary"),
		dependencies,
		"fabric-bake-b0.5-p0-r1"
	)

func _deps() -> Array:
	return [
		{"dependency_id": "dependency/fabric/compiler", "version_hash": _h("fabric")},
		{"dependency_id": "dependency/physical/core", "version_hash": _h("physical")},
	]

func _domain(signature: Dictionary, mode: String) -> Dictionary:
	return ValidatedDomain.create(
		String(signature["source_frontier_hash"]),
		String(signature["physical_topology_hash"]),
		[],
		[mode],
		0.0
	)

func _resolved_descriptor(signature: Dictionary, domain: Dictionary, artifact_label: String) -> Dictionary:
	return ModeDescriptor.create(
		"hybrid-mode/%s" % artifact_label,
		signature,
		domain,
		ModeDescriptor.resolved_rom_binding(
			_h("%s-artifact" % artifact_label),
			_h("%s-state-schema" % artifact_label),
			_h("%s-state-mapping" % artifact_label),
			_h("%s-reconstruction" % artifact_label)
		),
		1
	)

func _h(label: String) -> String:
	return Utils.canonical_hash({"label": label})

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC-BAKE B0.5-P0 Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("FABRIC-BAKE B0.5-P0: %s" % failure)
	print("FABRIC-BAKE B0.5-P0 Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
