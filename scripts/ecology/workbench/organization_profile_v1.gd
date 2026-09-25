# EcologyWorkbench OrganizationProfile v1 (P9 / Repair R2).
# Organization presets are split into presentation-only hints and an optional
# canonical DEVELOPMENT_BIAS. The bias is implemented only through A3's
# versioned operator-reweighting contract; it cannot introduce operators or
# bypass A5 receipt admission.
class_name EcoWorkbenchOrganizationProfileV1
extends RefCounted

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Mutation = preload("res://scripts/research/ecology/v2/genome_mutation_v1.gd")

const SCHEMA := "dws.ecology.workbench.organization-profile.v1"
const MODES := ["FREE", "SOFT", "EARTH_LIKE", "NMS_LIKE", "CUSTOM"]
const RULE_CLASSES := ["VISUAL_ONLY", "DEVELOPMENT_BIAS", "BIOLOGICAL_WORLD_CONSTRAINT"]
const VERSION := 2
const APPLIED_STATUS := "APPLIED_CANONICAL_BIAS"

const RULE_CLASS_BY_MODE := {
	"FREE": "VISUAL_ONLY",
	"CUSTOM": "VISUAL_ONLY",
	"SOFT": "DEVELOPMENT_BIAS",
	"EARTH_LIKE": "DEVELOPMENT_BIAS",
	"NMS_LIKE": "DEVELOPMENT_BIAS",
}

# Only existing A3 operators may appear here. Zero means disabled for that
# profile. The presets are intentionally broad priors, not species templates.
const BIAS_PRESETS := {
	"SOFT": {
		"small": 45, "medium": 15, "regulatory": 20,
		"development_parameter": 15, "none": 5,
	},
	"EARTH_LIKE": {
		"small": 30, "medium": 15, "regulatory": 25,
		"development_parameter": 25, "none": 5,
	},
	"NMS_LIKE": {
		# Deliberately stays inside broadly admissible A3 operators. Context-
		# dependent topology operators (activate/rewire) remain available to A3
		# itself but are not used as preset priors until an applicability witness
		# becomes part of the bias contract.
		"small": 15, "medium": 25, "regulatory": 15,
		"development_parameter": 40, "none": 5,
	},
}

const VISUAL_PRESETS := {
	"FREE": {"palette_seed": 0, "material_hint": "standard", "smoothing": true, "presentation_detail": "HIGH"},
	"SOFT": {"palette_seed": 11, "material_hint": "soft_matte", "smoothing": true, "presentation_detail": "MEDIUM"},
	"EARTH_LIKE": {"palette_seed": 23, "material_hint": "carbon_brown", "smoothing": true, "presentation_detail": "HIGH"},
	"NMS_LIKE": {"palette_seed": 41, "material_hint": "exotic_saturated", "smoothing": false, "presentation_detail": "HIGH"},
	"CUSTOM": {"palette_seed": 0, "material_hint": "standard", "smoothing": true, "presentation_detail": "HIGH"},
}

static func preset(mode: String) -> Dictionary:
	var normalized := String(mode).to_upper()
	if not MODES.has(normalized):
		normalized = "FREE"
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"mode": normalized,
		"rule_class": String(RULE_CLASS_BY_MODE[normalized]),
		"visual": VISUAL_PRESETS[normalized].duplicate(true),
	}

static func validate(value: Variant) -> String:
	if not C.keys(value, ["schema", "version", "mode", "rule_class", "visual"]):
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
	if not C.keys(visual, ["palette_seed", "material_hint", "smoothing", "presentation_detail"]):
		return "PROFILE_VISUAL_FIELDS"
	if not C.integer(visual.palette_seed, 0, C.MAX_INT):
		return "PROFILE_PALETTE_SEED"
	if not visual.material_hint is String or String(visual.material_hint).is_empty() or String(visual.material_hint).length() > 64:
		return "PROFILE_MATERIAL_HINT"
	if not visual.smoothing is bool:
		return "PROFILE_SMOOTHING"
	if not String(visual.presentation_detail) in ["LOW", "MEDIUM", "HIGH"]:
		return "PROFILE_PRESENTATION_DETAIL"
	return ""

static func visual_profile(profile: Dictionary) -> Dictionary:
	if not validate(profile).is_empty():
		return visual_profile(preset("FREE"))
	return {
		"lod": String(profile.visual.presentation_detail),
		"palette_seed": int(profile.visual.palette_seed),
		"material_hint": String(profile.visual.material_hint),
		"smoothing": bool(profile.visual.smoothing),
	}

## Returns a canonical A3 bias or {} for visual-only modes.
static func canonical_bias(profile: Dictionary) -> Dictionary:
	if not validate(profile).is_empty() or String(profile.rule_class) != "DEVELOPMENT_BIAS":
		return {}
	var mode := String(profile.mode)
	if not BIAS_PRESETS.has(mode):
		return {}
	var bias := {
		"schema": Mutation.BIAS_SCHEMA,
		"name": "organization/%s" % mode.to_lower(),
		"version": VERSION,
		"operator_weights": BIAS_PRESETS[mode].duplicate(true),
	}
	return bias if Mutation.validate_bias(bias).is_empty() else {}

static func apply_development_bias(profile: Dictionary) -> Dictionary:
	var error := validate(profile)
	if not error.is_empty():
		return {"success": false, "status": "REJECTED", "error": "PROFILE_INVALID:" + error}
	match String(profile.rule_class):
		"VISUAL_ONLY":
			return {"success": true, "status": "NOT_APPLICABLE", "applied": false}
		"DEVELOPMENT_BIAS":
			var bias := canonical_bias(profile)
			if bias.is_empty():
				return {"success": false, "status": "REJECTED", "error": "PROFILE_CANONICAL_BIAS"}
			return {
				"success": true,
				"status": APPLIED_STATUS,
				"applied": true,
				"bias": bias,
				"bias_hash": C.digest(bias),
			}
		"BIOLOGICAL_WORLD_CONSTRAINT":
			return {"success": true, "status": "CANONICAL_LAW", "applied": false}
	return {"success": false, "status": "REJECTED", "error": "PROFILE_RULE_CLASS"}

static func resolve_weights(profile: Dictionary, seed: int) -> Dictionary:
	if not validate(profile).is_empty() or not C.integer(seed, 0, C.MAX_INT):
		return {}
	var bias := canonical_bias(profile)
	return {
		"schema": SCHEMA,
		"mode": String(profile.mode),
		"rule_class": String(profile.rule_class),
		"seed": seed,
		"operator_weights": {} if bias.is_empty() else bias.operator_weights.duplicate(true),
		"bias_hash": "" if bias.is_empty() else C.digest(bias),
		"realizable": true,
		"blocked": false,
		"blocked_status": "",
	}
