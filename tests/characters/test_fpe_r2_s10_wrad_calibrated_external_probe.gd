extends SceneTree

const P = preload("res://scripts/characters/presentation/first_person_hand_asset_profile.gd")
const V = preload("res://scripts/characters/presentation/calibrated_native_skeleton_first_person_hand_visual_provider_fix2.gd")
const R = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const C = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")
const PROFILE := "res://config/characters/hand-assets/wrad-arms-cc0.v1.json"
var failures: Array[String] = []
var assertions := 0
var diagnostics: Dictionary = {"schema":"planet_simulator.fpe_wrad_calibration_probe.v1","hands":{}}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var loaded: Dictionary = P.load_from_path(PROFILE)
	_check(bool(loaded.get("success", false)), "profile load")
	if not bool(loaded.get("success", false)):
		_done(false); return
	var profile := Dictionary(Dictionary(loaded.get("details", {})).get("profile", {}))
	var scene_path := String(Dictionary(profile.get("asset", {})).get("scene_path", ""))
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		print("FPE R2 S10 WRAD calibrated external probe: PASS (%d assertions, external_asset_present=false)" % assertions)
		quit(0); return
	var scene: Resource = load(scene_path)
	_check(scene is PackedScene, "WRAD is not PackedScene")
	if not scene is PackedScene:
		_done(true); return
	var host := Node3D.new(); get_root().add_child(host)
	for hand in ["right", "left"]:
		var provider = V.new()
		_check(bool(provider.setup_profiled(scene as PackedScene, profile, PROFILE, scene_path).get("success", false)), "%s provider setup" % hand)
		var rig = R.new(); host.add_child(rig)
		var setup: Dictionary = rig.setup(hand, 19, provider)
		_check(bool(setup.get("success", false)), "%s rig setup" % hand)
		if bool(setup.get("success", false)):
			var report := Dictionary(rig.create_report().get("visual_provider", {}))
			_check(String(report.get("pose_calibration_mode", "")) == "AUTO_CHAIN_PALM_V1", "%s calibration mode" % hand)
			_check(String(report.get("canonical_reference_pose", "")) == "open", "%s open reference" % hand)
			_check(bool(report.get("pose_delta_relative_to_open", false)), "%s open-relative marker" % hand)
			_check(String(report.get("root_orientation_mode", "")) == "PRESERVE_SOURCE_BASIS", "%s root orientation" % hand)
			var bone := provider._native_skeleton.find_bone("finger_index1.%s" % ("r" if hand == "right" else "l"))
			_check(bone >= 0, "%s index bone" % hand)
			rig.apply_pose(C.new().get_pose("open")); rig._process(0.2)
			var open_angle := rad_to_deg(Quaternion.IDENTITY.angle_to(provider._native_skeleton.get_bone_pose_rotation(bone)))
			_check(open_angle < 0.05, "%s open rest" % hand)
			rig.apply_pose(C.new().get_pose("beacon_pinch")); rig._process(0.2)
			var angle := rad_to_deg(Quaternion.IDENTITY.angle_to(provider._native_skeleton.get_bone_pose_rotation(bone)))
			_check(angle > 0.25 and angle <= 90.1, "%s pinch angle" % hand)
			var settled := Dictionary(rig.create_report().get("visual_provider", {}))
			_check(int(settled.get("last_driven_bone_count", 0)) == 15, "%s driven bones" % hand)
			_check(float(settled.get("max_native_pose_angle_deg", 999.0)) <= 90.1, "%s max angle" % hand)
			diagnostics["hands"][hand] = {"open_index_angle_deg":open_angle,"pinch_index_angle_deg":angle,"root_scale":float(settled.get("root_calibration_scale",0.0)),"axes":_axes(provider)}
		host.remove_child(rig); rig.free()
	host.queue_free(); _done(true)

func _axes(provider) -> Array:
	var out: Array = []
	for pair in provider._pose_pairs:
		var curl := pair.get("curl_axis", Vector3.ZERO) as Vector3
		var opp := pair.get("opposition_axis", Vector3.ZERO) as Vector3
		out.append({"source":String(pair.get("source_name","")),"canonical":String(pair.get("canonical_name","")),"curl":[curl.x,curl.y,curl.z],"opposition":[opp.x,opp.y,opp.z],"curl_sign":float(pair.get("curl_sign",1.0)),"curl_scale":float(pair.get("curl_scale",1.0))})
	return out

func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures.append(label)

func _done(external: bool) -> void:
	print("FPE_WRAD_CALIBRATION_JSON:%s" % JSON.stringify(diagnostics))
	if failures.is_empty():
		print("FPE R2 S10 WRAD calibrated external probe: PASS (%d assertions, external_asset_present=%s)" % [assertions, str(external).to_lower()]); quit(0); return
	for failure in failures: push_error(failure)
	print("FPE R2 S10 WRAD calibrated external probe: FAIL (%d failures, %d assertions, external_asset_present=%s)" % [failures.size(), assertions, str(external).to_lower()]); quit(1)
