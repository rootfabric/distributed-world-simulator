extends RefCounted

const DefinitionScript = preload("res://scripts/construction/parametric/construction_parametric_member_definition.gd")
const MaterialScript = preload("res://scripts/construction/parametric/construction_parametric_material.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")

static func compile(definition: Dictionary, material_definitions: Array, parameter_overrides: Dictionary, member_instance_id: String, item_instance_id: String, provenance: Dictionary = {}) -> Dictionary:
	var checked := DefinitionScript.validate(definition)
	if not bool(checked.get("success", false)): return checked
	var materials_result := _material_map(material_definitions)
	if not bool(materials_result.get("success", false)): return materials_result
	var materials: Dictionary = materials_result["materials"]
	var parameter_result := _parameters(definition, parameter_overrides)
	if not bool(parameter_result.get("success", false)): return parameter_result
	var parameters: Dictionary = parameter_result["parameters"]
	var metrics_result := _metrics(definition, materials, parameters)
	if not bool(metrics_result.get("success", false)): return metrics_result
	var instance := InstanceScript.create(member_instance_id, definition, parameters, metrics_result["material_usage"], metrics_result["geometry"], float(metrics_result["mass_kg"]), item_instance_id, provenance)
	checked = InstanceScript.validate(instance)
	if not bool(checked.get("success", false)): return checked
	return ParametricUtils.success({"instance": instance})

static func _parameters(definition: Dictionary, overrides: Dictionary) -> Dictionary:
	var parameters: Dictionary = Dictionary(definition["parameter_defaults"]).duplicate(true)
	for raw_key in overrides.keys():
		if typeof(raw_key) != TYPE_STRING or not parameters.has(raw_key): return ParametricUtils.failure("UNKNOWN_CONSTRUCTION_PARAMETRIC_PARAMETER")
		if not ParametricUtils.positive_number(overrides[raw_key]): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_PARAMETER_VALUE")
		parameters[raw_key] = ParametricUtils.metric(float(overrides[raw_key]))
	for parameter in parameters.keys():
		var bounds: Dictionary = definition["parameter_limits"][parameter]
		var number := float(parameters[parameter])
		if number < float(bounds["minimum"]) or number > float(bounds["maximum"]): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_PARAMETER_OUT_OF_RANGE", {"parameter": parameter})
	if String(definition["member_kind"]) == "PIPE" and float(parameters["wall_thickness_m"]) * 2.0 >= float(parameters["outer_diameter_m"]): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_PIPE_WALL_TOO_THICK")
	return ParametricUtils.success({"parameters": parameters})

