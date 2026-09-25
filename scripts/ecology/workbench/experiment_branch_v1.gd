# EcologyWorkbench ExperimentBranch v1 (P8, ECO ARCH2 A10.5 / ECO-POLYGON-1).
# Role: checkpoint / restore / fork / replay over one bound ExperimentController.
#   A checkpoint is an immutable canonical snapshot of the controller state
#   (field + population + feedback + tick) serialized through
#   canonical_value_v1.encode — presentation-independent canonical data, not
#   a second biological save model (the types are already canonical
#   Dictionaries; observatory_session save_text requires its own A7 session
#   and is NOT used for controller state).
#   fork() starts a new branch from a shared immutable parent checkpoint
#   (optionally through an environment_patch_v1 input patch); replay()
#   reproduces the identical final canonical hash from identical
#   manifest + seed + tick commands.
# Determinism: checkpoint ids and created_at are derived from
#   (manifest_hash, tick, canonical_state_hash) — NEVER from wall-clock.
# Layer: 2 (SIMULATION / ORCHESTRATION). Linked to A8 (checkpoint hash
#   provenance links branches; no second save format is introduced).
class_name EcoWorkbenchExperimentBranchV1
extends RefCounted

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const EnvironmentPatch = preload("res://scripts/ecology/workbench/environment_patch_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const RuntimeCheckpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")

const SCHEMA := "dws.ecology.workbench.experiment-branch.v1"
const CHECKPOINT_SCHEMA := "dws.ecology.workbench.checkpoint.v1"

var _controller: Object = null
var _founder_registry: Dictionary = {}
## Branch registry (session): branch_id -> {parent_branch_id,
## parent_checkpoint_id, manifest_hash, label, checkpoints: [ids]}.
var _branches: Dictionary = {}
## Immutable checkpoint store: checkpoint_id -> checkpoint (deep copy).
var _checkpoints: Dictionary = {}
# checkpoint_id -> digest(full checkpoint record), retained outside the
# checkpoint itself as the caller-owned trust anchor for rehashed tamper.
var _checkpoint_anchors: Dictionary = {}
var _root_branch_id := ""

## Bind a controller and open the root branch for its manifest.
func setup(controller: Object, founder_registry: Dictionary = {}) -> Dictionary:
	if controller == null or not controller.has_method("get_manifest"):
		return {"success": false, "error": "BRANCH_CONTROLLER"}
	_controller = controller
	_founder_registry = founder_registry.duplicate(true)
	_branches = {}
	_checkpoints = {}
	_checkpoint_anchors = {}
	var manifest: Dictionary = controller.get_manifest()
	var root_id := _branch_id("", "", Manifest.canonical_hash(manifest), 0)
	_branches[root_id] = {
		"parent_branch_id": "",
		"parent_checkpoint_id": "",
		"manifest_hash": Manifest.canonical_hash(manifest),
		"label": "root",
		"checkpoints": [],
	}
	_root_branch_id = root_id
	return {"success": true, "root_branch_id": root_id}

func set_founder_registry(founder_registry: Dictionary) -> void:
	_founder_registry = founder_registry.duplicate(true)

## Current branch = the newest registered branch (root until a fork).
func current_branch_id() -> String:
	var ids := _branches.keys()
	if ids.is_empty():
		return ""
	return ids[ids.size() - 1]

func root_branch_id() -> String:
	return _root_branch_id

# --- checkpoint ----------------------------------------------------------------

## Deterministic checkpoint id: digest of (manifest_hash, tick, state hash).
static func checkpoint_id_for(manifest_hash: String, tick: int, canonical_state_hash: String, state_checksum: String) -> String:
	# Identity binds BOTH the canonical ecology runtime and the complete
	# serialized checkpoint payload. This matters in WORLD_COMPAT: authority,
	# Matter/site bindings and damage overlay may legitimately change while the
	# biological runtime/tick stays identical.
	return C.digest({
		"schema": CHECKPOINT_SCHEMA,
		"manifest_hash": manifest_hash,
		"tick": tick,
		"canonical_state_hash": canonical_state_hash,
		"state_checksum": state_checksum,
	})

