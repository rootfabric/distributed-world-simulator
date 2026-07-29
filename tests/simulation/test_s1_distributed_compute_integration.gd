extends SceneTree

const RegistryScript = preload("res://scripts/simulation/aggregates/aggregate_adapter_registry.gd")
const AdapterScript = preload("res://tests/simulation/fixtures/test_transaction_aggregate_adapter.gd")
const FactoryScript = preload("res://tests/simulation/fixtures/test_transaction_snapshot_factory.gd")
const RepositoryScript = preload("res://scripts/simulation/transactions/aggregate_transaction_repository.gd")
const TransactionCoordinatorScript = preload("res://scripts/simulation/transactions/aggregate_transaction_coordinator.gd")
const InvariantRegistryScript = preload("res://scripts/simulation/transactions/transaction_invariant_registry.gd")
const PreconditionScript = preload("res://scripts/simulation/transactions/aggregate_precondition.gd")
const TransactionOperationScript = preload("res://scripts/simulation/transactions/aggregate_mutation_operation.gd")
const BatchScript = preload("res://scripts/simulation/transactions/mutation_batch.gd")
const JobQueueAdapterScript = preload("res://scripts/network/bus/adapters/in_memory_job_queue_adapter.gd")
const ReadSetScript = preload("res://scripts/simulation/compute/mutation_read_set.gd")
const WriteSetScript = preload("res://scripts/simulation/compute/mutation_write_set.gd")
const BudgetScript = preload("res://scripts/simulation/compute/execution_budget.gd")
const CapabilityScript = preload("res://scripts/simulation/compute/compute_capability_descriptor.gd")
const WorkerDescriptorScript = preload("res://scripts/simulation/compute/compute_worker_descriptor.gd")
const WorkerRegistryScript = preload("res://scripts/simulation/compute/compute_worker_registry.gd")
const JobScript = preload("res://scripts/simulation/compute/simulation_job_envelope.gd")
const FingerprintScript = preload("res://scripts/simulation/compute/determinism_fingerprint.gd")
const JobFactoryScript = preload("res://scripts/simulation/compute/simulation_job_factory.gd")
const JobQueueBridgeScript = preload("res://scripts/simulation/compute/simulation_job_queue_bridge.gd")
const LocalWorkerScript = preload("res://scripts/simulation/compute/local_compute_worker_adapter.gd")
const AuthorityScript = preload("res://scripts/simulation/compute/distributed_compute_authority.gd")
const HandlerScript = preload("res://tests/simulation/fixtures/test_growth_compute_handler.gd")
const ProposalOperationScript = preload("res://scripts/simulation/compute/mutation_proposal_operation.gd")
const ProposalScript = preload("res://scripts/simulation/compute/mutation_proposal.gd")
const ResultScript = preload("res://scripts/simulation/compute/simulation_job_result_envelope.gd")

const RULE_HASH := "8e4e34193f8d28f82f391f67c7e9984e2497c6dd8e9771cc18c23bbeb441a5de"

var assertions := 0
var failures: Array[String] = []
var _root: String


func _init() -> void:
	_root = "user://s1-integration-%d" % Time.get_ticks_usec()
	_test_queue_worker_authority_commit_and_replay()
	_test_input_projection_and_determinism()
	_test_stale_proposal_fencing()
	_test_malicious_write_and_budget_fencing()
	_test_worker_capability_fencing()
	_test_issued_job_registry_and_forgery_fencing()
	_finish()


