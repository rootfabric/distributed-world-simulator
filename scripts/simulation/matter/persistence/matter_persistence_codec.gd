extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddressScript = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const AddressScript = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const ResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const LedgerScript = preload("res://scripts/simulation/matter/contracts/matter_mass_ledger.gd")
const BatchScript = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

const TRANSPORT_SCHEMA: String = "planet_simulator.matter_persistence_transport.v1"
const TRANSPORT_FLOAT_ENCODING: String = "ieee754-binary64-le-hex"
const TRANSPORT_FIELDS: Array[String] = [
	"schema", "float_encoding", "payload", "typed_checksum", "checksum",
]
const FLOAT_TAG_KEY: String = "$matter_f64"
const FLOAT_TAG_FIELDS: Array[String] = [FLOAT_TAG_KEY]
const FLOAT_ARRAY_TAG_KEY: String = "$matter_f64_array"
const FLOAT_ARRAY_COUNT_KEY: String = "count"
const FLOAT_ARRAY_TAG_FIELDS: Array[String] = [FLOAT_ARRAY_TAG_KEY, FLOAT_ARRAY_COUNT_KEY]

const CELL_ADDRESS_FIELDS: Array[String] = [
	"schema", "universe_id", "instance_id", "space_id", "grid_id", "grid_revision",
	"root_id", "level", "path", "cell_id",
]
const BRICK_ADDRESS_FIELDS: Array[String] = [
	"schema", "cell_address", "storage_level", "brick_x", "brick_y", "brick_z", "address_id",
]
const COMPOSITION_FIELDS: Array[String] = ["schema", "components", "checksum"]
const COMPOSITION_COMPONENT_FIELDS: Array[String] = ["material_id", "mass_fraction"]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema", "snapshot_id", "address", "body_definition_hash", "generator_version",
	"generator_seed", "state_revision", "sample_count", "geometry_channel",
	"composition_channel", "property_channel", "checksum",
]
const GEOMETRY_FIELDS: Array[String] = [
	"schema", "encoding", "signed_distance_m", "occupancy_ratio",
]
const COMPOSITION_CHANNEL_FIELDS: Array[String] = [
	"schema", "encoding", "palette", "palette_indices",
]
const PROPERTY_FIELDS: Array[String] = [
	"schema", "encoding", "density_kg_m3", "integrity_ratio", "temperature_k",
	"porosity_ratio", "flags",
]
const REQUEST_FIELDS: Array[String] = [
	"schema", "operation_id", "body_id", "actor_id", "tool_id", "operation_type",
	"target_bricks", "expected_revisions", "shape", "source_container_id",
	"destination_container_id", "requested_mass_kg", "energy_budget_j", "client_tick", "checksum",
]
const SHAPE_FIELDS: Array[String] = [
	"kind", "start_position_m", "end_position_m", "radius_m", "half_extents_m",
]
const LEDGER_FIELDS: Array[String] = [
	"schema", "operation_id", "inputs", "outputs", "tolerance_kg", "input_total_kg",
	"output_total_kg", "balance_error_kg", "material_balance_kg", "closed", "checksum",
]
const LEDGER_ENTRY_FIELDS: Array[String] = ["account_id", "material_id", "mass_kg"]
const RESULT_FIELDS: Array[String] = [
	"schema", "operation_id", "status", "changed_bricks", "removed_mass_kg",
	"deposited_mass_kg", "extracted_composition", "generated_heat_j", "consumed_energy_j",
	"created_aggregate_ids", "mass_ledger", "error_code", "checksum",
]
const CHANGED_BRICK_FIELDS: Array[String] = [
	"address", "previous_revision", "new_revision", "snapshot_checksum",
]
const BATCH_FIELDS: Array[String] = [
	"schema", "batch_id", "container_id", "source_body_id", "source_operation_id",
	"total_mass_kg", "bulk_volume_m3", "composition", "temperature_k", "checksum",
]