## Create an immutable checkpoint of the bound controller state.
## branch_meta / operator_annotations: provenance only (must be canonical).
func create_checkpoint(parent_checkpoint_id: String = "", branch_meta: Dictionary = {}, operator_annotations: Dictionary = {}) -> Dictionary:
	if _controller == null:
		return {"success": false, "error": "BRANCH_CONTROLLER"}
	var serialized: Dictionary = _controller.serialize_state()
	if not bool(serialized.get("success", false)):
		return {"success": false, "error": "BRANCH_SERIALIZE:" + String(serialized.get("error", "?"))}
	var manifest_hash := String(serialized.manifest_hash)
	var tick := int(serialized.tick)
	var state_hash := String(serialized.state_hash)
	var state_checksum := String(serialized.state_checksum)
	var id := checkpoint_id_for(manifest_hash, tick, state_hash, state_checksum)
	var checkpoint := {
		"schema": CHECKPOINT_SCHEMA,
		"checkpoint_id": id,
		"manifest_hash": manifest_hash,
		"tick": tick,
		"canonical_state_hash": state_hash,
		"snapshot_text": String(serialized.state_text),
		"state_checksum": state_checksum,
		"runtime_checkpoint_checksum": String(serialized.checkpoint_checksum),
		"parent_checkpoint_id": parent_checkpoint_id,
		"branch_meta": branch_meta.duplicate(true),
		"operator_annotations": operator_annotations.duplicate(true),
		"created_at": {"tick": tick, "checkpoint_id": id},
	}
	var error := validate_checkpoint(checkpoint)
	if not error.is_empty():
		return {"success": false, "error": "BRANCH_CHECKPOINT_CREATE:" + error}
	if _checkpoints.has(id):
		return {"success": true, "checkpoint": _checkpoints[id].duplicate(true), "existing": true}
	_checkpoints[id] = checkpoint.duplicate(true)
	_checkpoint_anchors[id] = C.digest(checkpoint)
	var branch: Dictionary = _branches.get(current_branch_id(), {})
	if not branch.is_empty():
		branch.checkpoints.append(id)
	return {"success": true, "checkpoint": checkpoint, "existing": false}

## Structural validation proves snapshot_text is exactly the runtime state
## named by canonical_state_hash. Full rehashed-record tamper is additionally
## rejected by the manager's caller-owned _checkpoint_anchors map.
static func validate_checkpoint(checkpoint: Dictionary) -> String:
	var fields := ["schema", "checkpoint_id", "manifest_hash", "tick", "canonical_state_hash", "snapshot_text", "state_checksum", "runtime_checkpoint_checksum", "parent_checkpoint_id", "branch_meta", "operator_annotations", "created_at"]
	if not C.keys(checkpoint, fields) or checkpoint.schema != CHECKPOINT_SCHEMA:
		return "CHECKPOINT_SCHEMA"
	if not F.valid_hash(checkpoint.manifest_hash) or not F.valid_hash(checkpoint.canonical_state_hash):
		return "CHECKPOINT_HASH"
	if not F.valid_hash(checkpoint.state_checksum):
		return "CHECKPOINT_STATE_CHECKSUM"
	if checkpoint.checkpoint_id != checkpoint_id_for(String(checkpoint.manifest_hash), int(checkpoint.tick), String(checkpoint.canonical_state_hash), String(checkpoint.state_checksum)):
		return "CHECKPOINT_ID"
	if not checkpoint.snapshot_text is String or not F.valid_hash(checkpoint.state_checksum) or String(checkpoint.snapshot_text).sha256_text() != String(checkpoint.state_checksum):
		return "CHECKPOINT_STATE_CHECKSUM"
	var runtime_checkpoint := RuntimeCheckpoint.deserialize(String(checkpoint.snapshot_text), String(checkpoint.state_checksum), String(checkpoint.manifest_hash))
	if runtime_checkpoint.is_empty():
		return "CHECKPOINT_RUNTIME_ADMISSION"
	if int(runtime_checkpoint.tick) != int(checkpoint.tick):
		return "CHECKPOINT_TICK"
	if String(runtime_checkpoint.runtime_state_hash) != String(checkpoint.canonical_state_hash):
		return "CHECKPOINT_RUNTIME_HASH"
	if String(runtime_checkpoint.checksum) != String(checkpoint.runtime_checkpoint_checksum):
		return "CHECKPOINT_RUNTIME_CHECKSUM"
	return ""

# --- restore / fork / replay ---------------------------------------------------

