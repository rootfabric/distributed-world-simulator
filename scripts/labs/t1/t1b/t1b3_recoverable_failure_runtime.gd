extends "res://scripts/labs/t1/t1a7/t1_d0_recoverable_runtime_executor.gd"

const DependencyPropagatorScript = preload("res://scripts/construction/behavior/construction_runtime_dependency_failure_propagator.gd")
const CommandFailureHandlerScript = preload("res://scripts/construction/behavior/construction_runtime_command_failure_handler.gd")
const RuntimeSnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/construction_runtime_snapshot.gd")

const T1B3_SCHEMA: String = "planet_simulator.t1b3_recoverable_failure_runtime.v1"

var _failure_handler


func setup(m0_root: String) -> Dictionary:
	var base: Dictionary = super.setup(m0_root)
	if not bool(base.get("success", false)):
		return base

	_failure_handler = CommandFailureHandlerScript.new()
	var handler_setup: Dictionary = _failure_handler.setup(
		Callable(self, "_handle_runtime_command"),
		{
			"OPEN_DOOR": CommandFailureHandlerScript.POLICY_REQUIRE_ONLINE,
			"CLOSE_DOOR": CommandFailureHandlerScript.POLICY_REQUIRE_ONLINE,
			"TOGGLE_LIGHT": CommandFailureHandlerScript.POLICY_ALLOW_DEGRADED,
			"USE_WORKSTATION": CommandFailureHandlerScript.POLICY_REQUIRE_ONLINE,
			"START_GENERATOR": CommandFailureHandlerScript.POLICY_ALLOW_OFFLINE,
			"STOP_GENERATOR": CommandFailureHandlerScript.POLICY_ALLOW_OFFLINE,
		}
	)
	if not bool(handler_setup.get("success", false)):
		return _failure("T1B3_COMMAND_FAILURE_HANDLER_SETUP_FAILED", {"cause": handler_setup})

	_runtime_executor = RuntimeExecutorScript.new()
	var executor_setup: Dictionary = _runtime_executor.setup(
		_runtime_store,
		_runtime_ledger,
		Callable(_failure_handler, "handle"),
		Callable(self, "_commit_runtime_effect")
	)
	if not bool(executor_setup.get("success", false)):
		return _failure("T1B3_RUNTIME_EXECUTOR_SETUP_FAILED", {"cause": executor_setup})

	return _success({
		"schema": T1B3_SCHEMA,
		"report": get_report(),
		"failure_handler": _failure_handler.report(),
	})


func apply_failure_plan(
	requirements_by_runtime_id: Dictionary,
	base_availability_by_runtime_id: Dictionary,
	edges: Array
) -> Dictionary:
	if not _configured or _runtime_store == null:
		return _failure("T1B3_RUNTIME_NOT_CONFIGURED")
	var state: Dictionary = _runtime_store.to_dict()
	var plan: Dictionary = DependencyPropagatorScript.plan(
		Array(state.get("subjects", [])),
		requirements_by_runtime_id,
		base_availability_by_runtime_id,
		edges
	)
	if not bool(plan.get("success", false)):
		return _failure("T1B3_FAILURE_PLAN_REJECTED", {"cause": plan})

	var applied: Array[String] = []
	for proposal_value in Array(plan.get("proposals", [])):
		if not proposal_value is Dictionary:
			return _failure("T1B3_FAILURE_PLAN_PROPOSAL_INVALID")
		var proposal: Dictionary = Dictionary(proposal_value)
		if not bool(proposal.get("changed", false)):
			continue
		var runtime_id: String = String(proposal.get("runtime_id", ""))
		var committed: Dictionary = _runtime_store.update_subject(
			runtime_id,
			int(proposal.get("expected_revision", -1)),
			Dictionary(proposal.get("next_state", {}))
		)
		if not bool(committed.get("success", false)):
			return _failure("T1B3_FAILURE_PROPOSAL_COMMIT_FAILED", {
				"runtime_id": runtime_id,
				"cause": committed,
				"already_applied_runtime_ids": applied,
			})
		applied.append(runtime_id)

	return _success({
		"schema": T1B3_SCHEMA,
		"plan": plan.duplicate(true),
		"applied_runtime_ids": applied,
		"runtime_state": _runtime_store.to_dict(),
	})


func create_runtime_snapshot(authority_epoch: int, server_tick: int) -> Dictionary:
	if not _configured or _runtime_store == null:
		return _failure("T1B3_RUNTIME_NOT_CONFIGURED")
	var snapshot: Dictionary = RuntimeSnapshotScript.create(
		CONSTRUCT_ID,
		authority_epoch,
		server_tick,
		_runtime_store.to_dict()
	)
	var validation: Dictionary = RuntimeSnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		return _failure("T1B3_RUNTIME_SNAPSHOT_INVALID", {"cause": validation})
	return _success({"snapshot": snapshot})


func get_failure_handler_report() -> Dictionary:
	return _failure_handler.report() if _failure_handler != null else {}
