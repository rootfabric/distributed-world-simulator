extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const EnvGradient = preload("res://scripts/research/ecology/plant_environmental_gradient_v1.gd")
const Seasonal = preload("res://scripts/research/ecology/plant_seasonal_world_v1.gd")
const Disturbance = preload("res://scripts/research/ecology/plant_disturbance_succession_v1.gd")
const Coexistence = preload("res://scripts/research/ecology/plant_multi_niche_coexistence_v1.gd")

var assertions:=0
var failed:=false

func _init()->void:
	var parent := _disturbance_result()
	_check(bool(Disturbance.validate_result(parent).get("success",false)),"P3.6 source validates")
	var parent_before:=parent.duplicate(true)
	var niches:=_niches()
	var community:=Coexistence.community_from_parent(parent,niches)
	_check(community.size()==3,"initial community built for all patches")
	var skewed:=_skew_community(community,0.05,0.95)
	var result:=Coexistence.step(parent,skewed,niches,{"stabilization_fraction":0.5})
	_check(bool(Coexistence.validate_result(result).get("success",false)),"P3.7 differentiated niche step validates")
	_check(parent==parent_before,"P3.7 does not mutate P3.6 source")
	_check(String(result.get("disturbance_result_hash",""))==String(parent.get("result_hash","")),"exact P3.6 source hash embedded")
	_check(PackedStringArray(result["niche_order"])==PackedStringArray(["alpha","beta"]),"canonical niche order")
	var a:=_patch(result,"A"); var c:=_patch(result,"C")
	_check(float(_plant(a,"alpha")["target_share"]) > float(_plant(a,"beta")["target_share"]),"A environment favours alpha niche")
	_check(float(_plant(c,"beta")["target_share"]) > float(_plant(c,"alpha")["target_share"]),"C environment favours beta niche")
	_check(float(_plant(a,"alpha")["delta_biomass_kg"]) > 0.0,"rare alpha increases in its favourable niche")
	_check(float(_plant(c,"beta")["delta_biomass_kg"]) < 0.0 or float(_plant(c,"beta")["target_share"]) < 0.95,"overrepresented beta is pulled toward environmental target")
	_check(float(result["summary"]["distance_to_target_after"]) < float(result["summary"]["distance_to_target_before"]),"negative frequency feedback reduces target distance")
	_near(float(result["summary"]["conservation_error_kg"]),0.0,"biomass conserved")
	_check(int(result["summary"]["active_lineages_next"])==2,"both lineages remain regionally active")
	_check(int(result["summary"]["multi_niche_patches"])>=2,"multiple patches support more than one niche")

	var current:=skewed
	var previous_distance:=INF
	for step_index in range(12):
		var iteration:=Coexistence.step(parent,current,niches,{"stabilization_fraction":0.5})
		_check(bool(Coexistence.validate_result(iteration).get("success",false)),"iterative coexistence step validates %d"%step_index)
		var distance:=float(iteration["summary"]["distance_to_target_after"])
		_check(distance <= previous_distance + 1e-9,"distance converges monotonically %d"%step_index)
		previous_distance=distance
		current=iteration["next_community"]
	_check(previous_distance < 0.001,"repeated steps converge close to niche fixed point")
	var stable:=Coexistence.step(parent,current,niches,{"stabilization_fraction":0.5})
	_check(int(stable["summary"]["active_lineages_next"])==2,"stable regional coexistence survives convergence")

	var full:=Coexistence.step(parent,skewed,niches,{"stabilization_fraction":1.0})
	_near(float(full["summary"]["distance_to_target_after"]),0.0,"full stabilization reaches exact niche target")
	var fixed:=Coexistence.step(parent,full["next_community"],niches,{"stabilization_fraction":0.5})
	_near(float(fixed["summary"]["distance_to_target_before"]),0.0,"target state is a fixed point")
	_near(float(fixed["summary"]["distance_to_target_after"]),0.0,"fixed point remains stable")
	var no_change:=Coexistence.step(parent,skewed,niches,{"stabilization_fraction":0.0})
	_check(_community_equal(no_change["next_community"],no_change["input_community"]),"zero stabilization leaves community unchanged")

	var permuted_niches:=[niches[1],niches[0]]
	var permuted:=Coexistence.step(parent,skewed,permuted_niches,{"stabilization_fraction":0.5})
	_check(String(permuted.get("result_hash",""))==String(result.get("result_hash","")),"niche input order non-semantic")
	var permuted_community:=_reverse_inputs(skewed)
	var permuted_community_result:=Coexistence.step(parent,permuted_community,niches,{"stabilization_fraction":0.5})
	_check(String(permuted_community_result.get("result_hash",""))==String(result.get("result_hash","")),"community input order non-semantic")

	var symmetric:=_symmetric_niches()
	var symmetric_result:=Coexistence.step(parent,skewed,symmetric,{"stabilization_fraction":1.0})
	for patch_value in symmetric_result["patches"]:
		var patch:Dictionary=patch_value
		_near(float(_plant(patch,"alpha")["target_share"]),0.5,"symmetric niches do not create lexical winner alpha")
		_near(float(_plant(patch,"beta")["target_share"]),0.5,"symmetric niches do not create lexical winner beta")

	seed(999); var rng_before:=[randi(),randi(),randi()]
	seed(999); Coexistence.step(parent,skewed,niches,{"stabilization_fraction":0.5}); var rng_after:=[randi(),randi(),randi()]
	_check(rng_before==rng_after,"P3.7 consumes no global RNG")

	_check(Coexistence.step(parent,skewed,niches,{"stabilization_fraction":1.1}).is_empty(),"invalid stabilization fails closed")
	var bad_niches:=niches.duplicate(true); bad_niches[0]["temperature_breadth_c"]=0.0
	_check(Coexistence.step(parent,skewed,bad_niches,{"stabilization_fraction":0.5}).is_empty(),"zero niche breadth fails closed")
	bad_niches=niches.duplicate(true); bad_niches[0]["moisture_optimum"]=1.1
	_check(Coexistence.step(parent,skewed,bad_niches,{"stabilization_fraction":0.5}).is_empty(),"normalized optimum out of range fails closed")
	bad_niches=[niches[0],niches[0]]
	_check(Coexistence.step(parent,skewed,bad_niches,{"stabilization_fraction":0.5}).is_empty(),"duplicate niche IDs fail closed")
	var bad_community:=skewed.duplicate(true); bad_community[0]["plants"][0]["biomass_kg"]+=1.0
	_check(Coexistence.step(parent,bad_community,niches,{"stabilization_fraction":0.5}).is_empty(),"community total mismatch fails closed")
	var tampered_parent:=parent.duplicate(true); tampered_parent["result_hash"]="bad"
	_check(Coexistence.step(tampered_parent,skewed,niches,{"stabilization_fraction":0.5}).is_empty(),"tampered P3.6 parent fails closed")
	var tampered:=result.duplicate(true); tampered["patches"][0]["plants"][0]["next_biomass_kg"]+=0.1
	_check(not bool(Coexistence.validate_result(tampered).get("success",false)),"tampered plant record rejected")
	tampered=result.duplicate(true); tampered["next_community"][0]["plants"][0]["biomass_kg"]+=0.1
	_check(not bool(Coexistence.validate_result(tampered).get("success",false)),"tampered next community rejected")
	tampered=result.duplicate(true); tampered["summary"]["active_lineages_next"]=1
	_check(not bool(Coexistence.validate_result(tampered).get("success",false)),"tampered coexistence summary rejected")

	var empty_parent:=_empty_disturbance()
	var empty:=Coexistence.step(empty_parent,[],[],{"stabilization_fraction":0.5})
	_check(bool(Coexistence.validate_result(empty).get("success",false)),"empty ecosystem remains valid")
	_check(int(empty["summary"]["lineage_count"])==0,"empty niche summary")

	var aggregate:=(String(result["result_hash"])+"\n"+String(full["result_hash"])+"\n"+String(symmetric_result["result_hash"])+"\n"+String(empty["result_hash"])).sha256_text()
	if failed: quit(1); return
	print("ECO.P3.7 Multi-Niche / Stable Coexistence: PASS (%d assertions)"%assertions)
	print("aggregate_hash="+aggregate)
	print("coexistence_hash="+String(result["result_hash"]))
	print("equilibrium_hash="+String(full["result_hash"]))
	print("symmetric_hash="+String(symmetric_result["result_hash"]))
	print("parent_p3_6="+Coexistence.PARENT_P3_6_CANDIDATE_AGGREGATE)
	print("source_p3_6="+String(parent["result_hash"]))
	quit(0)

