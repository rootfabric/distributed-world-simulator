extends RefCounted

const Seasonal = preload("res://scripts/research/ecology/plant_seasonal_world_v1.gd")
const SCHEMA := "distributed_world_simulator.ecology.p3_6_disturbance_succession.v1"
const VERSION := "1.0.0"
const PARENT_P3_5_CANDIDATE_AGGREGATE := "255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83"
const EPS := 1e-12
const DIST := ["severity","heat_pressure","flood_pressure","drought_pressure","recovery_time_scale_years"]
const TRAIT := ["id","heat_resistance","flood_resistance","drought_resistance","recovery_rate","pioneer_capacity"]
const RESULT := ["schema","version","parent_p3_5_candidate_aggregate","seasonal_result","seasonal_result_hash","disturbance","recovery_years","traits","trait_order","patch_order","patches","summary","result_hash"]
const PATCH := ["id","parent_spatial_patch_hash","parent_seasonal_patch_hash","temperature_norm","moisture","resource_support","heat_load","flood_load","drought_load","biomass_before_kg","post_disturbance_biomass_kg","lost_biomass_kg","recovery_progress","recovery_pool_kg","final_biomass_kg","plant_order","plants","record_hash"]
const PLANT := ["id","biomass_before_kg","heat_resistance","flood_resistance","drought_resistance","damage_fraction","post_disturbance_biomass_kg","recovery_rate","pioneer_capacity","recovery_weight","recovered_biomass_kg","final_biomass_kg","record_hash"]
const SUMMARY := ["patch_count","plant_count","biomass_before_kg","post_disturbance_biomass_kg","lost_biomass_kg","recovered_biomass_kg","final_biomass_kg","mean_damage_fraction"]

static func apply(seasonal: Dictionary, disturbance: Dictionary, traits: Array, recovery_years_value) -> Dictionary:
	if not bool(Seasonal.validate_result(seasonal).get("success", false)): return {}
	var d := _norm_dist(disturbance); if d.is_empty(): return {}
	if typeof(recovery_years_value) not in [TYPE_INT,TYPE_FLOAT]: return {}
	var years := float(recovery_years_value); if not is_finite(years) or years < 0.0: return {}
	var spatial := _spatial(seasonal); if spatial.is_empty(): return {}
	var ids := _plant_ids(spatial)
	var ts := _norm_traits(traits, ids); if ts.is_empty() and not ids.is_empty(): return {}
	var tmap := {}; var torder := PackedStringArray()
	for tv in ts:
		var t: Dictionary = tv; var id := String(t["id"]); tmap[id]=t; torder.append(id)
	var smap := _map(Array(seasonal.get("patches",[]))); var pmap := _map(Array(spatial.get("patches",[])))
	var porder := PackedStringArray(spatial.get("patch_order",PackedStringArray()))
	if smap.size()!=porder.size() or pmap.size()!=porder.size(): return {}
	var bounds := _temp_bounds(seasonal); if bounds.is_empty(): return {}
	var patches: Array[Dictionary]=[]; var before:=0.0; var post:=0.0; var lost:=0.0; var recovered:=0.0; var damage:=0.0; var count:=0
	for pv in porder:
		var id:=String(pv); if not smap.has(id) or not pmap.has(id): return {}
		var p := _patch(Dictionary(pmap[id]),Dictionary(smap[id]),bounds,d,tmap,years); if p.is_empty(): return {}
		patches.append(p); before+=float(p["biomass_before_kg"]); post+=float(p["post_disturbance_biomass_kg"]); lost+=float(p["lost_biomass_kg"]); recovered+=float(p["recovery_pool_kg"])
		for x in Array(p["plants"]): damage+=float(Dictionary(x)["damage_fraction"]); count+=1
		if not _finite([before,post,lost,recovered,damage]): return {}
	var final:=post+recovered; if not is_finite(final) or final>before+EPS: return {}
	var summary={"patch_count":patches.size(),"plant_count":count,"biomass_before_kg":before,"post_disturbance_biomass_kg":post,"lost_biomass_kg":lost,"recovered_biomass_kg":recovered,"final_biomass_kg":final,"mean_damage_fraction":damage/float(count) if count>0 else 0.0}
	var out={"schema":SCHEMA,"version":VERSION,"parent_p3_5_candidate_aggregate":PARENT_P3_5_CANDIDATE_AGGREGATE,"seasonal_result":seasonal.duplicate(true),"seasonal_result_hash":String(seasonal.get("result_hash","")),"disturbance":d,"recovery_years":years,"traits":ts,"trait_order":torder,"patch_order":porder,"patches":patches,"summary":summary}
	out["result_hash"]=_hash(out); return out

