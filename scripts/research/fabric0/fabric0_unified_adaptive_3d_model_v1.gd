class_name Fabric0UnifiedAdaptive3DModelV1
extends RefCounted

const Sparse = preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_sparse_v1.gd")
const EPS := 1.0e-13
const G := 9.81
const IDX_ZA := 0
const IDX_ZB := 1
const IDX_ZC := 2
const IDX_TH := 3
const IDX_VA := 4
const IDX_VB := 5
const IDX_VC := 6
const IDX_OM := 7

static func new_world() -> Dictionary:
	var state := [0.5, 1.5, 2.8, -0.25, 0.0, 0.0, -3.0, 1.0]
	var world := {
		"time": 0.0,
		"state": state,
		"mass": [1.0, 1.0, 1.0, 0.40],
		"inv_mass": [1.0, 1.0, 1.0, 2.5],
		"box_half": Vector3(0.35, 0.40, 0.30),
		"frequency": 4.0,
		"contact_active": false,
		"side": -1,
		"events": [],
		"graph_history": [],
		"warm_force": {"floor|A": 0.0, "pair:A|B": 0.0},
		"warm_impulse": {"floor|A": 0.0, "pair:A|B": 0.0},
		"pattern_cache": {"entries": {}, "hits": 0, "misses": 0},
		"accepted_steps": 0,
		"rejected_steps": 0,
		"min_step": INF,
		"max_step": 0.0,
		"pcg_calls": 0,
		"pcg_iterations": 0,
		"max_constraint_residual": 0.0,
		"min_contact_force": INF,
	}
	world["initial_energy"] = _physical_energy(world, state)
	world["final_energy"] = world["initial_energy"]
	_refresh_reactions(world, state)
	return world

static func orientation_quaternion(state: Array) -> Quaternion:
	return Quaternion(Vector3.RIGHT, float(state[IDX_TH])).normalized()

static func active_feature(world: Dictionary, side_override = null) -> Dictionary:
	var side := int(world["side"]) if side_override == null else int(side_override)
	var hy := float(world["box_half"].y)
	if side < 0:
		return {"id":"edge:back_bottom", "relation":"pair:B|C|edge:back_bottom", "lineage":["BBL","BBR"], "rows_y":[hy], "point_count":2}
	return {"id":"edge:front_bottom", "relation":"pair:B|C|edge:front_bottom", "lineage":["BFL","BFR"], "rows_y":[-hy], "point_count":2}

static func degenerate_feature(world: Dictionary) -> Dictionary:
	var hy := float(world["box_half"].y)
	return {"id":"face:bottom", "relation":"pair:B|C|face:bottom", "lineage":["BBL","BBR","BFL","BFR"], "rows_y":[hy,-hy], "point_count":4}

static func current_contact_ids(world: Dictionary) -> Array:
	var ids := ["floor|A", "pair:A|B"]
	if bool(world["contact_active"]): ids.append(String(active_feature(world)["relation"]))
	ids.sort()
	return ids

static func feature_geometry(world: Dictionary, state: Array, y: float) -> Dictionary:
	var theta := float(state[IDX_TH])
	var hz := float(world["box_half"].z)
	var rz := sin(theta) * y - cos(theta) * hz
	var dr := cos(theta) * y + sin(theta) * hz
	var d2 := -sin(theta) * y + cos(theta) * hz
	return {"rz":rz, "dr":dr, "d2":d2}

static func free_support_gap(world: Dictionary, state: Array) -> float:
	var theta := float(state[IDX_TH])
	var hy := float(world["box_half"].y)
	var y := hy if theta < 0.0 else -hy
	var geo := feature_geometry(world, state, y)
	return float(state[IDX_ZC]) + float(geo["rz"]) - (float(state[IDX_ZB]) + 0.5)

static func _project_state(world: Dictionary, state: Array, contact_active: bool, side: int) -> Array:
	var s := state.duplicate(true)
	s[IDX_ZA] = 0.5; s[IDX_ZB] = 1.5
	s[IDX_VA] = 0.0; s[IDX_VB] = 0.0
	if contact_active:
		var f := active_feature(world, side)
		var y := float(f["rows_y"][0])
		var geo := feature_geometry(world, s, y)
		s[IDX_ZC] = 2.0 - float(geo["rz"])
		s[IDX_VC] = -float(geo["dr"]) * float(s[IDX_OM])
	return s

