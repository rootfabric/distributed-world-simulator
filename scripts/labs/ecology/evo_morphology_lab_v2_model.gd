extends RefCounted
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const E = preload("res://scripts/research/ecology/v2/environment_fixture_v1.gd")
const F = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const H = preload("res://scripts/research/ecology/v2/phenotype_snapshot_v1.gd")
const K = preload("res://scripts/research/ecology/v2/development_interpreter_v1.gd")
const M = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const S = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")

const IMPORTED_FAMILY := -1

var family := 0
var genome: Dictionary
var state: Dictionary
var environment: Dictionary
var generation := 0
var lineage: Array = []
var gallery: Array = []
var last_status := "READY"
var last_block_reason := ""

func _init() -> void:
	reset(0)

func reset(index: int = 0) -> bool:
	if index < 0 or index >= F.NAMES.size(): return false
	family = index
	genome = F.make(index)
	environment = E.create()
	state = S.create(genome)
	generation = 0
	lineage = [{"generation": 0, "hash": G.biological_hash(genome), "source": "FIXTURE", "family": F.NAMES[index]}]
	gallery.clear()
	last_status = "READY"
	last_block_reason = ""
	return not genome.is_empty() and not state.is_empty()

func phenotype() -> Dictionary:
	return H.compile(state, genome)

func step(ticks: int = 1, slice_ops: int = 4096) -> bool:
	last_block_reason = ""
	for _i in clampi(ticks, 0, 64):
		var result := _drive_tick(state, genome, environment, slice_ops)
		if result.has("state"): state = result.state
		last_status = String(result.get("status", result.get("error", "FAILED")))
		last_block_reason = String(result.get("reason", ""))
		if not bool(result.get("success", false)):
			return false
	return true

func resize_capacity(modules: int, tips: int) -> bool:
	var result := K.resize_capacity(state, genome, modules, tips)
	if not result.success:
		last_status = String(result.get("error", "INVALID_CAPACITY"))
		return false
	state = result.state
	last_status = "CAPACITY_RESIZED"
	last_block_reason = ""
	return true

func mutate(operator: String, seed: int) -> Dictionary:
	var result := M.mutate(genome, seed, operator)
	if result.success:
		genome = result.genome
		state = S.create(genome)
		generation += 1
		lineage.append({"generation": generation, "operator": operator, "hash": G.biological_hash(genome), "event_hash": result.event_hash})
		gallery.clear()
		last_status = "MUTATED"
		last_block_reason = ""
	return result

func environment_preview(water: int, light: int, ticks: int = 8, module_limit: int = 256, tip_limit: int = 32) -> Dictionary:
	var result := _simulate(genome, E.create(water, light), ticks, module_limit, tip_limit)
	return result.phenotype if result.success else {}

func generate(count: int = 100, seed: int = 1000, module_limit: int = 256, tip_limit: int = 32) -> Dictionary:
	gallery.clear()
	var signatures := {}
	var rejected := 0
	var blocked := 0
	var operators := ["small", "medium", "regulatory", "insert", "rewire"]
	for i in clampi(count, 1, 1000):
		var mutation := M.mutate(genome, seed + i, operators[i % operators.size()])
		if not mutation.success: rejected += 1; continue
		var simulated := _simulate(mutation.genome, environment.duplicate(true), 4, module_limit, tip_limit)
		if not simulated.success:
			rejected += 1
			if simulated.status == "BUDGET_BLOCKED": blocked += 1
			continue
		var p: Dictionary = simulated.phenotype
		signatures[p.topology_hash] = true
		gallery.append({"genome": mutation.genome, "phenotype": p, "event": mutation.event})
	return {"accepted": gallery.size(), "rejected": rejected, "blocked": blocked, "topology_signatures": signatures.size(), "viability": "NOT_PROVEN_BY_CONTRACT_VALIDITY"}

func export_genome() -> String:
	return G.serialize(genome)

func import_genome(text: String) -> bool:
	var value := G.deserialize(text)
	if value.is_empty(): return false
	genome = value
	state = S.create(genome)
	family = IMPORTED_FAMILY
	generation = 0
	lineage = [{"generation": 0, "hash": G.biological_hash(genome), "source": "IMPORT"}]
	gallery.clear()
	last_status = "IMPORTED"
	last_block_reason = ""
	return not state.is_empty()

func hashes() -> Dictionary:
	var p := phenotype()
	return {"genome": G.biological_hash(genome), "development": S.biological_hash(state), "phenotype": p.get("phenotype_hash", ""), "topology": p.get("topology_hash", "")}

func _drive_tick(source: Dictionary, g: Dictionary, env: Dictionary, slice_ops: int) -> Dictionary:
	var s := source
	if s.frame.is_empty():
		var opened := K.begin_tick(s, g, env, B.stock(), s.grant_seq + 1)
		if not opened.success: return opened
		s = opened.state
	for _slice in 4096:
		var result := K.advance(s, g, slice_ops)
		if not result.success: return result
		s = result.state
		match String(result.status):
			"RUNNING": pass
			"TICK_COMPLETE": return {"success": true, "state": s, "status": "TICK_COMPLETE"}
			"BUDGET_BLOCKED": return {"success": false, "state": s, "status": "BUDGET_BLOCKED", "reason": String(result.get("reason", "UNKNOWN_CAPACITY"))}
			_: return {"success": false, "state": s, "status": "INVALID_INTERPRETER_STATUS", "reason": String(result.status)}
	return {"success": false, "state": s, "status": "SLICE_LOOP_LIMIT"}

func _simulate(g: Dictionary, env: Dictionary, ticks: int, module_limit: int, tip_limit: int) -> Dictionary:
	var s := S.create(g)
	var resized := K.resize_capacity(s, g, module_limit, tip_limit)
	if not resized.success:
		return {"success": false, "status": String(resized.get("error", "INVALID_CAPACITY"))}
	s = resized.state
	for _tick in clampi(ticks, 0, 64):
		var result := _drive_tick(s, g, env, 4096)
		if result.has("state"): s = result.state
		if not result.success:
			return {"success": false, "state": s, "status": String(result.get("status", "FAILED")), "reason": String(result.get("reason", ""))}
	return {"success": true, "state": s, "status": "TICK_COMPLETE", "phenotype": H.compile(s, g)}
