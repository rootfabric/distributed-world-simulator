extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TypeReferenceScript = preload("res://scripts/simulation/aggregates/dynamic_type_reference.gd")
const IdentityScript = preload("res://scripts/simulation/aggregates/aggregate_identity.gd")
const AuthorityScript = preload("res://scripts/simulation/aggregates/aggregate_authority_state.gd")
const ScopeScript = preload("res://scripts/simulation/aggregates/aggregate_spatial_scope.gd")
const DescriptorScript = preload("res://scripts/simulation/aggregates/aggregate_descriptor.gd")
const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/aggregate_delta_envelope.gd")
const AdapterPortScript = preload("res://scripts/simulation/aggregates/aggregate_adapter_port.gd")
const RegistryScript = preload("res://scripts/simulation/aggregates/aggregate_adapter_registry.gd")
const SpatialRefScript = preload("res://scripts/simulation/spatial/spatial_ref.gd")

const HASH: String = "0390956062ef23cd6f9c9bd0ee3b488c47e576b4dcedb14eef38d9dc359b8572"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_dynamic_type_reference()
	_test_identity_authority_scope()
	_test_snapshot_delta()
	_test_adapter_port_registry()
	_test_runner_contracts()
	_finish()


func _test_dynamic_type_reference() -> void:
	var reference: Dictionary = TypeReferenceScript.create("core:test-cell", "1.0.0", HASH, "planet_simulator.test_cell.v1")
	_assert_ok(TypeReferenceScript.validate(reference), "Valid dynamic type reference rejected")
	_assert(TypeReferenceScript.normalize(reference) == reference, "Dynamic type normalization changed valid data")
	var prerelease: Dictionary = TypeReferenceScript.create("species:berry-grass", "1.2.0-alpha.1+build.7", HASH, "planet_simulator.test_cell.v1")
	_assert_ok(TypeReferenceScript.validate(prerelease), "Valid semantic package version rejected")
	var extra: Dictionary = reference.duplicate(true)
	extra["extra"] = true
	_assert_fail(TypeReferenceScript.validate(extra), "Unexpected dynamic type field accepted")
	var bad_hash: Dictionary = reference.duplicate(true)
	bad_hash["package_hash"] = HASH.to_upper()
	_assert_fail(TypeReferenceScript.validate(bad_hash), "Uppercase package hash accepted")
	var bad_schema: Dictionary = reference.duplicate(true)
	bad_schema["state_schema"] = "Bad Schema"
	_assert_fail(TypeReferenceScript.validate(bad_schema), "Invalid state schema accepted")
	for invalid_version in ["1.0", "1..0", "01.0.0", "1.0.0-"]:
		var bad_version: Dictionary = reference.duplicate(true)
		bad_version["package_version"] = invalid_version
		_assert_fail(TypeReferenceScript.validate(bad_version), "Invalid semantic package version accepted: %s" % invalid_version)
	var bad_package: Dictionary = reference.duplicate(true)
	bad_package["package_id"] = ":missing-namespace"
	_assert_fail(TypeReferenceScript.validate(bad_package), "Package ID with empty namespace accepted")
	var runtime_value: Dictionary = reference.duplicate(true)
	runtime_value["package_id"] = RefCounted.new()
	_assert_fail(TypeReferenceScript.validate(runtime_value), "Runtime object accepted in dynamic type reference")


