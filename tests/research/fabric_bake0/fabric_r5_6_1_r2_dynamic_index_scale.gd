extends SceneTree
## Standalone 5k/20k/100k moment-index cost and mathematical parity campaign.
## Uses synthetically generated but schema-valid Construction snapshots. Its
## synthetic checksums are NOT owner-issued mutation receipts; this test only
## measures the isolated, pre-verified Fenwick numerical update kernel. Owner
## authentication is tested separately in r2_dynamic_aggregate_acceptance.gd.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Index = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_index_v1.gd")

var checks := 0
var failures: Array = []
var cases: Array = []

func ck(value: bool, label: String, got = null) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error("R56_R2_INDEX_SCALE: " + label + " " + JSON.stringify(got))

func near(a: float,b: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a-b) <= 1.0e-7 + 1.0e-8*maxf(1.0,maxf(absf(a),absf(b)))

func moment_oracle(parts: Array, start: int, end: int) -> Dictionary:
	var mass := 0.0
	var x := 0.0
	var y := 0.0
	var z := 0.0
	for i in range(start,end):
		var p: Dictionary = parts[i]
		var m := float(p.mass_kg)
		mass += m
		x += m * float(p.local_position_m[0])
		y += m * float(p.local_position_m[1])
		z += m * float(p.local_position_m[2])
	var c := [x/mass,y/mass,z/mass]
	var inertial := [0.0,0.0,0.0]
	for i in range(start,end):
		var p: Dictionary=parts[i]
		var m:=float(p.mass_kg)
		var a: float = float(p.local_position_m[0])-c[0]
		var b: float = float(p.local_position_m[1])-c[1]
		var d: float = float(p.local_position_m[2])-c[2]
		inertial[0]+=m*(b*b+d*d)
		inertial[1]+=m*(a*a+d*d)
		inertial[2]+=m*(a*a+b*b)
	return {"mass":mass,"center":c,"diagonal":inertial}

func test_scale(n: int) -> void:
	var parts: Array = []
	var total := 0.0
	for i in range(n):
		var m:=1.0+0.125*float(i%4)
		total+=m
		parts.append(Part.create("part/r56r2-scale/%06d"%i,"item/r56r2-scale-%06d"%i,
			"BEAM","fabric_boundary" if i in [0,n-1] else "member",m,
			[float(i%97)*0.125,float(int(i/97)%37)*0.125,sin(float(i)*0.023)]))
	var snapshot:=Snapshot.create("construct/r56r2/scale-%06d"%n,"item/r56r2-scale",0,"OPERATIONAL",parts,[],{"floor":"point-mass"})
	var idx=Index.new()
	var started:Dictionary=idx.initialize(snapshot)
	ck(started.success,"index initialize "+str(n),started)
	if not started.success:return
	ck(idx.status().count==n and idx.status().build_scanned_parts==n,"linear one-time construction count "+str(n))
	var initial=idx.query_range(0,n)
	ck(initial.success and near(initial.details.total_mass,total),"initial total mass "+str(n),initial)
	var old_checksum:String=String(snapshot.checksum)
	var worst:=0
	var all_parts:=parts.duplicate(true)
	# 3 independent updates on far-apart indices; no full-tree rebuild.
	for event in range(3):
		var at := 1 if event==0 else (int(n/2) if event==1 else n-2)
		var before:Dictionary=all_parts[at].duplicate(true)
		var after:Dictionary=before.duplicate(true)
		after.local_position_m=[float(at%13)*0.2+0.5,float(event)+0.125,1.75-float(event)*0.25]
		var next:String=U.canonical_hash({"scale":n,"event":event,"previous":old_checksum})
		var updated:Dictionary=idx.apply_owner_verified([{"before":before,"after":after}],old_checksum,next,event+1,total)
		ck(updated.success,"one-part sparse update "+str(n)+"/"+str(event),updated)
		if not updated.success:continue
		worst=maxi(worst,int(updated.details.fenwick_nodes_touched))
		ck(int(updated.details.parts_updated)==1 and int(updated.details.full_moment_scans)==0,"sparse update contract "+str(n))
		ck(int(updated.details.fenwick_nodes_touched)<=18,"logarithmic touched nodes "+str(n),updated)
		all_parts[at]=after
		old_checksum=next
		for span in [[0,n],[maxi(0,at-3),mini(n,at+4)],[int(n/4),int(n*3/4)]]:
			var result:Dictionary=idx.query_range(span[0],span[1])
			ck(result.success,"range valid "+str(n),result)
			if not result.success:continue
			var truth:Dictionary=moment_oracle(all_parts,span[0],span[1])
			ck(near(float(result.details.total_mass),float(truth.mass)),"range mass parity "+str(n))
			for axis in range(3):
				ck(near(float(result.details.center_of_mass[axis]),float(truth.center[axis])),"COM axis "+str(axis)+" at "+str(n))
				ck(near(float(result.details.inertia_tensor_body[axis][axis]),float(truth.diagonal[axis])),"I diagonal "+str(axis)+" at "+str(n),[result.details.inertia_tensor_body[axis][axis],truth.diagonal[axis]])
	ck(idx.status().update_full_moment_scans==0 and idx.status().updated_parts==3,"no full scan in three updates "+str(n))
	cases.append({"n":n,"initial_parts_scanned":n,"sparse_updated_parts":idx.status().updated_parts,"total_fenwick_nodes_touched":idx.status().fenwick_nodes_touched,"max_nodes_per_part_update":worst})

func _initialize() -> void:
	for n in [5000,20000,100000]:
		test_scale(n)
	var payload:Dictionary={"schema":"fabric.r56_r2.dynamic_index_scale.v1","checks":checks,
		"failures":failures,"cases":cases}
	print("FABRIC_R56_R2_SCALE="+JSON.stringify(payload))
	quit(0 if failures.is_empty() else 1)
