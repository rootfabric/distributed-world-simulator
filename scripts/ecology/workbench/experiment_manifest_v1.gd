# EcologyWorkbench ExperimentManifest v1 (P1).
# Role: versioned immutable manifest of one ecology experiment (seed, zones,
#   founders, mutation operators, OrganizationProfile, metrics, checkpoints
#   schedule). Extension of observatory_protocol_v1.treatment; deterministic:
#   identical manifest + seed => identical start state.
# Layer: 2 (SIMULATION / ORCHESTRATION) — INPUT layer only: the manifest never
#   carries runtime biological state (populations, field state, snapshots).
# Canonical API used (owner map rows 1,3,4,5,7,9):
#   - canonical_value_v1.gd: encode/decode/digest — deterministic hash and
#     canonical text serialization (stable key ordering).
#   - organism_genome_v2.gd: validate() for inline founders, biological_hash()
#     reference form  [A1]
#   - genome_mutation_v1.gd: OPERATORS (allowed operator filter)  [A3]
#   - local_environment_field_v1.gd / environment_field_contract_v1.gd:
#     canonical spatial addressing bounds (origin_mm/cell_size_mm/width/depth)
#     and stock/signal limits  [A4]
# Forbidden: no second genome truth, no executable code in genotype, no
#   runtime state in the manifest.
class_name EcoWorkbenchExperimentManifestV1
extends RefCounted

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const OrganizationProfile = preload("res://scripts/ecology/workbench/organization_profile_v1.gd")

const SCHEMA := "dws.ecology.workbench.experiment-manifest.v1"
const FILE_SCHEMA := "dws.ecology.workbench.experiment-manifest-file.v1"
const ORGANIZATION_MODES := ["FREE", "SOFT", "EARTH_LIKE", "NMS_LIKE", "CUSTOM"]
const MODES := ["LAB", "WORLD_COMPAT"]
const FIELDS := [
	"schema", "experiment_id", "seed", "horizon_ticks", "founders",
	"environment", "placement", "mutation", "organization_profile",
	"feedback", "metrics", "checkpoint", "mode",
]
const ZONE_FIELDS := ["id", "water_mg", "light", "temperature", "nutrient_mg", "organic_mg"]
const PLACEMENT_FIELDS := ["founder_ref", "zone_id", "position_mm"]
const MAX_ZONES := 4096
const MAX_FOUNDERS := 4096
# Polygon LAB/WORLD field policy. A4 supports a wider absolute stock type, but
# its water development signal is stock/capacity. Keeping this explicit
# 1,000,000 mg capacity preserves established ecology semantics and makes the
# manifest fail closed instead of silently changing water availability.
const CELL_CAPACITY_MG := 1000000

## Validate manifest against canonical contracts. Returns "" when valid.
## Fail-closed: unknown fields, invalid seed, unresolvable/invalid founder
## references, invalid environment configuration and unknown enum values
## are hard errors.
static func validate(value: Variant) -> String:
	var exact_fields: Array = FIELDS.duplicate()
	if value is Dictionary and value.has("genesis"):
		exact_fields.append("genesis")
	if not C.keys(value, exact_fields) or value.schema != SCHEMA:
		return "MANIFEST_SCHEMA"
	if not C.identifier(value.experiment_id):
		return "MANIFEST_EXPERIMENT_ID"
	if not C.integer(value.seed, 0, C.MAX_INT):
		return "MANIFEST_SEED"
	if not C.integer(value.horizon_ticks, 0, C.MAX_INT):
		return "MANIFEST_HORIZON"
	if not value.mode is String or not value.mode in MODES:
		return "MANIFEST_MODE"
	if not value.organization_profile is String or not value.organization_profile in ORGANIZATION_MODES:
		return "MANIFEST_ORGANIZATION_PROFILE"
	if value.has("genesis"):
		if not value.genesis is Dictionary or not C.keys(value.genesis, ["founder_endowment"]):
			return "MANIFEST_GENESIS"
		if not B.valid_stock(value.genesis.founder_endowment):
			return "MANIFEST_GENESIS_ENDOWMENT"
	var founder_error := _validate_founders(value.founders)
	if not founder_error.is_empty():
		return founder_error
	var environment_error := _validate_environment(value.environment)
	if not environment_error.is_empty():
		return environment_error
	var placement_error := _validate_placement(value.placement, value.founders, value.environment)
	if not placement_error.is_empty():
		return placement_error
	var mutation_error := _validate_mutation(value.mutation)
	if not mutation_error.is_empty():
		return mutation_error
	if not value.feedback is Dictionary or not C.keys(value.feedback, ["enabled", "decomposition_enabled"]):
		return "MANIFEST_FEEDBACK"
	if not value.feedback.enabled is bool or not value.feedback.decomposition_enabled is bool:
		return "MANIFEST_FEEDBACK"
	if not value.metrics is Dictionary or not C.keys(value.metrics, ["requested"]):
		return "MANIFEST_METRICS"
	if not value.metrics.requested is Array or value.metrics.requested.size() > MAX_ZONES:
		return "MANIFEST_METRICS"
	for metric in value.metrics.requested:
		if not metric is String or metric.is_empty() or metric.length() > 128:
			return "MANIFEST_METRIC_NAME"
	if not value.checkpoint is Dictionary or not C.keys(value.checkpoint, ["interval_ticks"]):
		return "MANIFEST_CHECKPOINT"
	if not C.integer(value.checkpoint.interval_ticks, 0, C.MAX_INT):
		return "MANIFEST_CHECKPOINT_INTERVAL"
	return "NONCANONICAL_MANIFEST" if C.encode(value).is_empty() else ""