func _test_identity_authority_scope() -> void:
	var reference: Dictionary = TypeReferenceScript.create("core:test-cell", "1.0.0", HASH, "planet_simulator.test_cell.v1")
	var identity: Dictionary = IdentityScript.create("environment-cell/main/0/0", "ENVIRONMENT_CELL", "planet_simulator.test_cell.v1", reference)
	_assert_ok(IdentityScript.validate(identity), "Valid aggregate identity rejected")
	var mismatch: Dictionary = identity.duplicate(true)
	mismatch["state_schema"] = "planet_simulator.other.v1"
	_assert_fail(IdentityScript.validate(mismatch), "Identity/type schema mismatch accepted")
	var bad_kind: Dictionary = identity.duplicate(true)
	bad_kind["aggregate_kind"] = "environment_cell"
	_assert_fail(IdentityScript.validate(bad_kind), "Lowercase aggregate kind accepted")
	var authority: Dictionary = AuthorityScript.create("region-authority/main", 2, 7, 100)
	_assert_ok(AuthorityScript.validate(authority), "Valid authority state rejected")
	var bad_epoch: Dictionary = authority.duplicate(true)
	bad_epoch["authority_epoch"] = 0
	_assert_fail(AuthorityScript.validate(bad_epoch), "Zero authority epoch accepted")
	var none_scope: Dictionary = ScopeScript.create(ScopeScript.KIND_NONE)
	_assert_ok(ScopeScript.validate(none_scope), "NONE scope rejected")
	var cell_scope: Dictionary = ScopeScript.create(ScopeScript.KIND_CELL, {"cell_id": "cell/main/0/0"})
	_assert_ok(ScopeScript.validate(cell_scope), "CELL scope rejected")
	var point_scope: Dictionary = ScopeScript.create(ScopeScript.KIND_POINT, {"spatial_ref": SpatialRefScript.create("body/moon/fixed", Vector3.ZERO)})
	_assert_ok(ScopeScript.validate(point_scope), "POINT scope rejected")
	var bad_none: Dictionary = ScopeScript.create(ScopeScript.KIND_NONE, {"x": 1})
	_assert_fail(ScopeScript.validate(bad_none), "NONE scope with data accepted")
	var duplicate_cells: Dictionary = ScopeScript.create(ScopeScript.KIND_CELL_SET, {"cell_ids": ["cell/a", "cell/a"]})
	_assert_fail(ScopeScript.validate(duplicate_cells), "Duplicate cell IDs accepted")
	var malformed_cell: Dictionary = ScopeScript.create(ScopeScript.KIND_CELL, {"cell_id": "cell//broken"})
	_assert_fail(ScopeScript.validate(malformed_cell), "Spatial cell ID with empty path segment accepted")
	var uppercase_region: Dictionary = ScopeScript.create(ScopeScript.KIND_REGION, {"region_id": "region/Main"})
	_assert_fail(ScopeScript.validate(uppercase_region), "Uppercase spatial region ID accepted")
	var descriptor: Dictionary = DescriptorScript.create(identity, authority, cell_scope)
	_assert_ok(DescriptorScript.validate(descriptor), "Valid aggregate descriptor rejected")
	var runtime_descriptor: Dictionary = descriptor.duplicate(true)
	runtime_descriptor["partition_address"] = {"node": RefCounted.new()}
	_assert_fail(DescriptorScript.validate(runtime_descriptor), "Runtime partition value accepted")