static func _constraint_rows(world: Dictionary, state: Array, contact_active: bool, side: int, feature_override = null) -> Array:
	var rows: Array = []
	rows.append({"id":"floor|A", "relation":"floor|A", "j":[1.0,0.0,0.0,0.0], "gap":float(state[IDX_ZA])-0.5, "gamma":0.0})
	rows.append({"id":"pair:A|B", "relation":"pair:A|B", "j":[-1.0,1.0,0.0,0.0], "gap":float(state[IDX_ZB])-float(state[IDX_ZA])-1.0, "gamma":0.0})
	if contact_active:
		var f: Dictionary = active_feature(world, side) if feature_override == null else feature_override
		var omega := float(state[IDX_OM])
		var idx := 0
		for yv in f["rows_y"]:
			var geo := feature_geometry(world, state, float(yv))
			var gap := float(state[IDX_ZC]) + float(geo["rz"]) - (float(state[IDX_ZB])+0.5)
			rows.append({
				"id":"%s/row:%d" % [String(f["relation"]),idx],
				"relation":String(f["relation"]),
				"j":[0.0,-1.0,1.0,float(geo["dr"])],
				"gap":gap,
				"gamma":float(geo["d2"]) * omega * omega,
			})
			idx += 1
	return rows

static func _free_accel(world: Dictionary, state: Array) -> Array:
	return [-G,-G,-G,-float(world["frequency"])*float(world["frequency"])*float(state[IDX_TH])]

static func _constraint_solve(world: Dictionary, state: Array, contact_active: bool, side: int, update_cache: bool = false, feature_override = null) -> Dictionary:
	var rows := _constraint_rows(world,state,contact_active,side,feature_override)
	var minv: Array = world["inv_mass"]
	var afree := _free_accel(world,state)
	var velocity := [float(state[IDX_VA]),float(state[IDX_VB]),float(state[IDX_VC]),float(state[IDX_OM])]
	var matrix := Sparse._assemble_a(rows,minv)
	var rhs: Array = []
	for row in rows:
		var ja := Sparse._dot(row["j"],afree)
		var gv := Sparse._dot(row["j"],velocity)
		var stab := 400.0*float(row["gap"]) + 40.0*gv
		rhs.append(-(ja + float(row["gamma"]) + stab))
	var prep := Sparse._prepare_pattern(world["pattern_cache"],"main",matrix,update_cache)
	if not bool(prep["ok"]): return prep
	var initial := Sparse._zero(rows.size())
	if update_cache:
		for i in range(rows.size()):
			var rel := String(rows[i]["relation"])
			initial[i] = float(world["warm_force"].get(rel,0.0)) / float(Sparse._relation_row_count(rows,rel))
	var pcg := Sparse._pcg(matrix,rhs,initial,prep["inverse_diagonal"],1.0e-12,128)
	if not bool(pcg["ok"]): return pcg
	var lambda: Array = pcg["x"]
	var qdd := afree.duplicate(true)
	for r in range(rows.size()):
		for c in range(4): qdd[c] = float(qdd[c]) + float(minv[c])*float(rows[r]["j"][c])*float(lambda[r])
	var max_res := 0.0
	for r in range(rows.size()):
		var res := Sparse._dot(rows[r]["j"],qdd) + float(rows[r]["gamma"]) + 400.0*float(rows[r]["gap"]) + 40.0*Sparse._dot(rows[r]["j"],velocity)
		max_res = maxf(max_res,absf(res))
	if update_cache:
		world["pcg_calls"] = int(world["pcg_calls"])+1
		world["pcg_iterations"] = int(world["pcg_iterations"])+int(pcg["iterations"])
		world["max_constraint_residual"] = maxf(float(world["max_constraint_residual"]),max_res)
		var sums := {}; var counts := {}
		for r in range(rows.size()):
			var rel := String(rows[r]["relation"])
			sums[rel] = float(sums.get(rel,0.0)) + float(lambda[r]); counts[rel] = int(counts.get(rel,0))+1
			world["min_contact_force"] = minf(float(world["min_contact_force"]),float(lambda[r]))
		for rel in sums.keys(): world["warm_force"][rel] = float(sums[rel])
	return {"ok":true,"rows":rows,"matrix":matrix,"rhs":rhs,"lambda":lambda,"qdd":qdd,"pcg_iterations":int(pcg["iterations"]),"residual":max_res}

