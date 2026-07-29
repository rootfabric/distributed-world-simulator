extends RefCounted

const OperationScript = preload("res://scripts/simulation/compute/mutation_proposal_operation.gd")
const AdapterScript = preload("res://tests/simulation/fixtures/test_transaction_aggregate_adapter.gd")

var last_received_job: Dictionary = {}
var invocation_count := 0
var extra_operation := false
var undeclared_write := false
var instruction_units := 50


func execute_simulation_job(job: Dictionary) -> Dictionary:
	invocation_count += 1
	last_received_job = job.duplicate(true)
	var environment := _input(job, "aggregate/environment/cell-1")
	var population := _input(job, "aggregate/population/grass-1")
	var water := int(environment.get("projected_state", {}).get("quantity", 0))
	var biomass := int(population.get("projected_state", {}).get("quantity", 0))
	if not job.get("input_references", []).is_empty():
		job["input_references"][0]["projected_state"]["quantity"] = -999
	var environment_changes := {"quantity": maxi(0, water - 2)}
	var population_changes := {"metadata.last_growth_tick": int(job.get("to_tick", 0)), "quantity": biomass + 2}
	if undeclared_write:
		population_changes["metadata.secret"] = "tampered"
	var operations: Array = [
		OperationScript.create_update("aggregate/environment/cell-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, environment_changes),
		OperationScript.create_update("aggregate/population/grass-1", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, population_changes),
	]
	if extra_operation:
		operations.append(OperationScript.create_update("aggregate/population/extra", AdapterScript.AGGREGATE_KIND, AdapterScript.STATE_SCHEMA, {"quantity": 1}))
	return {"success": true, "operations": operations, "instruction_units": instruction_units}


func _input(job: Dictionary, aggregate_id: String) -> Dictionary:
	for input_reference in job.get("input_references", []):
		if String(input_reference.get("aggregate_id", "")) == aggregate_id:
			return input_reference
	return {}