static func encode_persistence_json(value: Dictionary) -> String:
	# Godot JSON number parsing does not preserve every binary64 value bit-for-bit.
	# Persistence therefore stores each float as an explicit little-endian IEEE-754
	# bit string inside a versioned transport envelope. The typed DTO checksum stays
	# authoritative and is verified again after exact float reconstruction.
	if value.is_empty():
		return ""
	var typed_checksum: String = String(value.get("checksum", ""))
	if not MatterUtilsScript.is_lower_hex_64(typed_checksum) \
		or MatterUtilsScript.compute_checksum(value) != typed_checksum:
		return ""
	var encoded_payload: Dictionary = _encode_transport_value(value, "$.payload")
	if not bool(encoded_payload.get("success", false)) \
		or typeof(encoded_payload.get("value")) != TYPE_DICTIONARY:
		return ""
	var envelope: Dictionary = {
		"schema": TRANSPORT_SCHEMA,
		"float_encoding": TRANSPORT_FLOAT_ENCODING,
		"payload": encoded_payload["value"],
		"typed_checksum": typed_checksum,
		"checksum": "",
	}
	envelope["checksum"] = MatterUtilsScript.compute_checksum(envelope)
	return MatterUtilsScript.canonical_json(envelope)


static func decode_persistence_json(encoded: String) -> Dictionary:
	if encoded.is_empty():
		return {}
	var parser := JSON.new()
	if parser.parse(encoded) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	var envelope: Dictionary = Dictionary(parser.data)
	if not _has_exact_fields(envelope, TRANSPORT_FIELDS) \
		or String(envelope.get("schema", "")) != TRANSPORT_SCHEMA \
		or String(envelope.get("float_encoding", "")) != TRANSPORT_FLOAT_ENCODING \
		or typeof(envelope.get("payload")) != TYPE_DICTIONARY \
		or not MatterUtilsScript.is_lower_hex_64(envelope.get("typed_checksum")) \
		or not bool(MatterUtilsScript.validate_checksum(envelope).get("success", false)):
		return {}
	var decoded_payload: Dictionary = _decode_transport_value(envelope["payload"], "$.payload")
	if not bool(decoded_payload.get("success", false)) \
		or typeof(decoded_payload.get("value")) != TYPE_DICTIONARY:
		return {}
	var value: Dictionary = Dictionary(decoded_payload["value"])
	var typed_checksum: String = String(envelope["typed_checksum"])
	if String(value.get("checksum", "")) != typed_checksum \
		or MatterUtilsScript.compute_checksum(value) != typed_checksum:
		return {}
	return value


static func rehydrate_composition(raw: Dictionary) -> Dictionary:
	if not _has_raw_composition_structure(raw):
		return {}
	var components: Array = []
	for raw_component in raw["components"]:
		var component: Dictionary = raw_component
		components.append({
			"material_id": String(component["material_id"]),
			"mass_fraction": float(component["mass_fraction"]),
		})
	var value: Dictionary = CompositionScript.create(components)
	return _finish_rehydration(raw, value, CompositionScript.validate(value))


static func rehydrate_snapshot(raw: Dictionary) -> Dictionary:
	if not _has_raw_snapshot_structure(raw):
		return {}
	var address: Dictionary = _rehydrate_brick_address(Dictionary(raw["address"]))
	if address.is_empty():
		return {}
	var geometry_raw: Dictionary = raw["geometry_channel"]
	var composition_raw: Dictionary = raw["composition_channel"]
	var properties_raw: Dictionary = raw["property_channel"]
	var typed_palette: Array = []
	for raw_composition in composition_raw["palette"]:
		var composition: Dictionary = rehydrate_composition(Dictionary(raw_composition))
		if composition.is_empty():
			return {}
		typed_palette.append(composition)
	var palette_indices: Array = []
	for raw_palette_index in composition_raw["palette_indices"]:
		palette_indices.append(int(raw_palette_index))
	var typed_flags: Array = []
	for raw_flags in properties_raw["flags"]:
		typed_flags.append(Array(raw_flags).duplicate())
	# Preserve the persisted columnar representation exactly. Rebuilding the
	# snapshot through a sample list can reorder or compact the composition
	# palette, producing a different checksum even when every sample is equal.
	var value: Dictionary = {
		"schema": String(raw["schema"]),
		"snapshot_id": String(raw["snapshot_id"]),
		"address": address,
		"body_definition_hash": String(raw["body_definition_hash"]),
		"generator_version": String(raw["generator_version"]),
		"generator_seed": int(raw["generator_seed"]),
		"state_revision": int(raw["state_revision"]),
		"sample_count": int(raw["sample_count"]),
		"geometry_channel": {
			"schema": String(geometry_raw["schema"]),
			"encoding": String(geometry_raw["encoding"]),
			"signed_distance_m": _float_array(geometry_raw["signed_distance_m"]),
			"occupancy_ratio": _float_array(geometry_raw["occupancy_ratio"]),
		},
		"composition_channel": {
			"schema": String(composition_raw["schema"]),
			"encoding": String(composition_raw["encoding"]),
			"palette": typed_palette,
			"palette_indices": palette_indices,
		},
		"property_channel": {
			"schema": String(properties_raw["schema"]),
			"encoding": String(properties_raw["encoding"]),
			"density_kg_m3": _float_array(properties_raw["density_kg_m3"]),
			"integrity_ratio": _float_array(properties_raw["integrity_ratio"]),
			"temperature_k": _float_array(properties_raw["temperature_k"]),
			"porosity_ratio": _float_array(properties_raw["porosity_ratio"]),
			"flags": typed_flags,
		},
		"checksum": String(raw["checksum"]),
	}
	return _finish_rehydration(raw, value, SnapshotScript.validate(value))


