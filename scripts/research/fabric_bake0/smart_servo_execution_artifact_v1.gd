extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/smart_servo_interface_contract_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/smart_servo_descriptor_v1.gd")

const SCHEMA := "planet_simulator.fabric_smart_servo_execution_artifact.v1"
const KIND := "SMART_SERVO"
const FIELDS: Array[String] = [
	"schema","artifact_id","artifact_kind","canonical_source_frontier",
	"authority_envelope","dependency_set","graph_hash","interface_contract",
	"descriptor_checksum","state_schema_hash","build_generation","derived_only",
	"artifact_hash","checksum",
]

static func create(
	artifact_id:String,frontier:Dictionary,authority:Dictionary,dependencies:Dictionary,
	graph_hash:String,interface_contract:Dictionary,descriptor:Dictionary,build_generation:int
)->Dictionary:
	var value:={
		"schema":SCHEMA,"artifact_id":artifact_id,"artifact_kind":KIND,
		"canonical_source_frontier":frontier.duplicate(true),
		"authority_envelope":authority.duplicate(true),"dependency_set":dependencies.duplicate(true),
		"graph_hash":graph_hash,"interface_contract":interface_contract.duplicate(true),
		"descriptor_checksum":String(descriptor.checksum),
		"state_schema_hash":U.canonical_hash({"state":interface_contract.state_quantities}),
		"build_generation":build_generation,"derived_only":true,"artifact_hash":"","checksum":"",
	}
	value.artifact_hash=U.canonical_hash(_identity(value))
	value.checksum=U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value:Dictionary)->Dictionary:
	var checked:=U.validate_exact_fields(value,FIELDS)
	if not checked.success:return checked
	if value.get("schema")!=SCHEMA or value.get("artifact_kind")!=KIND:
		return U.failure("UNSUPPORTED_SMART_SERVO_EXECUTION_ARTIFACT")
	if not U.is_canonical_id(value.get("artifact_id"),2):
		return U.failure("INVALID_SMART_SERVO_ARTIFACT_ID")
	checked=Frontier.validate(value.canonical_source_frontier)
	if not checked.success:return checked
	checked=Authority.validate_b0_safety(value.authority_envelope)
	if not checked.success:return checked
	checked=Dependencies.validate(value.dependency_set)
	if not checked.success:return checked
	checked=Interface.validate(value.interface_contract)
	if not checked.success:return checked
	for field in ["graph_hash","descriptor_checksum","state_schema_hash","artifact_hash"]:
		if not U.is_lower_hex_64(value.get(field)):
			return U.failure("INVALID_SMART_SERVO_ARTIFACT_HASH",{"field":field})
	var graph_bound:=false
	for source in value.canonical_source_frontier.sources:
		if String(source.source_domain)=="CONSTRUCTION" and String(source.source_hash)==String(value.graph_hash):
			graph_bound=true
	if not graph_bound:return U.failure("SMART_SERVO_ARTIFACT_GRAPH_SOURCE_MISMATCH")
	if not U.is_json_integer(value.get("build_generation")) or int(value.build_generation)<1:
		return U.failure("INVALID_SMART_SERVO_BUILD_GENERATION")
	if value.get("derived_only")!=true:return U.failure("SMART_SERVO_ARTIFACT_MUST_BE_DERIVED")
	if String(value.artifact_hash)!=U.canonical_hash(_identity(value)):
		return U.failure("SMART_SERVO_ARTIFACT_HASH_MISMATCH")
	return U.validate_checksum(value)

static func verify_descriptor(value:Dictionary,descriptor:Dictionary)->Dictionary:
	var checked:=validate(value)
	if not checked.success:return checked
	checked=Descriptor.validate(descriptor)
	if not checked.success:return checked
	if String(value.descriptor_checksum)!=String(descriptor.checksum):
		return U.failure("SMART_SERVO_ARTIFACT_DESCRIPTOR_MISMATCH")
	if String(value.graph_hash)!=String(descriptor.graph_hash):
		return U.failure("SMART_SERVO_ARTIFACT_DESCRIPTOR_SOURCE_MISMATCH")
	return U.success()

static func _identity(value:Dictionary)->Dictionary:
	var payload:=value.duplicate(true)
	payload.erase("artifact_hash");payload.erase("checksum")
	return payload
