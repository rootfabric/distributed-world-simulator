# EcologyWorkbench GenomeEditor v1 (P7, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: creation of NEW valid genome variants STRICTLY through the canonical
#   A3 mutation API (genome_mutation_v1 mutate/crossover/delete_rule).
#   Every produced variant is validated by organism_genome_v2.validate;
#   an invalid result is rejected with {success: false, error} and NOTHING
#   is applied. There is NO manual editing of internal Dictionaries that
#   bypasses validation, and NO application to a live population (canonical
#   rule: new genomes may only enter as manifest founders).
# Layer: 2 (SIMULATION / ORCHESTRATION) — input layer only.
# Canonical API used (owner map rows 1,4):
#   - genome_mutation_v1.gd: mutate/crossover/delete_rule + OPERATORS  [A3]
#   - organism_genome_v2.gd: validate/biological_hash  [A1]
#   - experiment_manifest_v1.gd: immutable founder/placement extension.
class_name EcoWorkbenchGenomeEditorV1
extends RefCounted

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")

const SCHEMA := "dws.ecology.workbench.genome-editor.v1"
const KINDS := ["mutate", "crossover", "delete_rule"]

## Propose a NEW validated genome variant from a parent genome.
## edit := {"kind": "mutate"|"crossover"|"delete_rule",
##          "operator"?: String (mutate; must be in Mutation.OPERATORS),
##          "donor"?: Dictionary (crossover; validated genome),
##          "seed"?: int, "rule_id"?: String (delete_rule)}.
## Returns {"success": true, "genome", "biological_hash", "event",
##          "event_hash", "parent_hash"} or {"success": false, "error"}.
## The parent is NEVER modified (canonical A3 duplicates its input).
static func propose_variant(parent_genome: Dictionary, edit: Dictionary) -> Dictionary:
	if not parent_genome is Dictionary:
		return _reject("EDITOR_PARENT_TYPE")
	var parent_error := Genome.validate(parent_genome)
	if not parent_error.is_empty():
		return _reject("EDITOR_PARENT_INVALID:" + parent_error)
	if not edit is Dictionary or not edit.has("kind") or not edit.kind in KINDS:
		return _reject("EDITOR_EDIT_KIND")
	var seed := 0
	if edit.has("seed") and edit.seed != null:
		if not C.integer(edit.seed, 0, C.MAX_INT):
			return _reject("EDITOR_SEED")
		seed = int(edit.seed)
	var result: Dictionary = {}
	match String(edit.kind):
		"mutate":
			var operator := "small"
			if edit.has("operator") and edit.operator != null:
				operator = String(edit.operator)
			if not operator in Mutation.OPERATORS:
				return _reject("EDITOR_OPERATOR_UNKNOWN:" + operator)
			result = Mutation.mutate(parent_genome, seed, operator)
		"crossover":
			if not edit.has("donor") or not edit.donor is Dictionary:
				return _reject("EDITOR_DONOR_MISSING")
			var donor_error := Genome.validate(edit.donor)
			if not donor_error.is_empty():
				return _reject("EDITOR_DONOR_INVALID:" + donor_error)
			result = Mutation.crossover(parent_genome, edit.donor, seed)
		"delete_rule":
			if not edit.has("rule_id") or not edit.rule_id is String or String(edit.rule_id).is_empty():
				return _reject("EDITOR_RULE_ID")
			result = Mutation.delete_rule(parent_genome, String(edit.rule_id), seed)
	if not bool(result.get("success", false)):
		return _reject("EDITOR_" + String(edit.kind).to_upper() + ":" + String(result.get("reason", "REJECTED")))
	var candidate: Dictionary = result.genome
	var candidate_error := Genome.validate(candidate)
	if not candidate_error.is_empty():
		# Never hand out or register a non-validating genome.
		return _reject("EDITOR_VARIANT_INVALID:" + candidate_error)
	return {
		"success": true,
		"genome": candidate.duplicate(true),
		"biological_hash": Genome.biological_hash(candidate),
		"event": result.get("event", {}),
		"event_hash": String(result.get("event_hash", "")),
		"parent_hash": Genome.biological_hash(parent_genome),
	}

## Register a validated genome into the session founder registry (in place;
## the registry maps biological_hash -> genome, matching the P1 founder
## reference form). Returns the biological hash ("" when invalid).
static func register_founder(founder_registry: Dictionary, genome: Dictionary) -> String:
	if not founder_registry is Dictionary:
		return ""
	var error := Genome.validate(genome)
	if not error.is_empty():
		return ""
	var hash := Genome.biological_hash(genome)
	if hash.is_empty():
		return ""
	founder_registry[hash] = genome.duplicate(true)
	return hash

## Build a NEW immutable manifest that plants an accepted variant as an
## additional founder (biological_hash reference form + placement entry),
## with the registry entry added so the controller can resolve it.
## Returns {"success", "manifest", "manifest_hash", "founder_id",
## "biological_hash"} or {"success": false, "error"}.
## Applying to a LIVE population is deliberately impossible: only founders.
static func add_founder_to_manifest(manifest: Dictionary, genome: Dictionary, founder_id: String, zone_id: String, position_mm: Array) -> Dictionary:
	if not manifest is Dictionary or not Manifest.validate(manifest).is_empty():
		return _reject("EDITOR_MANIFEST_INVALID")
	var genome_error := Genome.validate(genome)
	if not genome_error.is_empty():
		return _reject("EDITOR_GENOME_INVALID:" + genome_error)
	var hash := Genome.biological_hash(genome)
	if hash.is_empty():
		return _reject("EDITOR_GENOME_HASH")
	if not C.identifier(founder_id):
		return _reject("EDITOR_FOUNDER_ID")
	for founder in manifest.founders:
		if String(founder.founder_id) == founder_id:
			return _reject("EDITOR_FOUNDER_ID_TAKEN")
	var zone_ids := {}
	for zone in manifest.environment.zones:
		zone_ids[String(zone.id)] = true
	if not zone_ids.has(zone_id):
		return _reject("EDITOR_ZONE_UNKNOWN:" + zone_id)
	if not C.vector(position_mm, 10000000):
		return _reject("EDITOR_POSITION")
	var next := manifest.duplicate(true)
	next.founders.append({"founder_id": founder_id, "biological_hash": hash, "genome": null})
	next.placement.entries.append({"founder_ref": founder_id, "zone_id": zone_id, "position_mm": position_mm.duplicate(true)})
	var manifest_error := Manifest.validate(next)
	if not manifest_error.is_empty():
		return _reject("EDITOR_RESULT_INVALID:" + manifest_error)
	return {
		"success": true,
		"manifest": next,
		"manifest_hash": Manifest.canonical_hash(next),
		"founder_id": founder_id,
		"biological_hash": hash,
	}

static func _reject(error: String) -> Dictionary:
	return {"success": false, "error": error}
