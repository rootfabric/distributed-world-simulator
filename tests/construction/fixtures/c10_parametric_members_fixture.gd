extends RefCounted

const MaterialScript = preload("res://scripts/construction/parametric/construction_parametric_material.gd")
const LayerScript = preload("res://scripts/construction/parametric/construction_parametric_layer.gd")
const DefinitionScript = preload("res://scripts/construction/parametric/construction_parametric_member_definition.gd")
const CompilerScript = preload("res://scripts/construction/parametric/construction_parametric_compiler.gd")

static func materials() -> Array:
	return [
		MaterialScript.create("material/aluminum-6061", "Aluminum 6061", 2700.0, "aluminum_stock", 2.0, {"yield_strength_mpa": 276}),
		MaterialScript.create("material/concrete-c30", "Concrete C30", 2400.0, "concrete_mix", 25.0, {"compressive_strength_mpa": 30}),
		MaterialScript.create("material/copper", "Copper", 8960.0, "copper_stock", 1.0, {"conductivity_s_m": 58000000}),
		MaterialScript.create("material/gypsum", "Gypsum board", 800.0, "gypsum_board_stock", 12.0, {"fire_rating": "A2"}),
		MaterialScript.create("material/insulation", "Mineral insulation", 40.0, "insulation_stock", 5.0, {"thermal_conductivity_w_mk": 0.035}),
		MaterialScript.create("material/steel-s355", "Steel S355", 7850.0, "steel_stock", 10.0, {"yield_strength_mpa": 355}),
	]

static func material_map() -> Dictionary:
	var result := {}
	for material in materials(): result[String(material["material_id"])] = material
	return result

static func beam_definition(version: int = 1) -> Dictionary:
	return DefinitionScript.create(
		"parametric-definition/beam/rectangular-s355", version, "Rectangular S355 beam", "BEAM", "material/steel-s355",
		{"height_m": 0.2, "length_m": 4.0, "width_m": 0.1},
		{"height_m": DefinitionScript.limit(0.02, 1.0), "length_m": DefinitionScript.limit(0.1, 100.0), "width_m": DefinitionScript.limit(0.02, 1.0)},
		[], {"process": "CUT", "kerf_m": 0.003}, {"structural_grade": "S355"}
	)

static func panel_definition() -> Dictionary:
	return DefinitionScript.create(
		"parametric-definition/panel/aluminum", 1, "Aluminum panel", "PANEL", "material/aluminum-6061",
		{"length_m": 2.0, "thickness_m": 0.01, "width_m": 1.0},
		{"length_m": DefinitionScript.limit(0.1, 20.0), "thickness_m": DefinitionScript.limit(0.001, 0.2), "width_m": DefinitionScript.limit(0.1, 10.0)},
		[], {"process": "SHEET_CUT"}, {}
	)

static func pipe_definition() -> Dictionary:
	return DefinitionScript.create(
		"parametric-definition/pipe/steel", 1, "Steel pipe", "PIPE", "material/steel-s355",
		{"length_m": 3.0, "outer_diameter_m": 0.1, "wall_thickness_m": 0.005},
		{"length_m": DefinitionScript.limit(0.1, 100.0), "outer_diameter_m": DefinitionScript.limit(0.01, 2.0), "wall_thickness_m": DefinitionScript.limit(0.001, 0.2)},
		[], {"process": "PIPE_CUT"}, {"pressure_class": "PN16"}
	)

static func cable_definition() -> Dictionary:
	return DefinitionScript.create(
		"parametric-definition/cable/copper", 1, "Copper cable", "CABLE", "material/copper",
		{"diameter_m": 0.01, "length_m": 10.0},
		{"diameter_m": DefinitionScript.limit(0.001, 0.1), "length_m": DefinitionScript.limit(0.1, 1000.0)},
		[], {"process": "CABLE_CUT"}, {"conductor_count": 1}
	)

static func wall_definition() -> Dictionary:
	var layers := [
		LayerScript.create("layer/wall/concrete", "material/concrete-c30", 0.15, "structure"),
		LayerScript.create("layer/wall/gypsum", "material/gypsum", 0.0125, "interior_finish"),
		LayerScript.create("layer/wall/insulation", "material/insulation", 0.1, "thermal"),
	]
	return DefinitionScript.create(
		"parametric-definition/wall/layered", 1, "Layered wall", "LAYERED_WALL", "",
		{"height_m": 3.0, "length_m": 4.0},
		{"height_m": DefinitionScript.limit(0.5, 20.0), "length_m": DefinitionScript.limit(0.5, 100.0)},
		layers, {"process": "LAYER_ASSEMBLY"}, {"fire_compartment": true}
	)

static func all_definitions() -> Array:
	return [beam_definition(), cable_definition(), panel_definition(), pipe_definition(), wall_definition()]

static func beam_instance(key: String = "a", length_m: float = 4.0) -> Dictionary:
	return CompilerScript.compile(beam_definition(), materials(), {"length_m": length_m}, "parametric-member/beam/%s" % key, "item/parametric/beam/%s" % key, {"source": "C10_FIXTURE"})["instance"]

static func panel_instance(key: String = "a") -> Dictionary:
	return CompilerScript.compile(panel_definition(), materials(), {}, "parametric-member/panel/%s" % key, "item/parametric/panel/%s" % key, {"source": "C10_FIXTURE"})["instance"]

static func pipe_instance(key: String = "a") -> Dictionary:
	return CompilerScript.compile(pipe_definition(), materials(), {}, "parametric-member/pipe/%s" % key, "item/parametric/pipe/%s" % key, {"source": "C10_FIXTURE"})["instance"]

static func cable_instance(key: String = "a") -> Dictionary:
	return CompilerScript.compile(cable_definition(), materials(), {}, "parametric-member/cable/%s" % key, "item/parametric/cable/%s" % key, {"source": "C10_FIXTURE"})["instance"]

static func wall_instance(key: String = "a") -> Dictionary:
	return CompilerScript.compile(wall_definition(), materials(), {}, "parametric-member/wall/%s" % key, "item/parametric/wall/%s" % key, {"source": "C10_FIXTURE"})["instance"]
