extends RefCounted

const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")
const RecipeScript = preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")

static func compile_recipe(recipe_id: String, recipe_version: int, display_name: String, instance: Dictionary, work_units_per_kg: float = 2.0) -> Dictionary:
	var checked := InstanceScript.validate(instance)
	if not bool(checked.get("success", false)): return checked
	if not ParametricUtils.positive_number(work_units_per_kg): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_WORK_RATE")
	var inputs: Array = []
	var seen_definitions := {}
	for usage in instance["material_usage"]:
		var stock_definition_id := String(usage["stock_definition_id"])
		if seen_definitions.has(stock_definition_id): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_STOCK_DEFINITION_COLLISION")
		seen_definitions[stock_definition_id] = true
		inputs.append(RecipeScript.input_requirement(stock_definition_id, int(usage["stock_units"]), {"material_id": String(usage["material_id"])}))
	var output_components := {"condition": "INTACT", "parametric_member": instance.duplicate(true)}
	var output := RecipeScript.output_product("member", "parametric_%s" % String(instance["member_kind"]).to_lower(), display_name, 1, output_components)
	var work_units := maxi(1, int(ceil(float(instance["mass_kg"]) * work_units_per_kg)))
	var recipe := RecipeScript.create(recipe_id, recipe_version, display_name, inputs, [output], ["FABRICATION_CELL"], ["POWER"], work_units, {
		"process": "PARAMETRIC_MEMBER",
		"member_instance_id": String(instance["member_instance_id"]),
		"member_checksum": String(instance["checksum"]),
		"member_kind": String(instance["member_kind"]),
	})
	checked = RecipeScript.validate(recipe)
	if not bool(checked.get("success", false)): return checked
	return ParametricUtils.success({"recipe": recipe})
