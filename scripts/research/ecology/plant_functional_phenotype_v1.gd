extends RefCounted

## ECO.EVO7 FFF1 - PlantFunctionalPhenotype v1 (derived, read-only).
## Spec: docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md section 5.
## Audit: docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md (reuse-first decision).
##
## COMPILER DISCIPLINE (single morphological truth):
##   morphology is NEVER regenerated here. Realized PH0 traits and the growth
##   graph come exclusively from the accepted PH2 surface
##   plant_environment_coupled_development_v1.realize(...); this compiler only
##   derives functional read-outs (geometry proxies, gains, costs, fluxes).
##
## DECLARED COUPLINGS (R1 freeze, tested by G3):
##   realized_height_m        = graph.metrics.height_m * age_curve^0.8
##   realized_crown_radius_m  = graph.metrics.horizontal_radius_m * age_curve^0.5
##   realized_crown_density   = foliage_density * foliage_bearing_fraction
##                              (foliage_bearing = 0.35 + 0.65 * lateral_segment_fraction:
##                               a leaf-bearing trunk keeps density positive even
##                               when the deterministic skeleton grows no laterals)
##   leaf_area_index_proxy    = crown_density * PI * r^2 / 20.0        (cap 6)
##   leaf_size_proxy          = realized internode_length_m / 1.0       (declared)
##   leaf_conservative_strategy = 1 - leaf_economics_proxy
##   realized_root_depth_m    = genome.root_depth_m * (2*rsr) * age_curve^0.5
##   realized_root_spread_m   = root_spread_m      * (2*rsr) * age_curve^0.5
##   allocation factors       = 2*rsr (root side), 2*(1-rsr) (shoot side); 1.0 at rsr=0.5
##   structural_investment    = potential echo (environment coupling deferred, declared)
##   allocation scales FUNCTIONAL components only, never geometry (declared R1 limit)
##
## NO ENVIRONMENT FEEDBACK: environment sample is an INPUT (hash + component
## factors); this contract writes nothing back and produces no effect records.