func _test_snapshot_delta() -> void:
	var snapshot: Dictionary = _make_snapshot()
	_assert_ok(SnapshotScript.validate(snapshot), "Valid aggregate snapshot rejected")
	_assert(SnapshotScript.aggregate_id(snapshot) == "environment-cell/main/0/0", "Snapshot aggregate ID helper failed")
	var normalized: Dictionary = SnapshotScript.normalize(snapshot)
	_assert(UtilsScript.canonical_json(normalized) == UtilsScript.canonical_json(snapshot), "Aggregate snapshot normalization changed canonical content")
	var bad_checksum: Dictionary = snapshot.duplicate(true)
	bad_checksum["state"]["temperature_k"] = 999.0
	_assert_fail(SnapshotScript.validate(bad_checksum), "Modified aggregate snapshot checksum accepted")
	var runtime_state: Dictionary = snapshot.duplicate(true)
	runtime_state["state"]["node"] = RefCounted.new()
	_assert_fail(SnapshotScript.validate(runtime_state), "Runtime object accepted in aggregate state")
	var delta: Dictionary = DeltaScript.create(
		"aggregate-delta/test/1",
		"environment-cell/main/0/0",
		"ENVIRONMENT_CELL",
		"planet_simulator.test_cell.v1",
		"region-authority/main",
		2,
		7,
		8,
		101,
		{"temperature_k": 281.0, "soil.water": 0.5},
		["obsolete"]
	)
	_assert_ok(DeltaScript.validate(delta), "Valid aggregate delta rejected")
	var applied: Dictionary = DeltaScript.apply_to_snapshot(snapshot, delta)
	_assert_ok(applied, "Aggregate delta failed to apply")
	var result: Dictionary = applied.get("snapshot", {})
	_assert(float(result.get("state", {}).get("temperature_k", 0.0)) == 281.0, "Aggregate delta did not set root field")
	_assert(float(result.get("state", {}).get("soil", {}).get("water", 0.0)) == 0.5, "Aggregate delta did not set nested field")
	_assert(not result.get("state", {}).has("obsolete"), "Aggregate delta did not remove field")
	_assert(int(result.get("descriptor", {}).get("authority", {}).get("state_revision", -1)) == 8, "Aggregate delta revision not applied")
	_assert(int(result.get("descriptor", {}).get("authority", {}).get("server_tick", -1)) == 101, "Aggregate delta tick not applied")
	var stale: Dictionary = delta.duplicate(true)
	stale["base_revision"] = 6
	stale["checksum"] = DeltaScript.compute_checksum(stale)
	_assert_fail(DeltaScript.apply_to_snapshot(snapshot, stale), "Stale aggregate delta applied")
	var overlap: Dictionary = delta.duplicate(true)
	overlap["changed_fields"] = {"soil": {}, "soil.water": 0.5}
	overlap["removed_fields"] = []
	overlap["checksum"] = DeltaScript.compute_checksum(overlap)
	_assert_fail(DeltaScript.validate(overlap), "Overlapping aggregate delta paths accepted")
	var conflict: Dictionary = delta.duplicate(true)
	conflict["removed_fields"] = ["temperature_k"]
	conflict["checksum"] = DeltaScript.compute_checksum(conflict)
	_assert_fail(DeltaScript.validate(conflict), "Changed/removed path conflict accepted")


func _test_adapter_port_registry() -> void:
	_assert_fail(AdapterPortScript.validate_adapter(null), "Null aggregate adapter accepted")
	_assert_fail(AdapterPortScript.validate_adapter(RefCounted.new()), "Incomplete aggregate adapter accepted")
	_assert_fail(AdapterPortScript.validate_adapter(_FakeAdapter.new("BAD-KIND")), "Adapter kind with protocol punctuation accepted")
	var registry = RegistryScript.new()
	_assert_fail(registry.register_adapter(RefCounted.new()), "Unconfigured adapter registry accepted registration")
	_assert_ok(registry.setup(), "Adapter registry setup failed")
	var first = _FakeAdapter.new("TEST_KIND")
	var second = _FakeAdapter.new("TEST_KIND")
	_assert_ok(registry.register_adapter(first), "Valid aggregate adapter registration failed")
	var replay: Dictionary = registry.register_adapter(first)
	_assert_ok(replay, "Exact aggregate adapter replay failed")
	_assert(bool(replay.get("details", {}).get("replay", false)), "Exact adapter replay not marked")
	_assert_fail(registry.register_adapter(second), "Conflicting aggregate adapter accepted")
	_assert(registry.resolve_adapter("TEST_KIND") == first, "Adapter registry resolved wrong adapter")
	_assert(registry.get_registered_kinds() == ["TEST_KIND"], "Adapter registry kind list is wrong")


