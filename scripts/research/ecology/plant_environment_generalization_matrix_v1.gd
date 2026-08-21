extends RefCounted

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PatchMigration = preload("res://scripts/research/ecology/plant_patch_migration_v1.gd")
const Transfer = preload("res://scripts/research/ecology/plant_frozen_catalog_transfer_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.evo2_environment_generalization_matrix.v1"
const PLAN_SCHEMA := SCHEMA + ".plan"
const CELL_SCHEMA := SCHEMA + ".cell"
const PHASE_SCHEMA := SCHEMA + ".phase"
const VERSION := "1.0.0"
const PARENT_E2_3_ACCEPTED_AGGREGATE := "82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8"
const PARENT_E2_3_CODE_UNDER_TEST := "c7ee41371807ed7dbb75e7e1eae1587105873a26"
const CELL_ORDER: Array[String] = ["NEAR_SOURCE", "DRY", "WET", "NUTRIENT_POOR", "HIGH_SEASONALITY", "PATCH_ISOLATED"]
const YEARS := 30
const REACHABLE_BOUNDS := Rect2(1.01, -80.0, 100.0, 160.0)
const ISOLATED_BOUNDS := Rect2(500.0, -80.0, 100.0, 160.0)
const STATIC_PHASE := "STATIC"
const SEASONAL_PHASES: Array[String] = ["COOL_WET", "MILD", "HOT_DRY", "COOL_DARK"]
const CONTINUOUS_SEASONAL_DYNAMICS_CLAIMED := false

const PLAN_FIELDS: Array[String] = ["schema", "version", "parent_e2_3_accepted_aggregate", "parent_e2_3_code_under_test", "cells", "plan_hash"]
const CELL_INPUT_FIELDS: Array[String] = ["cell_id", "mode", "expected_reachability", "phases"]
const CELL_FIELDS: Array[String] = ["schema", "version", "cell_id", "mode", "expected_reachability", "phases", "cell_hash"]
const PHASE_INPUT_FIELDS: Array[String] = ["phase_id", "patch_id", "bounds", "environment", "transport_schedule"]
const PHASE_FIELDS: Array[String] = ["schema", "version", "phase_id", "patch_id", "bounds", "environment", "transport_schedule", "phase_hash"]
const RESULT_FIELDS: Array[String] = ["schema", "version", "parent_e2_3_accepted_aggregate", "parent_e2_3_code_under_test", "e2_2_bake_hash", "catalog_hash", "plan", "plan_hash", "cells", "matrix_hash"]
const CELL_RESULT_FIELDS: Array[String] = ["cell_id", "mode", "expected_reachability", "phase_results", "cell_result_hash"]
const PHASE_RESULT_FIELDS: Array[String] = ["phase_id", "patch_id", "environment_checksum", "target_hash", "colonization_status", "first_colonization_year", "final_population_state_hash", "composition", "transfer_result_hash", "transfer_result", "phase_result_hash"]


static func default_plan() -> Dictionary:
	return create_plan(_default_cells())


static func create_plan(cells: Array) -> Dictionary:
	if cells.size() != CELL_ORDER.size():
		return {}
	var canonical_cells: Array = []
	var seen := {}
	for value in cells:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var input: Dictionary = value
		if not _has_exact_fields(input, CELL_INPUT_FIELDS):
			return {}
		var cell := _canonical_cell(input)
		if cell.is_empty():
			return {}
		var cell_id := String(cell["cell_id"])
		if seen.has(cell_id):
			return {}
		seen[cell_id] = true
		canonical_cells.append(cell)
	for required_id in CELL_ORDER:
		if not seen.has(required_id):
			return {}
	canonical_cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return CELL_ORDER.find(String(a["cell_id"])) < CELL_ORDER.find(String(b["cell_id"]))
	)
	var plan := {
		"schema": PLAN_SCHEMA,
		"version": VERSION,
		"parent_e2_3_accepted_aggregate": PARENT_E2_3_ACCEPTED_AGGREGATE,
		"parent_e2_3_code_under_test": PARENT_E2_3_CODE_UNDER_TEST,
		"cells": canonical_cells,
	}
	plan["plan_hash"] = compute_plan_hash(plan)
	return plan if validate_plan(plan) else {}


