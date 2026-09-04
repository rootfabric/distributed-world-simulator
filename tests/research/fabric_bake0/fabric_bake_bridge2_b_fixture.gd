extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Subject = preload("res://scripts/research/fabric_bake0/mixed_representation_executable_subject_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const ContactBridge = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_bridge_v1.gd")
const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const FullReference = preload("res://scripts/research/fabric_bake0/dynamic_full_reference_solver_v1.gd")
const ROMCompiler = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const Certification = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_certification_v1.gd")
const DynamicBridge = preload("res://scripts/research/fabric_bake0/dynamic_rom_physical_bake_bridge_v1.gd")
const DynamicExecution = preload("res://scripts/research/fabric_bake0/dynamic_rom_execution_runtime_v1.gd")
const HybridRuntime = preload("res://scripts/research/fabric_bake0/hybrid_bake_executable_runtime_v1.gd")
const DynamicFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")
const Complex0 = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")
const OwnershipFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_a_fixture.gd")

static func build() -> Dictionary:
	var ownership_subject := OwnershipFixture.build()
	if not bool(ownership_subject.get("success", false)):
		return ownership_subject
	var canonical: Dictionary = ownership_subject["canonical"]
	var ownership: Dictionary = ownership_subject["contract"]

	var structural := Lifecycle.compile(canonical["view_request"], Complex0.lifecycle_options(canonical))
	if not bool(structural.get("success", false)) or String(structural.get("status", "")) != Lifecycle.STATUS_READY:
		return Utils.failure("BRIDGE2_B_STRUCTURAL_COMPILE_FAILED", {"result": structural})
	var structural_execution := Lifecycle.execute(structural, Complex0.reduced_state())
	if not bool(structural_execution.get("success", false)):
		return Utils.failure("BRIDGE2_B_STRUCTURAL_EXECUTION_FAILED", {"result": structural_execution})

	var contact := ContactBridge.compile(structural, _contact_request())
	if not bool(contact.get("ok", false)):
		return Utils.failure("BRIDGE2_B_CONTACT_COMPILE_FAILED", {"result": contact})
	var contact_execution := ContactBridge.support(structural, contact, [0.0, 0.0, 1.0, 0.0, 0.0, 0.0])
	if not bool(contact_execution.get("ok", false)):
		return Utils.failure("BRIDGE2_B_CONTACT_EXECUTION_FAILED", {"result": contact_execution})

	var dynamic_request := _dynamic_request(canonical)
	var full := FullCompiler.compile(dynamic_request)
	if not bool(full.get("success", false)):
		return Utils.failure("BRIDGE2_B_FULL_MODEL_COMPILE_FAILED", {"result": full})
	var full_initial := FullReference.initial_state(full["model"])
	if not bool(full_initial.get("success", false)):
		return Utils.failure("BRIDGE2_B_FULL_INITIAL_STATE_FAILED", {"result": full_initial})
	var full_execution := FullReference.step(
		full["model"], full_initial["state"], DynamicFixture.zero_flows(full["model"]["boundary_contract"]), 0.01
	)
	if not bool(full_execution.get("success", false)):
		return Utils.failure("BRIDGE2_B_FULL_EXECUTION_FAILED", {"result": full_execution})

	var rom := ROMCompiler.compile(full["model"])
	if not bool(rom.get("success", false)):
		return Utils.failure("BRIDGE2_B_ROM_COMPILE_FAILED", {"result": rom})
	var certification := Certification.create(full["model"], rom["descriptor"])
	if certification.is_empty():
		return Utils.failure("BRIDGE2_B_ROM_CERTIFICATION_FAILED")
	var dynamic_bundle_result := DynamicBridge.compile_bundle(
		full["model"], rom["descriptor"], rom["artifact_binding"], certification,
		"bake/bridge2-b-dynamic-rom", "artifact/bridge2-b-dynamic-rom", 1
	)
	if not bool(dynamic_bundle_result.get("success", false)):
		return Utils.failure("BRIDGE2_B_DYNAMIC_BUNDLE_FAILED", {"result": dynamic_bundle_result})
	var dynamic_bundle: Dictionary = dynamic_bundle_result["details"]["bundle"]
	var dynamic_started := DynamicExecution.start(
		dynamic_bundle["execution_artifact"], full["model"], rom["descriptor"], rom["artifact_binding"], certification
	)
	if not bool(dynamic_started.get("success", false)):
		return Utils.failure("BRIDGE2_B_DYNAMIC_START_FAILED", {"result": dynamic_started})

	var hybrid_blueprint := _hybrid_blueprint(dynamic_bundle, full["model"], rom, certification, ownership)
	var hybrid_compiled := HybridRuntime.compile_mode(hybrid_blueprint)
	if not bool(hybrid_compiled.get("success", false)):
		return Utils.failure("BRIDGE2_B_HYBRID_COMPILE_FAILED", {"result": hybrid_compiled})
	var hybrid_package: Dictionary = hybrid_compiled["details"]["package"]
	var hybrid_started := HybridRuntime.start(hybrid_package)
	if not bool(hybrid_started.get("success", false)):
		return Utils.failure("BRIDGE2_B_HYBRID_START_FAILED", {"result": hybrid_started})

	var witnesses := [
		{
			"representation_id": OwnershipFixture.FULL,
			"region_id": OwnershipFixture.REGION_IMPACT,
			"representation_kind": "FULL",
			"payload": {"full_model": full["model"], "execution": full_execution},
		},
		{
			"representation_id": OwnershipFixture.STRUCTURAL,
			"region_id": OwnershipFixture.REGION_STABLE,
			"representation_kind": "STRUCTURAL_BAKE",
			"payload": {"bundle": structural, "execution": structural_execution},
		},
		{
			"representation_id": OwnershipFixture.CONTACT,
			"region_id": OwnershipFixture.REGION_CONTACT,
			"representation_kind": "CONTACT_BAKE",
			"payload": {"parent_bundle": structural, "bundle": contact, "execution": contact_execution},
		},
		{
			"representation_id": OwnershipFixture.DYNAMIC,
			"region_id": OwnershipFixture.REGION_DYNAMIC,
			"representation_kind": "DYNAMIC_ROM",
			"payload": {
				"full_model": full["model"], "rom_descriptor": rom["descriptor"],
				"reduction_binding": rom["artifact_binding"], "certification": certification,
				"bundle": dynamic_bundle, "session": dynamic_started["details"]["session"],
			},
		},
		{
			"representation_id": OwnershipFixture.HYBRID,
			"region_id": OwnershipFixture.REGION_HYBRID,
			"representation_kind": "HYBRID_BAKE",
			"payload": {"package": hybrid_package, "session": hybrid_started["details"]["session"]},
		},
	]
	var compiled_subject := Subject.compile(ownership, witnesses)
	if not bool(compiled_subject.get("success", false)):
		return compiled_subject
	return {
		"success": true,
		"canonical": canonical,
		"ownership": ownership,
		"subject": compiled_subject["details"]["subject"],
		"witnesses": witnesses,
		"structural_bundle": structural,
		"structural_execution": structural_execution,
		"contact_bundle": contact,
		"contact_execution": contact_execution,
		"full_model": full["model"],
		"full_execution": full_execution,
		"rom": rom,
		"certification": certification,
		"dynamic_bundle": dynamic_bundle,
		"dynamic_session": dynamic_started["details"]["session"],
		"hybrid_package": hybrid_package,
		"hybrid_session": hybrid_started["details"]["session"],
	}