## Restore a checkpoint into the BOUND controller (strict manifest binding).
## After restore, further ticks continue deterministically from the
## checkpointed tick.
func restore(checkpoint: Dictionary) -> Dictionary:
	if _controller == null:
		return {"success": false, "error": "BRANCH_CONTROLLER"}
	var error := _trusted_checkpoint_error(checkpoint)
	if not error.is_empty():
		return {"success": false, "error": error}
	var reinit: Dictionary = _controller.initialize(_controller.get_manifest(), _founder_registry)
	if not bool(reinit.get("success", false)):
		return {"success": false, "error": "BRANCH_REINIT:" + String(reinit.get("error", "?"))}
	var loaded: Dictionary = _controller.load_state(String(checkpoint.snapshot_text), String(checkpoint.manifest_hash), String(checkpoint.state_checksum))
	if not bool(loaded.get("success", false)):
		return {"success": false, "error": "BRANCH_LOAD:" + String(loaded.get("error", "?"))}
	return {"success": true, "tick": int(loaded.tick), "status": String(loaded.status)}

## Fork a new branch from an immutable checkpoint. env_patch (OPTIONAL,
## environment_patch_v1 schema) produces a new immutable manifest AND is
## applied to the restored live field through the canonical owner-write API
## (controller.apply_field_patch). Returns a NEW controller instance bound
## to the branch; the parent checkpoint and parent branch stay untouched.
func fork(checkpoint: Dictionary, env_patch: Dictionary = {}, label: String = "") -> Dictionary:
	var error := _trusted_checkpoint_error(checkpoint)
	if not error.is_empty():
		return {"success": false, "error": error}
	if not env_patch.is_empty() and not env_patch is Dictionary:
		return {"success": false, "error": "BRANCH_PATCH_TYPE"}
	var manifest: Dictionary = _controller.get_manifest()
	if String(checkpoint.manifest_hash) != Manifest.canonical_hash(manifest):
		# Fork must start from the branch the manager is bound to (the
		# checkpoint's own manifest family); document as session limitation.
		return {"success": false, "error": "BRANCH_MANIFEST_FAMILY"}
	if not env_patch.is_empty():
		# Validate the patch against the ORIGINAL manifest up front, but keep
		# the original for initialize(): apply_field_patch below computes the
		# stock deltas against the controller's CURRENT (original) manifest
		# and switches it to the patched immutable manifest itself.
		# (Initializing with the patched manifest first would zero every
		# stock delta — the patch would never reach the live field.)
		var check: Dictionary = EnvironmentPatch.apply_patch(manifest, env_patch)
		if not bool(check.get("success", false)):
			return {"success": false, "error": "BRANCH_PATCH:" + String(check.get("error", "?"))}
	var branch_controller := Controller.new()
	var init_result: Dictionary = branch_controller.initialize(manifest, _founder_registry)
	if not bool(init_result.get("success", false)):
		return {"success": false, "error": "BRANCH_INIT:" + String(init_result.get("error", "?"))}
	var loaded: Dictionary = branch_controller.load_state(String(checkpoint.snapshot_text), String(checkpoint.manifest_hash), String(checkpoint.state_checksum))
	if not bool(loaded.get("success", false)):
		return {"success": false, "error": "BRANCH_LOAD:" + String(loaded.get("error", "?"))}
	if not env_patch.is_empty():
		var patched: Dictionary = branch_controller.apply_field_patch(env_patch)
		if not bool(patched.get("success", false)):
			return {"success": false, "error": "BRANCH_FIELD_PATCH:" + String(patched.get("error", "?"))}
	var manifest_hash := Manifest.canonical_hash(branch_controller.get_manifest())
	var branch_id := _branch_id(current_branch_id(), String(checkpoint.checkpoint_id), manifest_hash, _branches.size())
	_branches[branch_id] = {
		"parent_branch_id": current_branch_id(),
		"parent_checkpoint_id": String(checkpoint.checkpoint_id),
		"manifest_hash": manifest_hash,
		"label": label,
		"checkpoints": [],
	}
	return {"success": true, "branch_id": branch_id, "controller": branch_controller, "manifest_hash": manifest_hash}

