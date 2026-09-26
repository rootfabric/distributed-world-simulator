extends RefCounted
## A11 host orchestration / disk transport, NOT a second ecology state owner.
## The only live biological state remains in controller (A10.5). The bundle
## carries its existing shared-runtime checkpoint verbatim. An external caller
## must retain the returned SHA; a hash stored beside untrusted data is not trust.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
const WorldBinding = preload("res://scripts/research/ecology/v2/world_binding_v1.gd")
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "dws.ecology.habitat.checkpoint-transport.v1"
const FIELDS := ["schema", "manifest", "founder_registry", "checkpoint_text", "checkpoint_sha256"]
const MAX_SAVED_CHECKPOINTS := 64
const SUFFIX := ".eco.json"

var controller: Object = null
var founder_registry: Dictionary = {}
var _world_authority: Object = null
var _write_sequence := 0

func start(manifest: Dictionary, registry: Dictionary = {}, world_authority: Object = null) -> Dictionary:
	var staged := _stage(manifest, registry, world_authority)
	if not bool(staged.get("success", false)):
		return staged
	controller = staged.controller
	founder_registry = registry.duplicate(true)
	_world_authority = world_authority
	return {"success": true, "tick": controller.tick()}

## Workbench fork/rebind is an explicit swap, not another live trajectory.
## Registry is refreshed even if the controller object itself did not change.
func adopt(candidate: Object, registry: Dictionary = {}) -> Dictionary:
	if candidate == null or not candidate is Controller:
		return _fail("HABITAT_CONTROLLER")
	if not _valid_registry(registry):
		return _fail("HABITAT_REGISTRY")
	var state: Dictionary = candidate.serialize_state()
	if not bool(state.get("success", false)):
		return _fail("HABITAT_ADOPT:" + String(state.get("error", "?")))
	if candidate != controller:
		_world_authority = null
	controller = candidate
	founder_registry = registry.duplicate(true)
	return {"success": true}

func export_bundle() -> Dictionary:
	if controller == null:
		return _fail("HABITAT_NOT_STARTED")
	if not _valid_registry(founder_registry):
		return _fail("HABITAT_REGISTRY")
	var saved: Dictionary = controller.serialize_state()
	if not bool(saved.get("success", false)):
		return _fail("HABITAT_CHECKPOINT:" + String(saved.get("error", "?")))
	var payload := {
		"schema": SCHEMA,
		"manifest": controller.get_manifest(),
		"founder_registry": founder_registry.duplicate(true),
		"checkpoint_text": saved.state_text,
		"checkpoint_sha256": saved.state_checksum,
	}
	var text := C.encode(payload)
	if text.is_empty() or text.to_utf8_buffer().size() > C.MAX_BYTES:
		return _fail("HABITAT_BUNDLE_SIZE")
	return {"success": true, "text": text, "sha256": text.sha256_text(),
		"tick": int(saved.tick), "state_hash": String(saved.state_hash),
		"manifest_hash": String(saved.manifest_hash)}

## Failed restore leaves the current controller/registry untouched. WORLD_COMPAT
## requires a fresh caller-supplied adapter, never the adapter of the live session.
## The saved cursor must be admitted against CURRENT authority before import.
func restore_bundle(text: String, expected_sha256: String, fresh_world_authority: Object = null) -> Dictionary:
	if not _is_sha(expected_sha256):
		return _fail("HABITAT_EXTERNAL_ANCHOR_REQUIRED")
	if text.to_utf8_buffer().size() > C.MAX_BYTES:
		return _fail("HABITAT_BUNDLE_SIZE")
	if text.sha256_text() != expected_sha256.to_lower():
		return _fail("HABITAT_BUNDLE_ANCHOR")
	var decoded := C.decode(text)
	if not bool(decoded.get("success", false)):
		return _fail("HABITAT_BUNDLE_ENCODING")
	var value: Variant = decoded.value
	if not C.keys(value, FIELDS) or value.schema != SCHEMA:
		return _fail("HABITAT_BUNDLE_SCHEMA")
	if not value.manifest is Dictionary or not value.founder_registry is Dictionary \
			or not value.checkpoint_text is String or not value.checkpoint_sha256 is String:
		return _fail("HABITAT_BUNDLE_TYPES")
	var manifest: Dictionary = value.manifest
	var registry: Dictionary = value.founder_registry
	if not Manifest.validate(manifest).is_empty() or not _valid_registry(registry):
		return _fail("HABITAT_BUNDLE_INPUTS")
	var manifest_hash := Manifest.canonical_hash(manifest)
	var validated := Checkpoint.deserialize(String(value.checkpoint_text), String(value.checkpoint_sha256), manifest_hash)
	if validated.is_empty():
		return _fail("HABITAT_CANONICAL_CHECKPOINT")
	if int(validated.runtime_state.tick) > int(manifest.horizon_ticks):
		return _fail("HABITAT_CHECKPOINT_BEYOND_HORIZON")
	if String(manifest.mode) == "WORLD_COMPAT":
		if fresh_world_authority == null or fresh_world_authority == _world_authority:
			return _fail("HABITAT_FRESH_WORLD_AUTHORITY_REQUIRED")
		var context_error := _world_restore_context(validated.external_state, fresh_world_authority)
		if not context_error.is_empty():
			return _fail(context_error)
	elif fresh_world_authority != null:
		return _fail("HABITAT_LAB_WORLD_AUTHORITY")
	var staged := _stage(manifest, registry, fresh_world_authority)
	if not bool(staged.get("success", false)):
		return staged
	var candidate: Object = staged.controller
	var loaded: Dictionary = candidate.load_state(String(value.checkpoint_text), manifest_hash, String(value.checkpoint_sha256))
	if not bool(loaded.get("success", false)):
		return _fail("HABITAT_LOAD:" + String(loaded.get("error", "?")))
	controller = candidate
	founder_registry = registry.duplicate(true)
	_world_authority = fresh_world_authority
	return {"success": true, "tick": controller.tick(),
		"sha256": expected_sha256.to_lower(),
		"state_hash": controller.get_snapshot().canonical_state_hash}