static func validate_result(r: Dictionary) -> Dictionary:
	if not _exact(r,RESULT): return _fail("FIELDS")
	if String(r.get("schema",""))!=SCHEMA or String(r.get("version",""))!=VERSION or String(r.get("parent_p3_5_candidate_aggregate",""))!=PARENT_P3_5_CANDIDATE_AGGREGATE: return _fail("IDENTITY")
	if typeof(r.get("seasonal_result"))!=TYPE_DICTIONARY or typeof(r.get("disturbance"))!=TYPE_DICTIONARY or typeof(r.get("traits"))!=TYPE_ARRAY: return _fail("INPUT_TYPE")
	var s:Dictionary=r["seasonal_result"]; if not bool(Seasonal.validate_result(s).get("success",false)) or String(r.get("seasonal_result_hash",""))!=String(s.get("result_hash","")): return _fail("PARENT")
	if typeof(r.get("recovery_years")) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(r["recovery_years"])) or float(r["recovery_years"])<0.0: return _fail("YEARS")
	if not _derived_ok(r): return _fail("DERIVED")
	var expected:=apply(s,Dictionary(r["disturbance"]),Array(r["traits"]),float(r["recovery_years"])); if expected.is_empty(): return _fail("RECONSTRUCT")
	if String(r.get("result_hash",""))!=_hash(r) or String(r.get("result_hash",""))!=String(expected.get("result_hash","")): return _fail("HASH")
	return {"success":true,"error":""}

static func _patch(sp:Dictionary,se:Dictionary,b:Dictionary,d:Dictionary,tmap:Dictionary,years:float)->Dictionary:
	var t:=float(se.get("temperature_c",NAN)); var m:=float(se.get("moisture",NAN)); var res=se.get("resource_availability",{})
	if not is_finite(t) or not is_finite(m) or m<0.0 or m>1.0 or typeof(res)!=TYPE_DICTIONARY or not _resources(res): return {}
	var tn:=clampf((t-float(b["min"]))/(float(b["max"])-float(b["min"])),0.0,1.0); var sev:=float(d["severity"])
	var hl:=sev*float(d["heat_pressure"])*tn; var fl:=sev*float(d["flood_pressure"])*m; var dl:=sev*float(d["drought_pressure"])*(1.0-m); var support:=minf(float(res["light"]),minf(float(res["water"]),float(res["nutrients"])))
	var order:=PackedStringArray(sp.get("plant_order",PackedStringArray())); var src:Array=sp.get("plants",[]); if order.size()!=src.size(): return {}
	var tmp:Array[Dictionary]=[]; var before:=0.0; var post:=0.0; var weights:=0.0
	for v in src:
		if typeof(v)!=TYPE_DICTIONARY: return {}
		var x:Dictionary=v; var id:=String(x.get("id","")); if not tmap.has(id): return {}
		var tr:Dictionary=tmap[id]; var bm:=float(x.get("final_biomass_kg",-1.0)); if not is_finite(bm) or bm<0.0:return {}
		var surv:=(1.0-hl*(1.0-float(tr["heat_resistance"])))*(1.0-fl*(1.0-float(tr["flood_resistance"])))*(1.0-dl*(1.0-float(tr["drought_resistance"]))); surv=clampf(surv,0.0,1.0)
		var po:=bm*surv; var w:=(po+bm*float(tr["pioneer_capacity"]))*float(tr["recovery_rate"]); if not _finite([po,w]) or w<0.0:return {}
		tmp.append({"id":id,"before":bm,"post":po,"damage":1.0-surv,"weight":w,"trait":tr}); before+=bm; post+=po; weights+=w
	var lost:=maxf(0.0,before-post); var scale:=float(d["recovery_time_scale_years"]); var progress:=0.0 if years<=0.0 else years/(years+scale); var pool:=lost*progress*support
	if not _finite([before,post,lost,progress,pool]) or pool>lost+EPS:return {}
	var plants:Array[Dictionary]=[]; var final:=0.0
	for v in tmp:
		var x:Dictionary=v; var tr:Dictionary=x["trait"]; var rec:=pool*float(x["weight"])/weights if weights>EPS else 0.0; var fb:=float(x["post"])+rec
		var p={"id":String(x["id"]),"biomass_before_kg":float(x["before"]),"heat_resistance":float(tr["heat_resistance"]),"flood_resistance":float(tr["flood_resistance"]),"drought_resistance":float(tr["drought_resistance"]),"damage_fraction":float(x["damage"]),"post_disturbance_biomass_kg":float(x["post"]),"recovery_rate":float(tr["recovery_rate"]),"pioneer_capacity":float(tr["pioneer_capacity"]),"recovery_weight":float(x["weight"]),"recovered_biomass_kg":rec,"final_biomass_kg":fb}; p["record_hash"]=_record_hash(p,PLANT); plants.append(p); final+=fb
	var out={"id":String(sp.get("id","")),"parent_spatial_patch_hash":String(sp.get("record_hash","")),"parent_seasonal_patch_hash":String(se.get("record_hash","")),"temperature_norm":tn,"moisture":m,"resource_support":support,"heat_load":hl,"flood_load":fl,"drought_load":dl,"biomass_before_kg":before,"post_disturbance_biomass_kg":post,"lost_biomass_kg":lost,"recovery_progress":progress,"recovery_pool_kg":pool,"final_biomass_kg":final,"plant_order":order,"plants":plants}; out["record_hash"]=_patch_hash(out); return out

