extends SceneTree

const Vis55 = preload("res://scripts/labs/ecology/eco_evo7_vis5_5_visual_evidence_play1_handoff.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output_dir := OS.get_environment("DWS_VIS55_EVIDENCE_DIR")
	if output_dir.is_empty():
		output_dir = "user://vis5_5_evidence"
	var host := Vis55.new()
	host.auto_initialize = false
	root.add_child(host)
	if not host.initialize_runtime():
		push_error("VIS5.5 capture: runtime initialization failed")
		quit(1)
		return
	for _i in range(4):
		await process_frame
	var bundle: Dictionary = await host.capture_evidence_bundle(output_dir)
	if bundle.is_empty():
		push_error("VIS5.5 capture: evidence bundle failed")
		quit(1)
		return
	print("ECO.EVO7 VIS5.5 Visual Capture: PASS (%d PNGs)" % int(bundle.get("capture_count", 0)))
	print("VIS55_CAPTURE_DIR=" + String(bundle.get("output_directory", "")))
	print("VIS55_CAPTURE_BUNDLE_HASH=" + String(bundle.get("capture_bundle_hash", "")))
	print("VIS55_MANIFEST_SHA256=" + String(bundle.get("manifest_sha256", "")))
	quit(0)
