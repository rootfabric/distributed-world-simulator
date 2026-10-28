extends RefCounted
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const SCHEMA := "dws.ecology.organism-genome.v2"
const BOUNDS := {"length_permille": [250, 3000], "radius_permille": [250, 3000], "collector_permille": [100, 4000], "absorber_permille": [100, 4000]}

static func create(program: Dictionary, label: String = "organism") -> Dictionary:
	if not P.validate(program).is_empty():
		return {}
	var g := {"schema": SCHEMA, "label": label, "genes": {"length_permille": 1000, "radius_permille": 1000, "collector_permille": 1000, "absorber_permille": 1000}, "program": P.normalized(program)}
	return g if validate(g).is_empty() else {}

static func validate(g: Variant) -> String:
	if not C.keys(g, ["schema", "label", "genes", "program"]) or g.schema != SCHEMA:
		return "GENOME_SCHEMA"
	if not g.label is String or g.label.length() > 128:
		return "GENOME_LABEL"
	if not C.keys(g.genes, BOUNDS.keys()):
		return "GENE_FIELDS"
	for name in BOUNDS:
		if not C.integer(g.genes[name], BOUNDS[name][0], BOUNDS[name][1]):
			return "GENE_RANGE:" + name
	var error := P.validate(g.program)
	if not error.is_empty(): return error
	return "NONCANONICAL_GENOME" if C.encode(g).is_empty() else ""

static func biological_hash(g: Dictionary) -> String:
	if not validate(g).is_empty():
		return ""
	return C.digest({"schema": SCHEMA, "genes": g.genes, "program": P.normalized(g.program)})

static func serialize(g: Dictionary) -> String:
	if not validate(g).is_empty():
		return ""
	var normalized := g.duplicate(true)
	normalized.program = P.normalized(g.program)
	return C.encode({"schema": "dws.ecology.genome-file.v1", "genome": normalized, "biological_hash": biological_hash(g)})

static func deserialize(text: String) -> Dictionary:
	var parsed := C.decode(text)
	if not parsed.success:
		return {}
	var value: Variant = parsed.value
	if not C.keys(value, ["schema", "genome", "biological_hash"]) or value.schema != "dws.ecology.genome-file.v1":
		return {}
	if not validate(value.genome).is_empty() or value.biological_hash != biological_hash(value.genome):
		return {}
	return value.genome