## Reads existing A10 representations only. No world identity is invented and
## no caller-owned authority is mutated during context validation.
static func _world_restore_context(envelope: Dictionary, authority: Object) -> String:
	for method in ["region", "cursor", "export_state"]:
		if not authority.has_method(method):
			return "HABITAT_WORLD_CONTEXT_API"
	var saved := _world_raw(envelope)
	var current_envelope: Dictionary = authority.export_state()
	var current := _world_raw(current_envelope)
	if saved.is_empty() or current.is_empty() or not saved.get("cursor") is Dictionary:
		return "HABITAT_WORLD_CONTEXT_STATE"
	var current_region: Dictionary = authority.region()
	var admitted := WorldBinding.admit_cursor(saved.cursor, current_region)
	if not bool(admitted.get("success", false)):
		return "HABITAT_WORLD_CURRENT_AUTHORITY:" + String(admitted.get("error", "?"))
	var current_cursor: Dictionary = authority.cursor()
	if String(saved.cursor.get("entity_id", "")) != String(current_cursor.get("entity_id", "")):
		return "HABITAT_WORLD_ENTITY_MISMATCH"
	# A trusted historical checkpoint is not permission to rewind the caller's
	# already-advanced world bookkeeping inside the same owner/epoch. Cold
	# restore from a fresh cursor (0 -> N) and exact/equal continuation remain
	# valid; any component-wise rollback fails before import_state can mutate
	# the supplied authority object.
	for field in ["revision", "clock", "ecology_step"]:
		if not C.integer(saved.cursor.get(field), 0, C.MAX_INT) \
				or not C.integer(current_cursor.get(field), 0, C.MAX_INT):
			return "HABITAT_WORLD_CONTEXT_CURSOR:" + field
		if int(saved.cursor[field]) < int(current_cursor[field]):
			return "HABITAT_WORLD_CURSOR_ROLLBACK:" + field
	# Strict compatibility: a checkpoint may not overwrite current topology,
	# owner epoch/lifecycle, catalog or mapping with its historical versions.
	for field in ["manifest_hash", "region", "catalog", "mapping", "map_id"]:
		if not saved.has(field) or not current.has(field) or saved[field] != current[field]:
			return "HABITAT_WORLD_CONTEXT_MISMATCH:" + field
	return ""

static func _world_raw(envelope: Dictionary) -> Dictionary:
	if not envelope.get("state_text") is String:
		return {}
	var decoded: Variant = JSON.parse_string(String(envelope.state_text))
	if not decoded is Dictionary:
		return {}
	var normalized: Dictionary = NetworkUtils.canonicalize(decoded, "$.habitat_world_context")
	if not bool(normalized.get("success", false)) or not normalized.get("value") is Dictionary:
		return {}
	return normalized.value

