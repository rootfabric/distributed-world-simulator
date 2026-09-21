# EcologyWorkbench ExperimentMetrics v1 (P10, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: READ-ONLY observatory accumulator over COMPLETED controller
#   snapshots (get_snapshot / debug_state / get_metrics only — never live
#   mutation, never in-flight state): population / births / deaths series,
#   resource stocks+flows, mutation events, lineage depth, morphology
#   diversity, body size, damage, decomposition, spatial distribution and
#   an event timeline [{tick, kind, entity_id, detail}].
# Layer: 3 (READ-ONLY PROJECTION). Forbidden: feeding back into simulation
#   state — observing must never change canonical_state_hash.
# Timeline kinds: birth | death | mutation | damage | mineralization.
class_name EcoWorkbenchExperimentMetricsV1
extends RefCounted

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")

const SCHEMA := "dws.ecology.workbench.experiment-metrics.v1"
const TIMELINE_KINDS := ["birth", "death", "mutation", "damage", "mineralization"]
const MAX_TIMELINE_EVENTS := 4096

var series: Dictionary = {}
var timeline: Array = []
var experiment_facts: Dictionary = {}

var _prev_alive: Dictionary = {}
var _prev_genome_hash: Dictionary = {}
var _prev_stock: Dictionary = {}
var _prev_mineralized_mg := -1
var _mutations_enabled := false
var _mutation_operator := ""
var _started := false

## Reset the accumulator and record experiment input facts (manifest).
func begin(manifest: Dictionary) -> void:
	series = {
		"tick": [], "generation": [],
		"population": [], "alive": [], "births": [], "deaths": [], "mutation_events": [],
		"resource_stocks": [], "resource_flows": [],
		"lineage_depth_max": [],
		"morphology_unique_signatures": [], "morphology_shannon_permille": [],
		"body_modules_total": [], "damage": [], "mineralized_mg": [],
		"spatial": [],
	}
	timeline = []
	experiment_facts = {
		"schema": SCHEMA,
		"experiment_id": String(manifest.get("experiment_id", "")),
		"manifest_hash": Manifest.canonical_hash(manifest),
		"seed": int(manifest.get("seed", 0)),
		"mutations_enabled": bool(manifest.get("mutation", {}).get("mutations_enabled", false)),
	}
	_prev_alive = {}
	_prev_genome_hash = {}
	_prev_stock = {}
	_prev_mineralized_mg = -1
	_mutations_enabled = bool(manifest.get("mutation", {}).get("mutations_enabled", false))
	_mutation_operator = String(manifest.get("mutation", {}).get("operator", ""))
	_started = false

