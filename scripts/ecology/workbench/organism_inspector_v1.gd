# EcologyWorkbench OrganismInspector v1 (P7, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: READ-ONLY inspection chain for one organism, derived exclusively
#   from the canonical state exposed by the ExperimentController
#   (debug_state + presentation views). The inspector owns NO biology and
#   performs NO writes: every section is a projection of canonical truth.
# Chain: Genome (rules, max_age, max_depth, biological_hash) ->
#   DevelopmentProgram (rules/actions summary) -> DevelopmentState (modules,
#   age) -> BodyGraph (topology_signature, roles histogram, bounds) ->
#   Phenotype (phenotype_snapshot_v1.compile) -> resources (reserves +
#   cumulative ledger, read-only) -> damage (P12: three-layer WORLD_COMPAT
#   view via the polygon world adapter; explicit empty shape in LAB) ->
#   lineage (parent chain, lineage_depth from the P4 presentation view).
# Layer: 4 (PRESENTATION / read-only projection).
# Canonical API used (owner map rows 1,2,8 + auxiliary):
#   - organism_genome_v2.gd: biological_hash  [A1]
#   - body_graph_v1.gd: topology_signature  [A1/A2]
#   - phenotype_snapshot_v1.gd: compile  [A7]
class_name EcoWorkbenchOrganismInspectorV1
extends RefCounted

const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const BodyGraph = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Phenotype = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")

const SCHEMA := "dws.ecology.workbench.organism-inspector-view.v1"

## Full read-only inspection view for one organism of the bound controller.
## world_adapter (optional, P12 WORLD_COMPAT): when provided and it holds a
## damage overlay for this organism, the damage section shows the three
## SEPARATE layers (historical topology / damage overlay / effective active
## modules). Without it the section keeps the explicit empty LAB shape.
## Returns {"success": true, "view": {...}} or {"success": false, "error"}.
static func compile(controller: Object, individual_id: String, world_adapter: Object = null) -> Dictionary:
	if controller == null or not controller.has_method("debug_state"):
		return {"success": false, "error": "INSPECTOR_CONTROLLER"}
	var presentation := {}
	if controller.has_method("get_snapshot"):
		var snapshot: Dictionary = controller.get_snapshot()
		if bool(snapshot.get("success", false)):
			for entry in snapshot.get("presentation", []):
				if String(entry.individual_id) == individual_id:
					presentation = entry
					break
	return compile_from_debug(controller.debug_state(), individual_id, presentation, world_adapter)

## Same chain from a detached canonical debug state (equivalence harnesses).
static func compile_from_debug(debug: Dictionary, individual_id: String, presentation: Dictionary = {}, world_adapter: Object = null) -> Dictionary:
	var entry := _find_entry(debug, individual_id)
	if entry.is_empty():
		return {"success": false, "error": "INSPECTOR_ORGANISM_UNKNOWN:" + individual_id}
	var state: Dictionary = entry.state
	var genome: Dictionary = entry.blueprint.genome
	var genome_error := Genome.validate(genome)
	if not genome_error.is_empty():
		return {"success": false, "error": "INSPECTOR_GENOME:" + genome_error}
	var view := {
		"schema": SCHEMA,
		"individual_id": String(state.individual_id),
		"tick": int(debug.get("tick", 0)),
		"genome": _genome_section(genome),
		"development_program": _program_section(genome),
		"development_state": _development_section(state),
		"body_graph": _body_section(state),
		"phenotype": _phenotype_section(state, genome),
		"resources": _resources_section(state),
		"damage": _damage_section(state, world_adapter, individual_id),
		"lineage": _lineage_section(debug, state, presentation),
	}
	return {"success": true, "view": view}

## Genome reference for the editor UI (read-only duplicate).
static func genome_of(controller: Object, individual_id: String) -> Dictionary:
	if controller == null or not controller.has_method("debug_state"):
		return {}
	var entry := _find_entry(controller.debug_state(), individual_id)
	if entry.is_empty():
		return {}
	return entry.blueprint.genome.duplicate(true)

# --- sections -----------------------------------------------------------------

static func _genome_section(genome: Dictionary) -> Dictionary:
	return {
		"biological_hash": Genome.biological_hash(genome),
		"label": String(genome.label),
		"genes": genome.genes.duplicate(true),
		"rules": int(genome.program.rules.size()),
		"max_age": int(genome.program.max_age),
		"max_depth": int(genome.program.max_depth),
	}

