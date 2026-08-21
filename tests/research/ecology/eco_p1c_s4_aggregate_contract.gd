extends SceneTree
const Gate = preload("res://scripts/research/ecology/plant_competition_robustness_gate_v1.gd")
const EXPECTED_AGGREGATE_HASH := "0ca70eab1e5db569a45e244a6cd2f378469197472de2a7d35f8a4a15db870112"
func _hetero(case_hash:String,eff:int,top:float,sh:float,sub:int,niche:int,patch:float)->Dictionary:
	return {"case_hash":case_hash,"effective_founders_1pct":eff,"top1_biomass_share":top,"shannon_biomass_diversity":sh,"substantial_cluster_count":sub,"niche_enriched_cluster_count":niche,"top1_patch_dominance_ratio":patch,"failure_matrix":{"GLOBAL_TAKEOVER":"PASS","DIVERSITY_COLLAPSE":"PASS","RUNAWAY_TRAIT":"PASS_NO_MUTATION_STATIC_BOUNDED_FOUNDERS","CLUSTER_COLLAPSE":"PASS","FALSE_NICHE_UNIFORM":"NOT_APPLICABLE_HETEROGENEOUS"}}
func _init()->void:
	var cases=[
		_hetero("431c4b6c0683b692c9fe88fbc912f49c3659db122c8fdf2715f525ea712dc43b",17,0.27832221094551,2.40018055342691,3,3,0.8),
		_hetero("da7eaf61254bded7a52891abccbc2fb9130477bbde2c3fd6e440d83ebb3d42c0",18,0.20953475800384,2.47442432503343,3,2,0.4),
		_hetero("def061b2da3e350f43138c7c8519436c0eee168b2bffd4a69eee40499b50d6c9",17,0.24794290067339,2.29610063443602,3,2,0.4),
		_hetero("35801d690cb0f6fcbce63aa8abbcbdd85acadd7211b513855816325fea985cb5",15,0.19958690254908,2.47715651515013,3,3,0.72),
		_hetero("9714233b780bd901187c9dc9e1a6881ee15f4b6bd95376fea74b70629efbd3bc",17,0.21660622311158,2.44627358106803,3,3,0.52),
		_hetero("4da5daf6d51686de2d017500cf035aa9f91778d62592d27016a66fdf6f1dab9e",16,0.22491061053094,2.47278147314222,3,3,0.72),
	]
	var uniform={"case_hash":"8f27fb89d87d7b92911efcb80ae461d2d0f32ff169ed8f3efbdf73a296d67d47","effective_founders_1pct":11,"top1_biomass_share":0.18385030052412,"shannon_biomass_diversity":2.23649420608261,"substantial_cluster_count":3,"niche_enriched_cluster_count":0,"top1_patch_dominance_ratio":1.0,"max_niche_enrichment_span":0.0,"failure_matrix":{"GLOBAL_TAKEOVER":"PASS","RUNAWAY_TRAIT":"PASS_NO_MUTATION_STATIC_BOUNDED_FOUNDERS","DIVERSITY_COLLAPSE":"NOT_APPLICABLE_UNIFORM_CONTROL_EXPECTS_LOWER_DIVERSITY","CLUSTER_COLLAPSE":"NOT_APPLICABLE_UNIFORM_CONTROL","FALSE_NICHE_UNIFORM":"PASS"}}
	var deep=_hetero("ca49a238f82303ac6ad7e36d10f849baff07442873ab3b20c22d2d32f9f34411",15,0.27843144748739,2.33530222571843,3,3,0.8); deep["cycles"]=24
	var r:=Gate.aggregate(cases,uniform,deep)
	var assertions:=15; var failures:=0
	if String(r.get("aggregate_hash","")) != EXPECTED_AGGREGATE_HASH: failures+=1
	if int(r.get("seed_count",0)) != 6: failures+=1
	if int(r.get("minimum_effective_founders_1pct",0)) != 15: failures+=1
	if absf(float(r.get("maximum_top1_biomass_share",0.0))-0.27832221094551)>0.000000000001: failures+=1
	if absf(float(r.get("minimum_shannon_biomass_diversity",0.0))-2.29610063443602)>0.000000000001: failures+=1
	if int(r.get("minimum_substantial_cluster_count",0)) != 3: failures+=1
	if int(r.get("minimum_niche_enriched_cluster_count",0)) != 2: failures+=1
	if float(r.get("uniform_max_niche_enrichment_span",1.0)) > Gate.UNIFORM_MAX_NICHE_SPAN: failures+=1
	if int(r.get("deep_horizon_effective_founders_1pct",0)) != 15: failures+=1
	if float(r.get("deep_horizon_top1_biomass_share",1.0)) >= Gate.MAX_TOP1_BIOMASS_SHARE: failures+=1
	var fm:Dictionary=r.get("failure_matrix",{})
	if String(fm.get("GLOBAL_TAKEOVER","")) != "PASS": failures+=1
	if String(fm.get("DIVERSITY_COLLAPSE","")) != "PASS": failures+=1
	if String(fm.get("CLUSTER_COLLAPSE","")) != "PASS": failures+=1
	if String(fm.get("FALSE_NICHE_UNIFORM","")) != "PASS": failures+=1
	if not String(fm.get("RUNAWAY_TRAIT","")).begins_with("PASS"): failures+=1
	if failures==0:
		print("ECO.P1C-S4 Aggregate Contract: PASS (%d assertions) aggregate=%s failure_matrix=%s" % [assertions, String(r["aggregate_hash"]), str(fm)]); quit(0); return
	push_error("ECO.P1C-S4 Aggregate Contract: FAIL (%d/%d)" % [failures,assertions]); quit(1)