## Deterministic canonical hash. Identical manifests (any key order) hash
## identically; invalid manifests hash to "".
static func canonical_hash(manifest: Dictionary) -> String:
	if not validate(manifest).is_empty():
		return ""
	# Profile version is part of executable experiment semantics even though
	# the manifest stores only the profile name.
	return C.digest({"manifest": manifest, "organization_profile_version": OrganizationProfile.VERSION})

## Canonical text serialization (validated manifest only; "" when invalid).
static func to_text(manifest: Dictionary) -> String:
	var hash := canonical_hash(manifest)
	if hash.is_empty():
		return ""
	return C.encode({"schema": FILE_SCHEMA, "manifest": manifest, "manifest_hash": hash})

## Parse canonical text back into a validated manifest.
## Returns {"success": true, "manifest": Dictionary, "manifest_hash": String}
## or {"success": false, "error": String}.
static func from_text(text: String) -> Dictionary:
	var parsed := C.decode(text)
	if not parsed.success:
		return {"success": false, "error": String(parsed.error)}
	var value: Variant = parsed.value
	if not C.keys(value, ["schema", "manifest", "manifest_hash"]) or value.schema != FILE_SCHEMA:
		return {"success": false, "error": "MANIFEST_FILE_SCHEMA"}
	var error := validate(value.manifest)
	if not error.is_empty():
		return {"success": false, "error": error}
	if value.manifest_hash != canonical_hash(value.manifest):
		return {"success": false, "error": "MANIFEST_HASH_MISMATCH"}
	return {"success": true, "manifest": value.manifest, "manifest_hash": String(value.manifest_hash)}

## Deterministic treatment-level view for A7/A8 sessions. Input projection
## only — no runtime biological state.
static func to_treatment(manifest: Dictionary) -> Dictionary:
	if not validate(manifest).is_empty():
		return {}
	return {
		"schema": SCHEMA,
		"manifest_hash": canonical_hash(manifest),
		"experiment_id": manifest.experiment_id,
		"seed": manifest.seed,
		"horizon_ticks": manifest.horizon_ticks,
		"mutations_enabled": manifest.mutation.mutations_enabled,
		"effects_enabled": manifest.feedback.enabled,
		"mode": manifest.mode,
	}

static func _validate_founders(founders: Variant) -> String:
	if not founders is Array or founders.is_empty() or founders.size() > MAX_FOUNDERS:
		return "MANIFEST_FOUNDERS"
	var seen_ids := {}
	for founder in founders:
		if not founder is Dictionary:
			return "MANIFEST_FOUNDER"
		if not C.keys(founder, ["founder_id", "biological_hash", "genome"]):
			return "MANIFEST_FOUNDER_FIELDS"
		if not C.identifier(founder.founder_id):
			return "MANIFEST_FOUNDER_ID"
		if seen_ids.has(founder.founder_id):
			return "MANIFEST_FOUNDER_DUPLICATE_ID"
		seen_ids[founder.founder_id] = true
		var has_hash := founder.biological_hash != null
		var has_genome := founder.genome != null
		if has_hash == has_genome:
			# Exactly one reference form: biological_hash OR inline genome.
			return "MANIFEST_FOUNDER_REFERENCE"
		if has_hash:
			if not founder.biological_hash is String or founder.biological_hash.length() != 64:
				return "MANIFEST_FOUNDER_HASH"
			for character in founder.biological_hash:
				if not character in "0123456789abcdef":
					return "MANIFEST_FOUNDER_HASH"
		else:
			if not founder.genome is Dictionary:
				return "MANIFEST_FOUNDER_GENOME"
			var genome_error := Genome.validate(founder.genome)
			if not genome_error.is_empty():
				return "MANIFEST_FOUNDER_GENOME:" + genome_error
			# Inline genome must be an organism_genome_v2.create() product:
			# its biological_hash must match the genome it claims to be.
			if Genome.biological_hash(founder.genome).is_empty():
				return "MANIFEST_FOUNDER_GENOME_HASH"
	return ""