static func _program_section(genome: Dictionary) -> Dictionary:
	var rules: Array = []
	var action_count := 0
	for rule in genome.program.rules:
		var ops: Array = []
		for action in rule.actions:
			ops.append(String(action.op))
			if bool(action.enabled):
				action_count += 1
		rules.append({
			"id": String(rule.id),
			"next": String(rule.next),
			"channel": String(rule.guard.channel),
			"guard": [int(rule.guard.min), int(rule.guard.max)],
			"actions": ops,
		})
	return {
		"entry": String(genome.program.entry),
		"rule_count": int(genome.program.rules.size()),
		"enabled_action_count": action_count,
		"rules": rules,
	}

static func _development_section(state: Dictionary) -> Dictionary:
	return {
		"modules_count": int(state.development.modules.size()),
		"tips_count": int(state.development.tips.size()),
		"development_tick": int(state.development.tick),
		"age_ticks": int(state.age_ticks),
		"alive": bool(state.alive),
	}

static func _body_section(state: Dictionary) -> Dictionary:
	var modules: Array = state.development.modules
	var roles := {}
	var min_bounds := [10000000, 10000000, 10000000]
	var max_bounds := [-10000000, -10000000, -10000000]
	for module in modules:
		roles[String(module.role)] = int(roles.get(String(module.role), 0)) + 1
		for point_name in ["start_mm", "end_mm"]:
			var point: Array = module[point_name]
			for axis in 3:
				min_bounds[axis] = mini(min_bounds[axis], int(point[axis]))
				max_bounds[axis] = maxi(max_bounds[axis], int(point[axis]))
	if modules.is_empty():
		min_bounds = [0, 0, 0]
		max_bounds = [0, 0, 0]
	return {
		"topology_signature": BodyGraph.topology_signature(modules),
		"roles": roles,
		"bounds_min_mm": min_bounds,
		"bounds_max_mm": max_bounds,
		"module_count": int(modules.size()),
	}

static func _phenotype_section(state: Dictionary, genome: Dictionary) -> Dictionary:
	var compiled: Dictionary = Phenotype.compile(state.development, genome)
	if compiled.is_empty():
		return {"available": false}
	# Keep the derived view compact: drop the bulky geometry payload.
	var compact := compiled.duplicate(true)
	compact.erase("representation")
	return {"available": true, "snapshot": compact}

static func _resources_section(state: Dictionary) -> Dictionary:
	return {
		"metabolic_reserves": state.metabolic_reserves.duplicate(true),
		"cumulative": state.resource_ledger.duplicate(true),
	}

## Damage section (P12). LAB / no overlay: explicit empty shape. With a
## WORLD_COMPAT world adapter holding a damage overlay for this organism:
## three SEPARATE layers — historical body topology (read-only copy,
## topology_signature can never be modified by the overlay), the damage
## overlay itself (degraded/destroyed/disabled), and the effective active
## module set (presentation projection). The historical BodyGraph is not
## modified by damage (§25 invariant).
static func _damage_section(state: Dictionary, world_adapter: Object, individual_id: String) -> Dictionary:
	if world_adapter != null and world_adapter.has_method("damage_view"):
		var view: Dictionary = world_adapter.damage_view(individual_id)
		if not view.is_empty():
			return view
	return {"overlay_present": false, "overlay": {}}

static func _lineage_section(debug: Dictionary, state: Dictionary, presentation: Dictionary) -> Dictionary:
	var by_id := {}
	for entry in debug.population:
		by_id[String(entry.state.individual_id)] = entry
	var chain: Array = []
	var walker: Dictionary = state
	var guard := 0
	while guard < 256:
		guard += 1
		if String(walker.origin_kind) != "PARENT_TRANSFER" or walker.origin_receipt.is_empty():
			break
		var parent_id := String(walker.origin_receipt.parent_id)
		chain.append(parent_id)
		if not by_id.has(parent_id):
			break
		walker = by_id[parent_id].state
	var depth := int(presentation.get("lineage_depth", chain.size()))
	return {
		"origin_kind": String(state.origin_kind),
		"parent_chain": chain,
		"lineage_depth": depth,
	}

static func _find_entry(debug: Dictionary, individual_id: String) -> Dictionary:
	if not debug is Dictionary or not debug.has("population"):
		return {}
	for entry in debug.population:
		if String(entry.state.individual_id) == individual_id:
			return entry
	return {}

