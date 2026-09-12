extends RefCounted
## Predeclared experimental inputs. No output-based seed selection or live organism editing.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const M = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")
const LH = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const R = preload("res://scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const A6 = preload("res://scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd")
const PATH := "res://config/ecology/evo-arch2-a7-protocol.v1.json"
const SITES := ["wet", "dry", "dark"]
const PROTOCOL_SHA256 := "4264c7590762d65dbd65a8e951c6a008e4cac2ced0cc04bb43d8d3a66ef01ce4"
const MAX_PROTOCOL_BYTES := 4096

static func manifest() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null or file.get_length() > MAX_PROTOCOL_BYTES: return {}
	var text := file.get_as_text()
	file.close()
	return decode_manifest(text)

static func decode_manifest(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_PROTOCOL_BYTES: return {}
	var result := C.decode(text)
	if not result.success or not result.value is Dictionary: return {}
	var v: Dictionary = result.value
	if not C.keys(v, ["schema", "id", "seeds", "horizon", "sites", "field_capacity_mg", "donor_material_mg", "study_endowment", "mutation_operator", "coordinate_units", "resource_units", "scope"]): return {}
	if v.schema != "dws.ecology.observatory-protocol.v1" or v.id != "EVO-ARCH2-A7-R1": return {}
	if v.seeds != [20260912, 104729, 130363] or v.horizon != 16 or v.field_capacity_mg != 10000: return {}
	if not B.valid_stock(v.study_endowment) or not C.integer(v.donor_material_mg, 1, 10000): return {}
	if v.mutation_operator != "module_parameter" or not v.sites is Array or v.sites.size() != 3: return {}
	for i in 3:
		var site: Variant = v.sites[i]
		if not C.keys(site, ["id", "water_mg", "light"]) or site.id != SITES[i]: return {}
		if not C.integer(site.water_mg, 0, v.field_capacity_mg) or not C.integer(site.light, 0, 1000): return {}
	return v if C.digest(v) == PROTOCOL_SHA256 else {}

static func treatment(seed: int = 20260912, common_garden: bool = false, effects_enabled: bool = true, mutations_enabled: bool = true) -> Dictionary:
	return {"seed": seed, "common_garden": common_garden, "effects_enabled": effects_enabled, "mutations_enabled": mutations_enabled}

static func valid_treatment(v: Variant, protocol: Dictionary) -> bool:
	if protocol.is_empty() or C.digest(protocol) != PROTOCOL_SHA256 or not C.keys(v, ["seed", "common_garden", "effects_enabled", "mutations_enabled"]): return false
	if not C.integer(v.seed, 0, C.MAX_INT) or not v.seed in protocol.seeds: return false
	return v.common_garden is bool and v.effects_enabled is bool and v.mutations_enabled is bool

static func ancestor() -> Dictionary:
	var actions := [P.action("extend", "support", [0, 30, 0], 1),
		P.action("differentiate", "collector", [18, 20, 0], 1, 400),
		P.action("differentiate", "absorber", [-22, -60, 8], 1, 0, 35),
		P.action("extend", "support", [4, 75, -8], 1),
		P.action("differentiate", "collector", [-28, 16, 9], 1, 900),
		P.action("differentiate", "reproductive", [12, 14, -9], 1), P.action("retire")]
	return G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 32, "max_depth": 1, "rules": [P.rule("start", actions)]}, "A7 shared study ancestor")

static func founding_genome(t: Dictionary, protocol: Dictionary) -> Dictionary:
	if not valid_treatment(t, protocol): return {"success": false, "error": "A7_TREATMENT"}
	return M.mutate(ancestor(), t.seed, protocol.mutation_operator if t.mutations_enabled else "none")

static func site_genesis(site_id: String, t: Dictionary, protocol: Dictionary) -> Dictionary:
	if not site_id in SITES or not valid_treatment(t, protocol): return {"success": false, "error": "A7_TREATMENT"}
	var mutation := founding_genome(t, protocol)
	if not mutation.success: return {"success": false, "error": "A7_MUTATION_REJECTED:" + String(mutation.get("reason", "unknown"))}
	var site: Dictionary = protocol.sites[0 if t.common_garden else SITES.find(site_id)]
	var field := Field.create("a7." + site_id, 1, [0, 0, 0], 1000, 1, 1,
		{"water_mg": site.water_mg, "nutrient_mg": 0, "organic_mg": 0}, F.stock(protocol.field_capacity_mg), F.signals(site.light, 500, 0, 0))
	var policy := LH.create_default()
	policy.uptake.basal_water_mg = 200
	policy.uptake.basal_nutrient_mg = 160
	policy.uptake.basal_organic_mg = 0
	policy.uptake.water_per_absorber_unit_mg = 0
	policy.uptake.nutrient_per_absorber_unit_mg = 0
	policy.uptake.organic_per_absorber_unit_mg = 0
	policy.metabolism.photosynthesis_area_divisor_mm2 = 1
	policy.growth.transfer_permille = 500
	policy.reproduction.endowment = {"material_mg": 10, "water_mg": 10, "energy_mj": 5}
	policy.reproduction.fee_energy_mj = 1
	policy.reproduction.interval_ticks = 4
	var study := R.individual(BP.create(mutation.genome, policy), "study", [500, 0, 500], protocol.study_endowment)
	var donor_policy := LH.create_default()
	for k in donor_policy.uptake: donor_policy.uptake[k] = 0
	donor_policy.survival.starvation_limit_ticks = 1
	var donor_genome := G.create({"schema": P.SCHEMA, "entry": "start", "max_age": 32, "max_depth": 1, "rules": [P.rule("start", [P.action("retire")])]}, "A7 litter donor")
	var donor := R.individual(BP.create(donor_genome, donor_policy), "litter-donor", [500, 0, 500], {"material_mg": protocol.donor_material_mg, "water_mg": 0, "energy_mj": 0})
	var feedback := A6.default_policy()
	feedback.decomposition_enabled = t.effects_enabled
	feedback.mineralization_enabled = t.effects_enabled
	feedback.material_return_mg = 200
	feedback.mineralization_per_cell_mg = 100
	return A6.create("a7/" + site_id + "/" + str(t.seed), field, [study, donor], feedback)
