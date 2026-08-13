extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const EnvGradient = preload("res://scripts/research/ecology/plant_environmental_gradient_v1.gd")
var n := 0
var failed := false

func _init() -> void:
	var spatial := _spatial(0.2)
	ok(bool(Dispersal.validate_result(spatial).get("success", false)), "source P3.3 validates")
	var coords := [{"id":"C","x":4.0,"y":2.0,"altitude":200.0},{"id":"A","x":0.0,"y":0.0,"altitude":0.0},{"id":"B","x":2.0,"y":0.0,"altitude":100.0}]
	var cfg := _cfg()
	var r := EnvGradient.apply(spatial, coords, cfg)
	ok(bool(EnvGradient.validate_result(r).get("success", false)), "P3.4 validates")
	ok(String(r["parent_p3_3_candidate_aggregate"]) == EnvGradient.PARENT_P3_3_CANDIDATE_AGGREGATE, "P3.3 parent pinned")
	ok(String(r["spatial_result_hash"]) == String(spatial["result_hash"]), "source result pinned")
	ok(PackedStringArray(r["patch_order"]) == PackedStringArray(["A","B","C"]), "canonical patch order")
	var a: Dictionary = r["patches"][0]; var b: Dictionary = r["patches"][1]; var c: Dictionary = r["patches"][2]
	near(float(a["temperature_c"]),20.0,"A temp"); near(float(a["moisture"]),0.8,"A moisture"); near(float(a["light"]),0.4,"A light"); near(float(a["nutrients"]),0.9,"A nutrients")
	near(float(b["temperature_c"]),17.0,"B temp"); near(float(b["moisture"]),0.6,"B moisture"); near(float(b["light"]),0.6,"B light"); near(float(b["nutrients"]),0.75,"B nutrients")
	near(float(c["temperature_c"]),15.0,"C temp"); near(float(c["moisture"]),0.45,"C moisture"); near(float(c["light"]),0.85,"C light"); near(float(c["nutrients"]),0.55,"C nutrients")
	ok(not a.has("biome") and not a.has("biome_id"), "no discrete biome")
	near(float(a["resource_availability"]["water"]),0.8,"moisture maps to water")
	near(float(c["resource_availability"]["light"]),0.85,"light resource bridge")
	var mid := EnvGradient.sample_values({"id":"M","x":1.0,"y":0.0,"altitude":50.0},cfg)
	near(float(mid["temperature_c"]),18.5,"affine midpoint temp"); near(float(mid["moisture"]),0.7,"affine midpoint moisture"); near(float(mid["light"]),0.5,"affine midpoint light"); near(float(mid["nutrients"]),0.825,"affine midpoint nutrients")
	var tiny := EnvGradient.sample_values({"id":"T","x":0.001,"y":0.0,"altitude":0.0},cfg)
	near(float(tiny["temperature_c"]),19.999,"small delta temp"); near(float(tiny["moisture"]),0.79995,"small delta moisture")
	var shifted := cfg.duplicate(true); shifted["origin"]={"x":10.0,"y":20.0,"altitude":30.0}
	var sv := EnvGradient.sample_values({"id":"S","x":10.0,"y":20.0,"altitude":30.0},shifted)
	near(float(sv["temperature_c"]),20.0,"origin translation temp"); near(float(sv["moisture"]),0.8,"origin translation moisture")
	var clampv := EnvGradient.sample_values({"id":"X","x":100.0,"y":0.0,"altitude":0.0},cfg)
	near(float(clampv["temperature_c"]),-50.0,"temperature clamp"); near(float(clampv["moisture"]),0.0,"moisture clamp"); near(float(clampv["light"]),1.0,"light clamp"); near(float(clampv["nutrients"]),0.0,"nutrient clamp")
	var ab := _edge(r,"A","B"); near(float(ab["distance_xy"]),2.0,"edge distance"); near(float(ab["altitude_delta"]),100.0,"edge altitude"); near(float(ab["temperature_delta_c"]),-3.0,"edge temp delta"); near(float(ab["moisture_delta"]),-0.2,"edge moisture delta")
	var ac := _edge(r,"A","C"); near(float(ac["distance_xy"]),sqrt(20.0),"edge diagonal distance")
	var perm := EnvGradient.apply(spatial,[coords[1],coords[0],coords[2]],cfg); ok(String(perm.get("result_hash",""))==String(r["result_hash"]),"coordinate permutation independent")
	var repeat := EnvGradient.apply(spatial,coords,cfg); ok(String(repeat.get("result_hash",""))==String(r["result_hash"]),"repeat deterministic")
	var empty_spatial := Dispersal.disperse([],[],{"dispersal_fraction":0.2}); var empty := EnvGradient.apply(empty_spatial,[],cfg); ok(bool(EnvGradient.validate_result(empty).get("success",false)),"empty spatial valid"); ok(int(empty["summary"]["patch_count"])==0,"empty summary")
	ok(EnvGradient.apply(spatial,[coords[0],coords[1]],cfg).is_empty(),"missing coordinate fails")
	ok(EnvGradient.apply(spatial,[coords[0],coords[1],{"id":"A","x":3.0,"y":0.0,"altitude":0.0}],cfg).is_empty(),"duplicate coordinate fails")
	var badc := coords.duplicate(true); badc[0]["extra"]=1; ok(EnvGradient.apply(spatial,badc,cfg).is_empty(),"unexpected coordinate field fails")
	badc = coords.duplicate(true); badc[0]["id"]="UNKNOWN"; ok(EnvGradient.apply(spatial,badc,cfg).is_empty(),"unknown coordinate id fails")
	badc = coords.duplicate(true); badc[0]["x"]=INF; ok(EnvGradient.apply(spatial,badc,cfg).is_empty(),"non-finite coordinate fails")
	var badcfg := cfg.duplicate(true); badcfg["light"]["max"]=1.1; ok(EnvGradient.apply(spatial,coords,badcfg).is_empty(),"normalized bound fails")
	badcfg = cfg.duplicate(true); badcfg["extra"]=1; ok(EnvGradient.apply(spatial,coords,badcfg).is_empty(),"unexpected config field fails")
	badcfg = cfg.duplicate(true); badcfg["temperature_c"]["x_slope"]=INF; ok(EnvGradient.apply(spatial,coords,badcfg).is_empty(),"non-finite coefficient fails")
	var badspatial := spatial.duplicate(true); badspatial["result_hash"]="bad"; ok(EnvGradient.apply(badspatial,coords,cfg).is_empty(),"tampered P3.3 source fails")
	var tamper := r.duplicate(true); tamper["patches"][0]["temperature_c"] += 1.0; ok(not bool(EnvGradient.validate_result(tamper).get("success",false)),"tampered patch rejected")
	tamper=r.duplicate(true); tamper["edge_gradients"][0]["distance_xy"] += 1.0; ok(not bool(EnvGradient.validate_result(tamper).get("success",false)),"tampered edge rejected")
	tamper=r.duplicate(true); tamper["summary"]["moisture_max"] = 0.1; ok(not bool(EnvGradient.validate_result(tamper).get("success",false)),"tampered summary rejected")
	tamper=r.duplicate(true); tamper["parent_p3_3_candidate_aggregate"]="bad"; ok(not bool(EnvGradient.validate_result(tamper).get("success",false)),"tampered parent rejected")
	tamper=r.duplicate(true); tamper["spatial_result_hash"]="bad"; ok(not bool(EnvGradient.validate_result(tamper).get("success",false)),"tampered source hash rejected")
	seed(987654); var q1:=randi(); EnvGradient.apply(spatial,coords,cfg); var q2:=randi(); seed(987654); ok(q1==randi() and q2==randi(),"P3.4 consumes no global RNG")
	var aggregate := (String(r["result_hash"])+"|"+String(empty["result_hash"])+"|"+EnvGradient.PARENT_P3_3_CANDIDATE_AGGREGATE).sha256_text()
	if failed:
		print("ECO.P3.4 Environmental Gradient: FAIL")
		quit(1); return
	print("ECO.P3.4 Environmental Gradient: PASS (%d assertions)" % n)
	print("aggregate_hash="+aggregate); print("gradient_hash="+String(r["result_hash"])); print("empty_hash="+String(empty["result_hash"])); print("parent_p3_3="+EnvGradient.PARENT_P3_3_CANDIDATE_AGGREGATE); print("source_p3_3="+String(spatial["result_hash"]))
	quit(0)

