extends SceneTree

## WP0.2 — content license ledger enforcement.
##
## Walks a directory tree and requires every contained file to live in a
## directory that has a complete SOURCE.md provenance record
## (see docs/world_packs/licenses/SOURCE_TEMPLATE.md).
##
## Headless usage:
##   godot --headless --path <project> --script res://tools/world_packs/check_asset_ledger.gd -- --root=res://assets/third_party
##
## Exit codes:
##   0 = every file is covered by a complete SOURCE.md (or the tree is empty)
##   1 = provenance violations found
##   2 = usage error

const DEFAULT_ROOT: String = "res://assets/third_party"

const REQUIRED_FIELDS: PackedStringArray = [
	"source_url",
	"creator",
	"asset",
	"download_date",
	"license",
	"license_url",
	"redistribution",
	"modifications",
	"checksum",
	"files_imported",
]


func _init() -> void:
	var options: Dictionary = _parse_options(OS.get_cmdline_user_args())
	if options.is_empty():
		print("WORLD_PACKS_LEDGER: USAGE ERROR (expected --root=DIR)")
		quit(2)
		return

	var root: String = String(options["root"])
	if not DirAccess.dir_exists_absolute(root):
		print("WORLD_PACKS_LEDGER: PASS (0 third-party files: %s does not exist)" % root)
		quit(0)
		return

	var files: PackedStringArray = PackedStringArray()
	_collect_files(root, files)
	var asset_files: PackedStringArray = PackedStringArray()
	for file_path in files:
		if String(file_path).get_file() != "SOURCE.md":
			asset_files.append(String(file_path))
	if asset_files.is_empty():
		print("WORLD_PACKS_LEDGER: PASS (0 third-party files under %s)" % root)
		quit(0)
		return

	var violations: PackedStringArray = PackedStringArray()
	var checked_dirs: Dictionary = {}
	for file_path in asset_files:
		var asset_dir: String = file_path.get_base_dir()
		if not checked_dirs.has(asset_dir):
			checked_dirs[asset_dir] = true
			_check_source_record(asset_dir, violations)
		if not FileAccess.file_exists("%s/SOURCE.md" % asset_dir):
			violations.append("%s: file has no sibling SOURCE.md" % file_path)

	if violations.is_empty():
		print("WORLD_PACKS_LEDGER: PASS (%d third-party file(s) in %d asset dir(s))" % [
			asset_files.size(), checked_dirs.size(),
		])
		quit(0)
	else:
		for violation in violations:
			print("WORLD_PACKS_LEDGER: VIOLATION %s" % violation)
		print("WORLD_PACKS_LEDGER: FAIL (%d violation(s))" % violations.size())
		quit(1)


func _parse_options(user_args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {}
	for raw_arg in user_args:
		var arg: String = String(raw_arg)
		if not arg.begins_with("--root="):
			print("WORLD_PACKS_LEDGER: USAGE ERROR (expected --root=DIR, got: %s)" % arg)
			return {}
		options["root"] = arg.substr("--root=".length())
	if options.is_empty():
		options["root"] = DEFAULT_ROOT
	return options


func _collect_files(dir_path: String, files: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		files.append(dir_path)
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var entry_path: String = "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_collect_files(entry_path, files)
		else:
			files.append(entry_path)
		entry = dir.get_next()
	dir.list_dir_end()


func _check_source_record(asset_dir: String, violations: PackedStringArray) -> void:
	var source_path: String = "%s/SOURCE.md" % asset_dir
	if not FileAccess.file_exists(source_path):
		violations.append("%s: asset directory has no SOURCE.md" % asset_dir)
		return
	var file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		violations.append("%s: SOURCE.md is unreadable" % source_path)
		return
	var values: Dictionary = {}
	for line in file.get_as_text().split("\n"):
		var trimmed: String = String(line).strip_edges()
		if trimmed.begins_with("#") or trimmed.is_empty():
			continue
		var colon: int = trimmed.find(":")
		if colon <= 0:
			continue
		values[trimmed.substr(0, colon).strip_edges()] = trimmed.substr(colon + 1).strip_edges()
	for field in REQUIRED_FIELDS:
		if not values.has(String(field)):
			violations.append("%s: SOURCE.md is missing required field '%s'" % [asset_dir, field])
		elif String(values[String(field)]).is_empty():
			violations.append("%s: SOURCE.md field '%s' has an empty value" % [asset_dir, field])
