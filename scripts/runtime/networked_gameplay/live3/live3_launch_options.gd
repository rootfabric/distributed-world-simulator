extends RefCounted

const Launch = preload("res://scripts/runtime/launch_options.gd")
const Repository = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const ConstructionPort = preload("res://scripts/runtime/networked_gameplay/live3/live3_construction_recovery_port.gd")
const EXTRA_KEYS := ["world-slot", "world-save-root", "world-control-file", "world-control-token", "world-status-file"]

static func parse(arguments) -> Dictionary:
	var forwarded: Array[String] = []
	var extra: Dictionary = {}
	var errors: Array[String] = []
	var explicit_native_root := false
	for raw in arguments:
		var arg := String(raw)
		var key := arg.trim_prefix("--").get_slice("=", 0)
		if arg.begins_with("--") and key in EXTRA_KEYS:
			if not arg.contains("=") or extra.has(key):
				errors.append("LIVE3_OPTION_MISSING_OR_DUPLICATE:" + key)
			else:
				extra[key] = arg.substr(arg.find("=") + 1)
		else:
			forwarded.append(arg)
			if arg.begins_with("--m6-persistence-root="):
				explicit_native_root = true
	if extra.is_empty() and errors.is_empty():
		return Launch.parse(forwarded)
	var slot := String(extra.get("world-slot", ""))
	var root := String(extra.get("world-save-root", "user://live3-worlds"))
	var canonical_root := ProjectSettings.globalize_path(root).simplify_path()
	# The existing parser must see the resolved native root when validating
	# --m6-result-file. It still owns all old role/timeout/network validation.
	if not explicit_native_root:
		forwarded.append("--m6-persistence-root=" + canonical_root.path_join(slot))
	var parsed: Dictionary = Launch.parse(forwarded)
	errors.append_array(parsed.get("errors", []))
	var options: Dictionary = parsed.get("options", {})
	if not valid_slot(slot):
		errors.append("LIVE3_WORLD_SLOT_INVALID")
	if not bool(options.get("network_mvp", false)) or options.get("role") != "dedicated-server":
		errors.append("LIVE3_WORLD_SLOT_REQUIRES_NETWORK_MVP_SERVER")
	if explicit_native_root:
		errors.append("LIVE3_AMBIGUOUS_PERSISTENCE_ROOT")
	if root.is_empty() or root.begins_with("res://") or (not root.begins_with("user://") and not root.is_absolute_path()):
		errors.append("LIVE3_SAVE_ROOT_MUST_BE_ABSOLUTE")
	var owner := "world/live3/" + slot
	var given_owner := String(options.get("node_id", ""))
	if given_owner not in ["local-dedicated-server", "local-listen-host", owner]:
		errors.append("LIVE3_WORLD_OWNER_MUST_MATCH_SLOT")
	var control := String(extra.get("world-control-file", ""))
	var token := String(extra.get("world-control-token", ""))
	var status := String(extra.get("world-status-file", ""))
	if not control.is_empty():
		if not control.is_absolute_path() or token.length() < 32 or status.is_empty():
			errors.append("LIVE3_OPERATOR_CONTROL_CONFIGURATION_INVALID")
	elif not token.is_empty():
		errors.append("LIVE3_CONTROL_TOKEN_WITHOUT_FILE")
	if not status.is_empty() and not status.is_absolute_path():
		errors.append("LIVE3_STATUS_PATH_MUST_BE_ABSOLUTE")
	for path in [control, status]:
		if not path.is_empty() and path_inside(path, canonical_root):
			errors.append("LIVE3_OPERATOR_FILES_MUST_BE_OUTSIDE_SAVE_ROOT")
	if not control.is_empty() and not status.is_empty() and normalized_path(control) == normalized_path(status):
		errors.append("LIVE3_CONTROL_AND_STATUS_MUST_DIFFER")
	options["live3_enabled"] = true
	options["live3_slot"] = slot
	options["live3_control_file"] = control
	options["live3_control_token"] = token
	options["live3_status_file"] = status
	options["node_id"] = owner
	options["m6_persistence_root"] = canonical_root.path_join(slot)
	return {"success": errors.is_empty(), "options": options, "errors": errors}

static func normalized_path(path: String) -> String:
	var value := ProjectSettings.globalize_path(path).simplify_path().replace("\\", "/").trim_suffix("/")
	return value.to_lower() if OS.get_name() == "Windows" else value

static func path_inside(path: String, root: String) -> bool:
	var p := normalized_path(path)
	var r := normalized_path(root)
	return p == r or p.begins_with(r + "/")

static func valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 48 or slot != slot.to_lower():
		return false
	if slot in ["con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]:
		return false
	for c in slot:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c in ["-", "_"]):
			return false
	return true

static func preflight_slot(options: Dictionary) -> Dictionary:
	if not bool(options.get("live3_enabled", false)):
		return {"success": true}
	var repository = Repository.new()
	var configured: Dictionary = repository.configure(String(options["m6_persistence_root"]))
	if not bool(configured.get("success", false)):
		return configured
	var loaded: Dictionary = repository.load_committed()
	if bool(loaded.get("success", false)):
		var checkpoint: Dictionary = loaded.get("details", {}).get("checkpoint", {})
		var gameplay: Dictionary = checkpoint.get("authority_state", {}).get("current_snapshot", {}).get("domain_components", {}).get("networked_gameplay_state", {})
		if not gameplay.get("live3_construction") is Dictionary:
			return {"success": false, "error_code": "LIVE3_LEGACY_OR_INCOMPLETE_SLOT_REQUIRES_MIGRATION"}
		var checked := ConstructionPort.validate_state(gameplay["live3_construction"], String(options["node_id"]), 1)
		if not bool(checked.get("success", false)):
			return checked
		# Do not let native M0 bootstrap recreate missing storage underneath a
		# saved Construction cut. Native M0 validates the actual bytes at bind.
		var m0 := repository.root_path.path_join("v0-p4-construction-m0")
		if not FileAccess.file_exists(m0.path_join("aggregate-transaction-state.json")) and not FileAccess.file_exists(m0.path_join("aggregate-transaction-state.previous.json")):
			return {"success": false, "error_code": "LIVE3_NATIVE_CONSTRUCTION_STORAGE_MISSING"}
		return loaded
	if loaded.get("error_code") != "AUTHORITATIVE_CHECKPOINT_NOT_FOUND":
		return loaded
	# An interrupted or partly deleted world is NOT a new world. Do not seed a
	# fresh M6 checkpoint next to already durable Construction or pending data.
	if has_files(repository.root_path):
		return {"success": false, "error_code": "LIVE3_EXISTING_SLOT_WITHOUT_CHECKPOINT"}
	return {"success": true, "source": "NEW"}

static func has_files(path: String, depth: int = 0) -> bool:
	if depth > 16:
		return true
	var dir := DirAccess.open(path)
	if dir == null:
		return true
	dir.include_hidden = true
	if not dir.get_files().is_empty():
		return true
	for name in dir.get_directories():
		if has_files(path.path_join(name), depth + 1):
			return true
	return false