static func rehydrate_request(raw: Dictionary) -> Dictionary:
	if not _has_raw_request_structure(raw):
		return {}
	var target_bricks: Array = []
	var expected_by_address: Dictionary = {}
	for index in range(raw["target_bricks"].size()):
		var address: Dictionary = _rehydrate_brick_address(Dictionary(raw["target_bricks"][index]))
		if address.is_empty():
			return {}
		target_bricks.append(address)
		expected_by_address[String(address["address_id"])] = int(raw["expected_revisions"][index])
	var shape_raw: Dictionary = raw["shape"]
	var shape: Dictionary = RequestScript.create_shape(
		String(shape_raw["kind"]),
		_float_array(shape_raw["start_position_m"]),
		_float_array(shape_raw["end_position_m"]),
		float(shape_raw["radius_m"]),
		_float_array(shape_raw["half_extents_m"])
	)
	var value: Dictionary = RequestScript.create({
		"operation_id": raw["operation_id"],
		"body_id": raw["body_id"],
		"actor_id": raw["actor_id"],
		"tool_id": raw["tool_id"],
		"operation_type": raw["operation_type"],
		"target_bricks": target_bricks,
		"expected_revision_by_address": expected_by_address,
		"shape": shape,
		"source_container_id": raw["source_container_id"],
		"destination_container_id": raw["destination_container_id"],
		"requested_mass_kg": float(raw["requested_mass_kg"]),
		"energy_budget_j": float(raw["energy_budget_j"]),
		"client_tick": int(raw["client_tick"]),
	})
	return _finish_rehydration(raw, value, RequestScript.validate(value))


static func rehydrate_ledger(raw: Dictionary) -> Dictionary:
	if not _has_raw_ledger_structure(raw):
		return {}
	var inputs: Array = _rehydrate_ledger_entries(raw["inputs"])
	var outputs: Array = _rehydrate_ledger_entries(raw["outputs"])
	var value: Dictionary = LedgerScript.create(
		String(raw["operation_id"]),
		inputs,
		outputs,
		float(raw["tolerance_kg"])
	)
	return _finish_rehydration(raw, value, LedgerScript.validate(value))


static func rehydrate_result(raw: Dictionary) -> Dictionary:
	if not _has_raw_result_structure(raw):
		return {}
	var composition: Dictionary = rehydrate_composition(Dictionary(raw["extracted_composition"]))
	var ledger: Dictionary = rehydrate_ledger(Dictionary(raw["mass_ledger"]))
	if composition.is_empty() or ledger.is_empty():
		return {}
	var changed_bricks: Array = []
	for raw_changed in raw["changed_bricks"]:
		var changed: Dictionary = raw_changed
		var address: Dictionary = _rehydrate_brick_address(Dictionary(changed["address"]))
		if address.is_empty():
			return {}
		changed_bricks.append({
			"address": address,
			"previous_revision": int(changed["previous_revision"]),
			"new_revision": int(changed["new_revision"]),
			"snapshot_checksum": String(changed["snapshot_checksum"]),
		})
	var value: Dictionary = ResultScript.create({
		"operation_id": raw["operation_id"],
		"status": raw["status"],
		"changed_bricks": changed_bricks,
		"removed_mass_kg": float(raw["removed_mass_kg"]),
		"deposited_mass_kg": float(raw["deposited_mass_kg"]),
		"extracted_composition": composition,
		"generated_heat_j": float(raw["generated_heat_j"]),
		"consumed_energy_j": float(raw["consumed_energy_j"]),
		"created_aggregate_ids": Array(raw["created_aggregate_ids"]).duplicate(),
		"mass_ledger": ledger,
		"error_code": raw["error_code"],
	})
	return _finish_rehydration(raw, value, ResultScript.validate(value))


