extends SceneTree

const Subject = preload("res://scripts/research/fabric_bake0/mixed_representation_executable_subject_v1.gd")
const PhysicalArtifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const FullReference = preload("res://scripts/research/fabric_bake0/dynamic_full_reference_solver_v1.gd")
const DynamicFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")
const OwnershipFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_a_fixture.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_b_fixture.gd")

var _checks := 0
var _failed := false

func _initialize() -> void:
	var built := Fixture.build()
	_require(bool(built.get("success", false)), "mixed executable subject builds", built)
	if _failed:
		_finish()
		return
	var subject: Dictionary = built["subject"]
	var ownership: Dictionary = built["ownership"]
	var canonical: Dictionary = built["canonical"]
	_require(bool(Subject.validate(subject, ownership).get("success", false)), "mixed executable subject validates")
	_require(subject["entries"].size() == 5, "all five representation witnesses present")
	_require(String(subject["canonical_source_frontier_hash"]) == String(canonical["frontier"]["frontier_hash"]), "subject uses canonical COMPLEX0 frontier")
	_require(String(subject["authority_epoch_binding"]) == String(canonical["authority"]["authority_epoch_binding"]), "subject uses canonical COMPLEX0 authority")
	_require(String(subject["execution_owner"]) == String(canonical["authority"]["execution_owner"]), "subject does not invent execution owner")

	var entries := _entry_map(subject)
	for representation_id in [OwnershipFixture.FULL, OwnershipFixture.STRUCTURAL, OwnershipFixture.CONTACT, OwnershipFixture.DYNAMIC, OwnershipFixture.HYBRID]:
		_require(entries.has(representation_id), "%s has executable witness" % representation_id)
		if entries.has(representation_id):
			_require(String(entries[representation_id]["source_frontier_hash"]) == String(canonical["frontier"]["frontier_hash"]), "%s exact frontier" % representation_id)
			_require(String(entries[representation_id]["authority_epoch_binding"]) == String(canonical["authority"]["authority_epoch_binding"]), "%s exact authority" % representation_id)
			_require(String(entries[representation_id]["ownership_role"]) == "ACTIVE_EXECUTION", "%s is active execution witness" % representation_id)

	_require(String(entries[OwnershipFixture.FULL]["witness_kind"]) == "FULL_REFERENCE_EXECUTION", "FULL uses real reference execution")
	_require(String(entries[OwnershipFixture.FULL]["physical_artifact_checksum"]) == "", "FULL does not fake a bake artifact")
	_require(int(built["full_execution"]["state"]["step_index"]) == 1, "FULL reference actually advances one step")
	_require(float(built["full_execution"]["state"]["time_s"]) == 0.01, "FULL reference time advances")

	_require(bool(PhysicalArtifact.validate(built["structural_bundle"]["artifact"]).get("success", false)), "STRUCTURAL_BAKE is real PhysicalBakeArtifact")
	_require(String(built["structural_execution"]["status"]) == "BRIDGE1_EXECUTED", "STRUCTURAL_BAKE executes through BRIDGE-1 gate")
	_require(String(entries[OwnershipFixture.STRUCTURAL]["physical_artifact_checksum"]) == String(built["structural_bundle"]["artifact"]["checksum"]), "structural witness binds exact artifact")

	_require(bool(PhysicalArtifact.validate(built["contact_bundle"]["artifact"]).get("success", false)), "CONTACT_BAKE is real PhysicalBakeArtifact")
	_require(bool(built["contact_execution"]["ok"]), "CONTACT_BAKE executable support query succeeds")
	_require(float(built["contact_execution"]["support"]) > 0.0, "CONTACT_BAKE returns physical support")
	_require(String(built["contact_bundle"]["parent_artifact_checksum"]) == String(built["structural_bundle"]["artifact"]["checksum"]), "CONTACT_BAKE is derived from same structural parent")

	_require(bool(PhysicalArtifact.validate(built["dynamic_bundle"]["physical_artifact"]).get("success", false)), "DYNAMIC_ROM is real PhysicalBakeArtifact")
	_require(String(built["dynamic_session"]["lifecycle"]["state"]) == "ACTIVE", "DYNAMIC_ROM execution lifecycle is active")
	_require(String(entries[OwnershipFixture.DYNAMIC]["physical_artifact_checksum"]) == String(built["dynamic_bundle"]["physical_artifact"]["checksum"]), "dynamic witness binds exact physical artifact")

	_require(String(built["hybrid_package"]["mode_contract"]["execution_qualification"]) == "B0_5_A_EXECUTABLE", "HYBRID_BAKE uses B0.5-A executable mode contract")
	_require(String(built["hybrid_session"]["current_mode_id"]) == "mode/bridge2-b/hybrid-a", "HYBRID_BAKE executable session starts")
	_require(String(entries[OwnershipFixture.HYBRID]["execution_identity_hash"]) == String(built["hybrid_package"]["package_hash"]), "hybrid witness binds exact package")
	_require(String(entries[OwnershipFixture.HYBRID]["underlying_physical_artifact_checksum"]) == String(entries[OwnershipFixture.DYNAMIC]["physical_artifact_checksum"]), "hybrid wrapper reuses exact B0.4 physical artifact instead of inventing second truth")

	var reversed: Array = built["witnesses"].duplicate(true)
	reversed.reverse()
	var deterministic := Subject.compile(ownership, reversed)
	_require(bool(deterministic.get("success", false)), "reverse witness presentation compiles", deterministic)
	if bool(deterministic.get("success", false)):
		_require(String(deterministic["details"]["subject"]["subject_hash"]) == String(subject["subject_hash"]), "mixed executable subject hash deterministic")
		_require(deterministic["details"]["subject"]["entries"] == subject["entries"], "mixed executable entries deterministic")

	var foreign_seed := DynamicFixture.build("ZERO")
	var foreign_full := FullCompiler.compile(foreign_seed["request"])
	_require(bool(foreign_full.get("success", false)), "foreign full witness prerequisite compiles")
	if bool(foreign_full.get("success", false)):
		var foreign_initial := FullReference.initial_state(foreign_full["model"])
		var foreign_execution := FullReference.step(
			foreign_full["model"], foreign_initial["state"], DynamicFixture.zero_flows(foreign_full["model"]["boundary_contract"]), 0.01
		)
		var foreign_witnesses: Array = built["witnesses"].duplicate(true)
		for index in range(foreign_witnesses.size()):
			if String(foreign_witnesses[index]["representation_id"]) == OwnershipFixture.FULL:
				foreign_witnesses[index] = foreign_witnesses[index].duplicate(true)
				foreign_witnesses[index]["payload"] = {"full_model": foreign_full["model"], "execution": foreign_execution}
				break
		var foreign_result := Subject.compile(ownership, foreign_witnesses)
		_require(not bool(foreign_result.get("success", false)), "foreign-frontier executable witness rejected")
		_require(_code(foreign_result) == "BRIDGE2_B_WITNESS_FRONTIER_MISMATCH", "foreign-frontier rejection code exact")

	var wrong_region: Array = built["witnesses"].duplicate(true)
	for index in range(wrong_region.size()):
		if String(wrong_region[index]["representation_id"]) == OwnershipFixture.DYNAMIC:
			wrong_region[index] = wrong_region[index].duplicate(true)
			wrong_region[index]["region_id"] = OwnershipFixture.REGION_HYBRID
			break
	var wrong_region_result := Subject.compile(ownership, wrong_region)
	_require(not bool(wrong_region_result.get("success", false)), "witness outside active-owner region rejected")
	_require(_code(wrong_region_result) == "BRIDGE2_B_WITNESS_NOT_ACTIVE_OWNER", "wrong-region rejection code exact")

	var duplicate: Array = built["witnesses"].duplicate(true)
	duplicate[0] = duplicate[1]
	var duplicate_result := Subject.compile(ownership, duplicate)
	_require(not bool(duplicate_result.get("success", false)), "duplicate representation witness rejected")

	var tampered_frontier := subject.duplicate(true)
	tampered_frontier["entries"][0]["source_frontier_hash"] = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var tampered_frontier_result := Subject.validate(tampered_frontier, ownership)
	_require(not bool(tampered_frontier_result.get("success", false)), "tampered manifest frontier rejected")
	_require(_code(tampered_frontier_result) == "BRIDGE2_B_ENTRY_FRONTIER_MISMATCH", "tampered manifest frontier code exact")

	var missing := subject.duplicate(true)
	missing["entries"].pop_back()
	var missing_result := Subject.validate(missing, ownership)
	_require(not bool(missing_result.get("success", false)), "missing executable representation rejected")
	_require(_code(missing_result) == "BRIDGE2_B_ENTRY_COVERAGE_MISMATCH", "missing entry code exact")

	_finish(subject)

func _entry_map(subject: Dictionary) -> Dictionary:
	var output := {}
	for entry in subject["entries"]:
		output[String(entry["representation_id"])] = entry
	return output

func _finish(subject: Dictionary = {}) -> void:
	if _failed:
		printerr("FABRIC-BAKE BRIDGE-2-B Executable Mixed Subject Acceptance: FAIL (%d successful assertions)" % _checks)
		quit(1)
		return
	print("FABRIC-BAKE BRIDGE-2-B Executable Mixed Subject Acceptance: PASS (%d assertions) subject=%s" % [_checks, String(subject.get("subject_hash", ""))])
	quit(0)

func _require(condition: bool, label: String, details = null) -> bool:
	if condition:
		_checks += 1
		return true
	_failed = true
	printerr("FABRIC-BAKE BRIDGE-2-B FAILURE: %s details=%s" % [label, str(details)])
	return false

func _code(result: Dictionary) -> String:
	return String(result.get("error_code", ""))
