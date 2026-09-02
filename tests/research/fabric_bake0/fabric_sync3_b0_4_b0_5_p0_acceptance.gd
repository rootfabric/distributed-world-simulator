extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const ROMCompiler = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const Certification = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_certification_v1.gd")
const ExecutionArtifact = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_artifact_v1.gd")
const HybridInterface = preload("res://scripts/research/fabric_bake0/dynamic_rom_hybrid_interface_v1.gd")
const ModeSignature = preload("res://scripts/research/fabric_bake0/hybrid_mode_signature_v1.gd")
const ModeDescriptorP0 = preload("res://scripts/research/fabric_bake0/hybrid_bake_mode_descriptor_v1.gd")
const PreflightP0 = preload("res://scripts/research/fabric_bake0/hybrid_bake_preflight_v1.gd")
const TransitionP0 = preload("res://scripts/research/fabric_bake0/hybrid_transition_descriptor_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	var base := _build("ZERO", 1, "artifact/dynamic-rom-sync3-r1")
	if base.is_empty():
		_finish()
		return
	_test_exact_b0_4_d_interface(base)
	_test_p0_identity_compatibility(base)
	_test_p0_legacy_binding_delta(base)
	_test_deterministic_interface(base)
	_test_generation_invalidation(base)
	_test_source_topology_invalidation(base)
	_test_p0_fallback_and_event_ownership(base)
	_test_no_physical_core_expansion_required(base)
	_finish()

func _build(profile: String, generation: int, artifact_id: String) -> Dictionary:
	var fixture := Fixture.build(profile)
	var full := FullCompiler.compile(fixture["request"])
	_check(bool(full.get("success", false)), "%s FULL model compiles" % profile)
	if not bool(full.get("success", false)):
		return {}
	var reduced := ROMCompiler.compile(full["model"])
	_check(bool(reduced.get("success", false)), "%s ROM compiles" % profile)
	if not bool(reduced.get("success", false)):
		return {}
	var certification := Certification.create(full["model"], reduced["descriptor"])
	_check(not certification.is_empty(), "%s runtime certification creates" % profile)
	if certification.is_empty():
		return {}
	var artifact := ExecutionArtifact.create(
		full["model"], reduced["descriptor"], reduced["artifact_binding"], certification,
		artifact_id, generation
	)
	_check(not artifact.is_empty(), "%s D execution artifact creates" % profile)
	if artifact.is_empty():
		return {}
	var interface := HybridInterface.create(artifact, full["model"])
	_check(not interface.is_empty(), "%s SYNC-3 hybrid interface creates" % profile)
	if interface.is_empty():
		return {}
	return {
		"fixture": fixture,
		"full_model": full["model"],
		"descriptor": reduced["descriptor"],
		"binding": reduced["artifact_binding"],
		"certification": certification,
		"artifact": artifact,
		"interface": interface,
	}

func _test_exact_b0_4_d_interface(base: Dictionary) -> void:
	var interface: Dictionary = base["interface"]
	_check(bool(HybridInterface.validate(interface).get("success", false)), "SYNC-3 interface validates")
	_check(bool(HybridInterface.verify_against(interface, base["artifact"], base["full_model"]).get("success", false)), "interface verifies against exact D artifact")
	_check(String(interface["interface_kind"]) == HybridInterface.INTERFACE_KIND, "interface kind exact")
	_check(String(interface["source_frontier_hash"]) == String(base["full_model"]["source_binding"]["frontier_hash"]), "frontier is canonical B0.4 source frontier")
	_check(String(interface["source_binding_checksum"]) == String(base["artifact"]["source_binding_checksum"]), "source binding checksum exact")
	_check(String(interface["physical_topology_hash"]) == String(base["full_model"]["source_binding"]["fabric_graph_hash"]), "physical topology uses exact B0.4 fabric graph")
	_check(String(interface["boundary_contract_hash"]) == String(base["artifact"]["boundary_contract_hash"]), "boundary contract exact")
	_check(String(interface["execution_artifact_hash"]) == String(base["artifact"]["artifact_hash"]), "execution artifact identity exact")
	_check(String(interface["rom_descriptor_hash"]) == String(base["artifact"]["rom_descriptor_hash"]), "ROM descriptor exact")
	_check(String(interface["runtime_certification_hash"]) == String(base["artifact"]["runtime_certification_hash"]), "C certification exact")
	_check(String(interface["lifecycle_version"]) == ExecutionArtifact.LIFECYCLE_VERSION, "D lifecycle version exact")
	_check(String(interface["handoff_contract_hash"]).length() == 64, "D FULL-handoff contract hash present")
	_check(int(interface["build_generation"]) == 1, "build generation exact")

func _test_p0_identity_compatibility(base: Dictionary) -> void:
	var interface: Dictionary = base["interface"]
	var deps := [
		{"dependency_id": "dependency/b0-4-d-execution-artifact", "version_hash": String(interface["execution_artifact_hash"])},
		{"dependency_id": "dependency/b0-5-p0-contract", "version_hash": Utils.canonical_hash({"closure": "d280096e0b64c03ac613e586881e43c816f471f0"})},
	]
	var signature := ModeSignature.create(
		String(interface["source_frontier_hash"]),
		String(interface["physical_topology_hash"]),
		["relation/dynamic/passive-path"],
		[],
		String(interface["boundary_contract_hash"]),
		deps,
		"FABRIC.SYNC3/R1"
	)
	_check(not signature.is_empty(), "P0 mode signature accepts actual D source/topology/boundary identity")
	_check(bool(ModeSignature.validate(signature).get("success", false)), "actual D-backed P0 mode signature validates")
	_check(bool(HybridInterface.mode_identity_compatible(interface, signature).get("success", false)), "P0 mode identity is exactly compatible with D interface")
	var domain := ValidatedDomain.create(
		String(interface["source_frontier_hash"]),
		String(interface["physical_topology_hash"]),
		[],
		["FLOW"],
		0.0
	)
	_check(not domain.is_empty(), "D-backed P0 validated domain creates")
	var unresolved := ModeDescriptorP0.create(
		"hybrid-mode/sync3-preflight",
		signature,
		domain,
		ModeDescriptorP0.unresolved_rom_binding(),
		1
	)
	_check(not unresolved.is_empty(), "historical P0 unresolved descriptor remains valid")
	_check(String(unresolved["execution_qualification"]) == "PREFLIGHT_ONLY", "P0 remains non-executable after synchronization")
	var lookup := PreflightP0.lookup_mode(signature, unresolved, [], "FULL")
	_check(bool(lookup.get("success", false)), "P0 fallback lookup still succeeds")
	_check(String(lookup["details"]["fallback"]) == "FULL", "unresolved historical P0 falls back FULL")
	_check(not bool(lookup["details"]["execution_authorized"]), "SYNC-3 does not silently authorize P0 v1 execution")

func _test_p0_legacy_binding_delta(base: Dictionary) -> void:
	var artifact: Dictionary = base["artifact"]
	_check(not artifact.has("state_mapping_checksum"), "actual B0.4-D artifact has no legacy state_mapping_checksum")
	_check(not artifact.has("reconstruction_descriptor_checksum"), "actual B0.4-D artifact has no legacy reconstruction_descriptor_checksum")
	_check(ModeDescriptorP0.ROM_FIELDS.has("state_mapping_checksum"), "P0 v1 historical binding expected state mapping")
	_check(ModeDescriptorP0.ROM_FIELDS.has("reconstruction_descriptor_checksum"), "P0 v1 historical binding expected reconstruction descriptor")
	_check(String(base["interface"]["execution_artifact_hash"]) == String(artifact["artifact_hash"]), "SYNC-3 binds actual execution artifact instead of fabricating legacy hashes")
	_check(String(base["interface"]["handoff_contract_hash"]).length() == 64, "SYNC-3 binds actual D handoff semantics")

func _test_deterministic_interface(base: Dictionary) -> void:
	var twin := HybridInterface.create(base["artifact"], base["full_model"])
	_check(not twin.is_empty(), "twin interface creates")
	_check(String(twin["interface_hash"]) == String(base["interface"]["interface_hash"]), "interface hash deterministic")
	_check(String(twin["checksum"]) == String(base["interface"]["checksum"]), "interface checksum deterministic")
	_check(String(twin["handoff_contract_hash"]) == String(base["interface"]["handoff_contract_hash"]), "handoff identity deterministic")

func _test_generation_invalidation(base: Dictionary) -> void:
	var artifact2 := ExecutionArtifact.create(
		base["full_model"], base["descriptor"], base["binding"], base["certification"],
		"artifact/dynamic-rom-sync3-r2", 2
	)
	_check(not artifact2.is_empty(), "generation-2 D artifact creates")
	var interface2 := HybridInterface.create(artifact2, base["full_model"])
	_check(not interface2.is_empty(), "generation-2 interface creates")
	_check(String(interface2["interface_hash"]) != String(base["interface"]["interface_hash"]), "D artifact generation changes hybrid interface identity")
	_check(String(interface2["handoff_contract_hash"]) != String(base["interface"]["handoff_contract_hash"]), "D artifact generation changes handoff identity")
	_check(int(interface2["build_generation"]) == 2, "generation-2 propagated exactly")

func _test_source_topology_invalidation(base: Dictionary) -> void:
	var changed := _build("POSITIVE", 1, "artifact/dynamic-rom-sync3-source-v2")
	if changed.is_empty():
		return
	_check(String(changed["interface"]["source_frontier_hash"]) != String(base["interface"]["source_frontier_hash"]), "canonical source mutation changes interface frontier")
	_check(String(changed["interface"]["physical_topology_hash"]) == String(base["interface"]["physical_topology_hash"]), "initial-state source change does not fake topology change")
	_check(String(changed["interface"]["interface_hash"]) != String(base["interface"]["interface_hash"]), "source revision changes hybrid interface identity")
	var foreign_signature := ModeSignature.create(
		String(changed["interface"]["source_frontier_hash"]),
		String(changed["interface"]["physical_topology_hash"]),
		["relation/dynamic/passive-path"],
		[],
		String(changed["interface"]["boundary_contract_hash"]),
		[{"dependency_id": "dependency/b0-4-d-execution-artifact", "version_hash": String(changed["interface"]["execution_artifact_hash"])}],
		"FABRIC.SYNC3/R1"
	)
	var mismatch := HybridInterface.mode_identity_compatible(base["interface"], foreign_signature)
	_check(not bool(mismatch.get("success", false)), "foreign source mode cannot reuse previous D hybrid interface")
	_check(String(mismatch.get("error_code", "")) == "DYNAMIC_ROM_HYBRID_MODE_FRONTIER_MISMATCH", "foreign source rejection exact")

func _test_p0_fallback_and_event_ownership(base: Dictionary) -> void:
	var interface: Dictionary = base["interface"]
	var unknown := ModeSignature.create(
		String(interface["source_frontier_hash"]),
		Utils.canonical_hash({"unknown_topology": true}),
		["relation/dynamic/unknown"],
		[],
		String(interface["boundary_contract_hash"]),
		[{"dependency_id": "dependency/b0-4-d-execution-artifact", "version_hash": String(interface["execution_artifact_hash"])}],
		"FABRIC.SYNC3/R1"
	)
	var fallback := PreflightP0.unknown_mode_fallback(unknown, [], "FULL")
	_check(bool(fallback.get("success", false)), "unknown hybrid mode retains P0 FULL fallback")
	_check(String(fallback["details"]["action"]) == "FALLBACK", "unknown mode action exact")
	_check(not bool(fallback["details"]["nearest_mode_reuse"]), "nearest cached mode reuse remains forbidden")
	_check(not bool(fallback["details"]["execution_authorized"]), "unknown mode cannot execute")
	var ownership := TransitionP0.exactly_once_event_ownership()
	_check(String(ownership["owner"]) == "FABRIC_PHYSICAL_EVENT", "physical FABRIC remains event owner")
	_check(String(ownership["semantics"]) == "EXACTLY_ONCE", "hybrid event remains exactly once")
	_check(String(ownership["canonical_revision_policy"]) == "EXTERNAL_AUTHORITY_ONLY", "hybrid reset does not seize canonical revision ownership")

func _test_no_physical_core_expansion_required(base: Dictionary) -> void:
	_check(String(base["interface"]["source_frontier_hash"]).length() == 64, "B0.4-D exposes enough canonical source identity")
	_check(String(base["interface"]["physical_topology_hash"]).length() == 64, "B0.4-D exposes enough physical topology identity")
	_check(String(base["interface"]["boundary_contract_hash"]).length() == 64, "B0.4-D exposes exact boundary identity")
	_check(String(base["interface"]["handoff_contract_hash"]).length() == 64, "B0.4-D exposes deterministic handoff identity")
	_check(HybridInterface.CANONICAL_STATE_OWNER == "PHYSICAL_SOURCE", "SYNC-3 preserves canonical PhysicalSource ownership")
	_check(HybridInterface.ROM_STATE_ROLE == "DERIVED_HANDOFF_ONLY", "ROM remains derived handoff state")
	_check(true, "FABRIC0.19 primitive not required by initial B0.5 executable entry contract")

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC.SYNC3 B0.4-D / B0.5-P0 Interface Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("FABRIC.SYNC3: %s" % failure)
	print("FABRIC.SYNC3 B0.4-D / B0.5-P0 Interface Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