static func rehydrate_batch(raw: Dictionary) -> Dictionary:
	if not _has_raw_batch_structure(raw):
		return {}
	var composition: Dictionary = rehydrate_composition(Dictionary(raw["composition"]))
	if composition.is_empty():
		return {}
	var value: Dictionary = BatchScript.create({
		"batch_id": raw["batch_id"],
		"container_id": raw["container_id"],
		"source_body_id": raw["source_body_id"],
		"source_operation_id": raw["source_operation_id"],
		"total_mass_kg": float(raw["total_mass_kg"]),
		"bulk_volume_m3": float(raw["bulk_volume_m3"]),
		"composition": composition,
		"temperature_k": float(raw["temperature_k"]),
	})
	return _finish_rehydration(raw, value, BatchScript.validate(value))


static func _rehydrate_cell_address(raw: Dictionary) -> Dictionary:
	if not _has_exact_fields(raw, CELL_ADDRESS_FIELDS) \
		or String(raw.get("schema", "")) != CellAddressScript.SCHEMA:
		return {}
	for field in ["universe_id", "instance_id", "space_id", "grid_id", "root_id", "cell_id"]:
		if typeof(raw.get(field)) != TYPE_STRING:
			return {}
	if not _is_raw_integer(raw.get("grid_revision")) or not _is_raw_integer(raw.get("level")) \
		or typeof(raw.get("path")) != TYPE_ARRAY:
		return {}
	var path: Array = []
	for raw_child in raw["path"]:
		if not _is_raw_integer(raw_child):
			return {}
		path.append(int(raw_child))
	var value: Dictionary = CellAddressScript.create(
		String(raw["universe_id"]),
		String(raw["instance_id"]),
		String(raw["space_id"]),
		String(raw["grid_id"]),
		int(raw["grid_revision"]),
		String(raw["root_id"]),
		path
	)
	if not bool(CellAddressScript.validate(value).get("success", false)) \
		or int(value["level"]) != int(raw["level"]) \
		or String(value["cell_id"]) != String(raw["cell_id"]):
		return {}
	return value


static func _rehydrate_brick_address(raw: Dictionary) -> Dictionary:
	if not _has_exact_fields(raw, BRICK_ADDRESS_FIELDS) \
		or String(raw.get("schema", "")) != AddressScript.SCHEMA \
		or typeof(raw.get("cell_address")) != TYPE_DICTIONARY \
		or typeof(raw.get("address_id")) != TYPE_STRING:
		return {}
	for field in ["storage_level", "brick_x", "brick_y", "brick_z"]:
		if not _is_raw_integer(raw.get(field)):
			return {}
	var cell_address: Dictionary = _rehydrate_cell_address(Dictionary(raw["cell_address"]))
	if cell_address.is_empty():
		return {}
	var value: Dictionary = AddressScript.create(
		cell_address,
		int(raw["storage_level"]),
		int(raw["brick_x"]),
		int(raw["brick_y"]),
		int(raw["brick_z"])
	)
	if not bool(AddressScript.validate(value).get("success", false)) \
		or String(value["address_id"]) != String(raw["address_id"]):
		return {}
	return value


static func _has_raw_composition_structure(raw: Dictionary) -> bool:
	if not _has_exact_fields(raw, COMPOSITION_FIELDS) \
		or String(raw.get("schema", "")) != CompositionScript.SCHEMA \
		or typeof(raw.get("components")) != TYPE_ARRAY \
		or not MatterUtilsScript.is_lower_hex_64(raw.get("checksum")):
		return false
	for raw_component in raw["components"]:
		if typeof(raw_component) != TYPE_DICTIONARY:
			return false
		var component: Dictionary = raw_component
		if not _has_exact_fields(component, COMPOSITION_COMPONENT_FIELDS) \
			or typeof(component.get("material_id")) != TYPE_STRING \
			or not _is_raw_number(component.get("mass_fraction")):
			return false
	return true


