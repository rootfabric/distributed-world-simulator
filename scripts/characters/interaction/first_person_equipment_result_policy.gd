class_name FirstPersonEquipmentResultPolicy
extends RefCounted

const NETWORK_PRESENTATION_FALSE_NEGATIVE := "CHARACTER_EQUIPMENT_NETWORK_APPLY_FAILED"
const RECOVERED_CODE := "FPE_AUTHORITY_APPLIED_PRESENTATION_WARNING"


func normalize(
	result: Dictionary,
	replica_relation: Dictionary,
	target_container_id: String,
	target_slot_index: int = -1,
	require_slot_match: bool = false
) -> Dictionary:
	var normalized: Dictionary = result.duplicate(true)
	if bool(normalized.get("success", false)):
		return normalized
	var code: String = String(normalized.get("error_code", normalized.get("code", "")))
	if code != NETWORK_PRESENTATION_FALSE_NEGATIVE:
		return normalized

	var details_value: Variant = normalized.get("details", {})
	if not details_value is Dictionary:
		return normalized
	var details: Dictionary = Dictionary(details_value)
	var network_value: Variant = details.get("network_result", {})
	if not network_value is Dictionary:
		return normalized
	var network_result: Dictionary = Dictionary(network_value)
	if not bool(network_result.get("success", false)):
		return normalized

	if String(replica_relation.get("kind", "")) != "CONTAINER":
		return normalized
	if String(replica_relation.get("container_id", "")) != target_container_id:
		return normalized
	if require_slot_match and target_slot_index >= 0:
		if int(replica_relation.get("slot_index", -1)) != target_slot_index:
			return normalized

	# Authority succeeded and the local replica already proves the requested
	# relation. The legacy CH9.6 controller reported the operation as failed only
	# because a synchronous presentation refresh returned an error after the
	# authoritative graph had been installed. Preserve that presentation failure
	# as a warning; never rewrite server rejection or an unconfirmed relation.
	var recovered: Dictionary = network_result.duplicate(true)
	recovered["success"] = true
	recovered["code"] = RECOVERED_CODE
	recovered["error_code"] = ""
	recovered["authority_applied"] = true
	recovered["network_apply_false_negative_recovered"] = true
	recovered["presentation_warning"] = details.get("cause", {})
	recovered["replica_relation"] = replica_relation.duplicate(true)
	recovered["target_container_id"] = target_container_id
	recovered["target_slot_index"] = target_slot_index
	recovered["message"] = "Сервер применил изменение экипировки; визуализация синхронизируется"
	return recovered


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.first_person_equipment_result_policy.v1",
		"recovers_only": NETWORK_PRESENTATION_FALSE_NEGATIVE,
		"requires_network_success": true,
		"requires_replica_target_relation": true,
		"changes_network_authority": false,
		"changes_item_authority": false,
	}