func _test_runner_contracts() -> void:
	var a1_runner: String = FileAccess.get_file_as_string("res://RUN_A1_GENERIC_AGGREGATE_TESTS.ps1")
	var network_runner: String = FileAccess.get_file_as_string("res://RUN_NETWORK_CONTRACT_TESTS.ps1")
	var world_runner: String = FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	_assert(not a1_runner.is_empty(), "A1 PowerShell runner is missing")
	_assert(a1_runner.contains("function Write-JsonFileAtomically"), "A1 runner lacks atomic JSON writer")
	_assert(a1_runner.contains("$Stream.Flush($true)"), "A1 runner does not force summary flush")
	_assert(a1_runner.contains("[IO.File]::Replace") and a1_runner.contains("[IO.File]::Move"), "A1 runner lacks atomic replace/move publication")
	_assert(a1_runner.contains("PSNativeCommandUseErrorActionPreference"), "A1 runner is not native-stderr safe")
	_assert(a1_runner.contains("finally") and a1_runner.contains("$ErrorActionPreference = $PreviousErrorActionPreference"), "A1 runner does not restore PowerShell preferences")
	_assert(a1_runner.contains("test_a1_generic_aggregate_contracts.gd"), "A1 runner omits contract tests")
	_assert(a1_runner.contains("test_a1_generic_aggregate_integration.gd"), "A1 runner omits integration tests")
	_assert(network_runner.contains("test_a1_generic_aggregate_contracts.gd") and network_runner.contains("test_a1_generic_aggregate_integration.gd"), "Network profile omits A1 suites")
	_assert(world_runner.contains("test_a1_generic_aggregate_contracts.gd") and world_runner.contains("test_a1_generic_aggregate_integration.gd"), "World regression omits A1 suites")
	_assert(world_runner.contains('$ExcludedTestDirectoryNames = @("fixtures")'), "World regression does not declare fixture directory exclusion")
	_assert(world_runner.contains("function Test-IsStandaloneTestScript"), "World regression lacks standalone-test discovery policy")
	_assert(world_runner.contains("Where-Object { Test-IsStandaloneTestScript -File $_ }"), "World regression does not apply fixture filtering during discovery")
	_assert(not world_runner.contains('"res://tests/simulation/fixtures/test_environment_cell_adapter.gd"'), "Environment cell adapter fixture is listed as a standalone world test")
	_assert(not world_runner.contains('"res://tests/simulation/fixtures/test_environment_cell_aggregate.gd"'), "Environment cell aggregate fixture is listed as a standalone world test")


func _make_snapshot() -> Dictionary:
	var reference: Dictionary = TypeReferenceScript.create("core:test-cell", "1.0.0", HASH, "planet_simulator.test_cell.v1")
	var identity: Dictionary = IdentityScript.create("environment-cell/main/0/0", "ENVIRONMENT_CELL", "planet_simulator.test_cell.v1", reference)
	var authority: Dictionary = AuthorityScript.create("region-authority/main", 2, 7, 100)
	var scope: Dictionary = ScopeScript.create(ScopeScript.KIND_CELL, {"cell_id": "cell/main/0/0"})
	var descriptor: Dictionary = DescriptorScript.create(identity, authority, scope)
	return SnapshotScript.create("aggregate-snapshot/test/1", descriptor, {
		"temperature_k": 278.0,
		"soil": {"water": 0.25},
		"obsolete": true,
	})


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("A1 generic aggregate contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("A1 generic aggregate contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


class _FakeAdapter:
	extends RefCounted
	var kind: String
	func _init(kind_value: String) -> void:
		kind = kind_value
	func get_aggregate_kind() -> String:
		return kind
	func supports_aggregate(_value) -> bool:
		return true
	func validate_snapshot(_snapshot: Dictionary) -> Dictionary:
		return {"success": true}
	func validate_delta(_delta: Dictionary) -> Dictionary:
		return {"success": true}
	func export_snapshot(_value, _snapshot_id: String) -> Dictionary:
		return {}
	func export_delta(_base_snapshot: Dictionary, _value, _delta_id: String) -> Dictionary:
		return {}
