extends RefCounted

const PartitionAddressScript = preload(
	"res://scripts/simulation/partition/partition_address.gd"
)

var face: int = 0
var x: int = 0
var y: int = 0
var universe_id: String = PartitionAddressScript.DEFAULT_UNIVERSE_ID
var instance_id: String = PartitionAddressScript.DEFAULT_INSTANCE_ID
var space_id: String = PartitionAddressScript.DEFAULT_SPACE_ID
var partition_scheme: String = PartitionAddressScript.DEFAULT_SCHEME
var partition_scheme_revision: int = PartitionAddressScript.DEFAULT_SCHEME_REVISION


func setup(
	face_value: int,
	x_value: int,
	y_value: int,
	universe_id_value: String = PartitionAddressScript.DEFAULT_UNIVERSE_ID,
	space_id_value: String = PartitionAddressScript.DEFAULT_SPACE_ID,
	partition_scheme_value: String = PartitionAddressScript.DEFAULT_SCHEME,
	instance_id_value: String = PartitionAddressScript.DEFAULT_INSTANCE_ID,
	partition_scheme_revision_value: int = PartitionAddressScript.DEFAULT_SCHEME_REVISION
) -> void:
	face = face_value
	x = x_value
	y = y_value
	universe_id = universe_id_value
	instance_id = instance_id_value
	space_id = space_id_value
	partition_scheme = partition_scheme_value
	partition_scheme_revision = partition_scheme_revision_value


func key() -> String:
	return PartitionAddressScript.zone_key(to_address())


func legacy_key() -> String:
	return "zone/f%d/%02d/%02d" % [face, x, y]


func short_name() -> String:
	return "%s F%d Z%02d,%02d" % [space_id, face, x, y]


func to_address() -> Dictionary:
	return PartitionAddressScript.create_cube_sphere(
		face,
		x,
		y,
		-1,
		-1,
		universe_id,
		space_id,
		partition_scheme,
		instance_id,
		partition_scheme_revision
	)
