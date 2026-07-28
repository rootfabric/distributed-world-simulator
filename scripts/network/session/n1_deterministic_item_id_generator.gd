extends RefCounted

const IDS_BY_DEFINITION: Dictionary = {
	"n1_storage_terminal": "item/00000000-0000-4000-8000-000000000001",
	"n1_command_cargo": "item/00000000-0000-4000-8000-000000000002",
}

var _issued: Dictionary = {}


func generate(definition_id: String = "") -> String:
	var normalized: String = definition_id.strip_edges()
	if not IDS_BY_DEFINITION.has(normalized) or _issued.has(normalized):
		return ""
	_issued[normalized] = true
	return String(IDS_BY_DEFINITION[normalized])