func _niches()->Array:
	return [
		{"id":"alpha","temperature_optimum_c":10.0,"temperature_breadth_c":12.0,"moisture_optimum":0.8,"moisture_breadth":0.5,"light_optimum":0.5,"light_breadth":0.5,"nutrients_optimum":0.9,"nutrients_breadth":0.7},
		{"id":"beta","temperature_optimum_c":15.0,"temperature_breadth_c":12.0,"moisture_optimum":0.65,"moisture_breadth":0.5,"light_optimum":0.85,"light_breadth":0.5,"nutrients_optimum":0.4,"nutrients_breadth":0.7},
	]
func _symmetric_niches()->Array:
	var a:Dictionary=_niches()[0].duplicate(true); var b:Dictionary=a.duplicate(true); b["id"]="beta"; return [a,b]

func _skew_community(base:Array,alpha_share:float,beta_share:float)->Array:
	var out:=[]
	for patch_value in base:
		var patch:Dictionary=patch_value; var total:=0.0
		for p in patch["plants"]: total+=float(p["biomass_kg"])
		out.append({"id":String(patch["id"]),"plant_order":PackedStringArray(["alpha","beta"]),"plants":[{"id":"alpha","biomass_kg":total*alpha_share},{"id":"beta","biomass_kg":total*beta_share}]})
	return out
