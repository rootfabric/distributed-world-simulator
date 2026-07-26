extends Node

var last_entity_id: String = ""
var next_active: bool = false


func toggle_survey_beacon_signal(entity_id: String) -> Dictionary:
	last_entity_id = entity_id
	return {
		"success": true,
		"active": next_active,
		"entity_id": entity_id,
		"message": "mock toggled",
	}