static func _derived_ok(r:Dictionary)->bool:
	if typeof(r.get("trait_order"))!=TYPE_PACKED_STRING_ARRAY or typeof(r.get("patch_order"))!=TYPE_PACKED_STRING_ARRAY or typeof(r.get("patches"))!=TYPE_ARRAY or typeof(r.get("summary"))!=TYPE_DICTIONARY:return false
	var to:PackedStringArray=r["trait_order"]; var ts:Array=r["traits"]; if to.size()!=ts.size():return false
	for i in ts.size():
		if typeof(ts[i])!=TYPE_DICTIONARY or not _exact(ts[i],TRAIT) or String(ts[i].get("id",""))!=String(to[i]):return false
	var po:PackedStringArray=r["patch_order"]; var ps:Array=r["patches"]; if po.size()!=ps.size():return false
	for i in ps.size():
		if typeof(ps[i])!=TYPE_DICTIONARY:return false
		var p:Dictionary=ps[i]; if not _exact(p,PATCH) or String(p.get("id",""))!=String(po[i]) or String(p.get("record_hash",""))!=_patch_hash(p):return false
		var porder= p.get("plant_order"); var plants=p.get("plants"); if typeof(porder)!=TYPE_PACKED_STRING_ARRAY or typeof(plants)!=TYPE_ARRAY or porder.size()!=plants.size():return false
		for j in plants.size():
			if typeof(plants[j])!=TYPE_DICTIONARY:return false
			var x:Dictionary=plants[j]; if not _exact(x,PLANT) or String(x.get("id",""))!=String(porder[j]) or String(x.get("record_hash",""))!=_record_hash(x,PLANT):return false
	if not _exact(Dictionary(r["summary"]),SUMMARY):return false
	return true

static func _hash(r:Dictionary)->String:
	var a:=PackedStringArray([SCHEMA,VERSION,PARENT_P3_5_CANDIDATE_AGGREGATE,String(r.get("seasonal_result_hash","")),"years="+str(r.get("recovery_years",0.0))])
	var d:Dictionary=r.get("disturbance",{}); for k in DIST:a.append("d|%s=%s"%[k,str(d.get(k,0))])
	for v in Array(r.get("traits",[])): var x:Dictionary=v;a.append("t|%s"%_record_hash(x,TRAIT))
	for v in Array(r.get("patches",[])): var x:Dictionary=v;a.append("p|%s"%String(x.get("record_hash","")))
	var s:Dictionary=r.get("summary",{}); for k in SUMMARY:a.append("s|%s=%s"%[k,str(s.get(k,0))])
	return "\n".join(a).sha256_text()

static func _patch_hash(p:Dictionary)->String:
	var a:=PackedStringArray()
	for k in PATCH:
		if k=="plants":
			for v in Array(p.get(k,[])):a.append("plant|"+String(Dictionary(v).get("record_hash","")))
		elif k=="plant_order":
			for id in PackedStringArray(p.get(k,PackedStringArray())):a.append("order|"+String(id))
		elif k!="record_hash":a.append("%s=%s"%[k,str(p.get(k,0))])
	return "\n".join(a).sha256_text()