static func validate_plan(plan: Dictionary) -> bool:
	if not _has_exact_fields(plan, PLAN_FIELDS):
		return false
	if String(plan.get("schema", "")) != PLAN_SCHEMA or String(plan.get("version", "")) != VERSION:
		return false
	if String(plan.get("parent_e2_3_accepted_aggregate", "")) != PARENT_E2_3_ACCEPTED_AGGREGATE:
		return false
	if String(plan.get("parent_e2_3_code_under_test", "")) != PARENT_E2_3_CODE_UNDER_TEST:
		return false
	if typeof(plan.get("cells")) != TYPE_ARRAY:
		return false
	var cells: Array = plan["cells"]
	if cells.size() != CELL_ORDER.size():
		return false
	var rebuilt_input: Array = []
	for index in range(cells.size()):
		if typeof(cells[index]) != TYPE_DICTIONARY:
			return false
		var cell: Dictionary = cells[index]
		if not _has_exact_fields(cell, CELL_FIELDS) or String(cell.get("cell_id", "")) != CELL_ORDER[index]:
			return false
		var phase_inputs: Array = []
		for phase_value in Array(cell["phases"]):
			var phase: Dictionary = phase_value
			phase_inputs.append({
				"phase_id": phase["phase_id"],
				"patch_id": phase["patch_id"],
				"bounds": phase["bounds"],
				"environment": phase["environment"],
				"transport_schedule": phase["transport_schedule"],
			})
		rebuilt_input.append({
			"cell_id": cell["cell_id"],
			"mode": cell["mode"],
			"expected_reachability": cell["expected_reachability"],
			"phases": phase_inputs,
		})
	var rebuilt := _build_plan_without_validation(rebuilt_input)
	return not rebuilt.is_empty() and rebuilt == plan


static func run(bake_export: Dictionary, plan: Dictionary) -> Dictionary:
	if not validate_plan(plan):
		return {}
	if String(bake_export.get("bake_hash", "")) != Transfer.ACCEPTED_E2_2_BAKE_HASH or String(bake_export.get("catalog_hash", "")) != Transfer.ACCEPTED_E2_2_CATALOG_HASH:
		return {}
	var cells_out: Array = []
	for cell_value in Array(plan["cells"]):
		var cell: Dictionary = cell_value
		var phase_results: Array = []
		for phase_value in Array(cell["phases"]):
			var phase: Dictionary = phase_value
			var patch := PatchMigration.create_patch(String(phase["patch_id"]), Rect2(phase["bounds"]), Dictionary(phase["environment"]))
			if patch.is_empty():
				return {}
			var target := Transfer.create_target(
				"E2.4/%s/%s" % [String(cell["cell_id"]), String(phase["phase_id"])],
				[patch],
				YEARS,
				Array(phase["transport_schedule"]).duplicate(true)
			)
			if target.is_empty():
				return {}
			var transfer_result := Transfer.transfer(bake_export, target)
			if transfer_result.is_empty():
				return {}
			var phase_result := {
				"phase_id": String(phase["phase_id"]),
				"patch_id": String(phase["patch_id"]),
				"environment_checksum": String(Dictionary(phase["environment"])["checksum"]),
				"target_hash": String(target["target_hash"]),
				"colonization_status": String(transfer_result["colonization_status"]),
				"first_colonization_year": int(transfer_result["first_colonization_year"]),
				"final_population_state_hash": String(transfer_result["final_population_state_hash"]),
				"composition": _final_composition(transfer_result, String(phase["patch_id"])),
				"transfer_result_hash": String(transfer_result["result_hash"]),
				"transfer_result": transfer_result,
			}
			phase_result["phase_result_hash"] = _phase_result_hash(phase_result)
			phase_results.append(phase_result)
		var cell_result := {
			"cell_id": String(cell["cell_id"]),
			"mode": String(cell["mode"]),
			"expected_reachability": String(cell["expected_reachability"]),
			"phase_results": phase_results,
		}
		cell_result["cell_result_hash"] = _cell_result_hash(cell_result)
		cells_out.append(cell_result)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_e2_3_accepted_aggregate": PARENT_E2_3_ACCEPTED_AGGREGATE,
		"parent_e2_3_code_under_test": PARENT_E2_3_CODE_UNDER_TEST,
		"e2_2_bake_hash": String(bake_export["bake_hash"]),
		"catalog_hash": String(bake_export["catalog_hash"]),
		"plan": plan.duplicate(true),
		"plan_hash": String(plan["plan_hash"]),
		"cells": cells_out,
	}
	result["matrix_hash"] = compute_matrix_hash(result)
	return result


