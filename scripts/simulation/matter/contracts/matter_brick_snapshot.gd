extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const AddressScript = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const SampleScript = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")

const SCHEMA: String = "planet_simulator.matter_brick_snapshot.v1"
const GEOMETRY_SCHEMA: String = "planet_simulator.matter_geometry_channel.v1"
const COMPOSITION_SCHEMA: String = "planet_simulator.matter_composition_channel.v1"
const PROPERTY_SCHEMA: String = "planet_simulator.matter_property_channel.v1"
const FIELDS: Array[String] = [
	"schema",
	"snapshot_id",
	"address",
	"body_definition_hash",
	"generator_version",
	"generator_seed",
	"state_revision",
	"sample_count",
	"geometry_channel",
	"composition_channel",
	"property_channel",
	"checksum",
]
const GEOMETRY_FIELDS: Array[String] = [
	"schema", "encoding", "signed_distance_m", "occupancy_ratio",
]
const COMPOSITION_FIELDS: Array[String] = [
	"schema", "encoding", "palette", "palette_indices",
]
const PROPERTY_FIELDS: Array[String] = [
	"schema", "encoding", "density_kg_m3", "integrity_ratio", "temperature_k", "porosity_ratio", "flags",
]


static func create(
	snapshot_id: String,
	address: Dictionary,
	body_definition_hash: String,
	generator_version: String,
	generator_seed: int,
	state_revision: int,
	samples: Array
) -> Dictionary:
	var palette: Array = []
	var palette_by_checksum: Dictionary = {}
	var signed_distance: Array = []
	var occupancy: Array = []
	var palette_indices: Array = []
	var density: Array = []
	var integrity: Array = []
	var temperature: Array = []
	var porosity: Array = []
	var flags: Array = []
	for sample in samples:
		var sample_value: Dictionary = Dictionary(sample)
		var composition: Dictionary = Dictionary(sample_value.get("composition", {})).duplicate(true)
		var composition_checksum: String = String(composition.get("checksum", ""))
		if not palette_by_checksum.has(composition_checksum):
			palette_by_checksum[composition_checksum] = palette.size()
			palette.append(composition)
		signed_distance.append(float(sample_value.get("signed_distance_m", 0.0)))
		occupancy.append(float(sample_value.get("occupancy_ratio", 0.0)))
		palette_indices.append(int(palette_by_checksum[composition_checksum]))
		density.append(float(sample_value.get("density_kg_m3", 0.0)))
		integrity.append(float(sample_value.get("integrity_ratio", 0.0)))
		temperature.append(float(sample_value.get("temperature_k", 0.0)))
		porosity.append(float(sample_value.get("porosity_ratio", 0.0)))
		flags.append(Array(sample_value.get("flags", [])).duplicate())
	var value: Dictionary = {
		"schema": SCHEMA,
		"snapshot_id": snapshot_id.strip_edges().to_lower(),
		"address": address.duplicate(true),
		"body_definition_hash": body_definition_hash.strip_edges().to_lower(),
		"generator_version": generator_version.strip_edges(),
		"generator_seed": generator_seed,
		"state_revision": state_revision,
		"sample_count": samples.size(),
		"geometry_channel": {
			"schema": GEOMETRY_SCHEMA,
			"encoding": "RAW_F64_V1",
			"signed_distance_m": signed_distance,
			"occupancy_ratio": occupancy,
		},
		"composition_channel": {
			"schema": COMPOSITION_SCHEMA,
			"encoding": "PALETTE_INDEXED_V1",
			"palette": palette,
			"palette_indices": palette_indices,
		},
		"property_channel": {
			"schema": PROPERTY_SCHEMA,
			"encoding": "RAW_PROPERTIES_V1",
			"density_kg_m3": density,
			"integrity_ratio": integrity,
			"temperature_k": temperature,
			"porosity_ratio": porosity,
			"flags": flags,
		},
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_BRICK_SNAPSHOT_SCHEMA")
	if not MatterUtilsScript.is_canonical_id(value.get("snapshot_id"), 2):
		return MatterUtilsScript.failure("INVALID_MATTER_BRICK_SNAPSHOT_ID")
	if typeof(value.get("address")) != TYPE_DICTIONARY \
		or not bool(AddressScript.validate(value["address"]).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_BRICK_SNAPSHOT_ADDRESS")
	if not MatterUtilsScript.is_lower_hex_64(value.get("body_definition_hash")):
		return MatterUtilsScript.failure("INVALID_MATTER_BODY_DEFINITION_HASH")
	if not MatterUtilsScript.is_semantic_version(value.get("generator_version")):
		return MatterUtilsScript.failure("INVALID_MATTER_BRICK_GENERATOR_VERSION")
	for field in ["generator_seed", "state_revision", "sample_count"]:
		if not MatterUtilsScript.is_json_integer(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_BRICK_INTEGER", {"field": field})
	if int(value["state_revision"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_BRICK_REVISION")
	var sample_count: int = int(value["sample_count"])
	if sample_count < 1 or sample_count > MatterUtilsScript.MAX_SAMPLE_COUNT:
		return MatterUtilsScript.failure("INVALID_MATTER_BRICK_SAMPLE_COUNT")
	var channels: Dictionary = _validate_channels(value, sample_count)
	if not bool(channels.get("success", false)):
		return channels
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_brick_snapshot")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)


static func sample_at(value: Dictionary, index: int) -> Dictionary:
	if not bool(validate(value).get("success", false)) or index < 0 or index >= int(value["sample_count"]):
		return {}
	var geometry: Dictionary = value["geometry_channel"]
	var composition_channel: Dictionary = value["composition_channel"]
	var properties: Dictionary = value["property_channel"]
	var palette_index: int = int(composition_channel["palette_indices"][index])
	return SampleScript.create(
		float(geometry["signed_distance_m"][index]),
		float(geometry["occupancy_ratio"][index]),
		float(properties["density_kg_m3"][index]),
		Dictionary(composition_channel["palette"][palette_index]),
		float(properties["integrity_ratio"][index]),
		float(properties["temperature_k"][index]),
		float(properties["porosity_ratio"][index]),
		Array(properties["flags"][index])
	)


static func _validate_channels(value: Dictionary, sample_count: int) -> Dictionary:
	for field in ["geometry_channel", "composition_channel", "property_channel"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_MATTER_BRICK_CHANNEL", {"field": field})
	var geometry: Dictionary = value["geometry_channel"]
	var exact_geometry: Dictionary = MatterUtilsScript.validate_exact_fields(geometry, GEOMETRY_FIELDS)
	if not bool(exact_geometry.get("success", false)) or String(geometry.get("schema", "")) != GEOMETRY_SCHEMA \
		or String(geometry.get("encoding", "")) != "RAW_F64_V1":
		return MatterUtilsScript.failure("INVALID_MATTER_GEOMETRY_CHANNEL")
	var composition_channel: Dictionary = value["composition_channel"]
	var exact_composition: Dictionary = MatterUtilsScript.validate_exact_fields(composition_channel, COMPOSITION_FIELDS)
	if not bool(exact_composition.get("success", false)) \
		or String(composition_channel.get("schema", "")) != COMPOSITION_SCHEMA \
		or String(composition_channel.get("encoding", "")) != "PALETTE_INDEXED_V1":
		return MatterUtilsScript.failure("INVALID_MATTER_COMPOSITION_CHANNEL")
	var properties: Dictionary = value["property_channel"]
	var exact_properties: Dictionary = MatterUtilsScript.validate_exact_fields(properties, PROPERTY_FIELDS)
	if not bool(exact_properties.get("success", false)) or String(properties.get("schema", "")) != PROPERTY_SCHEMA \
		or String(properties.get("encoding", "")) != "RAW_PROPERTIES_V1":
		return MatterUtilsScript.failure("INVALID_MATTER_PROPERTY_CHANNEL")
	for channel_field in ["signed_distance_m", "occupancy_ratio"]:
		if typeof(geometry.get(channel_field)) != TYPE_ARRAY or geometry[channel_field].size() != sample_count:
			return MatterUtilsScript.failure("MATTER_GEOMETRY_CHANNEL_SIZE_MISMATCH", {"field": channel_field})
	for channel_field in ["density_kg_m3", "integrity_ratio", "temperature_k", "porosity_ratio", "flags"]:
		if typeof(properties.get(channel_field)) != TYPE_ARRAY or properties[channel_field].size() != sample_count:
			return MatterUtilsScript.failure("MATTER_PROPERTY_CHANNEL_SIZE_MISMATCH", {"field": channel_field})
	if typeof(composition_channel.get("palette")) != TYPE_ARRAY or composition_channel["palette"].is_empty():
		return MatterUtilsScript.failure("EMPTY_MATTER_COMPOSITION_PALETTE")
	if typeof(composition_channel.get("palette_indices")) != TYPE_ARRAY \
		or composition_channel["palette_indices"].size() != sample_count:
		return MatterUtilsScript.failure("MATTER_COMPOSITION_CHANNEL_SIZE_MISMATCH")
	for palette_index in range(composition_channel["palette"].size()):
		var composition = composition_channel["palette"][palette_index]
		if typeof(composition) != TYPE_DICTIONARY \
			or not bool(CompositionScript.validate(composition).get("success", false)):
			return MatterUtilsScript.failure("INVALID_MATTER_COMPOSITION_PALETTE_ENTRY", {"index": palette_index})
	for index in range(sample_count):
		var selected_palette = composition_channel["palette_indices"][index]
		if not MatterUtilsScript.is_json_integer(selected_palette):
			return MatterUtilsScript.failure("INVALID_MATTER_PALETTE_INDEX", {"index": index})
		var palette_index: int = int(selected_palette)
		if palette_index < 0 or palette_index >= composition_channel["palette"].size():
			return MatterUtilsScript.failure("MATTER_PALETTE_INDEX_OUT_OF_RANGE", {"index": index})
		for numeric_field in ["signed_distance_m", "occupancy_ratio"]:
			if not MatterUtilsScript.is_finite_number(geometry[numeric_field][index]):
				return MatterUtilsScript.failure("INVALID_MATTER_GEOMETRY_VALUE", {"field": numeric_field, "index": index})
		for numeric_field in ["density_kg_m3", "integrity_ratio", "temperature_k", "porosity_ratio"]:
			if not MatterUtilsScript.is_finite_number(properties[numeric_field][index]):
				return MatterUtilsScript.failure("INVALID_MATTER_PROPERTY_VALUE", {"field": numeric_field, "index": index})
		if typeof(properties["flags"][index]) != TYPE_ARRAY:
			return MatterUtilsScript.failure("INVALID_MATTER_PROPERTY_FLAGS", {"index": index})
		var sample: Dictionary = SampleScript.create(
			float(geometry["signed_distance_m"][index]),
			float(geometry["occupancy_ratio"][index]),
			float(properties["density_kg_m3"][index]),
			Dictionary(composition_channel["palette"][palette_index]),
			float(properties["integrity_ratio"][index]),
			float(properties["temperature_k"][index]),
			float(properties["porosity_ratio"][index]),
			Array(properties["flags"][index])
		)
		if not bool(SampleScript.validate(sample).get("success", false)):
			return MatterUtilsScript.failure("INVALID_MATTER_BRICK_SAMPLE", {"index": index})
	return MatterUtilsScript.success()