## Observe one COMPLETED controller state. Read-only by construction:
## every input is a deep copy from the controller read APIs. Call after a
## finished tick (or at tick 0 for the genesis baseline).
func observe(controller: Object) -> Dictionary:
	if controller == null:
		return {"success": false, "error": "METRICS_CONTROLLER"}
	var snapshot: Dictionary = controller.get_snapshot()
	if not bool(snapshot.get("success", false)):
		return {"success": false, "error": "METRICS_SNAPSHOT:" + String(snapshot.get("error", "?"))}
	var debug: Dictionary = controller.debug_state()
	var tick := int(snapshot.get("tick", 0))
	var presentation: Array = snapshot.get("presentation", [])
	# --- population / alive / births / deaths --------------------------------
	var alive_map := {}
	var module_count := {}
	var parent_of := {}
	var genome_hash := {}
	var signature_count := {}
	var body_modules_total := 0
	for entry in debug.population:
		var state: Dictionary = entry.state
		var id := String(state.individual_id)
		alive_map[id] = bool(state.alive)
		module_count[id] = int(state.development.modules.size())
		body_modules_total += int(state.development.modules.size())
		var parent_id := ""
		if state.origin_kind == "PARENT_TRANSFER" and not state.origin_receipt.is_empty():
			parent_id = String(state.origin_receipt.parent_id)
		parent_of[id] = parent_id
		genome_hash[id] = Genome.biological_hash(entry.blueprint.genome)
		if bool(state.alive):
			var signature := String(B.topology_signature(state.development.modules))
			if not signature.is_empty():
				signature_count[signature] = int(signature_count.get(signature, 0)) + 1
	var births := 0
	var deaths := 0
	var mutations := 0
	if _started:
		for id in alive_map.keys():
			if not _prev_alive.has(id):
				births += 1
				_emit(tick, "birth", id, {"module_count": int(module_count[id])})
				var parent_id := String(parent_of.get(id, ""))
				if not parent_id.is_empty() and _prev_genome_hash.has(parent_id):
					if String(genome_hash[id]) != String(_prev_genome_hash[parent_id]):
						# Repaired lineage truth (R1/R2): a mutated genome is
						# admitted through a sealed canonical mutation receipt,
						# so a differing child genome IS an inherited mutation.
						mutations += 1
						_emit(tick, "mutation", id, {
							"applied": true, "operator": _mutation_operator,
							"parent_id": parent_id,
							"parent_hash": String(_prev_genome_hash[parent_id]).substr(0, 12),
							"child_hash": String(genome_hash[id]).substr(0, 12),
						})
					elif _mutations_enabled:
						# Mutations are enabled and the admitted genome equals
						# the parent: a canonical NEUTRAL A3 event (e.g. the
						# "none" control operator), not a rejection. There is
						# no fallback path — admission is fail-closed.
						_emit(tick, "mutation", id, {
							"applied": true, "neutral": true, "operator": _mutation_operator,
							"parent_id": parent_id,
							"parent_hash": String(_prev_genome_hash[parent_id]).substr(0, 12),
							"child_hash": String(genome_hash[id]).substr(0, 12),
						})
			elif bool(_prev_alive[id]) and not bool(alive_map[id]):
				deaths += 1
				_emit(tick, "death", id, {"module_count": int(module_count[id])})
	# --- field stocks / flows -------------------------------------------------
	var stock := {}
	for cell in debug.field.cells:
		for resource in ["water_mg", "nutrient_mg", "organic_mg"]:
			stock[resource] = int(stock.get(resource, 0)) + int(cell.stocks[resource])
	var flows := {}
	if _started and not _prev_stock.is_empty():
		for resource in stock.keys():
			flows[resource] = int(stock[resource]) - int(_prev_stock.get(resource, stock[resource]))
	# --- lineage depth / morphology diversity / spatial -----------------------
	var generation := 0
	var spatial := {}
	for view in presentation:
		generation = maxi(generation, int(view.get("lineage_depth", 0)))
		var zone := String(view.get("zone_id", ""))
		spatial[zone] = int(spatial.get(zone, 0)) + 1
	var unique_signatures := signature_count.size()
	var shannon := 0.0
	var classified := 0
	for signature in signature_count.keys():
		classified += int(signature_count[signature])
	if classified > 0:
		for signature in signature_count.keys():
			var p := float(signature_count[signature]) / float(classified)
			if p > 0.0:
				shannon -= p * log(p)
	# --- decomposition (feedback frame, read-only) ----------------------------
	var mineralized := int(debug.feedback.frame.get("mineralized_mg", 0))
	if _started and _prev_mineralized_mg >= 0 and mineralized > _prev_mineralized_mg:
		_emit(tick, "mineralization", "field", {"delta_mg": mineralized - _prev_mineralized_mg})
	# --- append series ---------------------------------------------------------
	series.tick.append(tick)
	series.generation.append(generation)
	series.population.append(presentation.size())
	series.alive.append(_alive_count(alive_map))
	series.births.append(births)
	series.deaths.append(deaths)
	series.mutation_events.append(mutations)
	series.resource_stocks.append(stock.duplicate())
	series.resource_flows.append(flows.duplicate())
	series.lineage_depth_max.append(generation)
	series.morphology_unique_signatures.append(unique_signatures)
	series.morphology_shannon_permille.append(roundi(shannon * 1000.0))
	series.body_modules_total.append(body_modules_total)
	series.damage.append(0)  # LAB: no damage model in canonical snapshots yet.
	series.mineralized_mg.append(mineralized)
	series.spatial.append(spatial.duplicate())
	_prev_alive = alive_map.duplicate()
	_prev_genome_hash = genome_hash.duplicate()
	_prev_stock = stock.duplicate()
	_prev_mineralized_mg = mineralized
	_started = true
	return {"success": true, "tick": tick}

## Final summary for comparison (P11 batch input). Derived data only.
func summary(final_state_hash: String = "") -> Dictionary:
	var counts := {}
	for kind in TIMELINE_KINDS:
		counts[kind] = 0
	for event in timeline:
		counts[String(event.kind)] = int(counts.get(String(event.kind), 0)) + 1
	var last: int = series.tick.size() - 1
	var final := {}
	if last >= 0:
		for key in ["tick", "generation", "population", "alive", "lineage_depth_max",
				"morphology_unique_signatures", "morphology_shannon_permille",
				"body_modules_total", "mineralized_mg"]:
			final[key] = series[key][last]
		final["births_total"] = _series_sum("births")
		final["deaths_total"] = _series_sum("deaths")
		final["mutation_events_total"] = _series_sum("mutation_events")
	return {
		"schema": SCHEMA,
		"facts": experiment_facts.duplicate(true),
		"observations": series.tick.size(),
		"final": final,
		"event_counts": counts,
		"final_state_hash": final_state_hash,
	}

func _series_sum(key: String) -> int:
	var total := 0
	for value in series.get(key, []):
		total += int(value)
	return total

func _emit(tick: int, kind: String, entity_id: String, detail: Dictionary) -> void:
	if timeline.size() >= MAX_TIMELINE_EVENTS:
		return
	timeline.append({
		"index": timeline.size(),
		"tick": tick,
		"kind": kind,
		"entity_id": entity_id,
		"detail": detail.duplicate(),
	})

static func _alive_count(alive_map: Dictionary) -> int:
	var count := 0
	for id in alive_map.keys():
		if bool(alive_map[id]):
			count += 1
	return count
