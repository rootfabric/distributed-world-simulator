# EcologyWorkbench OrganizationProfile v1 (P9, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: versioned, explicit organization rule set for experiments:
#   FREE / SOFT / EARTH_LIKE / NMS_LIKE / CUSTOM (manifest enum). Three rule
#   classes are STRICTLY separated (brief §18-19) and never mix:
#   a) VISUAL_ONLY — {palette, material_hint, smoothing, presentation_detail};
#      applied ONLY to the generic realizer's visual_profile (colour /
#      detail). NEVER influences canonical state. The ONLY implemented class.
#   b) DEVELOPMENT_BIAS — a canonical hook in A3 (genome_mutation/development)
#      does NOT exist today: the A5 parent-transfer witness rejects mutated
#      genomes (known since P2) and OPERATORS is a closed canonical list.
#      Per brief §18 there must be NO polygon-only mutation engine: profiles
#      of this class return status BLOCKED_CANONICAL_EXTENSION_REQUIRED with
#      the required canonical hook description. The formal canonical
#      extension proposal lives in
#      docs/research/ecology/ECO_ARCH2_A10_5_P9_DEVELOPMENT_BIAS_EXTENSION_RU.md
#      (STOP condition, properly documented).
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

const SCHEMA := "dws.ecology.workbench.organization-profile.v1"
const MODES := ["FREE", "SOFT", "EARTH_LIKE", "NMS_LIKE", "CUSTOM"]
const RULE_CLASSES := ["VISUAL_ONLY", "DEVELOPMENT_BIAS", "BIOLOGICAL_WORLD_CONSTRAINT"]
const VERSION := 1

# The STOP-conditional status required by the brief for DEVELOPMENT_BIAS.
const BLOCKED_STATUS := "BLOCKED_CANONICAL_EXTENSION_REQUIRED"
# The canonical API that must exist before DEVELOPMENT_BIAS can be realized.
const REQUIRED_HOOK := "A3 genome_mutation_v1 must accept a named, versioned bias (reweighting only ALLOWED operators/transitions) AND the A5 parent-transfer witness must admit genomes provably produced by that canonical hook; see docs/research/ecology/ECO_ARCH2_A10_5_P9_DEVELOPMENT_BIAS_EXTENSION_RU.md"

# Rule class per manifest mode. FREE/CUSTOM are pure VISUAL_ONLY acceptance
# modes; the "organization" presets (SOFT/EARTH_LIKE/NMS_LIKE) DECLARE a
# development-bias intent (blocked until the canonical extension exists);
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

## DEVELOPMENT_BIAS application request. The canonical hook does not exist
## (closed OPERATORS list + A5 parent-transfer witness rejects mutated
## genomes), so by the brief §18 rule there is NO polygon-only mutation
## engine: every DEVELOPMENT_BIAS profile is blocked with the required
## canonical extension documented. VISUAL_ONLY profiles are simply not
## applicable here. Pure: NEVER mutates anything.
static func apply_development_bias(profile: Dictionary) -> Dictionary:
	var error := validate(profile)
	if not error.is_empty():
		return {"success": false, "status": "REJECTED", "error": "PROFILE_INVALID:" + error}
	match String(profile.rule_class):
		"VISUAL_ONLY":
			return {"success": true, "status": "NOT_APPLICABLE", "applied": false,
				"detail": "VISUAL_ONLY profile has no development semantics (presentation only)"}
		"DEVELOPMENT_BIAS":
			# STOP condition (brief §18): blocked until the canonical
			# extension exists. Nothing is applied, canonical state is
			# unchanged by construction (this function is pure).
			return {"success": false, "status": BLOCKED_STATUS, "applied": false,
				"required_hook": REQUIRED_HOOK}
		"BIOLOGICAL_WORLD_CONSTRAINT":
			return {"success": true, "status": "CANONICAL_LAW", "applied": false,
				"detail": "biological/world constraints are canonical law OUTSIDE OrganizationProfile; no workbench stub exists"}
	return {"success": false, "status": "REJECTED", "error": "PROFILE_RULE_CLASS"}

## Deterministic bias weights for a given seed (provenance reports only;
## never consumed by simulation while DEVELOPMENT_BIAS is blocked).
static func resolve_weights(profile: Dictionary, seed: int) -> Dictionary:
	var error := validate(profile)
	if not error.is_empty():
		return {}
	var base := preset(String(profile.mode))
	# Deterministic, seed-dependent provenance weights over the CLOSED
	# canonical operator list only (never new operators).
	var weights := {}
	var operators := ["small", "medium", "regulatory", "duplicate", "activate", "delete", "rewire", "insert", "module_parameter", "development_parameter", "none"]
	for index in operators.size():
		weights[operators[index]] = 1 + ((seed + (index + 1) * int(base.visual.palette_seed + 7)) % 97)
	return {
		"schema": SCHEMA,
		"mode": String(base.mode),
		"rule_class": String(base.rule_class),
		"seed": seed,
		"operator_weights": weights,
		"realizable": String(base.rule_class) == "VISUAL_ONLY",
		"blocked": String(base.rule_class) == "DEVELOPMENT_BIAS",
		"blocked_status": BLOCKED_STATUS if String(base.rule_class) == "DEVELOPMENT_BIAS" else "",
	}