func _cfg() -> Dictionary:
	return {"origin":{"x":0.0,"y":0.0,"altitude":0.0},"temperature_c":_ch(20.0,-1.0,0.5,-0.01,-50.0,50.0),"moisture":_ch(0.8,-0.05,0.025,-0.001,0.0,1.0),"light":_ch(0.4,0.05,0.025,0.001,0.0,1.0),"nutrients":_ch(0.9,-0.05,-0.025,-0.0005,0.0,1.0)}
func _ch(base:float,x:float,y:float,a:float,lo:float,hi:float)->Dictionary: return {"base":base,"x_slope":x,"y_slope":y,"altitude_slope":a,"min":lo,"max":hi}
func _spatial(f:float)->Dictionary:
	var pa:=_density([{"id":"alpha","biomass_kg":6.0},{"id":"beta","biomass_kg":4.0}],10.0); var pb:=_density([{"id":"beta","biomass_kg":2.0}],2.0); var pc:=_density([],10.0)
	return Dispersal.disperse([{"id":"C","density_result":pc,"boundary_export_fraction":0.0},{"id":"A","density_result":pa,"boundary_export_fraction":0.25},{"id":"B","density_result":pb,"boundary_export_fraction":0.0}],[{"from":"A","to":"C","weight":1.0},{"from":"A","to":"B","weight":3.0}],{"dispersal_fraction":f})
func _density(plants:Array,cap:float)->Dictionary:
	var cp:=[]; for p in plants: cp.append({"id":String(p["id"]),"demand":_res(1.0),"capture_efficiency":_res(1.0)})
	var c:=Competition.compete(_res(100.0),cp); return Density.step(c,{"area_m2":cap,"reference_capacity_kg_m2":1.0,"minimum_capacity_fraction":0.25,"max_recovery_fraction":0.25,"max_decline_fraction":0.6},plants)
func _res(v:float)->Dictionary: return {"light":v,"water":v,"nutrients":v}
func _edge(r:Dictionary,a:String,b:String)->Dictionary:
	for e in r["edge_gradients"]:
		if e["from"]==a and e["to"]==b: return e
	return {}
func ok(v:bool,msg:String)->void:
	if not v:
		failed = true; push_error("FAIL: "+msg); return
	n+=1
func near(a:float,b:float,msg:String)->void: ok(absf(a-b)<=0.000000001,msg+" actual="+str(a)+" expected="+str(b))