static func _has_raw_snapshot_structure(raw: Dictionary) -> bool:
	if not _has_exact_fields(raw, SNAPSHOT_FIELDS) \
		or String(raw.get("schema", "")) != SnapshotScript.SCHEMA \
		or typeof(raw.get("snapshot_id")) != TYPE_STRING \
		or typeof(raw.get("address")) != TYPE_DICTIONARY \
		or typeof(raw.get("body_definition_hash")) != TYPE_STRING \
		or typeof(raw.get("generator_version")) != TYPE_STRING \
		or not _is_raw_integer(raw.get("generator_seed")) \
		or not _is_raw_integer(raw.get("state_revision")) \
		or not _is_raw_integer(raw.get("sample_count")) \
		or not MatterUtilsScript.is_lower_hex_64(raw.get("checksum")):
		return false
	var sample_count: int = int(raw["sample_count"])
	if sample_count < 1 or sample_count > MatterUtilsScript.MAX_SAMPLE_COUNT:
		return false
	if typeof(raw.get("geometry_channel")) != TYPE_DICTIONARY \
		or typeof(raw.get("composition_channel")) != TYPE_DICTIONARY \
		or typeof(raw.get("property_channel")) != TYPE_DICTIONARY:
		return false
	var geometry: Dictionary = raw["geometry_channel"]
	var composition: Dictionary = raw["composition_channel"]
	var properties: Dictionary = raw["property_channel"]
	if not _has_exact_fields(geometry, GEOMETRY_FIELDS) \
		or String(geometry.get("schema", "")) != SnapshotScript.GEOMETRY_SCHEMA \
		or typeof(geometry.get("encoding")) != TYPE_STRING \
		or not _is_number_array(geometry.get("signed_distance_m"), sample_count) \
		or not _is_number_array(geometry.get("occupancy_ratio"), sample_count):
		return false
	if not _has_exact_fields(composition, COMPOSITION_CHANNEL_FIELDS) \
		or String(composition.get("schema", "")) != SnapshotScript.COMPOSITION_SCHEMA \
		or typeof(composition.get("encoding")) != TYPE_STRING \
		or typeof(composition.get("palette")) != TYPE_ARRAY \
		or typeof(composition.get("palette_indices")) != TYPE_ARRAY \
		or composition["palette_indices"].size() != sample_count:
		return false
	for raw_composition in composition["palette"]:
		if typeof(raw_composition) != TYPE_DICTIONARY \
			or not _has_raw_composition_structure(Dictionary(raw_composition)):
			return false
	for palette_index in composition["palette_indices"]:
		if not _is_raw_integer(palette_index):
			return false
	if not _has_exact_fields(properties, PROPERTY_FIELDS) \
		or String(properties.get("schema", "")) != SnapshotScript.PROPERTY_SCHEMA \
		or typeof(properties.get("encoding")) != TYPE_STRING \
		or not _is_number_array(properties.get("density_kg_m3"), sample_count) \
		or not _is_number_array(properties.get("integrity_ratio"), sample_count) \
		or not _is_number_array(properties.get("temperature_k"), sample_count) \
		or not _is_number_array(properties.get("porosity_ratio"), sample_count) \
		or typeof(properties.get("flags")) != TYPE_ARRAY \
		or properties["flags"].size() != sample_count:
		return false
	for raw_flags in properties["flags"]:
		if not _is_string_array(raw_flags):
			return false
	return true


static func _has_raw_request_structure(raw: Dictionary) -> bool:
	if not _has_exact_fields(raw, REQUEST_FIELDS) \
		or String(raw.get("schema", "")) != RequestScript.SCHEMA \
		or not MatterUtilsScript.is_lower_hex_64(raw.get("checksum")):
		return false
	for field in [
		"operation_id", "body_id", "actor_id", "tool_id", "operation_type",
		"source_container_id", "destination_container_id",
	]:
		if typeof(raw.get(field)) != TYPE_STRING:
			return false
	if typeof(raw.get("target_bricks")) != TYPE_ARRAY \
		or raw["target_bricks"].is_empty() \
		or typeof(raw.get("expected_revisions")) != TYPE_ARRAY \
		or raw["expected_revisions"].size() != raw["target_bricks"].size() \
		or typeof(raw.get("shape")) != TYPE_DICTIONARY \
		or not _is_raw_number(raw.get("requested_mass_kg")) \
		or not _is_raw_number(raw.get("energy_budget_j")) \
		or not _is_raw_integer(raw.get("client_tick")):
		return false
	for address in raw["target_bricks"]:
		if typeof(address) != TYPE_DICTIONARY:
			return false
	for revision in raw["expected_revisions"]:
		if not _is_raw_integer(revision):
			return false
	var shape: Dictionary = raw["shape"]
	if not _has_exact_fields(shape, SHAPE_FIELDS) \
		or typeof(shape.get("kind")) != TYPE_STRING \
		or not _is_number_array(shape.get("start_position_m"), 3) \
		or not _is_number_array(shape.get("end_position_m"), 3) \
		or not _is_raw_number(shape.get("radius_m")) \
		or not _is_number_array(shape.get("half_extents_m"), 3):
		return false
	return true


