extends SceneTree

const Env = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_recruitment_traits_v1.gd")
const Divergence = preload("res://scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd")
const Bake = preload("res://scripts/research/ecology/plant_evolution_bake_export_v1.gd")
const Transfer = preload("res://scripts/research/ecology/plant_frozen_catalog_transfer_v1.gd")
const Matrix = preload("res://scripts/research/ecology/plant_environment_generalization_matrix_v1.gd")

const FINAL_YEAR := 12
const SOURCE_RUN_HASH := "d44a160531d7f49cd0d0018a1fa8cb55d6be8ebf8157e5cb555232b8dd0fb337"
var assertions := 0
var failed := false

func _init() -> void:
	var bake := _bake()
	_check(not bake.is_empty() and Bake.validate_export(bake), "accepted E2.2 fixture validates")
	_check(String(bake.get("bake_hash", "")) == Transfer.ACCEPTED_E2_2_BAKE_HASH, "E2.2 bake pinned")
	_check(String(bake.get("catalog_hash", "")) == Transfer.ACCEPTED_E2_2_CATALOG_HASH, "E2.2 catalog pinned")
	_check(Matrix.PARENT_E2_3_ACCEPTED_AGGREGATE == "82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8", "E2.3 aggregate pinned")
	_check(Matrix.PARENT_E2_3_CODE_UNDER_TEST == "c7ee41371807ed7dbb75e7e1eae1587105873a26", "E2.3 code head pinned")

	var plan := Matrix.default_plan()
	_check(not plan.is_empty() and Matrix.validate_plan(plan), "default matrix plan valid")
	_check(_cell_ids(plan) == Matrix.CELL_ORDER and Array(plan["cells"]).size() == 6, "exact six canonical cells")
	_check(_phase_ids(plan, "HIGH_SEASONALITY") == Matrix.SEASONAL_PHASES, "seasonal phases canonical")
	_check(_phase_inputs(_cell(plan, "HIGH_SEASONALITY")).size() == 4, "seasonality uses four envelope phases")
	_check(_seasonal_patch_ids(plan) == ["target/e24-high-seasonality"], "seasonal envelope keeps one patch identity")
	_check(not Matrix.CONTINUOUS_SEASONAL_DYNAMICS_CLAIMED, "no continuous seasonality claim")
	_check(_checksum(plan, "NEAR_SOURCE", "STATIC") == _checksum(plan, "PATCH_ISOLATED", "STATIC"), "isolation control uses identical environment")
	_check(_bounds(plan, "NEAR_SOURCE", "STATIC") != _bounds(plan, "PATCH_ISOLATED", "STATIC"), "isolation control differs geographically")
	_check(_unique(_seasonal_checksums(plan)) == 4, "seasonal environments distinct")

	var reversed: Array = []
	for v in Array(plan["cells"]):
		var c: Dictionary = v
		var phases := _phase_inputs(c); phases.reverse()
		reversed.append({"cell_id":c["cell_id"],"mode":c["mode"],"expected_reachability":c["expected_reachability"],"phases":phases})
	reversed.reverse()
	_check(Matrix.create_plan(reversed) == plan, "input ordering canonicalizes")

	var before_bake := bake.duplicate(true); var before_plan := plan.duplicate(true)
	seed(24042404); var expected_rng := [randi(),randi(),randi(),randi()]
	seed(24042404); var result := Matrix.run(bake, plan); var actual_rng := [randi(),randi(),randi(),randi()]
	_check(not result.is_empty(), "matrix executes")
	_check(actual_rng == expected_rng, "matrix consumes no global RNG")
	_check(Matrix.validate_result(bake, result), "matrix deterministic replay validates")
	_check(bake == before_bake and plan == before_plan, "inputs not mutated")
	_check(String(result["e2_2_bake_hash"]) == Transfer.ACCEPTED_E2_2_BAKE_HASH and String(result["catalog_hash"]) == Transfer.ACCEPTED_E2_2_CATALOG_HASH, "one frozen artifact retained")
	_check(String(result["matrix_hash"]).length() == 64 and String(result["plan_hash"]) == String(plan["plan_hash"]), "matrix binds canonical plan/hash")

	for cell_id in Matrix.CELL_ORDER:
		var c := _cell_result(result, cell_id)
		_check(not c.is_empty() and String(c["cell_id"]) == cell_id, cell_id + " result present")
		for pv in Array(c["phase_results"]):
			var p: Dictionary = pv; var tr: Dictionary = p["transfer_result"]
			_check(String(tr["catalog_hash"]) == Transfer.ACCEPTED_E2_2_CATALOG_HASH, cell_id + "/" + String(p["phase_id"]) + " same catalog")
			_check(not bool(tr["evolution_enabled"]) and not bool(tr["canonical_species_declared"]) and not bool(tr["production_authority_claimed"]), cell_id + "/" + String(p["phase_id"]) + " frozen research authority")
			_check(_target_empty(tr, String(p["patch_id"])), cell_id + "/" + String(p["phase_id"]) + " starts empty")
			_check(String(p["target_hash"]).length() == 64 and String(p["final_population_state_hash"]).length() == 64 and String(p["transfer_result_hash"]).length() == 64, cell_id + "/" + String(p["phase_id"]) + " hashes valid")

	var near := _phase_result(result,"NEAR_SOURCE","STATIC"); var dry := _phase_result(result,"DRY","STATIC")
	var wet := _phase_result(result,"WET","STATIC"); var poor := _phase_result(result,"NUTRIENT_POOR","STATIC")
	var isolated := _phase_result(result,"PATCH_ISOLATED","STATIC")
	_check(String(near["colonization_status"]) == "COLONIZED" and int(near["first_colonization_year"]) > 0, "near-source colonizes causally")
	_check(String(isolated["colonization_status"]) == "VALID_NO_COLONIZATION" and int(isolated["first_colonization_year"]) == -1, "isolated control validly does not colonize")
	_check(String(near["environment_checksum"]) == String(isolated["environment_checksum"]) and String(near["transfer_result_hash"]) != String(isolated["transfer_result_hash"]), "geography changes equal-suitability outcome")
	_check(_valid(dry) and _valid(wet) and _valid(poor), "dry/wet/nutrient-poor execute validly")
	_check(_unique([near["final_population_state_hash"],dry["final_population_state_hash"],wet["final_population_state_hash"],poor["final_population_state_hash"]]) >= 2, "environment challenges change population state")
	_check(_unique([near["transfer_result_hash"],dry["transfer_result_hash"],wet["transfer_result_hash"],poor["transfer_result_hash"]]) >= 3, "environment challenges change causal histories")
	var seasonal := Array(_cell_result(result,"HIGH_SEASONALITY")["phase_results"])
	_check(seasonal.size() == 4 and _unique_phase_state(seasonal) >= 2, "seasonal envelope yields distinct states")
	for pv in seasonal: _check(_valid(Dictionary(pv)), "seasonal phase valid: " + String(Dictionary(pv)["phase_id"]))

	var bad_plan := plan.duplicate(true); bad_plan["plan_hash"] = "0".repeat(64)
	_check(not Matrix.validate_plan(bad_plan) and Matrix.run(bake,bad_plan).is_empty(), "plan tamper fails closed")
	var duplicate := _plan_inputs(plan); duplicate[5]["cell_id"] = "NEAR_SOURCE"
	_check(Matrix.create_plan(duplicate).is_empty(), "duplicate/missing cell fails closed")
	var incomplete := _plan_inputs(plan); Array(incomplete[4]["phases"]).pop_back()
	_check(Matrix.create_plan(incomplete).is_empty(), "incomplete seasonal envelope fails closed")
	var bad_bake := bake.duplicate(true); bad_bake["bake_hash"] = "0".repeat(64)
	_check(Matrix.run(bad_bake,plan).is_empty(), "tampered bake fails closed")

	var tampered := result.duplicate(true); var cells: Array = tampered["cells"]; var c0: Dictionary = cells[0]; var ps: Array = c0["phase_results"]; var p0: Dictionary = ps[0]
	p0["colonization_status"] = "VALID_NO_COLONIZATION"; p0["phase_result_hash"] = Matrix._phase_result_hash(p0); ps[0] = p0
	c0["phase_results"] = ps; c0["cell_result_hash"] = Matrix._cell_result_hash(c0); cells[0] = c0; tampered["cells"] = cells; tampered["matrix_hash"] = Matrix.compute_matrix_hash(tampered)
	_check(not Matrix.validate_result(bake,tampered), "fully rehashed result tamper rejected by replay")

	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_environment_generalization_matrix_v1.gd")
	_check(source.find("plant_mutation") == -1 and source.find("mutation_kernel") == -1, "no mutation path")
	_check(source.find("biome") == -1 and source.find("species_table") == -1, "no biome species table")
	_check(source.find("Transfer.transfer") >= 0 and source.find("SEASONAL_ENVELOPE") >= 0, "accepted transfer reused and seasonality bounded")

	if failed: quit(1); return
	print("ECO.EVO2 E2.4 Environment Generalization Matrix: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + String(result["matrix_hash"])); print("plan_hash=" + String(result["plan_hash"])); print("parent_e2_3=" + Matrix.PARENT_E2_3_ACCEPTED_AGGREGATE); print("parent_e2_3_head=" + Matrix.PARENT_E2_3_CODE_UNDER_TEST)
	print("bake_hash=" + String(result["e2_2_bake_hash"])); print("catalog_hash=" + String(result["catalog_hash"]))
	for cell_id in Matrix.CELL_ORDER:
		var c := _cell_result(result,cell_id); print("cell_%s_hash=%s" % [cell_id.to_lower(),String(c["cell_result_hash"])])
		for pv in Array(c["phase_results"]):
			var p: Dictionary = pv; print("phase_%s_%s=%s|%s|%s" % [cell_id.to_lower(),String(p["phase_id"]).to_lower(),String(p["colonization_status"]),str(int(p["first_colonization_year"])),String(p["transfer_result_hash"])])
	quit(0)

func _bake() -> Dictionary:
	var ga0 := Genome.create("genome/e22-alpha-early",1.2,0.48,1.4,0.38,0.22,0.62,140,14.0,8.0); var ga1 := Genome.create("genome/e22-alpha-late",1.5,0.54,1.7,0.34,0.25,0.65,130,16.0,8.5)
	var gb := Genome.create("genome/e22-beta",0.8,0.72,0.6,0.70,0.28,0.28,360,28.0,3.0); var go := Genome.create("genome/e22-other",2.3,0.60,2.2,0.50,0.32,0.48,180,20.0,10.0)
	var ta := Traits.create("recruit/e22-alpha",0.38,4.5); var tb := Traits.create("recruit/e22-beta",0.18,1.8); var to := Traits.create("recruit/e22-other",0.30,3.0)
	var rows := [
		_lineage("eco-lineage/e22-alpha",[_obs("eco-lineage/e22-alpha",["eco-lineage/e22-root","eco-lineage/e22-alpha"],2,12,ga1,ta,"patch/alpha"),_obs("eco-lineage/e22-alpha",["eco-lineage/e22-root","eco-lineage/e22-alpha"],2,8,ga0,ta,"patch/alpha")],[1,2,2,2,3,3,3,4]),
		_lineage("eco-lineage/e22-beta",[_obs("eco-lineage/e22-beta",["eco-lineage/e22-root","eco-lineage/e22-beta"],1,12,gb,tb,"patch/beta")],[0,1,1,1,1,2,2,2]),
		_lineage("eco-lineage/e22-extinct",[_obs("eco-lineage/e22-extinct",["eco-lineage/e22-root","eco-lineage/e22-extinct"],1,12,go,to,"patch/extinct")],[1,1,1,1,1,1,1,0]),
		_lineage("eco-lineage/e22-transient",[_obs("eco-lineage/e22-transient",["eco-lineage/e22-root","eco-lineage/e22-transient"],1,12,go,to,"patch/transient")],[0,0,0,1,0,1,1,1]),
		_lineage("eco-lineage/e22-recent",[_obs("eco-lineage/e22-recent",["eco-lineage/e22-root","eco-lineage/e22-recent"],8,12,go,to,"patch/recent")],[0,0,0,0,1,1,1,1]),
		_lineage("eco-lineage/e22-stale",[_obs("eco-lineage/e22-stale",["eco-lineage/e22-root","eco-lineage/e22-stale"],1,9,go,to,"patch/stale")],[1,1,1,1,1,1,1,1])]
	var source := Bake.create_source(rows,FINAL_YEAR,SOURCE_RUN_HASH); return Bake.export_catalog(source) if not source.is_empty() else {}

func _lineage(id:String, observations:Array, counts:Array) -> Dictionary:
	var h:Array=[]; var start:=FINAL_YEAR-Bake.WINDOW_YEARS+1
	for i in range(counts.size()): h.append({"year":start+i,"occupied_patch_count":int(counts[i])})
	return {"lineage_id":id,"observations":observations.duplicate(true),"occupancy_history":h}

func _obs(id:String, ancestry:Array, split:int, end:int, genome:Dictionary, traits:Dictionary, patch:String) -> Dictionary:
	var geo:Array=[]; var eco:Array=[]
	for y in range(split+1,end+1): geo.append({"year":y,"patch_ids":[patch]}); eco.append({"year":y,"environment":Env.create(float(y),float(-y),10.0+float(y)*0.2,0.45,0.75,0.62,0.02,22000+y,"e22-fixture")})
	return Divergence.create_observation(id,ancestry,split,genome,traits,geo,eco)

func _phase_inputs(c:Dictionary)->Array:
	var a:Array=[]
	for v in Array(c.get("phases",[])):
		var p:Dictionary=v; a.append({"phase_id":p["phase_id"],"patch_id":p["patch_id"],"bounds":p["bounds"],"environment":Dictionary(p["environment"]).duplicate(true),"transport_schedule":Array(p["transport_schedule"]).duplicate(true)})
	return a
func _plan_inputs(plan:Dictionary)->Array:
	var a:Array=[]
	for v in Array(plan["cells"]): var c:Dictionary=v; a.append({"cell_id":c["cell_id"],"mode":c["mode"],"expected_reachability":c["expected_reachability"],"phases":_phase_inputs(c)})
	return a
func _cell_ids(plan:Dictionary)->Array[String]:
	var a:Array[String]=[]
	for v in Array(plan.get("cells",[])):
		a.append(String(Dictionary(v).get("cell_id","")))
	return a
func _cell(plan:Dictionary,id:String)->Dictionary:
	for v in Array(plan.get("cells",[])):
		var c:Dictionary=v
		if String(c.get("cell_id",""))==id:
			return c
	return {}
func _phase(plan:Dictionary,cid:String,pid:String)->Dictionary:
	for v in Array(_cell(plan,cid).get("phases",[])):
		var p:Dictionary=v
		if String(p.get("phase_id",""))==pid:
			return p
	return {}
func _phase_ids(plan:Dictionary,cid:String)->Array[String]:
	var a:Array[String]=[]
	for v in Array(_cell(plan,cid).get("phases",[])):
		a.append(String(Dictionary(v).get("phase_id","")))
	return a
func _checksum(plan:Dictionary,cid:String,pid:String)->String:
	return String(Dictionary(_phase(plan,cid,pid).get("environment",{})).get("checksum",""))
func _bounds(plan:Dictionary,cid:String,pid:String)->Rect2:
	return Rect2(_phase(plan,cid,pid).get("bounds",Rect2()))
func _seasonal_patch_ids(plan:Dictionary)->Array[String]:
	var seen:={}
	for v in Array(_cell(plan,"HIGH_SEASONALITY").get("phases",[])):
		seen[String(Dictionary(v).get("patch_id",""))]=true
	var a:Array[String]=[]
	for k in seen.keys():
		a.append(String(k))
	a.sort()
	return a
func _seasonal_checksums(plan:Dictionary)->Array:
	var a:Array=[]
	for v in Array(_cell(plan,"HIGH_SEASONALITY").get("phases",[])):
		a.append(String(Dictionary(Dictionary(v).get("environment",{})).get("checksum","")))
	return a
func _cell_result(result:Dictionary,id:String)->Dictionary:
	for v in Array(result.get("cells",[])):
		var c:Dictionary=v
		if String(c.get("cell_id",""))==id:
			return c
	return {}
func _phase_result(result:Dictionary,cid:String,pid:String)->Dictionary:
	for v in Array(_cell_result(result,cid).get("phase_results",[])):
		var p:Dictionary=v
		if String(p.get("phase_id",""))==pid:
			return p
	return {}
func _target_empty(tr:Dictionary,pid:String)->bool:
	var h:Array=tr.get("history",[])
	if h.is_empty():
		return false
	for v in Array(Dictionary(h[0]).get("patch_summaries",[])):
		var p:Dictionary=v
		if String(p.get("patch_id",""))==pid:
			return float(p.get("total_adult_biomass_kg_m2",-1.0))==0.0 and int(p.get("total_seed_bank_seed_count",-1))==0
	return false
func _valid(p:Dictionary)->bool:
	var status:=String(p.get("colonization_status",""))
	return (status=="COLONIZED" and int(p.get("first_colonization_year",-1))>0) or (status=="VALID_NO_COLONIZATION" and int(p.get("first_colonization_year",0))==-1)
func _unique(values:Array)->int:
	var seen:={}
	for v in values:
		seen[String(v)]=true
	return seen.size()
func _unique_phase_state(values:Array)->int:
	var a:Array=[]
	for v in values:
		var p:Dictionary=v
		a.append(String(p.get("colonization_status",""))+"|"+String(p.get("final_population_state_hash","")))
	return _unique(a)
func _check(ok:bool,label:String)->void:
	assertions+=1
	if not ok:failed=true;push_error("ECO.EVO2 E2.4 assertion failed: "+label)