static func _record_hash(x:Dictionary,fields:Array)->String:
	var a:=PackedStringArray();for k in fields:
		if k!="record_hash":a.append("%s=%s"%[k,str(x.get(k,0))])
	return "\n".join(a).sha256_text()

static func _norm_dist(x: Dictionary) -> Dictionary:
	if not _exact(x, DIST) or not _numbers(x, DIST):
		return {}
	for k in DIST.slice(0, 4):
		if float(x[k]) < 0.0 or float(x[k]) > 1.0:
			return {}
	if float(x["recovery_time_scale_years"]) <= 0.0:
		return {}
	var out := {}
	for k in DIST:
		out[k] = float(x[k])
	return out

static func _norm_traits(xs: Array, expected: PackedStringArray) -> Array[Dictionary]:
	var m := {}
	for value in xs:
		if typeof(value) != TYPE_DICTIONARY:
			return []
		var x: Dictionary = value
		if not _exact(x, TRAIT) or not _numbers(x, TRAIT.slice(1)):
			return []
		var id := String(x.get("id", ""))
		if id.is_empty() or m.has(id):
			return []
		for k in TRAIT.slice(1):
			if float(x[k]) < 0.0 or float(x[k]) > 1.0:
				return []
		m[id] = x
	var ids := PackedStringArray()
	for k in m.keys():
		ids.append(String(k))
	ids.sort()
	var exp := expected.duplicate()
	exp.sort()
	if ids != exp:
		return []
	var out: Array[Dictionary] = []
	for id in ids:
		var src: Dictionary = m[id]
		var item := {"id": id}
		for k in TRAIT.slice(1):
			item[k] = float(src[k])
		out.append(item)
	return out

static func _spatial(s: Dictionary) -> Dictionary:
	var e = s.get("environment_result", {})
	if typeof(e) != TYPE_DICTIONARY:
		return {}
	var value = Dictionary(e).get("spatial_result", {})
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value

static func _temp_bounds(s: Dictionary) -> Dictionary:
	var e = s.get("environment_result", {})
	if typeof(e) != TYPE_DICTIONARY:
		return {}
	var f = Dictionary(e).get("field_config", {})
	if typeof(f) != TYPE_DICTIONARY:
		return {}
	var channel = Dictionary(f).get("temperature_c", {})
	if typeof(channel) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = channel
	if not d.has("min") or not d.has("max"):
		return {}
	var mn := float(d["min"]); var mx := float(d["max"])
	if not is_finite(mn) or not is_finite(mx) or mx <= mn:
		return {}
	return {"min": mn, "max": mx}

static func _plant_ids(s: Dictionary) -> PackedStringArray:
	var m := {}
	for pv in Array(s.get("patches", [])):
		if typeof(pv) != TYPE_DICTIONARY:
			return PackedStringArray()
		for xv in Array(Dictionary(pv).get("plants", [])):
			if typeof(xv) != TYPE_DICTIONARY:
				return PackedStringArray()
			var id := String(Dictionary(xv).get("id", ""))
			if id.is_empty():
				return PackedStringArray()
			m[id] = true
	var out := PackedStringArray()
	for k in m.keys():
		out.append(String(k))
	out.sort()
	return out

static func _map(xs: Array) -> Dictionary:
	var out := {}
	for value in xs:
		if typeof(value) != TYPE_DICTIONARY:
			return {}
		var x: Dictionary = value
		var id := String(x.get("id", ""))
		if id.is_empty() or out.has(id):
			return {}
		out[id] = x
	return out

static func _resources(x: Dictionary) -> bool:
	var keys := ["light", "water", "nutrients"]
	if not _exact(x, keys) or not _numbers(x, keys):
		return false
	for k in keys:
		if float(x[k]) < 0.0 or float(x[k]) > 1.0:
			return false
	return true

static func _exact(x:Dictionary,fs:Array)->bool:
	if x.size()!=fs.size():return false
	for k in fs:if not x.has(k):return false
	return true
static func _numbers(x:Dictionary,fs:Array)->bool:
	for k in fs:if not x.has(k) or typeof(x[k]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(x[k])):return false
	return true
static func _finite(xs:Array)->bool:
	for x in xs:if not is_finite(float(x)):return false
	return true
static func _fail(e:String)->Dictionary:return {"success":false,"error":e}