static func validate_result(bake_export: Dictionary, result: Dictionary) -> bool:
	if not _has_exact_fields(result, RESULT_FIELDS):
		return false
	if String(result.get("schema", "")) != SCHEMA or String(result.get("version", "")) != VERSION:
		return false
	if String(result.get("parent_e2_3_accepted_aggregate", "")) != PARENT_E2_3_ACCEPTED_AGGREGATE or String(result.get("parent_e2_3_code_under_test", "")) != PARENT_E2_3_CODE_UNDER_TEST:
		return false
	if String(result.get("e2_2_bake_hash", "")) != Transfer.ACCEPTED_E2_2_BAKE_HASH or String(result.get("catalog_hash", "")) != Transfer.ACCEPTED_E2_2_CATALOG_HASH:
		return false
	if typeof(result.get("plan")) != TYPE_DICTIONARY or not validate_plan(Dictionary(result["plan"])):
		return false
	if String(result.get("plan_hash", "")) != String(Dictionary(result["plan"])["plan_hash"]):
		return false
	if typeof(result.get("cells")) != TYPE_ARRAY or Array(result["cells"]).size() != CELL_ORDER.size():
		return false
	for index in range(CELL_ORDER.size()):
		var cell_value = Array(result["cells"])[index]
		if typeof(cell_value) != TYPE_DICTIONARY:
			return false
		var cell: Dictionary = cell_value
		if not _has_exact_fields(cell, CELL_RESULT_FIELDS) or String(cell.get("cell_id", "")) != CELL_ORDER[index]:
			return false
		if typeof(cell.get("phase_results")) != TYPE_ARRAY or Array(cell["phase_results"]).is_empty():
			return false
		for phase_value in Array(cell["phase_results"]):
			if typeof(phase_value) != TYPE_DICTIONARY or not _has_exact_fields(Dictionary(phase_value), PHASE_RESULT_FIELDS):
				return false
	var matrix_hash := String(result.get("matrix_hash", ""))
	if matrix_hash.length() != 64 or matrix_hash != compute_matrix_hash(result):
		return false
	var expected := run(bake_export, Dictionary(result["plan"]))
	return not expected.is_empty() and expected == result


static func compute_plan_hash(plan: Dictionary) -> String:
	var tokens := PackedStringArray([PLAN_SCHEMA, VERSION, PARENT_E2_3_ACCEPTED_AGGREGATE, PARENT_E2_3_CODE_UNDER_TEST])
	for value in Array(plan.get("cells", [])):
		tokens.append(String(Dictionary(value).get("cell_hash", "")))
	return "\n".join(tokens).sha256_text()


static func compute_matrix_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, PARENT_E2_3_ACCEPTED_AGGREGATE, PARENT_E2_3_CODE_UNDER_TEST,
		String(result.get("e2_2_bake_hash", "")), String(result.get("catalog_hash", "")), String(result.get("plan_hash", "")),
	])
	for value in Array(result.get("cells", [])):
		tokens.append(String(Dictionary(value).get("cell_result_hash", "")))
	return "\n".join(tokens).sha256_text()