static func _validate_environment(environment: Variant) -> String:
	if not environment is Dictionary or not C.keys(environment, ["spatial", "zones"]):
		return "MANIFEST_ENVIRONMENT"
	var spatial: Dictionary = environment.spatial
	if not C.keys(spatial, ["origin_mm", "cell_size_mm", "width", "depth"]):
		return "MANIFEST_ENVIRONMENT_SPATIAL"
	if not C.vector(spatial.origin_mm, FieldContract.MAX_PORT_COORD_MM):
		return "MANIFEST_ENVIRONMENT_SPATIAL"
	if not C.integer(spatial.cell_size_mm, 1, 1000000):
		return "MANIFEST_ENVIRONMENT_CELL_SIZE"
	if not C.integer(spatial.width, 1, 64) or not C.integer(spatial.depth, 1, 64):
		return "MANIFEST_ENVIRONMENT_DIMENSIONS"
	if spatial.width * spatial.depth > FieldContract.MAX_CELLS:
		return "MANIFEST_ENVIRONMENT_DIMENSIONS"
	if not FieldContract.valid_footprint(spatial.origin_mm, spatial.cell_size_mm, spatial.width, spatial.depth):
		return "MANIFEST_ENVIRONMENT_FOOTPRINT"
	var zones: Array = environment.zones
	if not zones is Array or zones.is_empty() or zones.size() > MAX_ZONES:
		return "MANIFEST_ENVIRONMENT_ZONES"
	if zones.size() > spatial.width * spatial.depth:
		return "MANIFEST_ENVIRONMENT_ZONES"
	var seen_zone_ids := {}
	for zone in zones:
		if not zone is Dictionary or not C.keys(zone, ZONE_FIELDS):
			return "MANIFEST_ZONE_FIELDS"
		if not C.identifier(zone.id):
			return "MANIFEST_ZONE_ID"
		if seen_zone_ids.has(zone.id):
			return "MANIFEST_ZONE_DUPLICATE_ID"
		seen_zone_ids[zone.id] = true
		# Stocks: canonical [A4] resource stock bounds (nonnegative).
		for stock_field in ["water_mg", "nutrient_mg", "organic_mg"]:
			if not C.integer(zone[stock_field], 0, CELL_CAPACITY_MG):
				return "MANIFEST_ZONE_STOCK:" + stock_field
		# Signals: nonnegative light / temperature (canonical signal domain).
		for signal_field in ["light", "temperature"]:
			if not C.integer(zone[signal_field], 0, C.MAX_INT):
				return "MANIFEST_ZONE_SIGNAL:" + signal_field
	return ""

static func _validate_placement(placement: Variant, founders: Array, environment: Dictionary) -> String:
	if not placement is Dictionary or not C.keys(placement, ["entries"]):
		return "MANIFEST_PLACEMENT"
	var entries: Array = placement.entries
	if not entries is Array or entries.is_empty() or entries.size() > C.MAX_INT:
		return "MANIFEST_PLACEMENT_ENTRIES"
	var founder_ids := {}
	for founder in founders:
		founder_ids[founder.founder_id] = true
	var zone_ids := {}
	for zone in environment.zones:
		zone_ids[zone.id] = true
	for entry in entries:
		if not entry is Dictionary or not C.keys(entry, PLACEMENT_FIELDS):
			return "MANIFEST_PLACEMENT_ENTRY_FIELDS"
		if not entry.founder_ref is String or not founder_ids.has(entry.founder_ref):
			return "MANIFEST_PLACEMENT_FOUNDER_REF"
		if not entry.zone_id is String or not zone_ids.has(entry.zone_id):
			return "MANIFEST_PLACEMENT_ZONE_ID"
		if not C.vector(entry.position_mm, FieldContract.MAX_PORT_COORD_MM):
			return "MANIFEST_PLACEMENT_POSITION"
	return ""

static func _validate_mutation(mutation: Variant) -> String:
	if not mutation is Dictionary or not C.keys(mutation, ["operator", "mutations_enabled"]):
		return "MANIFEST_MUTATION"
	if not mutation.operator is String or not mutation.operator in Mutation.OPERATORS:
		return "MANIFEST_MUTATION_OPERATOR"
	if not mutation.mutations_enabled is bool:
		return "MANIFEST_MUTATION_ENABLED"
	return ""
