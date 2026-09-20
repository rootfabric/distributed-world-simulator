# EcologyWorkbench OrganizationProfile v1 (P9, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: versioned, explicit organization rule set for experiments:
#   FREE / SOFT / EARTH_LIKE / NMS_LIKE / CUSTOM (manifest enum). Three rule
#   classes are STRICTLY separated (brief §18-19) and never mix:
#   a) VISUAL_ONLY — {palette, material_hint, smoothing, presentation_detail};
#      applied ONLY to the generic realizer visual_profile. NEVER influences canonical state.
#   b) DEVELOPMENT_BIAS — explicit canonical input implemented by the shared A3 bias hook;
#      it only reweights already-allowed operators. A5 mutation receipts prove inherited variants.
#   c) BIOLOGICAL/WORLD CONSTRAINT — canonical law (conservation, resource
#      costs, world physics, ownership), OUTSIDE OrganizationProfile by
#      definition. No code stub here; documented for completeness.
# Layer: 2 (SIMULATION / ORCHESTRATION input) for the bias intent,
#   Layer 4 (PRESENTATION) for the visual part. FREE = default acceptance
#   mode: no organization constraint, standard palette.
# Invariants (roadmap R2 §3.1): FREE disables organizational biases but NOT
#   conservation, resource costs, world physics, ownership.
class_name EcoWorkbenchOrganizationProfileV1
extends RefCounted

const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")

const SCHEMA := "dws.ecology.workbench.organization-profile.v1"
const MODES := ["FREE", "SOFT", "EARTH_LIKE", "NMS_LIKE", "CUSTOM"]
const RULE_CLASSES := ["VISUAL_ONLY", "DEVELOPMENT_BIAS", "BIOLOGICAL_WORLD_CONSTRAINT"]
const VERSION := 1

# The STOP-conditional status required by the brief for DEVELOPMENT_BIAS.
const BLOCKED_STATUS := "BLOCKED_CANONICAL_EXTENSION_REQUIRED" # historical status; no longer returned after Repair R1
const APPLIED_STATUS := "APPLIED_CANONICAL_BIAS"

# Rule class per manifest mode. FREE/CUSTOM are pure VISUAL_ONLY acceptance
# modes; the "organization" presets (SOFT/EARTH_LIKE/NMS_LIKE) DECLARE a
# development-bias intent implemented through the shared canonical A3/A5 extension;
# their visual part still applies (presentation-only).
const RULE_CLASS_BY_MODE := {
	"FREE": "VISUAL_ONLY",
	"CUSTOM": "VISUAL_ONLY",
	"SOFT": "DEVELOPMENT_BIAS",
	"EARTH_LIKE": "DEVELOPMENT_BIAS",
	"NMS_LIKE": "DEVELOPMENT_BIAS",
}

# VISUAL_ONLY presets: presentation-only parameters consumed by the generic
# realizer visual_profile. palette = deterministic palette seed;
# material_hint/smoothing = future presentation hints (never canonical);
# presentation_detail maps to the realizer LOD table.
const BIAS_PRESETS := {
	"SOFT": {"small": 40, "medium": 15, "regulatory": 20, "module_parameter": 10, "development_parameter": 10, "none": 5},
	"EARTH_LIKE": {"small": 25, "medium": 10, "regulatory": 20, "duplicate": 10, "module_parameter": 15, "development_parameter": 15, "none": 5},
	"NMS_LIKE": {"small": 15, "medium": 10, "duplicate": 20, "activate": 10, "rewire": 10, "insert": 15, "module_parameter": 15, "none": 5},
}

const VISUAL_PRESETS := {
	"FREE": {"palette_seed": 0, "material_hint": "standard", "smoothing": true, "presentation_detail": "HIGH"},
	"SOFT": {"palette_seed": 11, "material_hint": "soft_matte", "smoothing": true, "presentation_detail": "MEDIUM"},
	"EARTH_LIKE": {"palette_seed": 23, "material_hint": "carbon_brown", "smoothing": true, "presentation_detail": "HIGH"},
	"NMS_LIKE": {"palette_seed": 41, "material_hint": "exotic_saturated", "smoothing": false, "presentation_detail": "HIGH"},
	"CUSTOM": {"palette_seed": 0, "material_hint": "standard", "smoothing": true, "presentation_detail": "HIGH"},
}

## Deterministic profile for a manifest mode. Pure.
static func preset(mode: String) -> Dictionary:
	var normalized := String(mode).to_upper()
	if not MODES.has(normalized):
		normalized = "FREE"
	var visual: Dictionary = VISUAL_PRESETS[normalized].duplicate(true)
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"mode": normalized,
		"rule_class": String(RULE_CLASS_BY_MODE[normalized]),
		"visual": visual,
	}