static func _build_plan_without_validation(cells: Array) -> Dictionary:
	if cells.size() != CELL_ORDER.size():
		return {}
	var canonical_cells: Array = []
	var seen := {}
	for input_value in cells:
		if typeof(input_value) != TYPE_DICTIONARY:
			return {}
		var input: Dictionary = input_value
		var cell := _canonical_cell({
			"cell_id": input.get("cell_id", ""),
			"mode": input.get("mode", ""),
			"expected_reachability": input.get("expected_reachability", ""),
			"phases": input.get("phases", []),
		})
		if cell.is_empty() or seen.has(String(cell["cell_id"])):
			return {}
		seen[String(cell["cell_id"])] = true
		canonical_cells.append(cell)
	for required_id in CELL_ORDER:
		if not seen.has(required_id):
			return {}
	canonical_cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return CELL_ORDER.find(String(a["cell_id"])) < CELL_ORDER.find(String(b["cell_id"]))
	)
	var plan := {
		"schema": PLAN_SCHEMA,
		"version": VERSION,
		"parent_e2_3_accepted_aggregate": PARENT_E2_3_ACCEPTED_AGGREGATE,
		"parent_e2_3_code_under_test": PARENT_E2_3_CODE_UNDER_TEST,
		"cells": canonical_cells,
	}
	plan["plan_hash"] = compute_plan_hash(plan)
	return plan


static func _canonical_cell(input: Dictionary) -> Dictionary:
	var cell_id := String(input.get("cell_id", ""))
	var mode := String(input.get("mode", ""))
	var reachability := String(input.get("expected_reachability", ""))
	if not cell_id in CELL_ORDER or not mode in ["STATIC", "SEASONAL_ENVELOPE"] or not reachability in ["REACHABLE", "ISOLATED"]:
		return {}
	if typeof(input.get("phases")) != TYPE_ARRAY:
		return {}
	var phases: Array = []
	var seen := {}
	for value in Array(input["phases"]):
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var phase_input: Dictionary = value
		if not _has_exact_fields(phase_input, PHASE_INPUT_FIELDS):
			return {}
		var phase := _canonical_phase(phase_input)
		if phase.is_empty() or seen.has(String(phase["phase_id"])):
			return {}
		seen[String(phase["phase_id"])] = true
		phases.append(phase)
	if mode == "STATIC":
		if phases.size() != 1 or String(Dictionary(phases[0])["phase_id"]) != STATIC_PHASE:
			return {}
	else:
		if phases.size() != SEASONAL_PHASES.size():
			return {}
		for required_phase in SEASONAL_PHASES:
			if not seen.has(required_phase):
				return {}
		phases.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return SEASONAL_PHASES.find(String(a["phase_id"])) < SEASONAL_PHASES.find(String(b["phase_id"]))
		)
	var cell := {"schema": CELL_SCHEMA, "version": VERSION, "cell_id": cell_id, "mode": mode, "expected_reachability": reachability, "phases": phases}
	cell["cell_hash"] = _cell_hash(cell)
	return cell


static func _canonical_phase(input: Dictionary) -> Dictionary:
	var phase_id := String(input.get("phase_id", ""))
	var patch_id := String(input.get("patch_id", ""))
	if phase_id.is_empty() or patch_id.is_empty() or typeof(input.get("environment")) != TYPE_DICTIONARY or typeof(input.get("transport_schedule")) != TYPE_ARRAY:
		return {}
	var environment: Dictionary = Dictionary(input["environment"]).duplicate(true)
	if not bool(EnvironmentSample.validate(environment).get("success", false)):
		return {}
	if typeof(input.get("bounds")) != TYPE_RECT2:
		return {}
	var bounds := Rect2(input["bounds"])
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return {}
	var schedule := _canonical_schedule(Array(input["transport_schedule"]))
	if schedule.is_empty():
		return {}
	var phase := {"schema": PHASE_SCHEMA, "version": VERSION, "phase_id": phase_id, "patch_id": patch_id, "bounds": bounds, "environment": environment, "transport_schedule": schedule}
	phase["phase_hash"] = _phase_hash(phase)
	return phase


