extends SceneTree

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Fixture = preload("res://tests/matter/transactions/mw10_test_fixture.gd")
const Plan = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_plan.gd")
const Receipt = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_receipt.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const BrickAddress = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const LocalLedger = preload("res://scripts/simulation/matter/contracts/matter_mass_ledger.gd")
const MatterResult = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const MaterialBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const PhysicalOutput = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_physical_output.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_valid_contract_and_determinism()
	_test_receipt_and_result_bindings()
	_test_region_and_external_mass_binding()
	_test_exact_fields_and_no_thermodynamic_synthesis()
	if failures.is_empty():
		print("MW10 canonical physical output: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("MW10 canonical physical output: FAIL (%d assertions, %d failures)" % [
			assertions, failures.size()
		])
		quit(1)


func _test_valid_contract_and_determinism() -> void:
	var plan: Dictionary = Fixture.plan_ab()
	var a: Dictionary = _output(plan, Fixture.REGION_A, 7.0, 2.8, 240.0, 0)
	var b: Dictionary = _output(plan, Fixture.REGION_B, 3.0, 1.2, 265.0, 1)
	var value: Dictionary = PhysicalOutput.create(plan, [b, a])
	_assert(not value.is_empty(), "valid physical output created")
	_assert_ok(PhysicalOutput.validate(value), "valid physical output validates")
	_assert(
		String(value["participant_outputs"][0]["region_id"]) == Fixture.REGION_A,
		"participant physical outputs sort by region"
	)
	_assert(
		String(value["participant_outputs"][1]["region_id"]) == Fixture.REGION_B,
		"participant B sorted second"
	)
	_assert(absf(float(value["total_mass_kg"]) - 10.0) <= 0.000001, "total mass derives from canonical batches")
	_assert(absf(float(value["total_bulk_volume_m3"]) - 4.0) <= 0.000001, "total volume derives from canonical batches")
	var same: Dictionary = PhysicalOutput.create(plan, [a, b])
	_assert(String(same.get("checksum", "")) == String(value.get("checksum", "")), "arrival order does not affect checksum")
	_assert(
		PhysicalOutput.material_batches(value).size() == 2,
		"contract preserves participant batches instead of synthesizing one"
	)
	_assert(
		float(PhysicalOutput.participant_output_by_region(value, Fixture.REGION_A)["material_batch"]["temperature_k"]) == 240.0,
		"region A temperature is preserved"
	)
	_assert(
		float(PhysicalOutput.participant_output_by_region(value, Fixture.REGION_B)["material_batch"]["temperature_k"]) == 265.0,
		"region B temperature is preserved"
	)


func _test_receipt_and_result_bindings() -> void:
	var plan: Dictionary = Fixture.plan_ab()
	var a: Dictionary = _output(plan, Fixture.REGION_A, 7.0, 2.8, 240.0, 0)
	var b: Dictionary = _output(plan, Fixture.REGION_B, 3.0, 1.2, 265.0, 1)
	var value: Dictionary = PhysicalOutput.create(plan, [a, b])

	var bad_receipt: Dictionary = value.duplicate(true)
	bad_receipt["participant_outputs"][0]["commit_receipt"] = b["commit_receipt"].duplicate(true)
	_rechecksum_participant(bad_receipt, 0)
	_rechecksum(bad_receipt)
	_assert_error(
		PhysicalOutput.validate(bad_receipt),
		"MATTER_CROSS_REGION_PHYSICAL_COMMIT_RECEIPT_BINDING_MISMATCH",
		"receipt from another region"
	)

	var bad_operation: Dictionary = value.duplicate(true)
	var result: Dictionary = bad_operation["participant_outputs"][0]["matter_result"]
	result["operation_id"] = "matter-operation/other"
	result["mass_ledger"]["operation_id"] = "matter-operation/other"
	result["mass_ledger"]["checksum"] = MatterUtils.compute_checksum(result["mass_ledger"])
	result["checksum"] = MatterUtils.compute_checksum(result)
	_rechecksum_participant(bad_operation, 0)
	_rechecksum(bad_operation)
	_assert_error(
		PhysicalOutput.validate(bad_operation),
		"MATTER_CROSS_REGION_PHYSICAL_MATTER_RESULT_BINDING_MISMATCH",
		"participant result operation drift"
	)

	var bad_batch_id: Dictionary = value.duplicate(true)
	var batch: Dictionary = bad_batch_id["participant_outputs"][0]["material_batch"]
	batch["batch_id"] = "matter-batch/wrong"
	batch["checksum"] = MatterUtils.compute_checksum(batch)
	_rechecksum_participant(bad_batch_id, 0)
	_rechecksum(bad_batch_id)
	_assert_error(
		PhysicalOutput.validate(bad_batch_id),
		"MATTER_CROSS_REGION_PHYSICAL_BATCH_RESULT_ID_MISMATCH",
		"batch/result identity drift"
	)