## Validate a profile value (preset() product or compatible Dictionary).
## Returns "" when valid. Every bias is named, bounded and versioned.
static func validate(value: Variant) -> String:
	if not value is Dictionary or not value.has_all(["schema", "version", "mode", "rule_class", "visual"]):
		return "PROFILE_FIELDS"
	if String(value.schema) != SCHEMA:
		return "PROFILE_SCHEMA"
	if int(value.version) != VERSION:
		return "PROFILE_VERSION"
	if not String(value.mode) in MODES:
		return "PROFILE_MODE"
	if not String(value.rule_class) in RULE_CLASSES:
		return "PROFILE_RULE_CLASS"
	if String(value.rule_class) != String(RULE_CLASS_BY_MODE[String(value.mode)]):
		return "PROFILE_RULE_CLASS_MODE"
	var visual: Dictionary = value.visual
	if not visual is Dictionary or not visual.has_all(["palette_seed", "material_hint", "smoothing", "presentation_detail"]):
		return "PROFILE_VISUAL_FIELDS"
	if not visual.palette_seed is int or int(visual.palette_seed) < 0:
		return "PROFILE_PALETTE_SEED"
	if not visual.material_hint is String or String(visual.material_hint).length() > 64:
		return "PROFILE_MATERIAL_HINT"
	if not visual.smoothing is bool:
		return "PROFILE_SMOOTHING"
	if not String(visual.presentation_detail) in ["LOW", "MEDIUM", "HIGH"]:
		return "PROFILE_PRESENTATION_DETAIL"
	return ""

## visual_profile consumed by GenericMorphologyRealizer.realize()
## (presentation ONLY; never touches canonical state).
static func visual_profile(profile: Dictionary) -> Dictionary:
	var error := validate(profile)
	if not error.is_empty():
		# Unknown/invalid profile: universal fallback = FREE defaults.
		return visual_profile(preset("FREE"))
	return {
		"lod": String(profile.visual.presentation_detail),
		"palette_seed": int(profile.visual.palette_seed),
		"material_hint": String(profile.visual.material_hint),
		"smoothing": bool(profile.visual.smoothing),
	}

## DEVELOPMENT_BIAS application request. The profile returns a validated canonical A3 bias;
## simulation applies it through the shared composed runtime. No polygon-only mutation engine exists.
static func canonical_bias(profile: Dictionary) -> Dictionary:
	var error := validate(profile)
	if not error.is_empty() or String(profile.rule_class) != "DEVELOPMENT_BIAS": return {}
	var mode := String(profile.mode)
	if not BIAS_PRESETS.has(mode): return {}
	var bias := {"schema": Mutation.BIAS_SCHEMA, "name": "organization/%s" % mode.to_lower(), "version": VERSION,
		"operator_weights": BIAS_PRESETS[mode].duplicate(true)}
	return bias if Mutation.validate_bias(bias).is_empty() else {}

static func apply_development_bias(profile: Dictionary) -> Dictionary:
	var error := validate(profile)
	if not error.is_empty():
		return {"success": false, "status": "REJECTED", "error": "PROFILE_INVALID:" + error}
	match String(profile.rule_class):
		"VISUAL_ONLY":
			return {"success": true, "status": "NOT_APPLICABLE", "applied": false,
				"detail": "VISUAL_ONLY profile has no development semantics (presentation only)"}
		"DEVELOPMENT_BIAS":
			var bias := canonical_bias(profile)
			if bias.is_empty():
				return {"success": false, "status": "REJECTED", "error": "PROFILE_CANONICAL_BIAS"}
			return {"success": true, "status": APPLIED_STATUS, "applied": true, "bias": bias}
		"BIOLOGICAL_WORLD_CONSTRAINT":
			return {"success": true, "status": "CANONICAL_LAW", "applied": false,
				"detail": "biological/world constraints remain outside OrganizationProfile"}
	return {"success": false, "status": "REJECTED", "error": "PROFILE_RULE_CLASS"}

## Deterministic canonical bias weights/provenance.
static func resolve_weights(profile: Dictionary, seed: int) -> Dictionary:
	var error := validate(profile)
	if not error.is_empty(): return {}
	var bias := canonical_bias(profile)
	return {
		"schema": SCHEMA, "mode": String(profile.mode), "rule_class": String(profile.rule_class), "seed": seed,
		"operator_weights": {} if bias.is_empty() else bias.operator_weights.duplicate(true),
		"realizable": true, "blocked": false, "blocked_status": "",
	}
