extends SceneTree

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const AdapterScript = preload("res://tests/simulation/fixtures/test_transaction_aggregate_adapter.gd")
const FactoryScript = preload("res://tests/simulation/fixtures/test_transaction_snapshot_factory.gd")
const ReadSetScript = preload("res://scripts/simulation/compute/mutation_read_set.gd")
const WriteSetScript = preload("res://scripts/simulation/compute/mutation_write_set.gd")
const BudgetScript = preload("res://scripts/simulation/compute/execution_budget.gd")
const InputScript = preload("res://scripts/simulation/compute/simulation_job_input_reference.gd")
const FingerprintScript = preload("res://scripts/simulation/compute/determinism_fingerprint.gd")
const CapabilityScript = preload("res://scripts/simulation/compute/compute_capability_descriptor.gd")
const WorkerScript = preload("res://scripts/simulation/compute/compute_worker_descriptor.gd")
const JobScript = preload("res://scripts/simulation/compute/simulation_job_envelope.gd")
const ProposalOperationScript = preload("res://scripts/simulation/compute/mutation_proposal_operation.gd")
const ProposalScript = preload("res://scripts/simulation/compute/mutation_proposal.gd")
const ResultScript = preload("res://scripts/simulation/compute/simulation_job_result_envelope.gd")

const RULE_HASH := "8e4e34193f8d28f82f391f67c7e9984e2497c6dd8e9771cc18c23bbeb441a5de"
const CHECKPOINT := "v16.9.0-simulation-s1-distributed-compute-fix1"
const BUILD_ID := "s1-distributed-compute-contracts-fix1"
const CURRENT_CHECKPOINT := "v16.9.1-runtime-h1-playable-listen-host"
const CURRENT_BUILD_ID := "h1-playable-listen-host"
const CURRENT_ROADMAP_CHECKPOINT := "v16.10.3-domain-m4-canonical-shared-gameplay"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_access_sets()
	_test_budget_and_worker_descriptors()
	_test_job_contract()
	_test_projection_scope_contract()
	_test_fingerprint_scope_binding()
	_test_proposal_and_result_contracts()
	_test_project_wiring()
	_finish()


