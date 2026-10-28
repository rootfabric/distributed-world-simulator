extends RefCounted
## Converts an A4 field read into the environment sample consumed by the accepted A2 interpreter.
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const L = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const E = preload("res://scripts/research/ecology/v2/environment_fixture_v1.gd")

static func sample_for_development(field: Dictionary, organism_id: String, position_mm: Array, extent_mm: int, supports: Array = [{"id": "ground", "kind": "plane_y", "position_mm": [0, 0, 0]}]) -> Dictionary:
	var request := Ports.sample_request(organism_id, position_mm, extent_mm)
	var result := L.sample(field, request, supports)
	if not result.success:
		return {}
	var sample: Dictionary = result.sample
	return sample if F.validate_sample(sample).is_empty() and E.validate(sample).is_empty() else {}