func _reverse_inputs(base:Array)->Array:
	var out:=[]
	for i in range(base.size()-1,-1,-1):
		var patch:Dictionary=base[i]; out.append({"id":String(patch["id"]),"plant_order":PackedStringArray(["beta","alpha"]),"plants":[Dictionary(patch["plants"][1]).duplicate(true),Dictionary(patch["plants"][0]).duplicate(true)]})
	return out
func _community_equal(a:Array,b:Array)->bool: return a==b

func _disturbance_result()->Dictionary:
	return Disturbance.apply(_seasonal(0.0),_disturbance(0.8,1.0,0.0,0.0),_traits(),2.0)
func _empty_disturbance()->Dictionary:
	var spatial:=Dispersal.disperse([],[],{"dispersal_fraction":0.2}); var env:=EnvGradient.apply(spatial,[],_environment_config()); var season:=Seasonal.evaluate(env,0.0,_season_config()); return Disturbance.apply(season,_disturbance(0.8,1.0,1.0,1.0),[],2.0)
func _traits()->Array: return [{"id":"alpha","heat_resistance":0.9,"flood_resistance":0.2,"drought_resistance":0.2,"recovery_rate":0.4,"pioneer_capacity":0.2},{"id":"beta","heat_resistance":0.2,"flood_resistance":0.8,"drought_resistance":0.8,"recovery_rate":0.9,"pioneer_capacity":0.9}]
func _disturbance(s:float,h:float,f:float,d:float)->Dictionary:return {"severity":s,"heat_pressure":h,"flood_pressure":f,"drought_pressure":d,"recovery_time_scale_years":2.0}
func _seasonal(t:float)->Dictionary:return Seasonal.evaluate(_environment(),t,_season_config())
func _season_config()->Dictionary:return {"cycle":{"period_years":1.0,"epoch_year":0.0,"phase_x_slope":0.0,"phase_y_slope":0.125,"phase_altitude_slope":0.0},"temperature_c":{"amplitude":10.0,"phase_offset":0.0},"moisture":{"amplitude":0.2,"phase_offset":0.25},"light":{"amplitude":0.1,"phase_offset":0.5},"nutrients":{"amplitude":0.15,"phase_offset":0.75}}
func _environment()->Dictionary:return EnvGradient.apply(_spatial(0.2),[{"id":"C","x":4.0,"y":2.0,"altitude":200.0},{"id":"A","x":0.0,"y":0.0,"altitude":0.0},{"id":"B","x":2.0,"y":0.0,"altitude":100.0}],_environment_config())
func _environment_config()->Dictionary:return {"origin":{"x":0.0,"y":0.0,"altitude":0.0},"temperature_c":_channel(20.0,-1.0,0.5,-0.01,-50.0,50.0),"moisture":_channel(0.8,-0.05,0.025,-0.001,0.0,1.0),"light":_channel(0.4,0.05,0.025,0.001,0.0,1.0),"nutrients":_channel(0.9,-0.05,-0.025,-0.0005,0.0,1.0)}
func _channel(b:float,x:float,y:float,z:float,mn:float,mx:float)->Dictionary:return {"base":b,"x_slope":x,"y_slope":y,"altitude_slope":z,"min":mn,"max":mx}
func _spatial(f:float)->Dictionary:
	var a:=_density([{"id":"alpha","biomass_kg":6.0},{"id":"beta","biomass_kg":4.0}],10.0); var b:=_density([{"id":"beta","biomass_kg":2.0}],2.0); var c:=_density([],10.0)
	return Dispersal.disperse([{"id":"C","density_result":c,"boundary_export_fraction":0.0},{"id":"A","density_result":a,"boundary_export_fraction":0.25},{"id":"B","density_result":b,"boundary_export_fraction":0.0}],[{"from":"A","to":"C","weight":1.0},{"from":"A","to":"B","weight":3.0}],{"dispersal_fraction":f})
func _density(plants:Array,capacity:float)->Dictionary:
	var cp:=[]; for p in plants:cp.append({"id":String(p["id"]),"demand":_resources(1.0),"capture_efficiency":_resources(1.0)})
	return Density.step(Competition.compete(_resources(100.0),cp),{"area_m2":capacity,"reference_capacity_kg_m2":1.0,"minimum_capacity_fraction":0.25,"max_recovery_fraction":0.25,"max_decline_fraction":0.6},plants)
func _resources(v:float)->Dictionary:return {"light":v,"water":v,"nutrients":v}
func _patch(result:Dictionary,id:String)->Dictionary:
	for value in result.get("patches",[]):
		if typeof(value)==TYPE_DICTIONARY and String(value.get("id",""))==id:return value
	return {}
func _plant(patch:Dictionary,id:String)->Dictionary:
	for value in patch.get("plants",[]):
		if typeof(value)==TYPE_DICTIONARY and String(value.get("id",""))==id:return value
	return {}
func _check(c:bool,m:String)->void:
	if not c:failed=true;push_error("FAIL: "+m);return
	assertions+=1
func _near(a:float,e:float,m:String)->void:_check(absf(a-e)<=1e-9,m+" actual="+str(a)+" expected="+str(e))
