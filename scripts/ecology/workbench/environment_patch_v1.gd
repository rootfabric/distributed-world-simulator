# EcologyWorkbench EnvironmentPatch v1 (P4, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: immutable environment editing helper — a patch may only change
#   EXISTING manifest zone fields among the A4-allowed inputs
#   (stocks: water/nutrient/organic; signals: light/temperature), within
#   canonical bounds. Applying a patch produces a NEW validated manifest
#   (immutable update, new canonical hash); the source manifest is never
#   mutated. NO runtime field mutation happens here (world-compat is P12).
# Layer: 2 (SIMULATION / ORCHESTRATION) — INPUT layer only.
# Canonical bounds follow the P1 manifest schema (experiment_manifest_v1):
#   stocks 0..Manifest.CELL_CAPACITY_MG, signals 0..C.MAX_INT. No new fields, no
#   duplicates of existing schema fields.
class_name EcoWorkbenchEnvironmentPatchV1
extends RefCounted

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const FieldContract = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")

const SCHEMA := "dws.ecology.workbench.environment-patch.v1"
const STOCK_FIELDS := ["water_mg", "nutrient_mg", "organic_mg"]
const SIGNAL_FIELDS := ["light", "temperature"]
const EDITABLE_FIELDS := ["water_mg", "nutrient_mg", "organic_mg", "light", "temperature"]

## Validate a patch against a manifest. Returns "" when valid.
## patch := {"schema": SCHEMA, "zones": {"<zone_id>": {"water_mg": 100, ...}}}.
## Fail-closed: wrong schema, unknown zone, unknown field (only existing zone
## fields may be patched), non-integer or out-of-canonical-bounds values.
static func validate_patch(manifest: Dictionary, patch: Dictionary) -> String:
	if not C.keys(patch, ["schema", "zones"]) or patch.schema != SCHEMA:
		return "PATCH_SCHEMA"
	if not patch.zones is Dictionary or patch.zones.is_empty():
		return "PATCH_ZONES"
	var zone_ids := {}
	for zone in manifest.environment.zones:
		zone_ids[String(zone.id)] = true
	for zone_id in patch.zones:
		if not zone_ids.has(String(zone_id)):
			return "PATCH_ZONE_UNKNOWN:" + String(zone_id)
		var edits: Variant = patch.zones[zone_id]
		if not edits is Dictionary or edits.is_empty():
			return "PATCH_EDITS:" + String(zone_id)
		for field in edits:
			if not field in EDITABLE_FIELDS:
				return "PATCH_FIELD_UNKNOWN:" + String(field)
		for field in STOCK_FIELDS:
			if edits.has(field) and not C.integer(edits[field], 0, Manifest.CELL_CAPACITY_MG):
				return "PATCH_STOCK_BOUNDS:" + String(field)
		for field in SIGNAL_FIELDS:
			if edits.has(field) and not C.integer(edits[field], 0, C.MAX_INT):
				return "PATCH_SIGNAL_BOUNDS:" + String(field)
	return ""

## Apply a validated patch immutably. Returns
## {"success": true, "manifest": new_manifest, "manifest_hash": String,
##  "previous_hash": String} or {"success": false, "error": String}.
## The source manifest is left untouched (deep-copied before edit); the result
## re-passes Manifest.validate before it is returned.
static func apply_patch(manifest: Dictionary, patch: Dictionary) -> Dictionary:
	var previous_hash := Manifest.canonical_hash(manifest)
	var error := validate_patch(manifest, patch)
	if not error.is_empty():
		return {"success": false, "error": error}
	var next := manifest.duplicate(true)
	for zone_id in patch.zones:
		for zone in next.environment.zones:
			if String(zone.id) == String(zone_id):
				for field in patch.zones[zone_id]:
					zone[field] = patch.zones[zone_id][field]
				break
	var manifest_error := Manifest.validate(next)
	if not manifest_error.is_empty():
		return {"success": false, "error": "PATCH_RESULT_INVALID:" + manifest_error}
	return {
		"success": true,
		"manifest": next,
		"manifest_hash": Manifest.canonical_hash(next),
		"previous_hash": previous_hash,
	}

## Convenience builder for a single-field edit.
static func patch(zone_id: String, field: String, value: int) -> Dictionary:
	return {"schema": SCHEMA, "zones": {zone_id: {field: value}}}
