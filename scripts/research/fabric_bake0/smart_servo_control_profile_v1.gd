extends RefCounted
## Deterministic output-side PD control law for T11 Smart Servo.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_smart_servo_control_profile.v1"
const FIELDS: Array[String] = [
	"schema","profile_id","position_kp_nm_rad","velocity_kd_nm_s_rad",
	"position_tolerance_rad","velocity_tolerance_rad_s","checksum",
]

static func create(
	profile_id:String,
	position_kp_nm_rad:float,
	velocity_kd_nm_s_rad:float,
	position_tolerance_rad:float,
	velocity_tolerance_rad_s:float
)->Dictionary:
	var value := {
		"schema":SCHEMA,
		"profile_id":profile_id,
		"position_kp_nm_rad":position_kp_nm_rad,
		"velocity_kd_nm_s_rad":velocity_kd_nm_s_rad,
		"position_tolerance_rad":position_tolerance_rad,
		"velocity_tolerance_rad_s":velocity_tolerance_rad_s,
		"checksum":"",
	}
	value.checksum=U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value:Dictionary)->Dictionary:
	var checked:=U.validate_exact_fields(value,FIELDS)
	if not checked.success:return checked
	if value.get("schema")!=SCHEMA or not U.is_canonical_id(value.get("profile_id"),2):
		return U.failure("INVALID_SMART_SERVO_CONTROL_PROFILE")
	for field in ["position_kp_nm_rad","velocity_kd_nm_s_rad","position_tolerance_rad","velocity_tolerance_rad_s"]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_SMART_SERVO_CONTROL_GAIN",{"field":field})
	return U.validate_checksum(value)
