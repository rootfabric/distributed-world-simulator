class_name FabricConstruct0ToyboxContract
extends RefCounted

const PART_KINDS: Array[String] = [
	"BLOCK",
	"PLATE",
	"BEAM",
	"CYLINDER",
	"WHEEL",
	"AXLE",
	"WEIGHT",
	"ANCHOR",
]

const RELATION_KINDS: Array[String] = [
	"RIGID",
	"HINGE",
	"AXLE",
	"SLIDER",
	"SPRING_DAMPER",
	"BREAKABLE",
]

const ENVIRONMENT_KINDS: Array[String] = [
	"FLOOR",
	"RAMP",
	"MOVING_SURFACE",
]

const TOOL_KINDS: Array[String] = [
	"FORCE",
	"IMPULSE",
	"TORQUE",
	"ADD_LOAD",
	"BREAK_BOND",
]

const EXPERIMENTS: Array[String] = [
	"INCLINED_PLANE",
	"SEESAW",
	"CART",
	"CATAPULT",
	"BREAKABLE_BRIDGE",
]

const RUNTIME_KINDS: Array[String] = [
	"SLIDER_FRICTION",
	"HINGE_OSCILLATOR",
	"ROLLING_CART",
	"HINGE_SPRING_RELEASE",
	"STRUCTURAL_LOAD",
]

static func relation_metadata(kind: String, parameters: Dictionary = {}) -> Dictionary:
	assert(RELATION_KINDS.has(kind))
	var metadata := {
		"construct0_toybox": true,
		"relation_kind": kind,
		"parameters": parameters.duplicate(true),
	}
	return metadata

static func environment(kind: String, parameters: Dictionary = {}) -> Dictionary:
	assert(ENVIRONMENT_KINDS.has(kind))
	return {
		"kind": kind,
		"parameters": parameters.duplicate(true),
	}

static func validate_experiment(value: Dictionary) -> Dictionary:
	for field in ["experiment_id", "runtime_kind", "snapshot", "relations", "environment", "controls"]:
		if not value.has(field):
			return _failure("TOYBOX_MISSING_%s" % field.to_upper())
	if not EXPERIMENTS.has(String(value["experiment_id"])):
		return _failure("TOYBOX_UNKNOWN_EXPERIMENT")
	if not RUNTIME_KINDS.has(String(value["runtime_kind"])):
		return _failure("TOYBOX_UNKNOWN_RUNTIME_KIND")
	if typeof(value["relations"]) != TYPE_ARRAY:
		return _failure("TOYBOX_RELATIONS_NOT_ARRAY")
	for relation_any in value["relations"]:
		if typeof(relation_any) != TYPE_DICTIONARY:
			return _failure("TOYBOX_RELATION_NOT_DICTIONARY")
		var relation: Dictionary = relation_any
		if not RELATION_KINDS.has(String(relation.get("kind", ""))):
			return _failure("TOYBOX_UNKNOWN_RELATION_KIND")
		if String(relation.get("part_a_id", "")).is_empty() or String(relation.get("part_b_id", "")).is_empty():
			return _failure("TOYBOX_RELATION_PART_MISSING")
	if typeof(value["environment"]) != TYPE_DICTIONARY:
		return _failure("TOYBOX_ENVIRONMENT_NOT_DICTIONARY")
	var environment_value: Dictionary = value["environment"]
	if not ENVIRONMENT_KINDS.has(String(environment_value.get("kind", ""))):
		return _failure("TOYBOX_UNKNOWN_ENVIRONMENT_KIND")
	if typeof(value["controls"]) != TYPE_DICTIONARY:
		return _failure("TOYBOX_CONTROLS_NOT_DICTIONARY")
	return {"success": true, "error_code": "", "message": ""}

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