func _test_region_and_external_mass_binding() -> void:
	var plan: Dictionary = Fixture.plan_ab()
	var a: Dictionary = _output(plan, Fixture.REGION_A, 7.0, 2.8, 240.0, 0)
	var b: Dictionary = _output(plan, Fixture.REGION_B, 3.0, 1.2, 265.0, 1)
	var value: Dictionary = PhysicalOutput.create(plan, [a, b])

	var bad_region_mass: Dictionary = value.duplicate(true)
	var batch: Dictionary = bad_region_mass["participant_outputs"][0]["material_batch"]
	batch["total_mass_kg"] = 6.5
	batch["checksum"] = MatterUtils.compute_checksum(batch)
	var result: Dictionary = bad_region_mass["participant_outputs"][0]["matter_result"]
	result["removed_mass_kg"] = 6.5
	result["mass_ledger"] = _local_ledger(String(plan["operation_id"]), 6.5, Fixture.REGION_A)
	result["checksum"] = MatterUtils.compute_checksum(result)
	bad_region_mass["total_mass_kg"] = 9.5
	_rechecksum_participant(bad_region_mass, 0)
	_rechecksum(bad_region_mass)
	_assert_error(
		PhysicalOutput.validate(bad_region_mass),
		"MATTER_CROSS_REGION_PHYSICAL_REGION_LEDGER_MISMATCH",
		"participant batch cannot disagree with distributed regional mass"
	)

	var bad_external: Dictionary = value.duplicate(true)
	var ledger: Dictionary = bad_external["plan"]["mass_ledger"]
	ledger["external_outputs"][0]["mass_kg"] = 9.5
	ledger["material_balances"][0]["external_output_kg"] = 9.5
	ledger["material_balances"][0]["residual_kg"] = -0.5
	ledger["checksum"] = MatterUtils.compute_checksum(ledger)
	bad_external["plan"]["checksum"] = MatterUtils.compute_checksum(bad_external["plan"])
	_rechecksum(bad_external)
	_assert(not bool(PhysicalOutput.validate(bad_external).get("success", false)), "tampered distributed ledger rejected")


func _test_exact_fields_and_no_thermodynamic_synthesis() -> void:
	var plan: Dictionary = Fixture.plan_ab()
	var a: Dictionary = _output(plan, Fixture.REGION_A, 7.0, 2.8, 240.0, 0)
	var b: Dictionary = _output(plan, Fixture.REGION_B, 3.0, 1.2, 265.0, 1)
	var value: Dictionary = PhysicalOutput.create(plan, [a, b])

	var extra: Dictionary = value.duplicate(true)
	extra["aggregate_temperature_k"] = 247.5
	_rechecksum(extra)
	_assert(not bool(PhysicalOutput.validate(extra).get("success", false)), "contract rejects synthesized aggregate temperature field")

	var extra_participant: Dictionary = value.duplicate(true)
	extra_participant["participant_outputs"][0]["derived_density_kg_m3"] = 2500.0
	_rechecksum_participant(extra_participant, 0)
	_rechecksum(extra_participant)
	_assert(not bool(PhysicalOutput.validate(extra_participant).get("success", false)), "participant output rejects synthesized density")

	var wrong_kind: Dictionary = value.duplicate(true)
	wrong_kind["output_kind"] = "AGGREGATED_GUESS"
	_rechecksum(wrong_kind)
	_assert_error(
		PhysicalOutput.validate(wrong_kind),
		"INVALID_MATTER_CROSS_REGION_PHYSICAL_OUTPUT_KIND",
		"unknown physical output kind"
	)