func _test_access_sets() -> void:
	var read_set := _read_set()
	_assert_ok(ReadSetScript.validate(read_set), "Valid read set rejected")
	_assert(ReadSetScript.contains_path(read_set, "aggregate/environment/cell-1", "metadata.temperature_k"), "Declared read path missing")
	_assert(not ReadSetScript.contains_path(read_set, "aggregate/environment/cell-1", "metadata.secret"), "Undeclared read path accepted")
	var unsorted := ReadSetScript.create([
		ReadSetScript.entry("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, ["quantity"]),
		ReadSetScript.entry("aggregate/environment/cell-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, ["quantity"]),
	])
	_assert_error(ReadSetScript.validate(unsorted), "MUTATION_READ_SET_NOT_CANONICAL", "Unsorted read set accepted")
	var overlapping := ReadSetScript.create([ReadSetScript.entry("aggregate/environment/cell-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, ["metadata", "metadata.temperature_k"])])
	_assert_error(ReadSetScript.validate(overlapping), "MUTATION_READ_PATHS_NOT_CANONICAL", "Overlapping read paths accepted")
	var write_set := _write_set()
	_assert_ok(WriteSetScript.validate(write_set), "Valid write set rejected")
	_assert(WriteSetScript.allows_operation(write_set, "aggregate/population/grass-1", "UPDATE"), "Declared update operation missing")
	_assert(WriteSetScript.allows_path(write_set, "aggregate/population/grass-1", "metadata.last_growth_tick"), "Declared write path missing")
	_assert(not WriteSetScript.allows_path(write_set, "aggregate/population/grass-1", "metadata.secret"), "Undeclared write path accepted")
	var empty_update := WriteSetScript.create([WriteSetScript.entry("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, ["UPDATE"], [])])
	_assert_error(WriteSetScript.validate(empty_update), "UPDATE_WRITE_SET_REQUIRES_PATHS", "Update without paths accepted")
	var create_set := WriteSetScript.create([WriteSetScript.entry("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, ["CREATE"], ["quantity"])])
	_assert_error(WriteSetScript.validate(create_set), "INVALID_MUTATION_WRITE_OPERATION_KIND", "CREATE was accepted by S1 protocol v1")
	var delete_set := WriteSetScript.create([WriteSetScript.entry("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, ["DELETE"], ["quantity"])])
	_assert_error(WriteSetScript.validate(delete_set), "INVALID_MUTATION_WRITE_OPERATION_KIND", "DELETE was accepted by S1 protocol v1")


func _test_budget_and_worker_descriptors() -> void:
	var budget := _budget()
	_assert_ok(BudgetScript.validate(budget), "Valid budget rejected")
	_assert(BudgetScript.contains(BudgetScript.create(10, 65536, 10000), budget), "Containing budget rejected")
	_assert(not BudgetScript.contains(BudgetScript.create(1, 65536, 10000), budget), "Insufficient operation budget accepted")
	_assert_error(BudgetScript.validate(BudgetScript.create(0, 1, 1)), "INVALID_EXECUTION_BUDGET", "Zero operation budget accepted")
	var capability := _capability()
	_assert_ok(CapabilityScript.validate(capability), "Valid capability rejected")
	_assert(CapabilityScript.supports(capability, "VEGETATION_ADVANCE", RULE_HASH, budget), "Supported job rejected")
	_assert(not CapabilityScript.supports(capability, "WEATHER_ADVANCE", RULE_HASH, budget), "Unsupported job type accepted")
	var worker := _worker()
	_assert_ok(WorkerScript.validate(worker), "Valid worker rejected")
	_assert(not WorkerScript.find_capability(worker, "capability/vegetation-growth").is_empty(), "Worker capability not found")
	var duplicate_capabilities := WorkerScript.create("worker/test/growth-1", 1, 1, [capability, capability])
	_assert_error(WorkerScript.validate(duplicate_capabilities), "COMPUTE_WORKER_CAPABILITIES_NOT_CANONICAL", "Duplicate worker capability accepted")


func _test_job_contract() -> void:
	var job := _job()
	_assert_ok(JobScript.validate(job), "Valid simulation job rejected")
	var round_trip := NetworkUtilsScript.json_round_trip(job)
	_assert(bool(round_trip.get("success", false)) and NetworkUtilsScript.canonical_json(round_trip.get("value")) == NetworkUtilsScript.canonical_json(job), "Simulation job did not survive canonical round-trip")
	var changed_tick := job.duplicate(true)
	changed_tick["to_tick"] = 21
	_assert_error(JobScript.validate(changed_tick), "SIMULATION_JOB_DETERMINISM_FINGERPRINT_MISMATCH", "Changed job tick with stale fingerprint accepted")
	var bad_checksum := job.duplicate(true)
	bad_checksum["checksum"] = "0".repeat(64)
	_assert_error(JobScript.validate(bad_checksum), "SIMULATION_JOB_CHECKSUM_MISMATCH", "Invalid job checksum accepted")
	var unsorted_inputs := job.duplicate(true)
	unsorted_inputs["input_references"].reverse()
	_recompute_job(unsorted_inputs)
	_assert_error(JobScript.validate(unsorted_inputs), "SIMULATION_JOB_INPUTS_NOT_CANONICAL", "Unsorted job inputs accepted")
	var wrong_authority := job.duplicate(true)
	wrong_authority["input_references"][0]["authority_epoch"] = 4
	_recompute_job(wrong_authority)
	_assert_error(JobScript.validate(wrong_authority), "SIMULATION_JOB_INPUT_AUTHORITY_MISMATCH", "Input with different authority accepted")
	var wrong_write_kind := job.duplicate(true)
	wrong_write_kind["write_set"]["entries"][0]["aggregate_kind"] = "WRONG_KIND"
	_recompute_job(wrong_write_kind)
	_assert_error(JobScript.validate(wrong_write_kind), "WRITE_SET_INPUT_IDENTITY_MISMATCH", "Write-set kind different from input accepted")
	var wrong_write_schema := job.duplicate(true)
	wrong_write_schema["write_set"]["entries"][0]["state_schema"] = "wrong.state.v1"
	_recompute_job(wrong_write_schema)
	_assert_error(JobScript.validate(wrong_write_schema), "WRITE_SET_INPUT_IDENTITY_MISMATCH", "Write-set schema different from input accepted")
	_assert_ok(FingerprintScript.validate(job["determinism_fingerprint"]), "Valid deterministic fingerprint rejected")
	var changed_fingerprint: Dictionary = job["determinism_fingerprint"].duplicate(true)
	changed_fingerprint["deterministic_seed"] = 18
	_assert_error(FingerprintScript.validate(changed_fingerprint), "DETERMINISM_FINGERPRINT_MISMATCH", "Changed deterministic seed accepted")


func _test_projection_scope_contract() -> void:
	var extra_field := _job()
	extra_field["input_references"][0]["projected_state"]["metadata"]["secret"] = "leaked"
	_recompute_input(extra_field["input_references"][0])
	_recompute_job(extra_field)
	_assert_error(JobScript.validate(extra_field), "SIMULATION_JOB_PROJECTED_STATE_SCOPE_MISMATCH", "Extra projected field outside read set accepted")
	var missing_field := _job()
	missing_field["input_references"][0]["projected_state"].erase("quantity")
	_recompute_input(missing_field["input_references"][0])
	_recompute_job(missing_field)
	_assert_error(JobScript.validate(missing_field), "SIMULATION_JOB_PROJECTED_READ_PATH_MISSING", "Missing declared projected field accepted")
	var extra_input := _job()
	var extra_snapshot := FactoryScript.create_snapshot("aggregate/zz-extra", 0, 1, "FIELD", "", {}, 1, {})
	extra_input["input_references"].append(InputScript.create(extra_snapshot, {"quantity": 1}))
	_recompute_job(extra_input)
	_assert_error(JobScript.validate(extra_input), "SIMULATION_JOB_INPUT_READ_SET_MISMATCH", "Input reference outside read set accepted")


func _test_fingerprint_scope_binding() -> void:
	var job := _job()
	var baseline := String(job["determinism_fingerprint"]["fingerprint"])
	var changed_read := _read_set()
	changed_read["entries"][1]["paths"] = ["metadata.health"]
	var read_fingerprint := _fingerprint(job, "VEGETATION_ADVANCE", "capability/vegetation-growth", changed_read, _write_set())
	_assert(String(read_fingerprint["fingerprint"]) != baseline, "Read-set change did not alter fingerprint")
	var changed_write := _write_set()
	changed_write["entries"][1]["paths"] = ["metadata.last_growth_tick"]
	var write_fingerprint := _fingerprint(job, "VEGETATION_ADVANCE", "capability/vegetation-growth", _read_set(), changed_write)
	_assert(String(write_fingerprint["fingerprint"]) != baseline, "Write-set change did not alter fingerprint")
	var type_fingerprint := _fingerprint(job, "WEATHER_ADVANCE", "capability/vegetation-growth", _read_set(), _write_set())
	_assert(String(type_fingerprint["fingerprint"]) != baseline, "Job type change did not alter fingerprint")
	var capability_fingerprint := _fingerprint(job, "VEGETATION_ADVANCE", "capability/weather", _read_set(), _write_set())
	_assert(String(capability_fingerprint["fingerprint"]) != baseline, "Capability change did not alter fingerprint")


func _test_proposal_and_result_contracts() -> void:
	var operation_a := ProposalOperationScript.create_update("aggregate/environment/cell-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, {"quantity": 8})
	var operation_b := ProposalOperationScript.create_update("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, {"metadata.last_growth_tick": 20, "quantity": 7})
	_assert_ok(ProposalOperationScript.validate(operation_a), "Valid proposal operation rejected")
	var overlapping := ProposalOperationScript.create_update("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, {"metadata": {}, "metadata.last_growth_tick": 20})
	_assert_error(ProposalOperationScript.validate(overlapping), "MUTATION_PROPOSAL_PATHS_NOT_CANONICAL", "Overlapping proposal paths accepted")
	var non_finite := ProposalOperationScript.create_update("aggregate/environment/cell-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, {"quantity": NAN})
	_assert_error(ProposalOperationScript.validate(non_finite), "NON_CANONICAL_COMPUTE_VALUE", "Non-finite proposal value accepted")
	var job := _job()
	var proposal := ProposalScript.create("proposal/growth/1", String(job["job_id"]), 1, String(job["checksum"]), "worker/test/growth-1", "capability/vegetation-growth", String(job["determinism_fingerprint"]["fingerprint"]), RULE_HASH, [operation_a, operation_b], 50)
	_assert_ok(ProposalScript.validate(proposal), "Valid proposal rejected")
	_assert(int(proposal["operation_count"]) == 2 and int(proposal["output_bytes"]) > 0, "Proposal metrics not calculated")
	var changed_metric := proposal.duplicate(true)
	changed_metric["operation_count"] = 1
	changed_metric["proposal_hash"] = ProposalScript.compute_proposal_hash(changed_metric)
	changed_metric["checksum"] = ProposalScript.compute_checksum(changed_metric)
	_assert_error(ProposalScript.validate(changed_metric), "MUTATION_PROPOSAL_METRIC_MISMATCH", "Incorrect proposal operation count accepted")
	var result := ResultScript.success_result("result/growth/1", proposal)
	_assert_ok(ResultScript.validate(result), "Valid job result rejected")
	_assert(String(result["job_checksum"]) == String(job["checksum"]), "Result did not retain issued job checksum")
	var same := ResultScript.success_result("result/growth/1", proposal)
	_assert(String(result["result_hash"]) == String(same["result_hash"]), "Deterministic result hash changed for same input")
	var failure := ResultScript.failure_result("result/growth/failure", String(job["job_id"]), 1, String(job["checksum"]), "worker/test/growth-1", "TRANSIENT_WORKER_FAILURE", true)
	_assert_ok(ResultScript.validate(failure), "Valid failed result rejected")
	var result_job_mismatch := result.duplicate(true)
	result_job_mismatch["job_checksum"] = "0".repeat(64)
	result_job_mismatch["result_hash"] = ResultScript.compute_result_hash(result_job_mismatch)
	result_job_mismatch["checksum"] = ResultScript.compute_checksum(result_job_mismatch)
	_assert_error(ResultScript.validate(result_job_mismatch), "SIMULATION_JOB_RESULT_PROPOSAL_MISMATCH", "Result/proposal job checksum mismatch accepted")
	var invalid_success := result.duplicate(true)
	invalid_success["retryable"] = true
	invalid_success["result_hash"] = ResultScript.compute_result_hash(invalid_success)
	invalid_success["checksum"] = ResultScript.compute_checksum(invalid_success)
	_assert_error(ResultScript.validate(invalid_success), "INVALID_SUCCESSFUL_SIMULATION_JOB_RESULT", "Retryable successful result accepted")


func _test_project_wiring() -> void:
	var network_runner := FileAccess.get_file_as_string("res://RUN_NETWORK_CONTRACT_TESTS.ps1")
	var world_runner := FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	var s1_runner := FileAccess.get_file_as_string("res://RUN_S1_DISTRIBUTED_COMPUTE_TESTS.ps1")
	var roadmap_text := FileAccess.get_file_as_string("res://config/network/network-roadmap.v1.json")
	var architecture := FileAccess.get_file_as_string("res://docs/architecture/S1_DISTRIBUTED_COMPUTE_CONTRACTS_RU.md")
	_assert(not s1_runner.is_empty(), "S1 PowerShell runner missing")
	_assert(s1_runner.contains("Write-JsonFileAtomically") and s1_runner.contains("PSNativeCommandUseErrorActionPreference"), "S1 runner lacks atomic/stderr-safe summary")
	_assert(network_runner.contains("test_s1_distributed_compute_contracts.gd") and network_runner.contains("test_s1_distributed_compute_integration.gd"), "Network runner does not include S1")
	_assert(network_runner.contains("Foundation N0 through M4 plus M5 preparation"), "Network runner final status does not include the current M4 runtime plus M5 preparation gate")
	_assert(world_runner.contains("test_s1_distributed_compute_contracts.gd") and world_runner.contains("test_s1_distributed_compute_integration.gd"), "World runner does not include S1")
	_assert(architecture.contains("issued job") and architecture.contains("job_checksum") and architecture.contains("M0"), "S1 architecture does not document issued-job boundary")
	var roadmap = JSON.parse_string(roadmap_text)
	_assert(roadmap is Dictionary, "Roadmap JSON invalid")
	if roadmap is Dictionary:
		_assert(String(roadmap.get("project_checkpoint", "")) == CURRENT_ROADMAP_CHECKPOINT, "Roadmap checkpoint stale")
		var statuses: Dictionary = {}
		for phase in roadmap.get("phases", []):
			statuses[String(phase.get("id", ""))] = String(phase.get("status", ""))
		_assert(String(statuses.get("M0", "")) == "accepted" and String(statuses.get("S1", "")) == "accepted", "M0/S1 roadmap statuses inconsistent")
	_assert(s1_runner.contains(CURRENT_CHECKPOINT) and s1_runner.contains(CURRENT_BUILD_ID), "S1 runner checkpoint/build ID stale")
	var sources := [
		"res://scripts/simulation/compute/local_compute_worker_adapter.gd",
		"res://scripts/simulation/compute/distributed_compute_authority.gd",
		"res://scripts/simulation/compute/simulation_job_queue_bridge.gd",
	]
	for source_path in sources:
		var source := FileAccess.get_file_as_string(source_path).to_lower()
		_assert(not source.contains("nats.connect") and not source.contains("jetstream") and not source.contains("enetmultiplayerpeer"), "S1 source imports concrete network SDK: %s" % source_path)


func _read_set() -> Dictionary:
	return ReadSetScript.create([
		ReadSetScript.entry("aggregate/environment/cell-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, ["metadata.temperature_k", "quantity"]),
		ReadSetScript.entry("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, ["quantity"]),
	])


func _write_set() -> Dictionary:
	return WriteSetScript.create([
		WriteSetScript.entry("aggregate/environment/cell-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, ["UPDATE"], ["quantity"]),
		WriteSetScript.entry("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, ["UPDATE"], ["metadata.last_growth_tick", "quantity"]),
	])


func _budget() -> Dictionary:
	return BudgetScript.create(2, 65536, 1000)


func _capability() -> Dictionary:
	return CapabilityScript.create("capability/vegetation-growth", ["VEGETATION_ADVANCE"], [RULE_HASH], BudgetScript.create(8, 1048576, 100000))


func _worker() -> Dictionary:
	return WorkerScript.create("worker/test/growth-1", 1, 1, [_capability()])


func _job() -> Dictionary:
	var environment := FactoryScript.create_snapshot("aggregate/environment/cell-1", 0, 1, "FIELD", "", {}, 10, {"temperature_k": 280, "secret": "hidden"})
	var population := FactoryScript.create_snapshot("aggregate/population/grass-1", 0, 1, "FIELD", "", {}, 5, {"health": 1.0, "secret": "hidden"})
	var inputs := [
		InputScript.create(environment, {"metadata": {"temperature_k": 280}, "quantity": 10}),
		InputScript.create(population, {"quantity": 5}),
	]
	return JobScript.create("job/vegetation/growth-1", "VEGETATION_ADVANCE", 1, "capability/vegetation-growth", "authority/test-main", 3, 1, 20, inputs, _read_set(), _write_set(), RULE_HASH, "growth-v1", 17, _budget())


func _fingerprint(job: Dictionary, job_type: String, capability_id: String, read_set: Dictionary, write_set: Dictionary) -> Dictionary:
	return FingerprintScript.create(job["input_references"], job_type, capability_id, read_set, write_set, RULE_HASH, "growth-v1", 17, 1, 20)


func _recompute_input(input_reference: Dictionary) -> void:
	input_reference["projected_state_hash"] = NetworkUtilsScript.payload_hash(input_reference["projected_state"])


func _recompute_job(job: Dictionary) -> void:
	job["determinism_fingerprint"] = FingerprintScript.create(job["input_references"], String(job["job_type"]), String(job["required_capability_id"]), job["read_set"], job["write_set"], String(job["rule_package_hash"]), String(job["algorithm_version"]), int(job["deterministic_seed"]), int(job["from_tick"]), int(job["to_tick"]))
	job["checksum"] = JobScript.compute_checksum(job)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("S1 distributed compute contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("S1 distributed compute contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
