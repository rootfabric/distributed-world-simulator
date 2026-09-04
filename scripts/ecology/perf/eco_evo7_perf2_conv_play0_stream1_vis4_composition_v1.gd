extends RefCounted

## ECO.EVO7 PERF2.CONV R1 — STREAM1 + VIS4 convergence composition.
##
## This is an authority-neutral join seam. It configures the accepted optimized
## STREAM1 executor through the public Workbench API after PLAY0 initialization
## and exposes read-only integrated evidence. It owns no ecology publication,
## biology, persistence, networking or rendering truth.

const StreamExecutor = preload(
	"res://scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd"
)

const SCHEMA := "distributed_world_simulator.ecology.evo7_perf2_conv.composition.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-PERF2.CONV-R1"

const MODE := "STREAM1_OPTIMIZED_PLUS_VIS4"
const DEFAULT_PARENTS_PER_CHUNK := 64
const DEFAULT_AUDIT_INTERVAL := 10
const DEFAULT_AUDIT_GENERATION_1 := true

const ACCEPTED_STREAM1_HEAD := "4d0d95a2f0cf8aeb9642765c17a071f039e0f1c4"
const PERF24_CANDIDATE_HEAD := "840cfcea62ef7192b510235f915b849829654c6c"
const VIS49_ACCEPTED_EXECUTABLE_HEAD := "ab44617d8961add81a6c9f245c99d0b68eaeab52"
const VIS49_ACCEPTED_EXECUTABLE_TREE := "9d543a3db4f54a676e9f25152785c36a72c56a30"
const ANCESTRY_MERGE_HEAD := "3d41fe4542782e24a33bbac388404679756b4d67"
const ANCESTRY_MERGE_TREE := "415152ef85bd46b0c3f95bf3da826ec3f3dbb75f"

const AUTHORITIES := {
	"canonical": false,
	"ecology_truth_write": false,
	"generation_commit": false,
	"biology_write": false,
	"presentation_truth_write": false,
	"persistence_write": false,
	"network_write": false,
	"composition_only": true,
	"measurement_only": true,
}

var _configured := false
var _playground = null
var _workbench = null
var _executor = null
var _parents_per_chunk := DEFAULT_PARENTS_PER_CHUNK
var _audit_interval := DEFAULT_AUDIT_INTERVAL
var _audit_generation_1 := DEFAULT_AUDIT_GENERATION_1


func setup(playground, config: Dictionary = {}) -> bool:
	_configured = false
	_playground = null
	_workbench = null
	_executor = null

	if playground == null or not bool(playground.get("ready_success")):
		return false
	if not playground.has_method("get_workbench"):
		return false
	var wb = playground.get_workbench()
	if wb == null or not wb.has_method("set_generation_stream_executor"):
		return false
	if wb.has_method("has_generation_stream_executor") and bool(wb.has_generation_stream_executor()):
		return false

	_parents_per_chunk = int(config.get("parents_per_chunk", DEFAULT_PARENTS_PER_CHUNK))
	_audit_interval = int(config.get("audit_interval", DEFAULT_AUDIT_INTERVAL))
	_audit_generation_1 = bool(config.get("audit_generation_1", DEFAULT_AUDIT_GENERATION_1))
	if _parents_per_chunk < 1 or _audit_interval < 1:
		return false

	var executor = StreamExecutor.new()
	if not executor.setup({
		"parents_per_chunk": _parents_per_chunk,
		"audit_interval": _audit_interval,
		"audit_generation_1": _audit_generation_1,
		"pipeline_mode": StreamExecutor.PIPELINE_OPTIMIZED,
	}):
		return false
	if not wb.set_generation_stream_executor(executor):
		return false
	if not wb.has_generation_stream_executor():
		return false

	_playground = playground
	_workbench = wb
	_executor = executor
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func get_executor():
	return _executor


func get_stream_telemetry() -> Dictionary:
	return {} if not _configured or _executor == null else _executor.get_telemetry()


func get_contract() -> Dictionary:
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"mode": MODE,
		"configured": _configured,
		"parents_per_chunk": _parents_per_chunk,
		"audit_interval": _audit_interval,
		"audit_generation_1": _audit_generation_1,
		"pipeline_mode": StreamExecutor.PIPELINE_OPTIMIZED,
		"authorities": AUTHORITIES.duplicate(true),
		"accepted_stream1_head": ACCEPTED_STREAM1_HEAD,
		"perf2_4_candidate_head": PERF24_CANDIDATE_HEAD,
		"vis4_9_executable_head": VIS49_ACCEPTED_EXECUTABLE_HEAD,
		"vis4_9_executable_tree": VIS49_ACCEPTED_EXECUTABLE_TREE,
		"ancestry_merge_head": ANCESTRY_MERGE_HEAD,
		"ancestry_merge_tree": ANCESTRY_MERGE_TREE,
	}