## Immutable content-addressed files. Never overwrite an earlier checkpoint.
## Failed/incomplete temporary files are never considered load candidates.
func save(directory: String) -> Dictionary:
	if directory.is_empty() or directory.length() > 2048:
		return _fail("HABITAT_SAVE_DIRECTORY")
	if not directory.is_absolute_path() and not directory.begins_with("user://") and not directory.begins_with("res://"):
		return _fail("HABITAT_SAVE_ABSOLUTE_PATH_REQUIRED")
	var absolute := ProjectSettings.globalize_path(directory).simplify_path()
	var project := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var comparable := absolute.to_lower() if OS.has_feature("windows") else absolute
	var project_comparable := project.to_lower() if OS.has_feature("windows") else project
	if comparable == project_comparable or (comparable.begins_with(project_comparable + "/") \
			and not comparable.begins_with(project_comparable + "/artifacts/")):
		return _fail("HABITAT_SAVE_PROTECTED_PATH")
	var exported := export_bundle()
	if not bool(exported.get("success", false)):
		return exported
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		return _fail("HABITAT_SAVE_MKDIR")
	var path := directory.path_join(String(exported.sha256) + SUFFIX)
	if FileAccess.file_exists(path):
		var existing := _read(path)
		if not bool(existing.get("success", false)) or String(existing.get("text", "")).sha256_text() != String(exported.sha256):
			return _fail("HABITAT_EXISTING_CHECKPOINT_CORRUPT")
		return _receipt(exported, path, true)
	var count := 0
	for filename in DirAccess.get_files_at(absolute):
		if filename.ends_with(SUFFIX):
			count += 1
	if count >= MAX_SAVED_CHECKPOINTS:
		return _fail("HABITAT_CHECKPOINT_STORAGE_LIMIT")
	_write_sequence += 1
	var temporary := path + ".%d.%d.tmp" % [OS.get_process_id(), _write_sequence]
	# Refuse even a stale temporary collision; never truncate unknown data.
	if FileAccess.file_exists(temporary):
		return _fail("HABITAT_TEMP_COLLISION")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail("HABITAT_SAVE_OPEN")
	file.store_string(String(exported.text))
	file.flush()
	var write_error := file.get_error()
	file.close()
	var written := _read(temporary)
	if write_error != OK or not bool(written.get("success", false)) \
			or String(written.get("text", "")).sha256_text() != String(exported.sha256):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _fail("HABITAT_SAVE_WRITE")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		var concurrent := _read(path)
		if bool(concurrent.get("success", false)) and String(concurrent.text).sha256_text() == String(exported.sha256):
			return _receipt(exported, path, true)
		return _fail("HABITAT_SAVE_CONFLICT")
	var renamed := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if renamed != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return _fail("HABITAT_SAVE_RENAME")
	return _receipt(exported, path, false)

func load_file(path: String, expected_sha256: String, fresh_world_authority: Object = null) -> Dictionary:
	if not _is_sha(expected_sha256):
		return _fail("HABITAT_EXTERNAL_ANCHOR_REQUIRED")
	var read := _read(path)
	if not bool(read.get("success", false)):
		return read
	return restore_bundle(String(read.text), expected_sha256, fresh_world_authority)

static func _stage(manifest: Dictionary, registry: Dictionary, authority: Object) -> Dictionary:
	if not Manifest.validate(manifest).is_empty() or not _valid_registry(registry):
		return _fail("HABITAT_INPUTS")
	if String(manifest.mode) == "LAB" and authority != null:
		return _fail("HABITAT_LAB_WORLD_AUTHORITY")
	var candidate := Controller.new()
	if authority != null:
		var attached: Dictionary = candidate.attach_world_authority(authority)
		if not bool(attached.get("success", false)):
			return attached
	var initialized: Dictionary = candidate.initialize(manifest, registry)
	if not bool(initialized.get("success", false)):
		return initialized
	return {"success": true, "controller": candidate}

static func _valid_registry(registry: Dictionary) -> bool:
	if registry.size() > Manifest.MAX_FOUNDERS:
		return false
	for key in registry:
		if not key is String or not registry[key] is Dictionary:
			return false
		if not Genome.validate(registry[key]).is_empty() or Genome.biological_hash(registry[key]) != key:
			return false
	return true

static func _read(path: String) -> Dictionary:
	if path.is_empty() or path.length() > 4096:
		return _fail("HABITAT_READ_PATH")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("HABITAT_READ_OPEN")
	var length := file.get_length()
	if length < 1 or length > C.MAX_BYTES:
		file.close()
		return _fail("HABITAT_READ_SIZE")
	var bytes := file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return _fail("HABITAT_READ_TRUNCATED")
	var text := bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		return _fail("HABITAT_READ_UTF8")
	return {"success": true, "text": text}

static func _is_sha(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value.to_lower():
		if not character in "0123456789abcdef":
			return false
	return true

static func _receipt(exported: Dictionary, path: String, reused: bool) -> Dictionary:
	return {"success": true, "path": path, "sha256": exported.sha256,
		"tick": exported.tick, "state_hash": exported.state_hash,
		"manifest_hash": exported.manifest_hash, "reused": reused}

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}