static func _derivative(world: Dictionary, raw_state: Array, contact_active: bool, side: int) -> Array:
	var state := _project_state(world,raw_state,contact_active,side)
	var solved := _constraint_solve(world,state,contact_active,side,false)
	assert(bool(solved["ok"]))
	var qdd: Array = solved["qdd"]
	return [float(state[IDX_VA]),float(state[IDX_VB]),float(state[IDX_VC]),float(state[IDX_OM]),float(qdd[0]),float(qdd[1]),float(qdd[2]),float(qdd[3])]

static func _velocity_project(world: Dictionary, raw_state: Array, contact_active: bool, side: int) -> Array:
	var state := _project_state(world,raw_state,false,side) if not contact_active else raw_state.duplicate(true)
	var rows := _constraint_rows(world,state,contact_active,side)
	var minv: Array = world["inv_mass"]
	var matrix := Sparse._assemble_a(rows,minv)
	var velocity := [float(state[IDX_VA]),float(state[IDX_VB]),float(state[IDX_VC]),float(state[IDX_OM])]
	var rhs: Array=[]
	for row in rows: rhs.append(-Sparse._dot(row["j"],velocity))
	var invdiag := Sparse._inverse_diagonal(matrix)
	var initial := Sparse._zero(rows.size())
	var solved := Sparse._pcg(matrix,rhs,initial,invdiag,1.0e-12,128); assert(bool(solved["ok"]))
	var impulse: Array = solved["x"]
	for r in range(rows.size()):
		for c in range(4): velocity[c] = float(velocity[c])+float(minv[c])*float(rows[r]["j"][c])*float(impulse[r])
	var out := state.duplicate(true); out[IDX_VA]=velocity[0];out[IDX_VB]=velocity[1];out[IDX_VC]=velocity[2];out[IDX_OM]=velocity[3]
	var sums := {}
	for r in range(rows.size()): sums[String(rows[r]["relation"])] = float(sums.get(String(rows[r]["relation"]),0.0))+float(impulse[r])
	for rel in sums.keys(): world["warm_impulse"][rel]=float(sums[rel])
	return out

static func _refresh_reactions(world: Dictionary, raw_state: Array) -> void:
	var state := _project_state(world,raw_state,bool(world["contact_active"]),int(world["side"]))
	world["state"] = state
	var solved := _constraint_solve(world,state,bool(world["contact_active"]),int(world["side"]),true)
	assert(bool(solved["ok"]))

static func _lineage_remap_scalar(oldf: Dictionary, value: float, newf: Dictionary) -> float:
	var set_new := {}; for x in newf["lineage"]: set_new[String(x)]=true
	var overlap := 0
	for x in oldf["lineage"]:
		if set_new.has(String(x)): overlap += 1
	return value if overlap > 0 else 0.0
static func world_hash(world: Dictionary) -> String:
	var s: Array=world["state"]; var events:Array=[]
	for e in world["events"]: events.append({"kind":String(e["kind"]),"time":float(e["time"]),"final_contact":String(e.get("final_contact",e.get("feature","")))})
	return Sparse._sha(JSON.stringify({"time":float(world["time"]),"state":s,"contact_active":bool(world["contact_active"]),"side":int(world["side"]),"contacts":current_contact_ids(world),"events":events},"",false))

static func quaternion_audit(world: Dictionary) -> Dictionary:
	var q:=orientation_quaternion(world["state"]); return {"length":q.length(),"x":q.x,"y":q.y,"z":q.z,"w":q.w,"axis":Vector3.RIGHT}

static func _physical_energy(world: Dictionary, state: Array) -> float:
	var theta:=float(state[IDX_TH]);var omega:=float(state[IDX_OM]);var inertia:=float(world["mass"][3]);var freq:=float(world["frequency"])
	var rot:=0.5*inertia*omega*omega+0.5*inertia*freq*freq*theta*theta
	var vert:=0.5*float(world["mass"][2])*float(state[IDX_VC])*float(state[IDX_VC])+float(world["mass"][2])*G*float(state[IDX_ZC])
	return rot+vert

