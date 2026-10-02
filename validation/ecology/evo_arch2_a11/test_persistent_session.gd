extends SceneTree

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const Session = preload("res://scripts/ecology/habitat/persistent_habitat_session_v1.gd")
const Preset = preload("res://scripts/ecology/habitat/habitat_preset_v1.gd")

var checks := 0
var failures: Array[String] = []
var directory := ""

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("A11_SESSION_FAIL " + message)

func write_file(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.close()
	return true

func _run() -> void:
	directory = "res://artifacts/runtime/eco-a11-fixtures/session-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var manifest := Preset.create(20260912, 64)
	check(not manifest.is_empty() and Manifest.validate(manifest).is_empty(), "self-contained preset validates")
	check(manifest.organization_profile == "FREE" and manifest.mode == "LAB", "FREE without archetype is default")
	check(manifest.environment.zones.size() == 3 and manifest.placement.entries.size() == 3, "wet/dry/dark placement")
	check(Preset.create(-1).is_empty() and Preset.create(0, 0).is_empty(), "invalid seed/horizon rejected")
	check(C.digest(manifest) == C.digest(Preset.create(20260912, 64)), "same preset deterministic")
	var session := Session.new()
	check(not session.export_bundle().success, "uninitialized save rejected")
	check(session.start(manifest).success, "start via accepted controller")
	var original: Object = session.controller
	var twin := Session.new()
	check(twin.start(manifest).success, "independent matching start")
	check(session.controller.get_snapshot().canonical_state_hash == twin.controller.get_snapshot().canonical_state_hash, "same genesis hash")
	var initial_account: Dictionary = session.controller.debug_state().runtime.accounting.initial.duplicate(true)
	check(session.controller.run(8).success, "advance real runtime 8 ticks")
	var exported: Dictionary = session.export_bundle()
	check(exported.success and int(exported.tick) == 8, "existing canonical checkpoint transported")
	check(exported.text == session.export_bundle().text, "repeated export byte deterministic")
	check(exported.sha256 == String(exported.text).sha256_text(), "external receipt matches bytes")
	var current_hash: String = session.controller.get_snapshot().canonical_state_hash
	check(not session.restore_bundle(exported.text, "").success, "missing external anchor rejected")
	check(not session.restore_bundle(exported.text, "0".repeat(64)).success, "wrong external anchor rejected")
	check(session.controller == original and session.controller.get_snapshot().canonical_state_hash == current_hash, "anchor failures atomic")

	# Fully valid alternate runtime, fully rehashed internally, still cannot
	# replace the caller's trusted outer bundle hash.
	check(twin.controller.run(3).success, "alternate valid state")
	var alternate: Dictionary = twin.export_bundle()
	check(alternate.success and alternate.sha256 != exported.sha256, "alternate has different genuine state")
	check(not session.restore_bundle(alternate.text, exported.sha256).success, "fully rehashed state substitution rejected")
	check(session.controller == original and session.controller.get_snapshot().canonical_state_hash == current_hash, "alternate rejection leaves live state untouched")

	var parsed := C.decode(exported.text)
	check(parsed.success, "transport canonical encoding")
	var invalid: Dictionary = parsed.value.duplicate(true)
	invalid["unknown"] = 1
	var invalid_text := C.encode(invalid)
	check(not session.restore_bundle(invalid_text, invalid_text.sha256_text()).success, "unknown envelope fields rejected even with caller anchor")
	invalid = parsed.value.duplicate(true)
	invalid.manifest.seed = int(invalid.manifest.seed) + 1
	invalid_text = C.encode(invalid)
	check(not session.restore_bundle(invalid_text, invalid_text.sha256_text()).success, "checkpoint cannot be rebound to different experiment")
	invalid = parsed.value.duplicate(true)
	invalid.checkpoint_text = "{}"
	invalid.checkpoint_sha256 = "{}".sha256_text()
	invalid_text = C.encode(invalid)
	check(not session.restore_bundle(invalid_text, invalid_text.sha256_text()).success, "malformed canonical state rejected despite rehash")
	invalid = parsed.value.duplicate(true)
	invalid.founder_registry = {"false-genome-hash": manifest.founders[0].genome}
	invalid_text = C.encode(invalid)
	check(not session.restore_bundle(invalid_text, invalid_text.sha256_text()).success, "forged founder registry key rejected")
	check(session.controller == original and session.controller.get_snapshot().canonical_state_hash == current_hash, "all malformed restores atomic")
	check(not session.start({}, {}).success and session.controller == original, "failed new session preserves live controller")

	var saved: Dictionary = session.save(directory)
	check(saved.success, "disk save completed")
	if bool(saved.get("success", false)):
		check(FileAccess.file_exists(saved.path), "durable immutable file exists")
		check(String(saved.path).get_file() == String(saved.sha256) + Session.SUFFIX, "content addressed path")
		var saved_again: Dictionary = session.save(directory)
		check(saved_again.success and saved_again.reused and saved_again.path == saved.path, "same state save is idempotentent")
		var restored := Session.new()
		var loaded: Dictionary = restored.load_file(saved.path, saved.sha256)
		check(loaded.success and restored.controller.tick() == 8, "cold session restores disk state")
		if loaded.success:
			check(restored.controller.get_snapshot().canonical_state_hash == current_hash, "restored canonical identity equal")
			check(session.controller.run(4).success and restored.controller.run(4).success, "both continuations execute")
			check(session.controller.get_snapshot().canonical_state_hash == restored.controller.get_snapshot().canonical_state_hash, "continuous vs resumed trajectory equal")
			check(restored.controller.debug_state().runtime.accounting.initial == initial_account, "genesis conservation anchor survives restore")
		# A missing or damaged requested file must not select a previous save.
		var before: String = restored.controller.get_snapshot().canonical_state_hash
		check(not restored.load_file(directory.path_join("missing.eco.json"), saved.sha256).success, "missing path rejected without fallback")
		var damaged := directory.path_join("damaged.eco.json")
		check(write_file(damaged, String(exported.text).substr(0, 30)), "write truncated fixture")
		check(not restored.load_file(damaged, exported.sha256).success, "truncated disk save rejected")
		check(restored.controller.get_snapshot().canonical_state_hash == before, "disk failure preserves live state")
		# Corrupted immutable path cannot be silently overwritten on save.
		var same := Session.new()
		check(same.restore_bundle(exported.text, exported.sha256).success, "restore tick-8 source for immutable collision")
		check(write_file(saved.path, "broken"), "corrupt existing immutable fixture")
		check(not same.save(directory).success, "corrupt immutable save rejected, not overwritten")
		check(FileAccess.get_file_as_string(saved.path) == "broken", "corrupt bytes retained for diagnosis")
		check(not same.save("res://scripts/ecology").success, "source-tree write rejected")
		check(not same.save("res://artifacts/../scripts/ecology").success, "source-tree traversal rejected")
		check(not same.save(ProjectSettings.globalize_path("res://scripts/ecology")).success, "absolute source-tree path rejected")
		check(not same.save("relative-unowned-folder").success, "implicit working-directory writes rejected")
	var oversized := "x".repeat(C.MAX_BYTES + 1)
	check(not session.restore_bundle(oversized, oversized.sha256_text()).success, "bounded transport decoding")
	var quota := directory.path_join("quota")
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(quota)) == OK, "quota fixture directory")
	var filled := true
	for index in Session.MAX_SAVED_CHECKPOINTS:
		filled = write_file(quota.path_join("reserved-%03d.eco.json" % index), "retained") and filled
	check(filled, "storage quota fixture populated")
	var limited: Dictionary = session.save(quota)
	check(not limited.success and limited.error == "HABITAT_CHECKPOINT_STORAGE_LIMIT", "storage bound fails closed rather than culling history")
	check(DirAccess.get_files_at(ProjectSettings.globalize_path(quota)).size() == Session.MAX_SAVED_CHECKPOINTS, "quota failure leaves all existing files")
	for filename in DirAccess.get_files_at(ProjectSettings.globalize_path(quota)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(quota.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(quota))
	for filename in DirAccess.get_files_at(ProjectSettings.globalize_path(directory)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	print("EVO_ARCH2_A11_SESSION checks=%d failed=%d" % [checks, failures.size()])
	print("EVO_ARCH2_A11_SESSION " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
