extends RefCounted

## ECO.EVO7 VIS4.5 — deterministic individuality presentation contract.
##
## The accepted PH5 GrowthGraph already uses development_individual_seed for
## branch choice, azimuth, bounded angle jitter and branch-length jitter. This
## helper does not regenerate or perturb that topology. It derives only a stable
## presentation-space orientation around the plant's local +Y axis and seals the
## source binding so PLAY0 can expose/replay individuality explicitly.

const SCHEMA := "distributed_world_simulator.ecology.evo7_vis4_5_deterministic_individuality.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-VIS4.5.R1"

const PRESENTATION_ONLY := true
const ECOLOGY_AUTHORITY := false
const NETWORK_AUTHORITY := false
const PERSISTENCE_AUTHORITY := false

const RESULT_FIELDS: Array[String] = [
	"schema", "version", "revision",
	"presentation_only", "ecology_authority", "network_authority", "persistence_authority",
	"record_id", "development_individual_seed",
	"source_descriptor_hash", "source_growth_graph_hash",
	"orientation_yaw_deg", "individuality_hash",
]


static func build(source_descriptor: Dictionary) -> Dictionary:
	if source_descriptor.is_empty():
		return {}
	var record_id := String(source_descriptor.get("record_id", ""))
	var seed := int(source_descriptor.get("development_individual_seed", -1))
	var descriptor_hash := String(source_descriptor.get("descriptor_hash", ""))
	var graph_hash := String(source_descriptor.get("growth_graph_hash", ""))
	if record_id.is_empty() or seed < 0:
		return {}
	if not _is_sha256_hex(descriptor_hash) or not _is_sha256_hex(graph_hash):
		return {}

	# Orientation is deliberately sourced only from the canonical development
	# individual seed. It rotates the already-built PH5 object as a whole and
	# cannot affect ecology, GrowthGraph, RenderDescription or materialization.
	var yaw_deg := 360.0 * _unit(seed, "play0/local-yaw")
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"presentation_only": PRESENTATION_ONLY,
		"ecology_authority": ECOLOGY_AUTHORITY,
		"network_authority": NETWORK_AUTHORITY,
		"persistence_authority": PERSISTENCE_AUTHORITY,
		"record_id": record_id,
		"development_individual_seed": seed,
		"source_descriptor_hash": descriptor_hash,
		"source_growth_graph_hash": graph_hash,
		"orientation_yaw_deg": yaw_deg,
	}
	result["individuality_hash"] = compute_hash(result)
	return result if validate(result) else {}


static func validate(value: Dictionary) -> bool:
	if not _exact_keys(value, RESULT_FIELDS):
		return false
	if String(value.get("schema", "")) != SCHEMA:
		return false
	if String(value.get("version", "")) != VERSION or String(value.get("revision", "")) != REVISION:
		return false
	if not bool(value.get("presentation_only", false)):
		return false
	if bool(value.get("ecology_authority", true)):
		return false
	if bool(value.get("network_authority", true)) or bool(value.get("persistence_authority", true)):
		return false
	if String(value.get("record_id", "")).is_empty():
		return false
	if int(value.get("development_individual_seed", -1)) < 0:
		return false
	if not _is_sha256_hex(String(value.get("source_descriptor_hash", ""))):
		return false
	if not _is_sha256_hex(String(value.get("source_growth_graph_hash", ""))):
		return false
	var yaw := float(value.get("orientation_yaw_deg", NAN))
	if not is_finite(yaw) or yaw < 0.0 or yaw >= 360.0:
		return false
	return String(value.get("individuality_hash", "")) == compute_hash(value)


static func compute_hash(value: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		String(value.get("record_id", "")),
		str(int(value.get("development_individual_seed", -1))),
		String(value.get("source_descriptor_hash", "")),
		String(value.get("source_growth_graph_hash", "")),
		"%.9f" % float(value.get("orientation_yaw_deg", 0.0)),
	])).sha256_text()


static func orientation_yaw_deg(individual_seed: int) -> float:
	if individual_seed < 0:
		return NAN
	return 360.0 * _unit(individual_seed, "play0/local-yaw")


static func _unit(seed: int, key: String) -> float:
	var digest := (str(seed) + "|" + key).sha256_text()
	var value := digest.substr(0, 12).hex_to_int()
	return float(value) / 281474976710655.0


static func _is_sha256_hex(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var decimal := code >= 48 and code <= 57
		var lower_hex := code >= 97 and code <= 102
		var upper_hex := code >= 65 and code <= 70
		if not decimal and not lower_hex and not upper_hex:
			return false
	return true


static func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true