static func _canonical_schedule(schedule: Array) -> Array:
	var target := Transfer.create_target("E2.4/SCHEDULE_CANONICALIZER", [PatchMigration.create_patch("target/e24-schedule-probe", REACHABLE_BOUNDS, _environment("SCHEDULE_PROBE", 16.0, 0.45, 0.90, 0.70, 0.02, 2404999))], YEARS, schedule)
	if target.is_empty():
		return []
	return Array(target["transport_schedule"]).duplicate(true)


static func _default_cells() -> Array:
	var schedule := _default_schedule()
	var near_env := _environment("NEAR_SOURCE", 17.5, 0.42, 0.94, 0.80, 0.02, 2404001)
	var dry_env := _environment("DRY", 24.0, 0.18, 0.98, 0.65, 0.01, 2404002)
	var wet_env := _environment("WET", 18.0, 0.82, 0.78, 0.78, 0.22, 2404003)
	var poor_env := _environment("NUTRIENT_POOR", 18.0, 0.48, 0.92, 0.12, 0.02, 2404004)
	var seasonal := [
		_phase_input("COOL_WET", "target/e24-high-seasonality", REACHABLE_BOUNDS, _environment("HIGH_SEASONALITY_COOL_WET", 7.0, 0.78, 0.55, 0.70, 0.16, 2404011), schedule),
		_phase_input("MILD", "target/e24-high-seasonality", REACHABLE_BOUNDS, _environment("HIGH_SEASONALITY_MILD", 16.0, 0.55, 0.82, 0.72, 0.05, 2404012), schedule),
		_phase_input("HOT_DRY", "target/e24-high-seasonality", REACHABLE_BOUNDS, _environment("HIGH_SEASONALITY_HOT_DRY", 31.0, 0.16, 0.99, 0.42, 0.01, 2404013), schedule),
		_phase_input("COOL_DARK", "target/e24-high-seasonality", REACHABLE_BOUNDS, _environment("HIGH_SEASONALITY_COOL_DARK", 5.0, 0.62, 0.34, 0.60, 0.09, 2404014), schedule),
	]
	return [
		_cell_input("NEAR_SOURCE", "STATIC", "REACHABLE", [_phase_input(STATIC_PHASE, "target/e24-near-source", REACHABLE_BOUNDS, near_env, schedule)]),
		_cell_input("DRY", "STATIC", "REACHABLE", [_phase_input(STATIC_PHASE, "target/e24-dry", REACHABLE_BOUNDS, dry_env, schedule)]),
		_cell_input("WET", "STATIC", "REACHABLE", [_phase_input(STATIC_PHASE, "target/e24-wet", REACHABLE_BOUNDS, wet_env, schedule)]),
		_cell_input("NUTRIENT_POOR", "STATIC", "REACHABLE", [_phase_input(STATIC_PHASE, "target/e24-nutrient-poor", REACHABLE_BOUNDS, poor_env, schedule)]),
		_cell_input("HIGH_SEASONALITY", "SEASONAL_ENVELOPE", "REACHABLE", seasonal),
		_cell_input("PATCH_ISOLATED", "STATIC", "ISOLATED", [_phase_input(STATIC_PHASE, "target/e24-isolated", ISOLATED_BOUNDS, near_env, schedule)]),
	]


static func _default_schedule() -> Array:
	return [
		{"year_start": 1, "transport_vector": Vector2(1.0, 0.0), "turbulence": 0.20},
		{"year_start": 15, "transport_vector": Vector2(-1.0, 0.0), "turbulence": 0.20},
		{"year_start": 19, "transport_vector": Vector2(1.0, 0.0), "turbulence": 0.20},
	]


static func _environment(label: String, temperature_c: float, moisture: float, sunlight: float, nutrients: float, flood: float, seed_value: int) -> Dictionary:
	return EnvironmentSample.create(240.0, -64.0, temperature_c, moisture, sunlight, nutrients, flood, seed_value, "eco-evo2-e2-4-" + label.to_lower())


static func _cell_input(cell_id: String, mode: String, reachability: String, phases: Array) -> Dictionary:
	return {"cell_id": cell_id, "mode": mode, "expected_reachability": reachability, "phases": phases}


