extends RefCounted

## ECO.EVO7 PAR3 — single pure candidate reproduction kernel (v1).
##
## SINGLE IMPLEMENTATION of deterministic LS3.3 candidate construction.
## The formulas are moved VERBATIM from
## eco_evo7_ls33_dispersal_recruitment_v1.gd (_mutation_seed, the candidate
## field layout and _candidate_hash); no biological value, key order
## semantic, rounding or hash input changes are allowed or made.
##
## Ownership: deterministic orchestration ONLY — mutation seed derivation,
## the reproduce_bundle call, candidate fields, candidate_hash construction.
## The actual mutation/reproduction stays in
## plant_mutation_lineage_extension_evo7_v1.reproduce_bundle(...): this
## kernel never implements mutation itself.
##
## Callers:
##   - serial LS3.3 _build_candidates (default path);
##   - the PAR3 parallel candidate executor (process workers);
## so serial and parallel candidate generation can never diverge by
## construction.
##
## Purity: static functions only; no Node, no SceneTree, no rendering, no
## physics, no FileAccess, no network, no OS, no global mutable RNG, no
## mutation of shared parent bundles (parent_bundle fields are deep-copied
## inside reproduce_bundle; this kernel never writes into the parent).

const LineageExtension = preload("res://scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd")

const KERNEL_SCHEMA := "distributed_world_simulator.ecology.evo7_par3_candidate_kernel.v1"
const KERNEL_VERSION := "1.0.0"

## Canonical parent order for reproduction: sorted by record_id.
static func ordered_parents(parents: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for parent_value in parents:
		if not parent_value is Dictionary:
			return []
		out.append(parent_value)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["record_id"]) < String(b["record_id"])
	)
	return out

## One deterministic candidate. Verbatim LS3.3 semantics:
##   mutation_seed   = _seed48(SCHEMA|mutation|evolution_seed|identity|
##                             bundle_checksum|generation|ordinal)
##   reproduction    = the LineageExtension bundle call (parent_bundle,
##                             mutation_seed, offspring_ordinal)
##   candidate_hash  = sha256 over the frozen candidate identity fields.
## schema/version/evolution_seed are passed by the caller (LS3.3 constants).
## Returns {} on reproduction/validation failure.
static func build_candidate(
	parent: Dictionary,
	generation: int,
	offspring_ordinal: int,
	schema: String,
	version: String,
	evolution_seed: int,
	adopt_reproduction_bundle: bool = false
) -> Dictionary:
	var parent_bundle: Dictionary = parent["hereditary_bundle"]
	var mutation_seed := _mutation_seed(schema, evolution_seed, parent, generation, offspring_ordinal)
	var reproduction := _canonical_reproduce(parent_bundle, mutation_seed, offspring_ordinal)
	if reproduction.is_empty():
		return {}
	## PERF2.4 R6: reproduce_bundle() returns a freshly-created child bundle.
	## Optimized STREAM1 may adopt that owned value directly instead of deep
	## copying the whole genome/traits/lineage tree once more. Legacy keeps the
	## historical defensive copy for an honest same-run A/B baseline.
	var child_bundle: Dictionary = (
		Dictionary(reproduction["bundle"])
		if adopt_reproduction_bundle
		else Dictionary(reproduction["bundle"]).duplicate(true)
	)
	var candidate := {
		"parent_record_id": String(parent["record_id"]),
		"parent_reproductive_identity": String(parent["reproductive_identity"]),
		"parent_cell_index": int(parent["cell_index"]),
		"generation": generation,
		"offspring_ordinal": offspring_ordinal,
		"mutation_seed": mutation_seed,
		"reproduction_result_hash": String(reproduction["result_hash"]),
		"child_bundle_checksum": String(child_bundle["bundle_checksum"]),
		"child_individual_id": String(Dictionary(child_bundle["lineage"])["individual_id"]),
		"child_bundle": child_bundle,
	}
	candidate["candidate_hash"] = candidate_hash(schema, version, candidate)
	return candidate

## Canonical candidate pool hash (verbatim LS3.3 _candidate_pool_hash).
static func candidate_pool_hash(candidates: Array, schema: String, version: String) -> String:
	var hashes := PackedStringArray()
	for value in candidates:
		hashes.append(String(value.get("candidate_hash", "")))
	hashes.sort()
	return (schema + "|" + version + "|candidate-pool|" + "|".join(hashes)).sha256_text()

## Canonical sort: by candidate_hash (frozen LS3.3 ordering).
static func sort_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate_hash"]) < String(b["candidate_hash"])
	)
	return candidates

