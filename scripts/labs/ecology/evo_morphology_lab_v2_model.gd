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

var family := 0
var genome: Dictionary
var state: Dictionary
var environment: Dictionary
var generation := 0
var lineage: Array = []
var gallery: Array = []

func _init() -> void:
	reset(0)

func reset(index: int = 0) -> bool:
	if index < 0 or index >= F.NAMES.size(): return false
	family = index
	genome = F.make(index)
	environment = E.create()
	state = S.create(genome)
	generation = 0
	lineage = [{"generation": 0, "hash": G.biological_hash(genome)}]
	gallery.clear()
	return not genome.is_empty() and not state.is_empty()

func phenotype() -> Dictionary:
	return H.compile(state, genome)

func step(ticks: int = 1, slice_ops: int = 4096) -> bool:
	for _i in clampi(ticks, 0, 64):
		var opened := K.begin_tick(state, genome, environment, B.stock(), state.grant_seq + 1)
		if not opened.success: return false
		state = opened.state
		for _j in 4096:
			var result := K.advance(state, genome, slice_ops)
			if not result.success: return false
			state = result.state
			if result.status != "RUNNING": break
	return true

func mutate(operator: String, seed: int) -> Dictionary:
	var result := M.mutate(genome, seed, operator)
	if result.success:
		genome = result.genome
		state = S.create(genome)
		generation += 1
		lineage.append({"generation": generation, "operator": operator, "hash": G.biological_hash(genome), "event_hash": result.event_hash})
	return result

func environment_preview(water: int, light: int, ticks: int = 8) -> Dictionary:
	var env := E.create(water, light)
	var s := S.create(genome)
	for _i in clampi(ticks, 0, 64):
		var opened := K.begin_tick(s, genome, env, B.stock(), s.grant_seq + 1)
		if not opened.success: return {}
		s = opened.state
		var done := false
		for _j in 4096:
			var result := K.advance(s, genome, 4096)
			if not result.success: return {}
			s = result.state
			if result.status != "RUNNING": done = true; break
		if not done: return {}
	return H.compile(s, genome)

func generate(count: int = 100, seed: int = 1000) -> Dictionary:
	gallery.clear()
	var signatures := {}
	var rejected := 0
	var operators := ["small", "medium", "regulatory", "insert", "rewire"]
	for i in clampi(count, 1, 1000):
		var mutation := M.mutate(genome, seed + i, operators[i % operators.size()])
		if not mutation.success: rejected += 1; continue
		var g: Dictionary = mutation.genome
		var s := S.create(g)
		var env := environment.duplicate(true)
		for _tick in 4:
			var opened := K.begin_tick(s, g, env, B.stock(), s.grant_seq + 1)
			if not opened.success: s = {}; break
			s = opened.state
			for _slice in 4096:
				var r := K.advance(s, g, 4096)
				if not r.success: s = {}; break
				s = r.state
				if r.status != "RUNNING": break
			if s.is_empty(): break
		if s.is_empty(): rejected += 1; continue
		var p := H.compile(s, g)
		signatures[p.topology_hash] = true
		gallery.append({"genome": g, "phenotype": p, "event": mutation.event})
	return {"accepted": gallery.size(), "rejected": rejected, "topology_signatures": signatures.size(), "viability": "NOT_PROVEN_BY_CONTRACT_VALIDITY"}

func export_genome() -> String:
	return G.serialize(genome)

func import_genome(text: String) -> bool:
	var value := G.deserialize(text)
	if value.is_empty(): return false
	genome = value
	state = S.create(genome)
	return true

func hashes() -> Dictionary:
	var p := phenotype()
	return {"genome": G.biological_hash(genome), "development": S.biological_hash(state), "phenotype": p.get("phenotype_hash", ""), "topology": p.get("topology_hash", "")}