func _test_queue_worker_authority_commit_and_replay() -> void:
	var runtime := _new_runtime("workflow")
	var job_result := _create_job(runtime, _budget())
	_assert_ok(job_result, "Job creation failed")
	_assert(not bool(job_result["details"]["replay"]), "First issued job marked replay")
	var job: Dictionary = job_result["details"]["job"]
	var issued: Dictionary = runtime["authority"].get_issued_job(String(job["job_id"]), int(job["job_attempt"]))
	_assert_ok(issued, "Authority did not retain issued job")
	_assert(String(issued["details"]["job"]["checksum"]) == String(job["checksum"]), "Issued job checksum changed")
	var submit: Dictionary = runtime["queue_bridge"].submit(job)
	_assert(bool(submit.get("success", false)) and String(submit.get("outcome", "")) == "ACCEPTED", "Simulation job was not accepted by B0 queue")
	var claim: Dictionary = runtime["queue_bridge"].claim("worker/test/growth-1")
	_assert_ok(claim, "Simulation job claim failed")
	_assert(String(claim["details"]["job"]["checksum"]) == String(job["checksum"]), "Queue bridge changed simulation job")
	var worker_output: Dictionary = runtime["worker"].execute(claim["details"]["job"])
	_assert_ok(worker_output, "Local worker execution failed")
	var result: Dictionary = worker_output["details"]["result"]
	_assert(bool(result["success"]), "Local worker returned failed result")
	_assert(String(result["job_checksum"]) == String(job["checksum"]), "Worker result lost issued job checksum")
	var before: Dictionary = runtime["transaction"].get_state_report()
	_assert_ok(before, "Pre-commit state report failed")
	var accepted: Dictionary = runtime["authority"].accept_result(result)
	_assert_ok(accepted, "Authority rejected valid result")
	_assert(not bool(accepted["details"]["replay"]), "First compute result marked replay")
	_assert(accepted["details"]["transaction_result"]["updated_aggregate_ids"].size() == 2, "Compute transaction did not update two aggregates")
	var ack: Dictionary = runtime["queue_bridge"].acknowledge(String(claim["details"]["delivery_id"]), "worker/test/growth-1")
	_assert(bool(ack.get("success", false)) and String(ack.get("outcome", "")) == "ACKNOWLEDGED", "Job delivery was not acknowledged after commit")
	var environment: Dictionary = runtime["transaction"].get_snapshot("aggregate/environment/cell-1")
	var population: Dictionary = runtime["transaction"].get_snapshot("aggregate/population/grass-1")
	_assert_ok(environment, "Environment aggregate missing after compute")
	_assert_ok(population, "Population aggregate missing after compute")
	_assert(int(environment["details"]["snapshot"]["state"]["quantity"]) == 8, "Environment resource was not consumed")
	_assert(int(population["details"]["snapshot"]["state"]["quantity"]) == 7, "Population biomass was not produced")
	_assert(int(population["details"]["snapshot"]["state"]["metadata"]["last_growth_tick"]) == 20, "Population growth tick missing")
	_assert(int(environment["details"]["snapshot"]["descriptor"]["authority"]["state_revision"]) == 1, "Environment revision did not advance")
	_assert(int(population["details"]["snapshot"]["descriptor"]["authority"]["server_tick"]) == 20, "Population tick did not advance")
	var after: Dictionary = runtime["transaction"].get_state_report()
	_assert_ok(after, "Post-commit state report failed")
	_assert(int(after["details"]["generation"]) == int(before["details"]["generation"]) + 1, "Compute commit did not create exactly one generation")
	_assert(int(after["details"]["outbox_count"]) == 1, "Compute commit did not create one outbox record")
	var replay: Dictionary = runtime["authority"].accept_result(result)
	_assert_ok(replay, "Exact compute result replay failed")
	_assert(bool(replay["details"]["replay"]), "Exact compute result did not report replay")
	var replay_state: Dictionary = runtime["transaction"].get_state_report()
	_assert(int(replay_state["details"]["generation"]) == int(after["details"]["generation"]), "Compute replay advanced transaction generation")
	var changed_operation := ProposalOperationScript.create_update("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, {"metadata.last_growth_tick": 20, "quantity": 8})
	var changed_proposal := ProposalScript.create(String(result["proposal"]["proposal_id"]), String(job["job_id"]), 1, String(job["checksum"]), "worker/test/growth-1", "capability/vegetation-growth", String(job["determinism_fingerprint"]["fingerprint"]), RULE_HASH, [result["proposal"]["operations"][0], changed_operation], 50)
	var changed_result := ResultScript.success_result(String(result["result_id"]), changed_proposal)
	_assert_error(runtime["authority"].accept_result(changed_result), "COMPUTE_RESULT_CONFLICT", "Changed result reused accepted job attempt")


func _test_input_projection_and_determinism() -> void:
	var runtime := _new_runtime("determinism")
	var job_result := _create_job(runtime, _budget())
	_assert_ok(job_result, "Determinism job creation failed")
	var job: Dictionary = job_result["details"]["job"]
	var original_checksum: String = String(job["checksum"])
	var first: Dictionary = runtime["worker"].execute(job)
	_assert_ok(first, "First deterministic worker run failed")
	var second: Dictionary = runtime["worker"].execute(job)
	_assert_ok(second, "Second deterministic worker run failed")
	_assert(String(first["details"]["result"]["result_hash"]) == String(second["details"]["result"]["result_hash"]), "Same job produced different result hash")
	_assert(String(first["details"]["result"]["proposal"]["proposal_hash"]) == String(second["details"]["result"]["proposal"]["proposal_hash"]), "Same job produced different proposal hash")
	_assert(String(job["checksum"]) == original_checksum, "Worker mutated authoritative job DTO")
	var received: Dictionary = runtime["handler"].last_received_job
	_assert(not received.has("repository") and not received.has("aggregate_registry"), "Worker received live infrastructure port")
	for input_reference in received.get("input_references", []):
		_assert(not Dictionary(input_reference.get("projected_state", {})).get("metadata", {}).has("secret"), "Worker received undeclared secret state")
	_assert(int(job["input_references"][0]["projected_state"]["quantity"]) == 10, "Handler mutation aliased original job input")
	_assert(runtime["handler"].invocation_count == 2, "Deterministic worker handler invocation count mismatch")


func _test_stale_proposal_fencing() -> void:
	var runtime := _new_runtime("stale")
	var job_result := _create_job(runtime, _budget())
	_assert_ok(job_result, "Stale job creation failed")
	var job: Dictionary = job_result["details"]["job"]
	var worker_output: Dictionary = runtime["worker"].execute(job)
	_assert_ok(worker_output, "Stale worker execution failed")
	var current: Dictionary = runtime["transaction"].get_snapshot("aggregate/environment/cell-1")["details"]["snapshot"]
	var changed := FactoryScript.create_snapshot("aggregate/environment/cell-1", 1, 5, "FIELD", "", {}, 9, {"temperature_k": 280, "secret": "hidden"})
	var precondition := PreconditionScript.create("aggregate/environment/cell-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, true, "authority/test-main", 3, 0)
	var operation := TransactionOperationScript.create(TransactionOperationScript.OP_UPDATE, "aggregate/environment/cell-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, changed)
	var batch := BatchScript.create("batch/external-environment-change", "operation/external-environment-change", "authority/test-main", 3, 5, [precondition], [operation], [])
	_assert_ok(runtime["transaction"].execute_batch(batch), "External aggregate change failed")
	var before: Dictionary = runtime["transaction"].get_state_report()
	_assert_error(runtime["authority"].accept_result(worker_output["details"]["result"]), "STALE_COMPUTE_INPUT_CHECKSUM", "Stale proposal was accepted")
	var after: Dictionary = runtime["transaction"].get_state_report()
	_assert(String(after["details"]["state_checksum"]) == String(before["details"]["state_checksum"]), "Stale proposal changed state")
	_assert(String(current["checksum"]) != String(runtime["transaction"].get_snapshot("aggregate/environment/cell-1")["details"]["snapshot"]["checksum"]), "External change did not alter input checksum")


func _test_malicious_write_and_budget_fencing() -> void:
	var runtime := _new_runtime("fences")
	var job_result := _create_job(runtime, _budget())
	_assert_ok(job_result, "Fence job creation failed")
	var job: Dictionary = job_result["details"]["job"]
	var valid_output: Dictionary = runtime["worker"].execute(job)
	_assert_ok(valid_output, "Valid worker output failed")
	var valid_result: Dictionary = valid_output["details"]["result"]
	var malicious_operation := ProposalOperationScript.create_update("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, {"metadata.secret": "tampered", "quantity": 7})
	var malicious_proposal := ProposalScript.create("proposal/malicious/write", String(job["job_id"]), 1, String(job["checksum"]), "worker/test/growth-1", "capability/vegetation-growth", String(job["determinism_fingerprint"]["fingerprint"]), RULE_HASH, [valid_result["proposal"]["operations"][0], malicious_operation], 50)
	var malicious_result := ResultScript.success_result("result/malicious/write", malicious_proposal)
	_assert_error(runtime["authority"].accept_result(malicious_result), "UNDECLARED_COMPUTE_WRITE", "Authority accepted undeclared write")
	var constrained_job_result := _create_job(runtime, BudgetScript.create(1, 65536, 1000), "job/vegetation/budget-ops")
	_assert_ok(constrained_job_result, "Constrained job creation failed")
	var constrained_output: Dictionary = runtime["worker"].execute(constrained_job_result["details"]["job"])
	_assert_ok(constrained_output, "Constrained worker did not return result envelope")
	_assert(not bool(constrained_output["details"]["result"]["success"]) and String(constrained_output["details"]["result"]["error_code"]) == "COMPUTE_OPERATION_BUDGET_EXCEEDED", "Operation budget overflow not fenced")
	var output_job_result := _create_job(runtime, BudgetScript.create(2, 128, 1000), "job/vegetation/budget-output")
	_assert_ok(output_job_result, "Output budget job creation failed")
	var output_budget_result: Dictionary = runtime["worker"].execute(output_job_result["details"]["job"])
	_assert(not bool(output_budget_result["details"]["result"]["success"]) and String(output_budget_result["details"]["result"]["error_code"]) == "COMPUTE_OUTPUT_BUDGET_EXCEEDED", "Output byte budget overflow not fenced")
	runtime["handler"].instruction_units = 2000
	var instruction_job_result := _create_job(runtime, BudgetScript.create(2, 65536, 1000), "job/vegetation/budget-instructions")
	_assert_ok(instruction_job_result, "Instruction budget job creation failed")
	var instruction_output: Dictionary = runtime["worker"].execute(instruction_job_result["details"]["job"])
	_assert(not bool(instruction_output["details"]["result"]["success"]) and String(instruction_output["details"]["result"]["error_code"]) == "COMPUTE_INSTRUCTION_BUDGET_EXCEEDED", "Instruction budget overflow not fenced")


func _test_worker_capability_fencing() -> void:
	var runtime := _new_runtime("capability")
	var job_result := _create_job(runtime, _budget())
	_assert_ok(job_result, "Capability job creation failed")
	var original_job: Dictionary = job_result["details"]["job"]
	var unsupported_job := original_job.duplicate(true)
	unsupported_job["required_capability_id"] = "capability/weather"
	_recompute_job(unsupported_job)
	var invalid = runtime["worker"].execute(unsupported_job)
	_assert_ok(invalid, "Capability rejection did not return a result envelope")
	_assert(not bool(invalid["details"]["result"]["success"]) and String(invalid["details"]["result"]["error_code"]) == "WORKER_CAPABILITY_NOT_FOUND", "Unknown capability was not fenced")
	var unregistered_result: Dictionary = runtime["worker"].execute(original_job)
	_assert_ok(unregistered_result, "Worker result creation failed")
	var empty_registry := WorkerRegistryScript.new()
	var alternate_authority := AuthorityScript.new()
	_assert_ok(alternate_authority.configure(runtime["transaction"], runtime["registry"], empty_registry), "Alternate authority configure failed")
	_assert_ok(alternate_authority.register_issued_job(original_job), "Alternate authority could not register issued job")
	_assert_error(alternate_authority.accept_result(unregistered_result["details"]["result"]), "COMPUTE_WORKER_NOT_FOUND", "Unregistered worker result accepted")


func _test_issued_job_registry_and_forgery_fencing() -> void:
	var runtime := _new_runtime("issued-fencing")
	var job_result := _create_job(runtime, _budget())
	_assert_ok(job_result, "Issued-job test creation failed")
	var job: Dictionary = job_result["details"]["job"]
	var valid_output: Dictionary = runtime["worker"].execute(job)
	_assert_ok(valid_output, "Issued-job worker execution failed")
	var valid_result: Dictionary = valid_output["details"]["result"]
	var no_issue_authority := AuthorityScript.new()
	_assert_ok(no_issue_authority.configure(runtime["transaction"], runtime["registry"], runtime["worker_registry"]), "No-issue authority configure failed")
	_assert_error(no_issue_authority.accept_result(valid_result), "COMPUTE_JOB_NOT_ISSUED", "Result for non-issued job accepted")
	var conflicting_job := job.duplicate(true)
	conflicting_job["deterministic_seed"] = 18
	_recompute_job(conflicting_job)
	_assert_ok(JobScript.validate(conflicting_job), "Conflicting job fixture invalid")
	_assert_error(runtime["authority"].register_issued_job(conflicting_job), "COMPUTE_JOB_CONFLICT", "Different job reused issued job attempt")
	var before_report: Dictionary = runtime["transaction"].get_state_report()
	_assert_ok(before_report, "Pre-forgery state report failed")
	var before_environment: Dictionary = runtime["transaction"].get_snapshot("aggregate/environment/cell-1")["details"]["snapshot"]
	var before_population: Dictionary = runtime["transaction"].get_snapshot("aggregate/population/grass-1")["details"]["snapshot"]
	var forged_job := job.duplicate(true)
	forged_job["to_tick"] = 999
	forged_job["write_set"]["entries"][1]["paths"] = ["metadata.last_growth_tick", "metadata.secret", "quantity"]
	_recompute_job(forged_job)
	_assert_ok(JobScript.validate(forged_job), "Forged self-consistent job fixture invalid")
	var forged_environment := ProposalOperationScript.create_update("aggregate/environment/cell-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, {"quantity": 8})
	var forged_population := ProposalOperationScript.create_update("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, {"metadata.last_growth_tick": 999, "metadata.secret": "owned", "quantity": 7})
	var forged_proposal := ProposalScript.create("proposal/forged/job", String(forged_job["job_id"]), int(forged_job["job_attempt"]), String(forged_job["checksum"]), "worker/test/growth-1", "capability/vegetation-growth", String(forged_job["determinism_fingerprint"]["fingerprint"]), RULE_HASH, [forged_environment, forged_population], 50)
	var forged_result := ResultScript.success_result("result/forged/job", forged_proposal)
	_assert_ok(ResultScript.validate(forged_result), "Forged result fixture is not self-consistent")
	_assert_error(runtime["authority"].accept_result(forged_result), "COMPUTE_JOB_CHECKSUM_MISMATCH", "Self-consistent forged job result was accepted")
	var after_report: Dictionary = runtime["transaction"].get_state_report()
	var after_environment: Dictionary = runtime["transaction"].get_snapshot("aggregate/environment/cell-1")["details"]["snapshot"]
	var after_population: Dictionary = runtime["transaction"].get_snapshot("aggregate/population/grass-1")["details"]["snapshot"]
	_assert(int(after_report["details"]["generation"]) == int(before_report["details"]["generation"]), "Forged result advanced M0 generation")
	_assert(String(after_report["details"]["state_checksum"]) == String(before_report["details"]["state_checksum"]), "Forged result changed authoritative state checksum")
	_assert(int(after_report["details"]["outbox_count"]) == int(before_report["details"]["outbox_count"]), "Forged result added outbox record")
	_assert(String(after_environment["checksum"]) == String(before_environment["checksum"]), "Forged result changed environment snapshot")
	_assert(String(after_population["checksum"]) == String(before_population["checksum"]), "Forged result changed population snapshot")
	_assert(int(after_population["descriptor"]["authority"]["state_revision"]) == int(before_population["descriptor"]["authority"]["state_revision"]), "Forged result changed state revision")
	_assert(int(after_population["descriptor"]["authority"]["server_tick"]) == int(before_population["descriptor"]["authority"]["server_tick"]), "Forged result changed server tick")
	_assert(not after_population["state"]["metadata"].has("secret") or String(after_population["state"]["metadata"]["secret"]) == "hidden", "Forged result wrote hidden metadata")


func _new_runtime(suffix: String) -> Dictionary:
	var registry := RegistryScript.new()
	_assert_ok(registry.setup(), "Aggregate registry setup failed")
	_assert_ok(registry.register_adapter(AdapterScript.new()), "Transaction adapter registration failed")
	var repository := RepositoryScript.new()
	_assert_ok(repository.configure(_root.path_join(suffix)), "Transaction repository configure failed")
	var invariant_registry := InvariantRegistryScript.new()
	_assert_ok(invariant_registry.setup(), "Invariant registry setup failed")
	var transaction := TransactionCoordinatorScript.new()
	_assert_ok(transaction.configure(registry, repository, invariant_registry), "Transaction coordinator configure failed")
	_assert_ok(transaction.bootstrap(_base_snapshots()), "Transaction bootstrap failed")
	var worker_registry := WorkerRegistryScript.new()
	_assert_ok(worker_registry.register_worker(_worker_descriptor()), "Worker registration failed")
	var authority := AuthorityScript.new()
	_assert_ok(authority.configure(transaction, registry, worker_registry), "Compute authority configure failed")
	var job_factory := JobFactoryScript.new()
	_assert_ok(job_factory.configure(transaction, authority), "Job factory configure failed")
	var handler := HandlerScript.new()
	var worker := LocalWorkerScript.new()
	_assert_ok(worker.configure(_worker_descriptor(), handler), "Local worker configure failed")
	var queue_adapter := JobQueueAdapterScript.new("adapter/s1-in-memory-job-queue", 16)
	var queue_bridge := JobQueueBridgeScript.new()
	_assert_ok(queue_bridge.configure(queue_adapter), "Queue bridge configure failed")
	return {
		"registry": registry,
		"repository": repository,
		"transaction": transaction,
		"job_factory": job_factory,
		"worker_registry": worker_registry,
		"handler": handler,
		"worker": worker,
		"authority": authority,
		"queue_adapter": queue_adapter,
		"queue_bridge": queue_bridge,
	}


func _base_snapshots() -> Array:
	return [
		FactoryScript.create_snapshot("aggregate/environment/cell-1", 0, 1, "FIELD", "", {}, 10, {"temperature_k": 280, "secret": "hidden"}),
		FactoryScript.create_snapshot("aggregate/population/grass-1", 0, 1, "FIELD", "", {}, 5, {"health": 1.0, "secret": "hidden"}),
	]


func _create_job(runtime: Dictionary, budget: Dictionary, job_id: String = "job/vegetation/growth-1") -> Dictionary:
	return runtime["job_factory"].create_job(job_id, "VEGETATION_ADVANCE", 1, "capability/vegetation-growth", "authority/test-main", 3, 1, 20, _read_set(), _write_set(), RULE_HASH, "growth-v1", 17, budget)


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


func _worker_descriptor() -> Dictionary:
	var capability := CapabilityScript.create("capability/vegetation-growth", ["VEGETATION_ADVANCE"], [RULE_HASH], BudgetScript.create(8, 1048576, 100000))
	return WorkerDescriptorScript.create("worker/test/growth-1", 1, 1, [capability])


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
		print("S1 distributed compute integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("S1 distributed compute integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