static func _phase_input(phase_id: String, patch_id: String, bounds: Rect2, environment: Dictionary, schedule: Array) -> Dictionary:
	return {"phase_id": phase_id, "patch_id": patch_id, "bounds": bounds, "environment": environment, "transport_schedule": schedule.duplicate(true)}


static func _final_composition(transfer_result: Dictionary, patch_id: String) -> Array:
	var history: Array = transfer_result.get("history", [])
	if history.is_empty():
		return []
	var final_summary: Dictionary = history[history.size() - 1]
	var patch := _history_patch(final_summary, patch_id)
	if patch.is_empty():
		return []
	var adults: Dictionary = patch.get("adult_biomass_by_lineage", {})
	var banks: Dictionary = patch.get("seed_bank_by_lineage", {})
	var ids: Array[String] = []
	for key in adults.keys():
		ids.append(String(key))
	for key in banks.keys():
		if not String(key) in ids:
			ids.append(String(key))
	ids.sort()
	var result: Array = []
	for species_id in ids:
		result.append({"research_species_id": species_id, "adult_biomass_kg_m2": float(adults.get(species_id, 0.0)), "seed_bank_seed_count": int(banks.get(species_id, 0))})
	return result


static func _history_patch(summary: Dictionary, patch_id: String) -> Dictionary:
	for value in Array(summary.get("patch_summaries", [])):
		var patch: Dictionary = value
		if String(patch.get("patch_id", "")) == patch_id:
			return patch
	return {}


static func _phase_hash(phase: Dictionary) -> String:
	var bounds := Rect2(phase.get("bounds", Rect2()))
	var tokens := PackedStringArray([
		PHASE_SCHEMA, VERSION, String(phase.get("phase_id", "")), String(phase.get("patch_id", "")),
		"bounds=%.12f,%.12f,%.12f,%.12f" % [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		String(Dictionary(phase.get("environment", {})).get("checksum", "")),
	])
	for value in Array(phase.get("transport_schedule", [])):
		var entry: Dictionary = value
		var vector := Vector2(entry.get("transport_vector", Vector2.ZERO))
		tokens.append("transport=%d|%.12f,%.12f|%.12f" % [int(entry.get("year_start", 0)), vector.x, vector.y, float(entry.get("turbulence", 0.0))])
	return "\n".join(tokens).sha256_text()


static func _cell_hash(cell: Dictionary) -> String:
	var tokens := PackedStringArray([CELL_SCHEMA, VERSION, String(cell.get("cell_id", "")), String(cell.get("mode", "")), String(cell.get("expected_reachability", ""))])
	for value in Array(cell.get("phases", [])):
		tokens.append(String(Dictionary(value).get("phase_hash", "")))
	return "\n".join(tokens).sha256_text()


static func _phase_result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		String(result.get("phase_id", "")), String(result.get("patch_id", "")), String(result.get("environment_checksum", "")),
		String(result.get("target_hash", "")), String(result.get("colonization_status", "")), str(int(result.get("first_colonization_year", -1))),
		String(result.get("final_population_state_hash", "")), String(result.get("transfer_result_hash", "")),
	])
	for value in Array(result.get("composition", [])):
		var item: Dictionary = value
		tokens.append("composition=%s|%.12f|%d" % [String(item.get("research_species_id", "")), float(item.get("adult_biomass_kg_m2", 0.0)), int(item.get("seed_bank_seed_count", 0))])
	return "\n".join(tokens).sha256_text()


static func _cell_result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([String(result.get("cell_id", "")), String(result.get("mode", "")), String(result.get("expected_reachability", ""))])
	for value in Array(result.get("phase_results", [])):
		tokens.append(String(Dictionary(value).get("phase_result_hash", "")))
	return "\n".join(tokens).sha256_text()


static func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.keys().size() != fields.size():
		return false
	for field_name in fields:
		if not value.has(field_name):
			return false
	for key in value.keys():
		if not String(key) in fields:
			return false
	return true
