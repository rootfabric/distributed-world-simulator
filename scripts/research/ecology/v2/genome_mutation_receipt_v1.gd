extends RefCounted
## Canonical A3 -> A5 mutation receipt.
##
## The receipt does not merely bind arbitrary parent/child hashes. Admission
## deterministically replays the canonical A3 transition from the exact parent
## genome, seed and optional versioned bias, then requires the replayed child
## genome and mutation event hash to match. A5 therefore cannot admit a valid
## but unrelated child genome under fabricated mutation provenance.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")

const SCHEMA := "dws.ecology.genome-mutation-receipt.v2"
const KEYS := [
	"schema", "parent_genome_hash", "child_genome_hash", "operator", "seed",
	"mutation_event_hash", "bias", "bias_hash", "receipt_hash",
]

## Issue only from an actual successful A3 result. mutation_result is the
## return value of Mutation.mutate() or Mutation.mutate_with_bias().
static func issue(parent_blueprint: Dictionary, mutation_result: Dictionary, seed: int, bias: Dictionary = {}) -> Dictionary:
	if not BP.validate(parent_blueprint).is_empty() or not C.integer(seed, 0, C.MAX_INT):
		return {}
	if not mutation_result is Dictionary or not bool(mutation_result.get("success", false)):
		return {}
	if not mutation_result.get("genome") is Dictionary or not mutation_result.get("event") is Dictionary:
		return {}
	var child_genome: Dictionary = mutation_result.genome
	if not G.validate(child_genome).is_empty():
		return {}
	var operator := String(mutation_result.get("selected_operator", mutation_result.event.get("operator", "")))
	if not operator in Mutation.OPERATORS:
		return {}
	if not bias is Dictionary:
		return {}
	var bias_copy: Dictionary = bias.duplicate(true)
	var bias_hash := ""
	if not bias_copy.is_empty():
		if not Mutation.validate_bias(bias_copy).is_empty():
			return {}
		bias_hash = C.digest(bias_copy)
		if not _valid_hash(bias_hash):
			return {}

	# Prove the supplied result itself is an authentic deterministic A3 result
	# before issuing a durable receipt.
	var replay := Mutation.mutate(parent_blueprint.genome, seed, operator) if bias_copy.is_empty() 		else Mutation.mutate_with_bias(parent_blueprint.genome, seed, bias_copy)
	if not bool(replay.get("success", false)):
		return {}
	var replay_operator := String(replay.get("selected_operator", replay.event.get("operator", "")))
	if replay_operator != operator:
		return {}
	if G.biological_hash(replay.genome) != G.biological_hash(child_genome):
		return {}
	if String(replay.get("event_hash", "")) != String(mutation_result.get("event_hash", "")):
		return {}

	var event: Dictionary = mutation_result.event
	if String(event.get("operator", "")) != operator 			or String(event.get("seed", "")) != str(seed) 			or String(event.get("parent_hash", "")) != G.biological_hash(parent_blueprint.genome) 			or String(event.get("child_hash", "")) != G.biological_hash(child_genome):
		return {}
	var mutation_event_hash := String(mutation_result.get("event_hash", ""))
	if not _valid_hash(mutation_event_hash) or mutation_event_hash != C.digest(event):
		return {}

	var value := {
		"schema": SCHEMA,
		"parent_genome_hash": G.biological_hash(parent_blueprint.genome),
		"child_genome_hash": G.biological_hash(child_genome),
		"operator": operator,
		"seed": seed,
		"mutation_event_hash": mutation_event_hash,
		"bias": bias_copy,
		"bias_hash": bias_hash,
		"receipt_hash": "",
	}
	value.receipt_hash = _receipt_hash(value)
	return value if validate(value).is_empty() else {}

static func validate(receipt: Variant) -> String:
	if not C.keys(receipt, KEYS) or String(receipt.schema) != SCHEMA:
		return "MUTATION_RECEIPT_SCHEMA"
	if not _valid_hash(receipt.parent_genome_hash) or not _valid_hash(receipt.child_genome_hash):
		return "MUTATION_RECEIPT_HASH"
	if not receipt.operator is String or not String(receipt.operator) in Mutation.OPERATORS:
		return "MUTATION_RECEIPT_OPERATOR"
	if not C.integer(receipt.seed, 0, C.MAX_INT):
		return "MUTATION_RECEIPT_SEED"
	if not _valid_hash(receipt.mutation_event_hash):
		return "MUTATION_RECEIPT_EVENT_HASH"
	if not receipt.bias is Dictionary:
		return "MUTATION_RECEIPT_BIAS"
	if receipt.bias.is_empty():
		if not String(receipt.bias_hash).is_empty():
			return "MUTATION_RECEIPT_BIAS"
	else:
		var bias_error := Mutation.validate_bias(receipt.bias)
		if not bias_error.is_empty() or C.digest(receipt.bias) != String(receipt.bias_hash):
			return "MUTATION_RECEIPT_BIAS"
	if not _valid_hash(receipt.receipt_hash) or String(receipt.receipt_hash) != _receipt_hash(receipt):
		return "MUTATION_RECEIPT_SEAL"
	return "NONCANONICAL_MUTATION_RECEIPT" if C.encode(receipt).is_empty() else ""

## Admission binding: receipt + exact parent + exact child + exact propagule.
## Crucially, A3 is replayed here. The child is admitted only when the replay
## reproduces the receipt's operator, genome hash and mutation event hash.
static func validate_admission(receipt: Variant, propagule: Dictionary, parent_blueprint: Dictionary, child_blueprint: Dictionary) -> String:
	var error := validate(receipt)
	if not error.is_empty():
		return error
	if not BP.validate(parent_blueprint).is_empty() or not BP.validate(child_blueprint).is_empty():
		return "MUTATION_RECEIPT_BLUEPRINT"
	if String(receipt.parent_genome_hash) != G.biological_hash(parent_blueprint.genome):
		return "MUTATION_RECEIPT_PARENT_GENOME"
	if String(receipt.child_genome_hash) != G.biological_hash(child_blueprint.genome):
		return "MUTATION_RECEIPT_CHILD_GENOME"
	var parent_binding := C.digest({
		"schema": BP.SCHEMA,
		"genome_hash": String(receipt.parent_genome_hash),
		"life_history": child_blueprint.life_history,
	})
	if String(propagule.get("blueprint_hash", "")) != parent_binding:
		return "MUTATION_RECEIPT_PROPAGULE_BINDING"

	var replay := Mutation.mutate(parent_blueprint.genome, int(receipt.seed), String(receipt.operator)) 		if receipt.bias.is_empty() 		else Mutation.mutate_with_bias(parent_blueprint.genome, int(receipt.seed), receipt.bias)
	if not bool(replay.get("success", false)):
		return "MUTATION_RECEIPT_REPLAY"
	var replay_operator := String(replay.get("selected_operator", replay.event.get("operator", "")))
	if replay_operator != String(receipt.operator):
		return "MUTATION_RECEIPT_REPLAY_OPERATOR"
	if G.biological_hash(replay.genome) != String(receipt.child_genome_hash):
		return "MUTATION_RECEIPT_REPLAY_CHILD"
	if String(replay.get("event_hash", "")) != String(receipt.mutation_event_hash):
		return "MUTATION_RECEIPT_REPLAY_EVENT"
	return ""

static func _receipt_hash(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.receipt_hash = ""
	return C.digest(payload)

static func _valid_hash(value: Variant) -> bool:
	if not value is String or String(value).length() != 64:
		return false
	for c in String(value):
		if not c in "0123456789abcdef":
			return false
	return true
