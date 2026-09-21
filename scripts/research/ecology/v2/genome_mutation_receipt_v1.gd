extends RefCounted
## Canonical genome mutation receipt (ECO ARCH2 A10.5 repair R1).
## Binds an accepted A3 mutation event to the canonical A5 parent-transfer
## admission of the mutated genome. A mutated child genome may ONLY enter a
## lineage through a sealed receipt issued from the actual parent blueprint
## and the actual mutated genome; A5 admission verifies the binding
## fail-closed. There is no fallback to the parent blueprint when a mutation
## was attempted: either a valid receipt + canonical admission, or failure.
## Layer: 1 (CANONICAL CONTRACT). Zero own biology: hashes and bindings only.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const BP = preload("res://scripts/research/ecology/v2/organism_blueprint_v1.gd")

const SCHEMA := "dws.ecology.genome-mutation-receipt.v1"
const KEYS := ["schema", "parent_genome_hash", "child_genome_hash", "operator", "seed", "event_hash", "bias_hash"]

## Issue a sealed receipt from the actual objects. parent_blueprint is the
## reproduced parent's blueprint (its genome hash is what an A5 propagule
## carries in blueprint_hash); child_genome is the accepted A3 output.
## bias_hash: "" or a 64-hex provenance hash of an explicit organization
## development bias (canonical bias extension hook; "" when unbiased).
static func issue(parent_blueprint: Dictionary, child_genome: Dictionary, operator: String, seed: int, bias_hash: String = "") -> Dictionary:
	if not BP.validate(parent_blueprint).is_empty() or not G.validate(child_genome).is_empty():
		return {}
	if not operator in Mutation.OPERATORS or not C.integer(seed, 0, C.MAX_INT):
		return {}
	if bias_hash != "" and not _valid_hash(bias_hash):
		return {}
	var parent_genome_hash: String = G.biological_hash(parent_blueprint.genome)
	var child_genome_hash: String = G.biological_hash(child_genome)
	if parent_genome_hash.is_empty() or child_genome_hash.is_empty():
		return {}
	var payload := {
		"schema": SCHEMA,
		"parent_genome_hash": parent_genome_hash,
		"child_genome_hash": child_genome_hash,
		"operator": operator,
		"seed": seed,
		"bias_hash": bias_hash,
	}
	var event_hash := C.digest(payload)
	if not _valid_hash(event_hash):
		return {}
	payload["event_hash"] = event_hash
	return payload

## Structural + seal validation of a receipt (no binding checks).
static func validate(receipt: Variant) -> String:
	if not C.keys(receipt, KEYS) or receipt.schema != SCHEMA:
		return "MUTATION_RECEIPT_SCHEMA"
	if not _valid_hash(receipt.parent_genome_hash) or not _valid_hash(receipt.child_genome_hash):
		return "MUTATION_RECEIPT_HASH"
	if not receipt.operator is String or not receipt.operator in Mutation.OPERATORS:
		return "MUTATION_RECEIPT_OPERATOR"
	if not C.integer(receipt.seed, 0, C.MAX_INT):
		return "MUTATION_RECEIPT_SEED"
	if receipt.bias_hash != "" and not _valid_hash(receipt.bias_hash):
		return "MUTATION_RECEIPT_BIAS"
	var payload: Dictionary = receipt.duplicate(true)
	payload.erase("event_hash")
	if C.digest(payload) != receipt.event_hash:
		return "MUTATION_RECEIPT_EVENT_HASH"
	return "NONCANONICAL_MUTATION_RECEIPT" if C.encode(receipt).is_empty() else ""

## Admission binding: the receipt must bind the EXACT parent blueprint and
## the EXACT mutated child blueprint of this propagule admission.
## propagule.blueprint_hash (written by A5 from the reproduced parent) must
## equal digest(parent genome hash + child-inherited life_history), which
## proves both the parent binding AND that the child inherited the parent
## life_history verbatim (A3 mutates the genome only).
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
	var parent_binding: String = C.digest({
		"schema": BP.SCHEMA,
		"genome_hash": String(receipt.parent_genome_hash),
		"life_history": child_blueprint.life_history,
	})
	if propagule.blueprint_hash != parent_binding:
		return "MUTATION_RECEIPT_PROPAGULE_BINDING"
	return ""

static func _valid_hash(v: Variant) -> bool:
	if not v is String or String(v).length() != 64:
		return false
	for c in String(v):
		if not c in "0123456789abcdef":
			return false
	return true