static func _has_raw_ledger_structure(raw: Dictionary) -> bool:
	if not _has_exact_fields(raw, LEDGER_FIELDS) \
		or String(raw.get("schema", "")) != LedgerScript.SCHEMA \
		or typeof(raw.get("operation_id")) != TYPE_STRING \
		or typeof(raw.get("inputs")) != TYPE_ARRAY \
		or typeof(raw.get("outputs")) != TYPE_ARRAY \
		or not _is_raw_number(raw.get("tolerance_kg")) \
		or not _is_raw_number(raw.get("input_total_kg")) \
		or not _is_raw_number(raw.get("output_total_kg")) \
		or not _is_raw_number(raw.get("balance_error_kg")) \
		or typeof(raw.get("material_balance_kg")) != TYPE_DICTIONARY \
		or typeof(raw.get("closed")) != TYPE_BOOL \
		or not MatterUtilsScript.is_lower_hex_64(raw.get("checksum")):
		return false
	for entries in [raw["inputs"], raw["outputs"]]:
		for raw_entry in entries:
			if typeof(raw_entry) != TYPE_DICTIONARY:
				return false
			var entry: Dictionary = raw_entry
			if not _has_exact_fields(entry, LEDGER_ENTRY_FIELDS) \
				or typeof(entry.get("account_id")) != TYPE_STRING \
				or typeof(entry.get("material_id")) != TYPE_STRING \
				or not _is_raw_number(entry.get("mass_kg")):
				return false
	for material_id in raw["material_balance_kg"].keys():
		if typeof(material_id) != TYPE_STRING \
			or not _is_raw_number(raw["material_balance_kg"][material_id]):
			return false
	return true


static func _has_raw_result_structure(raw: Dictionary) -> bool:
	if not _has_exact_fields(raw, RESULT_FIELDS) \
		or String(raw.get("schema", "")) != ResultScript.SCHEMA \
		or typeof(raw.get("operation_id")) != TYPE_STRING \
		or typeof(raw.get("status")) != TYPE_STRING \
		or typeof(raw.get("changed_bricks")) != TYPE_ARRAY \
		or not _is_raw_number(raw.get("removed_mass_kg")) \
		or not _is_raw_number(raw.get("deposited_mass_kg")) \
		or typeof(raw.get("extracted_composition")) != TYPE_DICTIONARY \
		or not _is_raw_number(raw.get("generated_heat_j")) \
		or not _is_raw_number(raw.get("consumed_energy_j")) \
		or not _is_string_array(raw.get("created_aggregate_ids")) \
		or typeof(raw.get("mass_ledger")) != TYPE_DICTIONARY \
		or typeof(raw.get("error_code")) != TYPE_STRING \
		or not MatterUtilsScript.is_lower_hex_64(raw.get("checksum")):
		return false
	for raw_changed in raw["changed_bricks"]:
		if typeof(raw_changed) != TYPE_DICTIONARY:
			return false
		var changed: Dictionary = raw_changed
		if not _has_exact_fields(changed, CHANGED_BRICK_FIELDS) \
			or typeof(changed.get("address")) != TYPE_DICTIONARY \
			or not _is_raw_integer(changed.get("previous_revision")) \
			or not _is_raw_integer(changed.get("new_revision")) \
			or typeof(changed.get("snapshot_checksum")) != TYPE_STRING:
			return false
	return _has_raw_composition_structure(Dictionary(raw["extracted_composition"])) \
		and _has_raw_ledger_structure(Dictionary(raw["mass_ledger"]))