func get_integrated_snapshot() -> Dictionary:
	if not _configured or _playground == null or _workbench == null or _executor == null:
		return {}
	var published: Dictionary = _playground.get_published_snapshot()
	var ecology: Dictionary = _workbench.get_ecology_snapshot()
	var presentation = _playground.get_presentation()
	if published.is_empty() or ecology.is_empty() or presentation == null:
		return {}

	var generation := int(published.get("generation", -1))
	var published_hash := String(published.get("ecology_state_hash", ""))
	if generation != int(ecology.get("generation", -2)):
		return {}
	if published_hash.length() != 64 or published_hash != String(ecology.get("state_hash", "")):
		return {}

	var presentation_contract: Dictionary = presentation.get_contract()
	if String(presentation_contract.get("source_ecology_hash", "")) != published_hash:
		return {}

	var morphology: Dictionary = _playground.get_published_morphology_descriptors()
	var reconstruction: Dictionary = _playground.get_published_reconstruction_evidence()
	if generation > 0:
		if morphology.is_empty() or reconstruction.is_empty():
			return {}
		if String(morphology.get("source_ecology_state_hash", "")) != published_hash:
			return {}

	var stream: Dictionary = _executor.get_telemetry()
	if String(stream.get("pipeline_mode", "")) != StreamExecutor.PIPELINE_OPTIMIZED:
		return {}

	var perf: Dictionary = _playground.get_performance_lod_state()
	if generation > 0 and perf.is_empty():
		return {}
	if generation > 0 and String(perf.get("source_ecology_hash", "")) != published_hash:
		return {}

	var result := {
		"schema": SCHEMA + ".snapshot",
		"version": VERSION,
		"revision": REVISION,
		"mode": MODE,
		"generation": generation,
		"ecology_state_hash": published_hash,
		"population_hash": String(published.get("population_hash", "")),
		"classification_hash": String(published.get("classification_hash", "")),
		"presentation_source_hash": String(presentation_contract.get("source_ecology_hash", "")),
		"ph5_active": bool(presentation_contract.get("ph5_active", false)),
		"morphology_descriptor_hash": String(morphology.get("adapter_hash", "")),
		"reconstruction_evidence_hash": String(reconstruction.get("evidence_hash", "")),
		"stream_telemetry": stream,
		"vis4_performance": perf,
		"authorities": AUTHORITIES.duplicate(true),
	}
	result["snapshot_hash"] = _snapshot_hash(result)
	return result if validate_integrated_snapshot(result) else {}


func validate_integrated_snapshot(value: Dictionary) -> bool:
	if String(value.get("schema", "")) != SCHEMA + ".snapshot":
		return false
	if String(value.get("version", "")) != VERSION or String(value.get("revision", "")) != REVISION:
		return false
	if String(value.get("mode", "")) != MODE:
		return false
	var generation := int(value.get("generation", -1))
	if generation < 0:
		return false
	var ecology_hash := String(value.get("ecology_state_hash", ""))
	if ecology_hash.length() != 64 or String(value.get("presentation_source_hash", "")) != ecology_hash:
		return false
	var stream_value = value.get("stream_telemetry")
	if not stream_value is Dictionary:
		return false
	var stream: Dictionary = stream_value
	if String(stream.get("pipeline_mode", "")) != StreamExecutor.PIPELINE_OPTIMIZED:
		return false
	if int(stream.get("parents_per_chunk", -1)) != _parents_per_chunk:
		return false
	if generation > 0:
		if not bool(value.get("ph5_active", false)):
			return false
		if String(value.get("morphology_descriptor_hash", "")).length() != 64:
			return false
		if String(value.get("reconstruction_evidence_hash", "")).length() != 64:
			return false
		var perf_value = value.get("vis4_performance")
		if not perf_value is Dictionary or Dictionary(perf_value).is_empty():
			return false
		if String(Dictionary(perf_value).get("source_ecology_hash", "")) != ecology_hash:
			return false
	var auth_value = value.get("authorities")
	if not auth_value is Dictionary or Dictionary(auth_value) != AUTHORITIES:
		return false
	return String(value.get("snapshot_hash", "")) == _snapshot_hash(value)


func _snapshot_hash(value: Dictionary) -> String:
	var stream: Dictionary = Dictionary(value.get("stream_telemetry", {}))
	var perf: Dictionary = Dictionary(value.get("vis4_performance", {}))
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		REVISION,
		str(int(value.get("generation", -1))),
		String(value.get("ecology_state_hash", "")),
		String(value.get("population_hash", "")),
		String(value.get("classification_hash", "")),
		String(value.get("presentation_source_hash", "")),
		String(value.get("morphology_descriptor_hash", "")),
		String(value.get("reconstruction_evidence_hash", "")),
		str(int(stream.get("stream_calls", 0))),
		str(int(stream.get("chunks_processed", 0))),
		str(int(stream.get("optimized_generation_calls", 0))),
		str(int(stream.get("max_parent_chunk_seen", 0))),
		str(int(stream.get("max_candidate_chunk_seen", 0))),
		str(int(perf.get("record_count", 0))),
		str(int(perf.get("materialization_cache_entries", 0))),
		str(int(perf.get("cost_units", 0))),
		String(perf.get("structural_evidence_hash", "")),
	])).sha256_text()