static func _dynamic_request(canonical: Dictionary) -> Dictionary:
	var seed := DynamicFixture.build("ZERO")
	var request: Dictionary = seed["request"].duplicate(true)
	request["model_id"] = "dynamic-model/bridge2-b-mixed-subject"
	request["canonical_source_frontier"] = canonical["frontier"].duplicate(true)
	request["authority_envelope"] = canonical["authority"].duplicate(true)
	return request

static func _hybrid_blueprint(
	dynamic_bundle: Dictionary,
	full_model: Dictionary,
	rom: Dictionary,
	certification: Dictionary,
	ownership: Dictionary
) -> Dictionary:
	var physical: Dictionary = dynamic_bundle["physical_artifact"]
	return {
		"mode_id": "mode/bridge2-b/hybrid-a",
		"mode_descriptor_id": "hybrid-mode/bridge2-b/executable-a",
		"active_relation_ids": ["relation/bridge2-b/hybrid-a"],
		"complementarity_active_ids": ["active-set/bridge2-b/hybrid-a"],
		"dependency_versions": [
			{"dependency_id": "dependency/bridge2-a/ownership", "version_hash": String(ownership["contract_hash"])},
			{"dependency_id": "dependency/bridge2-b/dynamic-artifact", "version_hash": String(physical["checksum"])},
		],
		"physical_bundle": dynamic_bundle,
		"full_model": full_model,
		"rom_descriptor": rom["descriptor"],
		"reduction_binding": rom["artifact_binding"],
		"certification": certification,
	}

static func _contact_request() -> Dictionary:
	return {
		"artifact_id": "bake/bridge2-b-contact-wrench",
		"model_id": "artifact/bridge2-b-contact-wrench",
		"patch_id": "contact-patch/bridge2-b-grid",
		"origin": Vector3.ZERO,
		"normal": Vector3(0.0, 0.0, 1.0),
		"t1": Vector3(1.0, 0.0, 0.0),
		"t2": Vector3(0.0, 1.0, 0.0),
		"points": _grid_points(11, 1.0, 0.75),
		"normal_support_limit": 12.0,
		"mu_tangent": 0.6,
		"mu_rolling": 0.08,
		"mu_torsion": 0.05,
		"effective_radius": 0.4,
		"minimum_reduction_ratio": 2.0,
	}

static func _grid_points(size: int, half_x: float, half_y: float) -> Array:
	var points: Array = []
	for iy in range(size):
		for ix in range(size):
			var x := lerpf(-half_x, half_x, float(ix) / float(size - 1))
			var y := lerpf(-half_y, half_y, float(iy) / float(size - 1))
			points.append({"id": "member/bridge2-b/%03d/%03d" % [iy, ix], "position": Vector3(x, y, 0.0)})
	return points