const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Extension = preload("res://scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const CoupledDevelopment = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_functional_phenotype.v1"
const VERSION := "1.0.0"

const DERIVED_REPRESENTATION := true
const CROWN_BASE_FOLIAGE := 0.35  # leaf-bearing trunk floor of the foliage-bearing fraction
const LEAF_AREA_REF_M2 := 20.0
const LEAF_AREA_CAP := 6.0
const LEAF_SIZE_REF_M := 1.0
const ROOT_REACH_EFFICIENCY := 0.22  # reuse of plant_resource_model_v1 root-reach constant
const STRUCTURAL_COST_SCALE := 0.095 / 8.0  # reuse of resource-model structural cost, rescaled
const SHOOT_MAINTENANCE_PER_LAI := 0.08
const ROOT_MAINTENANCE_PER_METER := 0.06

const _NUMERIC_FIELDS: Array[String] = [
	"realized_height_m", "realized_crown_radius_m", "realized_crown_density",
	"leaf_area_index_proxy", "leaf_size_proxy", "leaf_conservative_strategy",
	"structural_investment", "realized_root_depth_m", "realized_root_spread_m",
	"root_shoot_ratio", "photosynthetic_gain_proxy", "maintenance_cost_proxy",
	"net_resource_proxy", "establishment_capacity",
]

## inputs:
##   genome             - accepted PlantGenome v1 dictionary
##   ph2_realized       - output of CoupledDevelopment.realize(...) (non-empty)
##   traits_extension   - accepted EVO7 extension dictionary (see Extension)
##   environment_sample - accepted EnvironmentSample v1 dictionary (input only)
##   age_fraction       - finite float in [0, 1]
static func compile(inputs: Dictionary) -> Dictionary:
	var genome: Dictionary = inputs.get("genome", {})
	var ph2: Dictionary = inputs.get("ph2_realized", {})
	var ext: Dictionary = inputs.get("traits_extension", {})
	var env: Dictionary = inputs.get("environment_sample", {})
	if not bool(Genome.validate(genome).get("success", false)):
		return {}
	if not bool(Extension.validate(ext).get("success", false)):
		return {}
	if not bool(EnvironmentSample.validate(env).get("success", false)):
		return {}
	if String(ph2.get("schema", "")) != CoupledDevelopment.SCHEMA or ph2.is_empty():
		return {}
	var realized: Dictionary = ph2.get("realized_development_traits", {})
	var graph: Dictionary = ph2.get("growth_graph", {})
	if not bool(Traits.validate(realized).get("success", false)):
		return {}
	if String(graph.get("graph_hash", "")).is_empty() or not graph.has("metrics"):
		return {}
	if String(ph2.get("genome_checksum", "")) != String(genome["checksum"]):
		return {}
	if String(ph2.get("environment_checksum", "")) != String(env["checksum"]):
		return {}
	var age_fraction := float(inputs.get("age_fraction", -1.0))
	if not is_finite(age_fraction) or age_fraction < 0.0 or age_fraction > 1.0:
		return {}
	var individual_seed := int(ph2.get("individual_seed", -1))
	if individual_seed < 0:
		return {}

	var metrics: Dictionary = graph["metrics"]
	var height_age_curve := pow(age_fraction, 0.8)
	var radius_age_curve := pow(age_fraction, 0.5)
	var rsr := float(ext["root_shoot_ratio"])
	var root_alloc_factor := _snap(2.0 * rsr)
	var shoot_alloc_factor := _snap(2.0 * (1.0 - rsr))

	var realized_height := _snap(float(metrics["height_m"]) * height_age_curve)
	var realized_crown_radius := _snap(float(metrics["horizontal_radius_m"]) * radius_age_curve)
	var lateral_fraction := _lateral_fraction(metrics)
	var foliage_bearing := _snap(clampf(CROWN_BASE_FOLIAGE + (1.0 - CROWN_BASE_FOLIAGE) * lateral_fraction, 0.0, 1.0))
	var crown_density := _snap(clampf(float(ext["foliage_density"]) * foliage_bearing, 0.0, 1.0))
	var crown_area_m2 := _snap(PI * realized_crown_radius * realized_crown_radius)
	var leaf_area_index := _snap(clampf(crown_density * crown_area_m2 / LEAF_AREA_REF_M2, 0.0, LEAF_AREA_CAP))
	var leaf_size_proxy := _snap(clampf(float(realized["internode_length_m"]) / LEAF_SIZE_REF_M, 0.0, 1.0))
	var economics := float(ext["leaf_economics_proxy"])
	var conservative := _snap(1.0 - economics)
	var structural_investment := float(ext["structural_investment"])

	var realized_root_depth := _snap(float(genome["root_depth_m"]) * root_alloc_factor * radius_age_curve)
	var realized_root_spread := _snap(float(ext["root_spread_m"]) * root_alloc_factor * radius_age_curve)

	var moisture := float(env["soil_moisture"])
	var effective_moisture := _snap(clampf(moisture + minf(realized_root_depth, 20.0) * ROOT_REACH_EFFICIENCY * (1.0 - moisture), 0.0, 1.0))
	var activity := _snap(clampf(0.2 + 0.8 * effective_moisture, 0.0, 1.0))
	var light_growth := _snap(clampf(0.2 + 0.8 * float(env["sunlight"]), 0.0, 1.0))
	var height_light_access := _snap(0.6 + 0.4 * clampf(realized_height / 20.0, 0.0, 1.0))
	var fast_leaf_bonus := _snap(0.7 + 0.6 * economics)

	var photosynthetic_gain := _snap(leaf_area_index * float(env["sunlight"]) * light_growth * activity * fast_leaf_bonus * shoot_alloc_factor * height_light_access)
	var shoot_maintenance := _snap(SHOOT_MAINTENANCE_PER_LAI * leaf_area_index * shoot_alloc_factor)
	var root_maintenance := _snap(ROOT_MAINTENANCE_PER_METER * (realized_root_depth / 5.0 + realized_root_spread / 6.0) * root_alloc_factor)
	var structural_cost := _snap(structural_investment * STRUCTURAL_COST_SCALE * pow(realized_height, 1.2))
	var maintenance := _snap(shoot_maintenance + root_maintenance + structural_cost)
	var net_resource := _snap(photosynthetic_gain - maintenance)

	var transpiration_ppm := _ppm(leaf_area_index * activity * 120000.0 * shoot_alloc_factor)
	var shade_ppm := _ppm(clampf(crown_area_m2 / LEAF_AREA_REF_M2, 0.0, 3.0) * crown_density * clampf(realized_height / 12.0, 0.0, 1.0) * 90000.0)
	var litter_ppm := _ppm(leaf_area_index * (0.3 + 0.7 * economics) * 45000.0)
	var seed_norm := clampf(float(genome["seed_count"]) / 200.0, 0.0, 1.0)
	var establishment := _snap(clampf(0.35 * seed_norm + 0.35 * conservative + 0.30 * activity, 0.0, 1.0))

	var phenotype := {
		"schema": SCHEMA,
		"version": VERSION,
		"derived_representation": DERIVED_REPRESENTATION,
		"genome_hash": String(genome["checksum"]),
		"environment_hash": String(env["checksum"]),
		"individual_seed": individual_seed,
		"age_fraction": _snap(age_fraction),
		"inherited_traits_hash": String(ph2["inherited_traits_checksum"]),
		"growth_graph_hash": String(graph["graph_hash"]),
		"plasticity_phenotype_hash": String(ph2["phenotype_hash"]),
		"realized_height_m": realized_height,
		"realized_crown_radius_m": realized_crown_radius,
		"realized_crown_density": crown_density,
		"leaf_area_index_proxy": leaf_area_index,
		"leaf_size_proxy": leaf_size_proxy,
		"leaf_conservative_strategy": conservative,
		"structural_investment": structural_investment,
		"realized_root_depth_m": realized_root_depth,
		"realized_root_spread_m": realized_root_spread,
		"root_shoot_ratio": rsr,
		"photosynthetic_gain_proxy": photosynthetic_gain,
		"maintenance_cost_proxy": maintenance,
		"net_resource_proxy": net_resource,
		"transpiration_demand_ppm": transpiration_ppm,
		"shade_output_ppm": shade_ppm,
		"litter_flux_ppm": litter_ppm,
		"establishment_capacity": establishment,
	}
	phenotype["phenotype_hash"] = compute_phenotype_hash(phenotype)
	return phenotype

static func compute_phenotype_hash(phenotype: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION,
		str(int(phenotype.get("individual_seed", -1))),
		String(phenotype.get("genome_hash", "")),
		String(phenotype.get("environment_hash", "")),
		String(phenotype.get("inherited_traits_hash", "")),
		String(phenotype.get("growth_graph_hash", "")),
		String(phenotype.get("plasticity_phenotype_hash", "")),
	])
	for field_name in _NUMERIC_FIELDS:
		tokens.append("%.9f" % float(phenotype.get(field_name, 0.0)))
	tokens.append(str(int(phenotype.get("transpiration_demand_ppm", -1))))
	tokens.append(str(int(phenotype.get("shade_output_ppm", -1))))
	tokens.append(str(int(phenotype.get("litter_flux_ppm", -1))))
	return "|".join(tokens).sha256_text()

static func _lateral_fraction(metrics: Dictionary) -> float:
	var main := maxi(int(metrics.get("main_axis_segment_count", 0)), 0)
	var lateral := maxi(int(metrics.get("lateral_segment_count", 0)), 0)
	var total := main + lateral
	if total <= 0:
		return 0.0
	return float(lateral) / float(total)

static func _snap(value: float) -> float:
	return snappedf(value, 1e-9)

static func _ppm(value: float) -> int:
	return maxi(int(floor(_snap(value))), 0)
