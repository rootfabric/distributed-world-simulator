extends RefCounted
## A5 heritable wrapper: accepted GenomeV2 + inherited life-history policy.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const L = preload("res://scripts/research/ecology/v2/life_history_program_v1.gd")
const SCHEMA := "dws.ecology.organism-blueprint.v1"

static func create(genome: Dictionary, life_history: Dictionary = {}) -> Dictionary:
	var policy := L.create_default() if life_history.is_empty() else life_history.duplicate(true)
	var value := {"schema": SCHEMA, "genome": genome.duplicate(true), "life_history": policy}
	return value if validate(value).is_empty() else {}

static func validate(v: Variant) -> String:
	if not C.keys(v, ["schema", "genome", "life_history"]) or v.schema != SCHEMA:
		return "BLUEPRINT_SCHEMA"
	var genome_error := G.validate(v.genome)
	if not genome_error.is_empty(): return genome_error
	var life_error := L.validate(v.life_history)
	if not life_error.is_empty(): return life_error
	return "NONCANONICAL_BLUEPRINT" if C.encode(v).is_empty() else ""

static func biological_hash(v: Dictionary) -> String:
	if not validate(v).is_empty(): return ""
	return C.digest({"schema": SCHEMA, "genome_hash": G.biological_hash(v.genome), "life_history": v.life_history})

static func serialize(v: Dictionary) -> String:
	if not validate(v).is_empty(): return ""
	return C.encode({"schema": "dws.ecology.blueprint-file.v1", "blueprint": v, "biological_hash": biological_hash(v)})

static func deserialize(text: String) -> Dictionary:
	var decoded := C.decode(text)
	if not decoded.success or not decoded.value is Dictionary: return {}
	var v: Dictionary = decoded.value
	if not C.keys(v, ["schema", "blueprint", "biological_hash"]) or v.schema != "dws.ecology.blueprint-file.v1": return {}
	if not validate(v.blueprint).is_empty() or v.biological_hash != biological_hash(v.blueprint): return {}
	return v.blueprint
