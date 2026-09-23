extends RefCounted
## Hierarchical T11 graph: T5 Motor/Generator + T7 Gearbox + control profile.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const ServoControl = preload("res://scripts/research/fabric_bake0/smart_servo_control_profile_v1.gd")

const SCHEMA := "planet_simulator.fabric_smart_servo_graph.v1"
const FIELDS: Array[String] = [
	"schema","graph_id","motor_capsule","gearbox_capsule","control_profile",
	"graph_hash","checksum",
]

static func create(
	graph_id:String,
	motor_capsule:Dictionary,
	gearbox_capsule:Dictionary,
	control_profile:Dictionary
)->Dictionary:
	var value:={
		"schema":SCHEMA,
		"graph_id":graph_id,
		"motor_capsule":motor_capsule.duplicate(true),
		"gearbox_capsule":gearbox_capsule.duplicate(true),
		"control_profile":control_profile.duplicate(true),
		"graph_hash":"",
		"checksum":"",
	}
	value.graph_hash=U.canonical_hash(_identity(value))
	value.checksum=U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value:Dictionary)->Dictionary:
	var checked:=U.validate_exact_fields(value,FIELDS)
	if not checked.success:return checked
	if value.get("schema")!=SCHEMA or not U.is_canonical_id(value.get("graph_id"),2):
		return U.failure("INVALID_SMART_SERVO_GRAPH")
	checked=Capsule.validate(value.motor_capsule)
	if not checked.success:return checked
	checked=Capsule.validate(value.gearbox_capsule)
	if not checked.success:return checked
	if String(value.motor_capsule.executable_kind)!="MOTOR_GENERATOR":
		return U.failure("SMART_SERVO_MOTOR_KIND_MISMATCH")
	if String(value.gearbox_capsule.executable_kind)!="GEARBOX":
		return U.failure("SMART_SERVO_GEARBOX_KIND_MISMATCH")
	checked=ServoControl.validate(value.control_profile)
	if not checked.success:return checked
	if not U.is_lower_hex_64(value.get("graph_hash")) or String(value.graph_hash)!=U.canonical_hash(_identity(value)):
		return U.failure("SMART_SERVO_GRAPH_HASH_MISMATCH")
	return U.validate_checksum(value)

static func _identity(value:Dictionary)->Dictionary:
	return {
		"graph_id":value.graph_id,
		"motor_capsule":value.motor_capsule,
		"gearbox_capsule":value.gearbox_capsule,
		"control_profile":value.control_profile,
	}