func _output(
	plan: Dictionary,
	region_id: String,
	mass_kg: float,
	volume_m3: float,
	temperature_k: float,
	index: int
) -> Dictionary:
	var participant: Dictionary = Plan.participant_by_region(plan, region_id)
	var composition: Dictionary = Composition.create([
		{"material_id": "matter/basalt", "mass_fraction": 1.0},
	])
	var batch_id := "matter-batch/mw10-physical-%d" % index
	var batch: Dictionary = MaterialBatch.create({
		"batch_id": batch_id,
		"container_id": "matter-container/mw10-physical-%d" % index,
		"source_body_id": plan["body_id"],
		"source_operation_id": plan["operation_id"],
		"total_mass_kg": mass_kg,
		"bulk_volume_m3": volume_m3,
		"composition": composition,
		"temperature_k": temperature_k,
	})
	var address: Dictionary = BrickAddress.create(
		participant["region_root_address"],
		1,
		index,
		0,
		0
	)
	var result: Dictionary = MatterResult.create({
		"operation_id": plan["operation_id"],
		"status": "COMMITTED",
		"changed_bricks": [{
			"address": address,
			"previous_revision": 10,
			"new_revision": 11,
			"snapshot_checksum": MatterUtils.payload_hash([region_id, "snapshot", 11]),
		}],
		"removed_mass_kg": mass_kg,
		"deposited_mass_kg": 0.0,
		"extracted_composition": composition,
		"generated_heat_j": 0.0,
		"consumed_energy_j": 1.0,
		"created_aggregate_ids": [batch_id],
		"mass_ledger": _local_ledger(String(plan["operation_id"]), mass_kg, region_id),
		"error_code": "",
	})
	var previous: Dictionary = participant["previous_source_revision"]
	var source: Dictionary = SourceRevision.create(
		"MATTER",
		String(previous["source_id"]),
		int(previous["authority_epoch"]),
		int(previous["source_revision"]) + 1,
		MatterUtils.payload_hash([region_id, "physical-output-source"]),
		MatterUtils.payload_hash([region_id, "physical-output-dependency"])
	)
	var receipt: Dictionary = Receipt.create({
		"transaction_id": plan["transaction_id"],
		"region_id": region_id,
		"action": Receipt.ACTION_COMMIT,
		"participant_checksum": participant["checksum"],
		"prepare_receipt_checksum": MatterUtils.payload_hash([region_id, "prepare-receipt"]),
		"source_revision": source,
		"runtime_state_hash": MatterUtils.payload_hash([region_id, "committed-runtime-state"]),
		"created_tick": 40 + index,
	})
	return {
		"region_id": region_id,
		"participant_checksum": participant["checksum"],
		"commit_receipt": receipt,
		"matter_result": result,
		"material_batch": batch,
	}


func _local_ledger(operation_id: String, mass_kg: float, region_id: String) -> Dictionary:
	return LocalLedger.create(
		operation_id,
		[{
			"account_id": "matter-source/%s" % region_id.get_file(),
			"material_id": "matter/basalt",
			"mass_kg": mass_kg,
		}],
		[{
			"account_id": "matter-extracted/%s" % region_id.get_file(),
			"material_id": "matter/basalt",
			"mass_kg": mass_kg,
		}]
	)


func _rechecksum_participant(value: Dictionary, index: int) -> void:
	var output: Dictionary = value["participant_outputs"][index]
	output["checksum"] = MatterUtils.compute_checksum({
		"region_id": output["region_id"],
		"participant_checksum": output["participant_checksum"],
		"commit_receipt": output["commit_receipt"],
		"matter_result": output["matter_result"],
		"material_batch": output["material_batch"],
		"checksum": "",
	})


func _rechecksum(value: Dictionary) -> void:
	value["checksum"] = MatterUtils.compute_checksum(value)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)), "%s rejects" % message)
	_assert(
		String(result.get("error_code", "")) == error_code,
		"%s error=%s actual=%s" % [
			message,
			error_code,
			String(result.get("error_code", "")),
		]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		return
	failures.append(message)