# --- UI rendering ---------------------------------------------------------------

## Plain-text rendering of the inspection chain (inspector panel).
static func render_text(view: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("organism %s @ tick %d" % [String(view.individual_id), int(view.tick)])
	var genome: Dictionary = view.genome
	lines.append("GENOME hash=%s label=%s rules=%d max_age=%d max_depth=%d" % [
		String(genome.biological_hash).substr(0, 12), String(genome.label),
		int(genome.rules), int(genome.max_age), int(genome.max_depth),
	])
	var program: Dictionary = view.development_program
	lines.append("PROGRAM entry=%s rules=%d enabled_actions=%d" % [
		String(program.entry), int(program.rule_count), int(program.enabled_action_count),
	])
	for rule in program.rules:
		lines.append("  rule %s -> %s [%s %d..%d] ops=%s" % [
			String(rule.id), String(rule.next) if not String(rule.next).is_empty() else "-",
			String(rule.channel), int(rule.guard[0]), int(rule.guard[1]),
			",".join(PackedStringArray(rule.actions)),
		])
	var development: Dictionary = view.development_state
	lines.append("DEVELOPMENT modules=%d tips=%d age=%d dev_tick=%d alive=%s" % [
		int(development.modules_count), int(development.tips_count),
		int(development.age_ticks), int(development.development_tick),
		str(development.alive),
	])
	var body: Dictionary = view.body_graph
	var role_parts := PackedStringArray()
	for role in body.roles:
		role_parts.append("%s x%d" % [String(role), int(body.roles[role])])
	lines.append("BODY topology=%s modules=%d roles=[%s]" % [
		String(body.topology_signature).substr(0, 12), int(body.module_count),
		", ".join(role_parts),
	])
	lines.append("     bounds_mm min=%s max=%s" % [str(body.bounds_min_mm), str(body.bounds_max_mm)])
	if bool(view.phenotype.available):
		var stats: Dictionary = view.phenotype.snapshot.statistics
		lines.append("PHENOTYPE hash=%s modules=%d height=%d collector_area=%d absorber_reach=%d" % [
			String(view.phenotype.snapshot.phenotype_hash).substr(0, 12),
			int(stats.module_count), int(stats.height_mm),
			int(stats.collector_area_mm2), int(stats.absorber_reach_mm),
		])
	else:
		lines.append("PHENOTYPE unavailable")
	var reserves: Dictionary = view.resources.metabolic_reserves
	var ledger: Dictionary = view.resources.cumulative
	lines.append("RESERVES material=%d water=%d energy=%d" % [
		int(reserves.material_mg), int(reserves.water_mg), int(reserves.energy_mj),
	])
	lines.append("CUMULATIVE intake.water=%d intake.nutrient=%d maintenance.material=%d growth.material=%d" % [
		int(ledger.field_intake.water_mg), int(ledger.field_intake.nutrient_mg),
		int(ledger.maintenance.material_mg), int(ledger.growth_transferred.material_mg),
	])
	var damage: Dictionary = view.damage
	if bool(damage.get("overlay_present", false)) and damage.has("historical"):
		var historical: Dictionary = damage.historical
		var overlay: Dictionary = damage.overlay
		var effective: Dictionary = damage.effective
		lines.append("DAMAGE (three layers; historical topology is immutable)")
		lines.append("  HISTORICAL topology=%s modules=%d" % [
			String(historical.topology_signature).substr(0, 12), int(historical.module_count),
		])
		lines.append("  OVERLAY rev=%d degraded=%s destroyed=%s disabled=%s" % [
			int(overlay.revision), str(overlay.degraded_modules),
			str(overlay.destroyed_modules), str(overlay.disabled_modules),
		])
		lines.append("  EFFECTIVE active=%d ids=%s hash=%s" % [
			int(effective.active_module_count), str(effective.active_module_ids),
			String(effective.functional_hash).substr(0, 12),
		])
	else:
		lines.append("DAMAGE overlay_present=%s (reserved; empty in LAB)" % str(damage.get("overlay_present", false)))
	var lineage: Dictionary = view.lineage
	lines.append("LINEAGE origin=%s depth=%d chain=%s" % [
		String(lineage.origin_kind), int(lineage.lineage_depth),
		" <- ".join(PackedStringArray(lineage.parent_chain)) if not lineage.parent_chain.is_empty() else "(founder)",
	])
	return "\n".join(lines)

