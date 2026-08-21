extends SceneTree
const Competition = preload("res://scripts/research/ecology/plant_strategy_competition_baseline_v1.gd")
const EXPECTED_RESULT_HASH := "cf3bd5f417c9a49dd1c5eac0d93ea736b02ec0be25afd4945b1424a8dbde3928"
const EXPECTED_UNIFORM_HASH := "1c5128666314dfeec9ed09094931be58e76253f92bf9da50379a91eeb3b68a58"
const EXPECTED_ALT_HASH := "bded62e12ade0285c019d0dc2e4f77d0d6cb88431df7ade605160e0f18d82f8c"
const EXPECTED_POOL_HASH := "77acaada39a39c54224b73f2548ebc228343e869264e45780d08419ebb6bee38"
var assertions := 0
var failures: Array[String] = []
func _init() -> void:
 var r=Competition.run(); var u=Competition.run(Competition.DEFAULT_GRID_SIZE,Competition.DEFAULT_FOUNDER_COUNT,Competition.DEFAULT_WINNERS_PER_PATCH,Competition.DEFAULT_EVALUATION_SEASONS,Competition.DEFAULT_FOUNDER_SEED,true); var a=Competition.run(Competition.DEFAULT_GRID_SIZE,Competition.DEFAULT_FOUNDER_COUNT,Competition.DEFAULT_WINNERS_PER_PATCH,Competition.DEFAULT_EVALUATION_SEASONS,Competition.ALT_FOUNDER_SEED,false)
 _check(String(r.get("result_hash",""))==EXPECTED_RESULT_HASH,"default restart hash")
 _check(String(u.get("result_hash",""))==EXPECTED_UNIFORM_HASH,"uniform restart hash")
 _check(String(a.get("result_hash",""))==EXPECTED_ALT_HASH,"alternate restart hash")
 _check(String(r.get("founder_pool_hash",""))==EXPECTED_POOL_HASH,"founder pool restart hash")
 _check(String(r.get("founder_pool_hash",""))==String(u.get("founder_pool_hash","")),"default/control share pool after restart")
 if failures.is_empty(): print("ECO.P1C-S1 Restart Replay: PASS (%d assertions) result=%s uniform=%s alt=%s pool=%s" % [assertions,EXPECTED_RESULT_HASH,EXPECTED_UNIFORM_HASH,EXPECTED_ALT_HASH,EXPECTED_POOL_HASH]); quit(0); return
 for f in failures: push_error("ECO.P1C-S1 RESTART FAIL: %s" % f)
 quit(1)
func _check(c:bool,l:String): assertions+=1; failures.append(l) if not c else null