## Deterministic replay: identical checkpoint + manifest + seed + tick
## commands must reach the identical final canonical state hash.
## commands = tick batch counts (the controller command surface has no
## other inputs). Returns {"success", "canonical_state_hash", "tick"}.
static func replay(checkpoint: Dictionary, manifest: Dictionary, founder_registry: Dictionary, tick_commands: Array, expected_checkpoint_anchor: String = "") -> Dictionary:
	var error := validate_checkpoint(checkpoint)
	if not error.is_empty():
		return {"success": false, "error": "REPLAY_CHECKPOINT:" + error}
	if not F.valid_hash(expected_checkpoint_anchor) or C.digest(checkpoint) != expected_checkpoint_anchor:
		return {"success": false, "error": "REPLAY_EXTERNAL_ANCHOR"}
	if not tick_commands is Array or tick_commands.is_empty():
		return {"success": false, "error": "REPLAY_COMMANDS"}
	for command in tick_commands:
		if not C.integer(command, 1, C.MAX_INT):
			return {"success": false, "error": "REPLAY_COMMAND_VALUE"}
	var replay_controller := Controller.new()
	var init_result: Dictionary = replay_controller.initialize(manifest, founder_registry)
	if not bool(init_result.get("success", false)):
		return {"success": false, "error": "REPLAY_INIT:" + String(init_result.get("error", "?"))}
	var loaded: Dictionary = replay_controller.load_state(String(checkpoint.snapshot_text), String(checkpoint.manifest_hash), String(checkpoint.state_checksum))
	if not bool(loaded.get("success", false)):
		return {"success": false, "error": "REPLAY_LOAD:" + String(loaded.get("error", "?"))}
	for command in tick_commands:
		var run_result: Dictionary = replay_controller.run(int(command))
		if not bool(run_result.get("success", false)):
			return {"success": false, "error": "REPLAY_RUN:" + String(run_result.get("error", "?"))}
	var snapshot: Dictionary = replay_controller.get_snapshot()
	if not bool(snapshot.get("success", false)):
		return {"success": false, "error": "REPLAY_SNAPSHOT"}
	return {"success": true, "canonical_state_hash": String(snapshot.canonical_state_hash), "tick": int(snapshot.tick)}

func trusted_checkpoint_anchor(checkpoint_id: String) -> String:
	return String(_checkpoint_anchors.get(checkpoint_id, ""))

func _trusted_checkpoint_error(checkpoint: Dictionary) -> String:
	var error := validate_checkpoint(checkpoint)
	if not error.is_empty():
		return "BRANCH_CHECKPOINT:" + error
	var id := String(checkpoint.checkpoint_id)
	if not _checkpoint_anchors.has(id) or String(_checkpoint_anchors[id]) != C.digest(checkpoint):
		return "BRANCH_CHECKPOINT_EXTERNAL_ANCHOR"
	return ""

# --- registry views --------------------------------------------------------------

func get_checkpoint(checkpoint_id: String) -> Dictionary:
	return (_checkpoints.get(checkpoint_id, {}) as Dictionary).duplicate(true)

func branch_registry() -> Dictionary:
	var registry := {}
	for branch_id in _branches:
		var branch: Dictionary = _branches[branch_id]
		registry[String(branch_id)] = {
			"parent_branch_id": String(branch.parent_branch_id),
			"parent_checkpoint_id": String(branch.parent_checkpoint_id),
			"manifest_hash": String(branch.manifest_hash),
			"label": String(branch.label),
			"checkpoints": (branch.checkpoints as Array).duplicate(),
		}
	return registry

## Minimal human-readable branch tree (one line per branch).
func branch_tree_text() -> String:
	var lines: Array[String] = []
	_append_branch_line(_root_branch_id, 0, lines)
	return "\n".join(lines)

func _append_branch_line(branch_id: String, depth: int, lines: Array[String]) -> void:
	if not _branches.has(branch_id):
		return
	var branch: Dictionary = _branches[branch_id]
	var indent := "".repeat(depth * 2)
	var label := String(branch.label)
	if label.is_empty():
		label = branch_id.substr(0, 10)
	lines.append("%s- %s [%s] manifest=%s checkpoints=%d" % [
		indent, label, branch_id.substr(0, 10),
		String(branch.manifest_hash).substr(0, 8),
		(branch.checkpoints as Array).size(),
	])
	for other_id in _branches:
		if String(_branches[other_id].parent_branch_id) == branch_id:
			_append_branch_line(String(other_id), depth + 1, lines)

func _branch_id(parent_branch_id: String, parent_checkpoint_id: String, manifest_hash: String, index: int) -> String:
	return C.digest({
		"schema": SCHEMA,
		"kind": "branch",
		"parent_branch_id": parent_branch_id,
		"parent_checkpoint_id": parent_checkpoint_id,
		"manifest_hash": manifest_hash,
		"index": index,
	})