static func _has_raw_batch_structure(raw: Dictionary) -> bool:
	if not _has_exact_fields(raw, BATCH_FIELDS) \
		or String(raw.get("schema", "")) != BatchScript.SCHEMA \
		or not MatterUtilsScript.is_lower_hex_64(raw.get("checksum")):
		return false
	for field in ["batch_id", "container_id", "source_body_id", "source_operation_id"]:
		if typeof(raw.get(field)) != TYPE_STRING:
			return false
	if not _is_raw_number(raw.get("total_mass_kg")) \
		or not _is_raw_number(raw.get("bulk_volume_m3")) \
		or typeof(raw.get("composition")) != TYPE_DICTIONARY \
		or not _is_raw_number(raw.get("temperature_k")):
		return false
	return _has_raw_composition_structure(Dictionary(raw["composition"]))


static func _rehydrate_ledger_entries(raw_entries: Array) -> Array:
	var result: Array = []
	for raw_entry in raw_entries:
		var entry: Dictionary = raw_entry
		result.append({
			"account_id": String(entry["account_id"]),
			"material_id": String(entry["material_id"]),
			"mass_kg": float(entry["mass_kg"]),
		})
	return result


static func _finish_rehydration(
	raw: Dictionary,
	value: Dictionary,
	strict_validation: Dictionary
) -> Dictionary:
	if value.is_empty() or not bool(strict_validation.get("success", false)):
		return {}
	# JSON decoding does not preserve declared Variant types: integer-valued floats
	# become ints. Therefore the raw transport dictionary is not a valid checksum
	# domain. Verify the reconstructed typed DTO and compare its canonical checksum
	# with the checksum persisted in the raw payload.
	var persisted_checksum: String = String(raw.get("checksum", ""))
	if not MatterUtilsScript.is_lower_hex_64(persisted_checksum):
		return {}
	if String(value.get("checksum", "")) != persisted_checksum:
		return {}
	if MatterUtilsScript.compute_checksum(value) != persisted_checksum:
		return {}
	return value


static func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	return bool(MatterUtilsScript.validate_exact_fields(value, fields).get("success", false))


static func _is_raw_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _is_raw_integer(value) -> bool:
	return MatterUtilsScript.is_json_integer(value)


static func _is_number_array(value, expected_size: int = -1) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	if expected_size >= 0 and value.size() != expected_size:
		return false
	for component in value:
		if not _is_raw_number(component):
			return false
	return true


static func _is_string_array(value) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for item in value:
		if typeof(item) != TYPE_STRING:
			return false
	return true


static func _float_array(raw) -> Array:
	var result: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return result
	for component in raw:
		result.append(float(component))
	return result

static func _encode_transport_value(value, path: String) -> Dictionary:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return _transport_success(value)
		TYPE_INT:
			if not MatterUtilsScript.is_json_integer(value):
				return _transport_failure(path, "Integer exceeds the safe JSON range")
			return _transport_success(int(value))
		TYPE_FLOAT:
			var number: float = float(value)
			if not is_finite(number):
				return _transport_failure(path, "Non-finite float")
			return _transport_success({FLOAT_TAG_KEY: _float64_to_hex(number)})
		TYPE_ARRAY:
			if _is_non_empty_float_array(value):
				return _transport_success(_encode_float_array_tag(value))
			var array_value: Array = []
			for index in range(value.size()):
				var child: Dictionary = _encode_transport_value(value[index], "%s[%d]" % [path, index])
				if not bool(child.get("success", false)):
					return child
				array_value.append(child["value"])
			return _transport_success(array_value)
		TYPE_DICTIONARY:
			var dictionary_value: Dictionary = {}
			for raw_key in value.keys():
				if typeof(raw_key) != TYPE_STRING:
					return _transport_failure(path, "Dictionary keys must be String")
				var key: String = String(raw_key)
				var child: Dictionary = _encode_transport_value(value[raw_key], "%s.%s" % [path, key])
				if not bool(child.get("success", false)):
					return child
				dictionary_value[key] = child["value"]
			return _transport_success(dictionary_value)
		_:
			return _transport_failure(path, "Unsupported persistence Variant: %s" % type_string(typeof(value)))


