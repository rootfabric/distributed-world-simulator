extends SceneTree
const Gate = preload("res://scripts/research/ecology/plant_competition_robustness_gate_v1.gd")
const EXPECTED_DYNAMIC := "57881819ca113ace9bec0ae8c5a66a9a45d4164069bbf506c462bb29cd82d20f"
const EXPECTED_DIAGNOSTIC := "e3202b0afd3fb746ee6bd36b76a88b22e1957e070f4c5f6728b9849eaeb39f94"
const EXPECTED_CASE := "431c4b6c0683b692c9fe88fbc912f49c3659db122c8fdf2715f525ea712dc43b"
func _init()->void:
	var r:=Gate.run_case(1138701,18,false)
	var failures:=0; var assertions:=6
	if r.is_empty(): failures+=1
	if String(r.get("dynamic_result_hash","")) != EXPECTED_DYNAMIC: failures+=1
	if String(r.get("diagnostic_hash","")) != EXPECTED_DIAGNOSTIC: failures+=1
	if String(r.get("case_hash","")) != EXPECTED_CASE: failures+=1
	if String(r.get("failure_matrix",{}).get("GLOBAL_TAKEOVER","")) != "PASS": failures+=1
	if int(r.get("effective_founders_1pct",0)) != 17: failures+=1
	if failures==0:
		print("ECO.P1C-S4 Restart Replay: PASS (%d assertions) case=%s" % [assertions,EXPECTED_CASE]); quit(0); return
	push_error("ECO.P1C-S4 Restart Replay: FAIL (%d/%d)" % [failures,assertions]); quit(1)