## Cheap authority-side binding validation. This deliberately does NOT
## reproduce the child (that remains expensive worker/kernel work), but it
## proves that a proposal candidate is attached to a current parent, the
## canonical offspring ordinal and the exact deterministic mutation seed.
## The child bundle itself is validated before LS3.3 commits next_records.
static func validate_parent_binding(
	parent: Dictionary,
	candidate: Dictionary,
	generation: int,
	schema: String,
	evolution_seed: int,
	offspring_per_parent: int
) -> bool:
	if String(candidate.get("parent_record_id", "")) != String(parent.get("record_id", "")):
		return false
	if String(candidate.get("parent_reproductive_identity", "")) != String(parent.get("reproductive_identity", "")):
		return false
	if int(candidate.get("parent_cell_index", -1)) != int(parent.get("cell_index", -2)):
		return false
	if int(candidate.get("generation", -1)) != generation:
		return false
	var ordinal := int(candidate.get("offspring_ordinal", -1))
	if ordinal < 0 or ordinal >= offspring_per_parent:
		return false
	if int(candidate.get("mutation_seed", -1)) != _mutation_seed(
		schema, evolution_seed, parent, generation, ordinal):
		return false
	var bundle_value = candidate.get("child_bundle")
	if not bundle_value is Dictionary:
		return false
	var bundle: Dictionary = bundle_value
	if String(candidate.get("child_bundle_checksum", "")) != String(bundle.get("bundle_checksum", "")):
		return false
	var lineage_value = bundle.get("lineage")
	if not lineage_value is Dictionary:
		return false
	if String(candidate.get("child_individual_id", "")) != String(Dictionary(lineage_value).get("individual_id", "")):
		return false
	return true

## PERF2.4 optimized chunk seam.
##
## The caller must already provide parents in canonical record_id order. This
## avoids re-sorting every bounded STREAM1 chunk. Candidate formulas and hashes
## are unchanged; the only difference is that chunk-local candidate_hash
## canonicalization is deferred to the generation boundary.
static func build_presorted_unsorted(
	parents: Array,
	generation: int,
	schema: String,
	version: String,
	evolution_seed: int,
	offspring_per_parent: int,
	adopt_reproduction_bundle: bool = false
) -> Array[Dictionary]:
	if generation < 1 or schema.is_empty() or version.is_empty() or offspring_per_parent < 1:
		return []
	var out: Array[Dictionary] = []
	var previous_record_id := ""
	var has_previous := false
	for parent_value in parents:
		if not parent_value is Dictionary:
			return []
		var parent: Dictionary = parent_value
		var record_id := String(parent.get("record_id", ""))
		if record_id.is_empty():
			return []
		if has_previous and record_id < previous_record_id:
			return []
		previous_record_id = record_id
		has_previous = true
		for offspring_ordinal in offspring_per_parent:
			var candidate: Dictionary = build_candidate(
				parent, generation, offspring_ordinal, schema, version, evolution_seed,
				adopt_reproduction_bundle)
			if candidate.is_empty():
				return []
			out.append(candidate)
	return out

## Full serial build over ordered parents (audit oracle and default path).
## Returns [] on any failure (fail-closed).
static func build_all(
	parents: Array,
	generation: int,
	schema: String,
	version: String,
	evolution_seed: int,
	offspring_per_parent: int
) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = ordered_parents(parents)
	if ordered.size() != parents.size():
		return []
	var out: Array[Dictionary] = build_presorted_unsorted(
		ordered, generation, schema, version, evolution_seed, offspring_per_parent)
	if out.size() != ordered.size() * offspring_per_parent:
		return []
	return sort_candidates(out)

## ---------- verbatim LS3.3 internals ----------

static func _mutation_seed(schema: String, evolution_seed: int, parent: Dictionary, next_generation: int, offspring_ordinal: int) -> int:
	var key := "%s|mutation|%d|%s|%s|%d|%d" % [
		schema, evolution_seed, String(parent["reproductive_identity"]),
		String(parent["bundle_checksum"]), next_generation, offspring_ordinal,
	]
	return _seed48(key)

static func _canonical_reproduce(parent_bundle: Dictionary, mutation_seed: int, offspring_ordinal: int) -> Dictionary:
	## The only offspring creation call site: same extension, same call.
	return LineageExtension.reproduce_bundle(parent_bundle, mutation_seed, offspring_ordinal)

static func candidate_hash(schema: String, version: String, candidate: Dictionary) -> String:
	return "|".join(PackedStringArray([
		schema, version, "candidate",
		String(candidate.get("parent_reproductive_identity", "")),
		str(int(candidate.get("generation", -1))),
		str(int(candidate.get("offspring_ordinal", -1))),
		str(int(candidate.get("mutation_seed", 0))),
		String(candidate.get("reproduction_result_hash", "")),
		String(candidate.get("child_bundle_checksum", "")),
		String(candidate.get("child_individual_id", "")),
	])).sha256_text()

static func _seed48(key: String) -> int:
	return key.sha256_text().substr(0, 12).hex_to_int()