static func _decode_transport_value(value, path: String) -> Dictionary:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return _transport_success(value)
		TYPE_INT:
			if not MatterUtilsScript.is_json_integer(value):
				return _transport_failure(path, "Integer exceeds the safe JSON range")
			return _transport_success(int(value))
		TYPE_FLOAT:
			# Transport payloads must never contain untagged JSON numbers with
			# fractional values because their binary64 bits are not stable.
			if not MatterUtilsScript.is_json_integer(value):
				return _transport_failure(path, "Untagged fractional JSON number")
			return _transport_success(int(value))
		TYPE_ARRAY:
			var array_value: Array = []
			for index in range(value.size()):
				var child: Dictionary = _decode_transport_value(value[index], "%s[%d]" % [path, index])
				if not bool(child.get("success", false)):
					return child
				array_value.append(child["value"])
			return _transport_success(array_value)
		TYPE_DICTIONARY:
			var dictionary_source: Dictionary = value
			if _has_exact_fields(dictionary_source, FLOAT_TAG_FIELDS):
				return _decode_float_tag(dictionary_source, path)
			if _has_exact_fields(dictionary_source, FLOAT_ARRAY_TAG_FIELDS):
				return _decode_float_array_tag(dictionary_source, path)
			var dictionary_value: Dictionary = {}
			for raw_key in dictionary_source.keys():
				if typeof(raw_key) != TYPE_STRING:
					return _transport_failure(path, "Dictionary keys must be String")
				var key: String = String(raw_key)
				var child: Dictionary = _decode_transport_value(
					dictionary_source[raw_key], "%s.%s" % [path, key]
				)
				if not bool(child.get("success", false)):
					return child
				dictionary_value[key] = child["value"]
			return _transport_success(dictionary_value)
		_:
			return _transport_failure(path, "Unsupported decoded persistence Variant")


static func _decode_float_array_tag(value: Dictionary, path: String) -> Dictionary:
	if typeof(value.get(FLOAT_ARRAY_TAG_KEY)) != TYPE_STRING \
		or not MatterUtilsScript.is_json_integer(value.get(FLOAT_ARRAY_COUNT_KEY)):
		return _transport_failure(path, "Float array tag is malformed")
	var count: int = int(value[FLOAT_ARRAY_COUNT_KEY])
	var bits: String = String(value[FLOAT_ARRAY_TAG_KEY])
	if count < 1 or bits.length() != count * 16 or bits != bits.to_lower():
		return _transport_failure(path, "Float array tag length does not match count")
	for character in bits:
		if not String(character) in [
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
			"a", "b", "c", "d", "e", "f",
		]:
			return _transport_failure(path, "Float array tag contains a non-hex digit")
	var bytes: PackedByteArray = bits.hex_decode()
	if bytes.size() != count * 8:
		return _transport_failure(path, "Float array tag decoded to an invalid byte count")
	var result: Array = []
	for index in range(count):
		var number: float = bytes.decode_double(index * 8)
		if not is_finite(number):
			return _transport_failure(path, "Float array tag decoded to a non-finite value")
		result.append(number)
	return _transport_success(result)


static func _decode_float_tag(value: Dictionary, path: String) -> Dictionary:
	if typeof(value.get(FLOAT_TAG_KEY)) != TYPE_STRING:
		return _transport_failure(path, "Float tag must contain a hexadecimal String")
	var bits: String = String(value[FLOAT_TAG_KEY])
	if bits.length() != 16 or bits != bits.to_lower():
		return _transport_failure(path, "Float tag must contain 16 lower-case hex digits")
	for character in bits:
		if not String(character) in [
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
			"a", "b", "c", "d", "e", "f",
		]:
			return _transport_failure(path, "Float tag contains a non-hex digit")
	var bytes: PackedByteArray = bits.hex_decode()
	if bytes.size() != 8:
		return _transport_failure(path, "Float tag decoded to an invalid byte count")
	var number: float = bytes.decode_double(0)
	if not is_finite(number):
		return _transport_failure(path, "Float tag decoded to a non-finite value")
	return _transport_success(number)


static func _is_non_empty_float_array(value: Array) -> bool:
	if value.is_empty():
		return false
	for item in value:
		if typeof(item) != TYPE_FLOAT or not is_finite(float(item)):
			return false
	return true


static func _encode_float_array_tag(value: Array) -> Dictionary:
	var bytes := PackedByteArray()
	bytes.resize(value.size() * 8)
	for index in range(value.size()):
		bytes.encode_double(index * 8, float(value[index]))
	return {
		FLOAT_ARRAY_TAG_KEY: bytes.hex_encode(),
		FLOAT_ARRAY_COUNT_KEY: value.size(),
	}


static func _float64_to_hex(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()


static func _transport_success(value) -> Dictionary:
	return {"success": true, "value": value, "error": ""}


static func _transport_failure(path: String, error: String) -> Dictionary:
	return {"success": false, "value": null, "error": "%s: %s" % [path, error]}
