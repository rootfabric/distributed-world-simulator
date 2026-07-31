extends SceneTree

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FixtureScript = preload("res://tests/construction/fixtures/c8_fabrication_cell_fixture.gd")
const RecipeScript = preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")
const CatalogScript = preload("res://scripts/construction/fabrication/construction_fabrication_catalog.gd")
const MachineDefinitionScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_definition.gd")
const MachineCompilerScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_compiler.gd")
const MachineProfileScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_profile.gd")
const JobScript = preload("res://scripts/construction/fabrication/construction_fabrication_job.gd")
const QueueScript = preload("res://scripts/construction/fabrication/construction_fabrication_queue_store.gd")
const TransactionPlannerScript = preload("res://scripts/construction/fabrication/construction_fabrication_transaction_planner.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const PlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_test_recipe_contract()
	_test_catalog_contract()
	_test_machine_definition_and_profile()
	_test_job_and_queue_contract()
	_test_transaction_plans()
	_finish()

func _test_recipe_contract() -> void:
	var recipe := FixtureScript.recipe()
	_assert_ok(RecipeScript.validate(recipe), "Valid recipe rejected")
	_assert(String(recipe.recipe_id) == "fabrication-recipe/structural-beam", "Recipe ID mismatch")
	_assert(int(recipe.recipe_version) == 1, "Recipe version mismatch")
	_assert(recipe.input_requirements.size() == 2, "Recipe input count mismatch")
	_assert(String(recipe.input_requirements[0].definition_id) == "coolant", "Recipe inputs not sorted")
	_assert(String(recipe.output_products[0].product_key) == "beam", "Recipe output key mismatch")
	_assert(int(recipe.work_units) == 10, "Recipe work units mismatch")
	_assert(String(recipe.checksum).length() == 64, "Recipe checksum invalid")
	var roundtrip = JSON.parse_string(JSON.stringify(recipe, "", true, true))
	_assert(roundtrip is Dictionary, "Recipe JSON roundtrip failed")
	_assert_ok(RecipeScript.validate(roundtrip), "Recipe JSON roundtrip rejected")
	_assert(UtilsScript.canonical_json(roundtrip) == UtilsScript.canonical_json(recipe), "Recipe JSON roundtrip changed")
	var unexpected := recipe.duplicate(true); unexpected["unexpected_field"] = true
	_assert_error(RecipeScript.validate(unexpected), "UNEXPECTED_FIELD", "Recipe accepted unexpected field")
	var tampered := recipe.duplicate(true); tampered.display_name = "Tampered"
	_assert_error(RecipeScript.validate(tampered), "CONSTRUCTION_FABRICATION_RECIPE_CHECKSUM_MISMATCH", "Recipe accepted checksum tamper")
	var unsorted := recipe.duplicate(true); unsorted.input_requirements.reverse(); unsorted.checksum = RecipeScript.compute_checksum(unsorted)
	_assert_error(RecipeScript.validate(unsorted), "CONSTRUCTION_FABRICATION_INPUTS_NOT_SORTED", "Recipe accepted unsorted inputs")
	var no_inputs := recipe.duplicate(true); no_inputs.input_requirements = []; no_inputs.checksum = RecipeScript.compute_checksum(no_inputs)
	_assert_error(RecipeScript.validate(no_inputs), "CONSTRUCTION_FABRICATION_INPUTS_REQUIRED", "Recipe accepted no inputs")
	var no_outputs := recipe.duplicate(true); no_outputs.output_products = []; no_outputs.checksum = RecipeScript.compute_checksum(no_outputs)
	_assert_error(RecipeScript.validate(no_outputs), "CONSTRUCTION_FABRICATION_OUTPUTS_REQUIRED", "Recipe accepted no outputs")
	var bad_work := recipe.duplicate(true); bad_work.work_units = 0; bad_work.checksum = RecipeScript.compute_checksum(bad_work)
	_assert_error(RecipeScript.validate(bad_work), "INVALID_CONSTRUCTION_FABRICATION_WORK_UNITS", "Recipe accepted zero work")
	var bad_cap := recipe.duplicate(true); bad_cap.required_machine_capabilities = ["bad"]; bad_cap.checksum = RecipeScript.compute_checksum(bad_cap)
	_assert_error(RecipeScript.validate(bad_cap), "INVALID_CONSTRUCTION_FABRICATION_REQUIREMENT", "Recipe accepted invalid capability")

func _test_catalog_contract() -> void:
	var catalog = CatalogScript.new()
	_assert_ok(catalog.setup(), "Catalog setup failed")
	var recipe := FixtureScript.recipe()
	var first := catalog.publish(recipe)
	_assert_ok(first, "Catalog publish failed")
	_assert(not bool(first.replay), "First catalog publish marked replay")
	_assert(int(catalog.get_generation()) == 1, "Catalog generation mismatch")
	var replay := catalog.publish(recipe)
	_assert_ok(replay, "Catalog replay failed")
	_assert(bool(replay.replay), "Catalog replay not detected")
	_assert(int(catalog.get_generation()) == 1, "Catalog replay advanced generation")
	var conflict := recipe.duplicate(true); conflict.display_name = "Changed"; conflict.checksum = RecipeScript.compute_checksum(conflict)
	_assert_error(catalog.publish(conflict), "CONSTRUCTION_FABRICATION_RECIPE_VERSION_CONFLICT", "Catalog accepted version conflict")
	var v2 := FixtureScript.recipe(2)
	_assert_ok(catalog.publish(v2), "Catalog v2 publish failed")
	_assert(int(catalog.latest_version(String(recipe.recipe_id))) == 2, "Catalog latest version mismatch")
	_assert(String(catalog.get_recipe(String(recipe.recipe_id)).checksum) == String(v2.checksum), "Catalog latest lookup mismatch")
	var gap := FixtureScript.recipe(4)
	_assert_error(catalog.publish(gap), "CONSTRUCTION_FABRICATION_RECIPE_VERSION_GAP", "Catalog accepted version gap")
	var state := catalog.to_dict()
	_assert_ok(CatalogScript.validate_state(state), "Catalog state rejected")
	var restored = CatalogScript.new(); restored.setup()
	_assert_ok(restored.load_dict(state), "Catalog load failed")
	_assert(UtilsScript.canonical_json(restored.to_dict()) == UtilsScript.canonical_json(state), "Catalog roundtrip changed")
	var tampered := state.duplicate(true); tampered.recipes[0].display_name = "Broken"
	_assert_error(CatalogScript.validate_state(tampered), "CONSTRUCTION_FABRICATION_RECIPE_CHECKSUM_MISMATCH", "Catalog accepted tampered recipe")

func _test_machine_definition_and_profile() -> void:
	var snapshot := FixtureScript.machine_snapshot()
	var definition := FixtureScript.machine_definition()
	var behavior := FixtureScript.behavior_profile("cell-a", snapshot)
	var spatial := FixtureScript.powered_spatial_profile()
	_assert_ok(MachineDefinitionScript.validate(definition), "Machine definition rejected")
	var compiled := MachineCompilerScript.compile(snapshot, definition, behavior, spatial)
	_assert_ok(compiled, "Machine compile failed")
	var profile: Dictionary = compiled.profile
	_assert_ok(MachineProfileScript.validate(profile), "Machine profile rejected")
	_assert(String(profile.status) == "ONLINE", "Healthy machine not online")
	_assert(profile.capabilities.size() == 3, "Machine capability count mismatch")
	_assert(profile.affordances.size() == 5, "Machine affordance count mismatch")
	_assert(Array(profile.supported_recipe_ids).has("fabrication-recipe/structural-beam"), "Machine recipe missing")
	_assert(String(profile.input_container_id) != String(profile.output_container_id), "Machine containers collided")
	var offline := MachineCompilerScript.compile(snapshot, definition, behavior, FixtureScript.unpowered_spatial_profile())
	_assert_ok(offline, "Offline machine compile failed")
	_assert(String(offline.profile.status) == "OFFLINE", "Power loss did not stop machine")
	_assert(offline.profile.capabilities.is_empty(), "Offline machine exposes capabilities")
	_assert(offline.profile.affordances.is_empty(), "Offline machine exposes affordances")
	var degraded_snapshot := FixtureScript.machine_snapshot("cell-a", 1, {"spindle": "DEGRADED"}, {}, "OPERATIONAL")
	var degraded_behavior := FixtureScript.behavior_profile("cell-a", degraded_snapshot)
	var degraded := MachineCompilerScript.compile(degraded_snapshot, definition, degraded_behavior, spatial)
	_assert_ok(degraded, "Degraded machine compile failed")
	_assert(String(degraded.profile.status) == "DEGRADED", "Degraded provider not reflected")
	var same_containers := definition.duplicate(true); same_containers.output_container_id = same_containers.input_container_id; same_containers.checksum = MachineDefinitionScript.compute_checksum(same_containers)
	_assert_error(MachineDefinitionScript.validate(same_containers), "CONSTRUCTION_FABRICATION_MACHINE_CONTAINERS_MUST_DIFFER", "Machine accepted same containers")
	var bad_quorum := definition.duplicate(true); bad_quorum.minimum_intact_providers = 3; bad_quorum.checksum = MachineDefinitionScript.compute_checksum(bad_quorum)
	_assert_error(MachineDefinitionScript.validate(bad_quorum), "INVALID_CONSTRUCTION_FABRICATION_MACHINE_QUORUM", "Machine accepted invalid quorum")
	var bad_profile := profile.duplicate(true); bad_profile.status = "OFFLINE"; bad_profile.checksum = MachineProfileScript.compute_checksum(bad_profile)
	_assert_error(MachineProfileScript.validate(bad_profile), "OFFLINE_CONSTRUCTION_FABRICATION_MACHINE_EXPOSES_BEHAVIOR", "Offline profile retained behavior")

func _test_job_and_queue_contract() -> void:
	var recipe := FixtureScript.recipe()
	var compiled_profile: Dictionary = MachineCompilerScript.compile(FixtureScript.machine_snapshot(), FixtureScript.machine_definition(), FixtureScript.behavior_profile(), FixtureScript.powered_spatial_profile())
	var profile: Dictionary = compiled_profile["profile"]
	var materials := FixtureScript.material_projections()
	var bindings := []
	for projection in materials:
		bindings.append({"item_instance_id": String(projection.item_instance_id), "definition_id": String(projection.definition_id), "quantity": 1 if String(projection.definition_id) == "coolant" else 3, "components": Dictionary(projection.components).duplicate(true), "original_relation": Dictionary(projection.relation).duplicate(true), "source_revision": int(projection.revision), "source_fingerprint": UtilsScript.payload_hash(projection)})
	bindings.sort_custom(func(a,b): return String(a.item_instance_id) < String(b.item_instance_id))
	var job := JobScript.create("fabrication-job/contracts", recipe, profile, 500, bindings, [{"product_key": "beam", "item_instance_id": "item/fabricated/contracts/beam"}])
	_assert_ok(JobScript.validate(job), "Valid fabrication job rejected")
	_assert(String(job.status) == "QUEUED", "New job not queued")
	_assert(int(job.work_required) == 10 and int(job.work_completed) == 0, "New job progress mismatch")
	var bad_progress := JobScript.with_updates(job, {"work_completed": 11})
	_assert_error(JobScript.validate(bad_progress), "INVALID_CONSTRUCTION_FABRICATION_JOB_PROGRESS", "Job accepted excessive progress")
	var duplicate_output := job.duplicate(true); duplicate_output.output_bindings.append(duplicate_output.output_bindings[0].duplicate(true)); duplicate_output.checksum = JobScript.compute_checksum(duplicate_output)
	_assert_error(JobScript.validate(duplicate_output), "INVALID_CONSTRUCTION_FABRICATION_JOB_OUTPUT_BINDING", "Job accepted duplicate output")
	var queue = QueueScript.new(); _assert_ok(queue.setup(), "Queue setup failed")
	var enqueued := queue.enqueue(job); _assert_ok(enqueued, "Queue enqueue failed")
	_assert(not bool(enqueued.replay), "First enqueue marked replay")
	var replay := queue.enqueue(job); _assert_ok(replay, "Queue replay failed")
	_assert(bool(replay.replay), "Queue replay not detected")
	var changed := JobScript.with_updates(job, {"priority": 400})
	_assert_error(queue.enqueue(changed), "CONSTRUCTION_FABRICATION_JOB_ID_CONFLICT", "Queue accepted job conflict")
	var reserved := JobScript.with_updates(job, {"status": "RESERVED", "reservation_operation_id": "operation/contracts/reserve"})
	_assert_ok(queue.replace_job(String(job.checksum), reserved), "Queue reserve transition failed")
	var progressed := queue.advance(String(job.job_id), 4, "operation/contracts/progress")
	_assert_ok(progressed, "Queue progress failed")
	_assert(int(progressed.job.work_completed) == 4, "Queue progress mismatch")
	var progress_replay := queue.advance(String(job.job_id), 4, "operation/contracts/progress")
	_assert_ok(progress_replay, "Queue progress replay failed")
	_assert(bool(progress_replay.replay), "Queue progress replay not detected")
	_assert_error(queue.advance(String(job.job_id), 5, "operation/contracts/progress"), "CONSTRUCTION_FABRICATION_PROGRESS_OPERATION_CONFLICT", "Queue accepted progress operation conflict")
	var state := queue.to_dict(); _assert_ok(QueueScript.validate_state(state), "Queue state rejected")
	var restored = QueueScript.new(); restored.setup(); _assert_ok(restored.load_dict(state), "Queue load failed")
	_assert(UtilsScript.canonical_json(restored.to_dict()) == UtilsScript.canonical_json(state), "Queue roundtrip changed")
	var tampered := state.duplicate(true); tampered.jobs[0].priority = 1
	_assert_error(QueueScript.validate_state(tampered), "CONSTRUCTION_FABRICATION_JOB_CHECKSUM_MISMATCH", "Queue accepted tampered job")

func _test_transaction_plans() -> void:
	var snapshot := FixtureScript.machine_snapshot("plans")
	var recipe := FixtureScript.recipe()
	var compiled_profile: Dictionary = MachineCompilerScript.compile(snapshot, FixtureScript.machine_definition("plans"), FixtureScript.behavior_profile("plans", snapshot), FixtureScript.powered_spatial_profile("plans-power"))
	var profile: Dictionary = compiled_profile["profile"]
	var materials := FixtureScript.material_projections("plans")
	var bindings := []
	for projection in materials:
		bindings.append({"item_instance_id": String(projection.item_instance_id), "definition_id": String(projection.definition_id), "quantity": 1 if String(projection.definition_id) == "coolant" else 3, "components": Dictionary(projection.components).duplicate(true), "original_relation": Dictionary(projection.relation).duplicate(true), "source_revision": int(projection.revision), "source_fingerprint": UtilsScript.payload_hash(projection)})
	bindings.sort_custom(func(a,b): return String(a.item_instance_id) < String(b.item_instance_id))
	var job := JobScript.create("fabrication-job/plans", recipe, profile, 100, bindings, [{"product_key": "beam", "item_instance_id": "item/fabricated/plans/beam"}])
	var reserve := TransactionPlannerScript.build_reservation_plan("plan/fabrication/plans/reserve", "operation/fabrication/plans/reserve", snapshot, job, recipe, materials, String(profile.input_container_id))
	_assert_ok(reserve, "Reservation plan failed")
	_assert_ok(PlanScript.validate(reserve.plan), "Reservation plan invalid")
	_assert(String(reserve.plan.command_type) == PlanScript.COMMAND_FABRICATION_RESERVE, "Reservation command mismatch")
	_assert(reserve.plan.item_mutations.size() == 2, "Reservation mutation count mismatch")
	for mutation in reserve.plan.item_mutations:
		_assert(String(mutation.purpose) == ItemMutationScript.PURPOSE_TRANSFER_FABRICATION_INPUT, "Reservation used wrong purpose")
	var reserved_items: Array = []
	for mutation in reserve.plan.item_mutations: reserved_items.append(Dictionary(mutation.after_projection).duplicate(true))
	var after_reserve: Dictionary = reserve.plan.construct_mutation.after_snapshot
	_assert(String(after_reserve.compiled_facets.fabrication_runtime.active_job_id) == String(job.job_id), "Reservation runtime missing job")
	var complete := TransactionPlannerScript.build_completion_plan("plan/fabrication/plans/complete", "operation/fabrication/plans/complete", after_reserve, job, recipe, reserved_items, String(profile.output_container_id))
	_assert_ok(complete, "Completion plan failed")
	_assert_ok(PlanScript.validate(complete.plan), "Completion plan invalid")
	_assert(String(complete.plan.command_type) == PlanScript.COMMAND_FABRICATION_COMPLETE, "Completion command mismatch")
	var create_count := 0; var delete_count := 0; var update_count := 0
	for mutation in complete.plan.item_mutations:
		match String(mutation.operation_kind):
			"CREATE": create_count += 1
			"DELETE": delete_count += 1
			"UPDATE": update_count += 1
	_assert(create_count == 1 and delete_count == 1 and update_count == 1, "Completion mutation shape mismatch")
	var output_mutation: Dictionary = complete.plan.item_mutations.filter(func(m): return String(m.operation_kind) == "CREATE")[0]
	_assert(String(output_mutation.purpose) == ItemMutationScript.PURPOSE_CREATE_FABRICATED_ITEM, "Output used wrong purpose")
	_assert(String(output_mutation.after_projection.components.fabrication_origin.job_id) == String(job.job_id), "Output origin missing job")
	_assert(String(complete.plan.construct_mutation.after_snapshot.compiled_facets.fabrication_runtime.last_completed_job_id) == String(job.job_id), "Completion runtime missing job")
	var release := TransactionPlannerScript.build_release_plan("plan/fabrication/plans/release", "operation/fabrication/plans/release", after_reserve, job, reserved_items)
	_assert_ok(release, "Release plan failed")
	_assert_ok(PlanScript.validate(release.plan), "Release plan invalid")
	_assert(String(release.plan.command_type) == PlanScript.COMMAND_FABRICATION_RELEASE, "Release command mismatch")
	for mutation in release.plan.item_mutations:
		_assert(UtilsScript.canonical_json(mutation.after_projection.relation) == UtilsScript.canonical_json(bindings.filter(func(b): return String(b.item_instance_id) == String(mutation.item_instance_id))[0].original_relation), "Release did not restore relation")

func _assert_ok(result: Dictionary, message: String) -> void: _assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert_error(result: Dictionary, code: String, message: String) -> void: _assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])
func _assert(condition: bool, message: String) -> void: assertions += 1; if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("C8 fabrication cell contracts: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("C8 fabrication cell contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)