static func _material_map(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw in values:
		if typeof(raw) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MATERIAL")
		var checked := MaterialScript.validate(raw); if not bool(checked.get("success", false)): return checked
		var material_id := String(raw["material_id"])
		if result.has(material_id): return ParametricUtils.failure("DUPLICATE_CONSTRUCTION_PARAMETRIC_MATERIAL")
		result[material_id] = Dictionary(raw).duplicate(true)
	return ParametricUtils.success({"materials": result})

static func _metrics(definition: Dictionary, materials: Dictionary, parameters: Dictionary) -> Dictionary:
	var kind := String(definition["member_kind"])
	var length := float(parameters["length_m"])
	var width := 0.0
	var height := 0.0
	var outer_diameter := 0.0
	var wall_thickness := 0.0
	var diameter := 0.0
	var total_thickness := 0.0
	var cross_section := 0.0
	var surface_area := 0.0
	var volume := 0.0
	var bounding_box: Array = []
	var usage_volumes: Dictionary = {}
	match kind:
		"BEAM":
			width = float(parameters["width_m"]); height = float(parameters["height_m"])
			cross_section = width * height; volume = length * cross_section
			surface_area = 2.0 * (length * width + length * height + width * height)
			bounding_box = [length, height, width]
			usage_volumes[String(definition["primary_material_id"])] = volume
		"PANEL":
			width = float(parameters["width_m"]); total_thickness = float(parameters["thickness_m"]); height = total_thickness
			cross_section = width * total_thickness; volume = length * cross_section
			surface_area = 2.0 * (length * width + length * total_thickness + width * total_thickness)
			bounding_box = [length, total_thickness, width]
			usage_volumes[String(definition["primary_material_id"])] = volume
		"PIPE":
			outer_diameter = float(parameters["outer_diameter_m"]); wall_thickness = float(parameters["wall_thickness_m"])
			var outer_radius := outer_diameter * 0.5; var inner_radius := outer_radius - wall_thickness
			cross_section = PI * (outer_radius * outer_radius - inner_radius * inner_radius); volume = length * cross_section
			surface_area = 2.0 * PI * outer_radius * length + 2.0 * PI * (outer_radius * outer_radius - inner_radius * inner_radius)
			width = outer_diameter; height = outer_diameter; bounding_box = [length, outer_diameter, outer_diameter]
			usage_volumes[String(definition["primary_material_id"])] = volume
		"CABLE":
			diameter = float(parameters["diameter_m"]); var radius := diameter * 0.5
			cross_section = PI * radius * radius; volume = length * cross_section
			surface_area = 2.0 * PI * radius * length + 2.0 * PI * radius * radius
			width = diameter; height = diameter; bounding_box = [length, diameter, diameter]
			usage_volumes[String(definition["primary_material_id"])] = volume
		"LAYERED_WALL":
			height = float(parameters["height_m"])
			for layer in definition["layers"]:
				var layer_thickness := float(layer["thickness_m"])
				total_thickness += layer_thickness
				var layer_volume := length * height * layer_thickness
				var material_id := String(layer["material_id"])
				usage_volumes[material_id] = float(usage_volumes.get(material_id, 0.0)) + layer_volume
			width = total_thickness; cross_section = height * total_thickness; volume = length * cross_section
			surface_area = 2.0 * (length * height + length * total_thickness + height * total_thickness)
			bounding_box = [length, height, total_thickness]
		_:
			return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_KIND")
	var usage_result := _usage(usage_volumes, materials)
	if not bool(usage_result.get("success", false)): return usage_result
	var geometry := {
		"length_m": ParametricUtils.metric(length),
		"width_m": ParametricUtils.metric(width),
		"height_m": ParametricUtils.metric(height),
		"outer_diameter_m": ParametricUtils.metric(outer_diameter),
		"wall_thickness_m": ParametricUtils.metric(wall_thickness),
		"diameter_m": ParametricUtils.metric(diameter),
		"total_thickness_m": ParametricUtils.metric(total_thickness),
		"cross_section_area_m2": ParametricUtils.metric(cross_section),
		"surface_area_m2": ParametricUtils.metric(surface_area),
		"volume_m3": ParametricUtils.metric(volume),
		"bounding_box_m": [ParametricUtils.metric(float(bounding_box[0])), ParametricUtils.metric(float(bounding_box[1])), ParametricUtils.metric(float(bounding_box[2]))],
	}
	return ParametricUtils.success({"geometry": geometry, "material_usage": usage_result["usage"], "mass_kg": usage_result["mass_kg"]})

static func _usage(volumes: Dictionary, materials: Dictionary) -> Dictionary:
	var usage: Array = []
	var total_mass := 0.0
	var ids: Array = volumes.keys(); ids.sort()
	for material_id_value in ids:
		var material_id := String(material_id_value)
		if not materials.has(material_id): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MATERIAL_NOT_FOUND", {"material_id": material_id})
		var material: Dictionary = materials[material_id]
		var volume := ParametricUtils.metric(float(volumes[material_id]))
		var mass := ParametricUtils.metric(volume * float(material["density_kg_m3"]))
		var units := maxi(1, int(ceil(mass / float(material["stock_unit_mass_kg"]))))
		usage.append({"material_id": material_id, "stock_definition_id": String(material["stock_definition_id"]), "volume_m3": volume, "mass_kg": mass, "stock_units": units})
		total_mass += mass
	return ParametricUtils.success({"usage": usage, "mass_kg": ParametricUtils.metric(total_mass)})
