extends SceneTree
## Narrow numeric RED->GREEN regression: large but finite construct-local
## coordinate offsets MUST NOT silently collapse point-mass inertia.
## Independent source snapshots; does not mutate authoritative Construction.
const Index = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_index_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
var checks := 0
var failures: Array = []
var tested_offsets: Array = []
var unsafe_ranges_rejected := 0
var updated_after_rebase := false

func ck(ok: bool, label: String, details = null) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("R56_R2_NUMERIC: "+label+" "+JSON.stringify(details))

func near(a: float, b: float, tolerance: float = 1.0e-6) -> bool:
	return is_finite(a) and is_finite(b) and absf(a-b) <= tolerance

func part(id: String, x: float) -> Dictionary:
	return Part.create("part/numeric/"+id,"item/numeric/"+id,"BEAM","member",1.0,[x,0.0,0.0])

func source(name: String, parts: Array) -> Dictionary:
	return Snapshot.create("construct/numeric/"+name,"item/numeric/root",0,"OPERATIONAL",parts,[],{})

func simple_pair(offset: float) -> void:
	var parts: Array = [part("a",offset),part("b",offset+1.0)]
	var s := source("offset-"+str(int(offset)),parts)
	var idx = Index.new()
	var valid: Dictionary = Snapshot.validate(s)
	ck(valid.success,"canonical pair validates "+str(offset),valid)
	var built: Dictionary = idx.initialize(s)
	ck(built.success,"Fenwick initialized "+str(offset),built)
	if not built.success:
		return
	var q: Dictionary = idx.query_range(0,2)
	ck(q.success,"physical descriptor available "+str(offset),q)
	if not q.success:
		return
	ck(near(float(q.details.total_mass),2.0),"mass conserved "+str(offset),q)
	ck(near(float(q.details.center_of_mass[0]),offset+0.5,1.0e-4),"COM invariant "+str(offset),q)
	ck(near(float(q.details.inertia_tensor_body[1][1]),0.5),"Iyy must be 0.5 "+str(offset),q)
	ck(near(float(q.details.inertia_tensor_body[2][2]),0.5),"Izz must be 0.5 "+str(offset),q)
	ck(near(float(q.details.inertia_tensor_body[0][0]),0.0),"Ixx must be 0 "+str(offset),q)
	tested_offsets.append(offset)

func after_sparse_update() -> void:
	var start := 1.0e9
	var before_b: Dictionary = part("b",start+1.0)
	var idx = Index.new()
	var s := source("sparse",[part("a",start),before_b])
	ck(idx.initialize(s).success,"sparse test initialized")
	var after_b := part("b",start+2.0)
	var new_checksum := U.canonical_hash({"source":String(s.checksum),"event":"sparse-part-b"})
	var updated:Dictionary=idx.apply_owner_verified([{"before":before_b,"after":after_b}],String(s.checksum),new_checksum,1,2.0)
	ck(updated.success,"large-offset sparse update admitted",updated)
	if not updated.success:
		return
	ck(int(updated.details.fenwick_nodes_touched)<=2 and updated.details.full_moment_scans==0,"update remains O(log N)",updated)
	var q := idx.query_range(0,2)
	ck(q.success,"sparse query valid",q)
	if q.success:
		ck(near(float(q.details.center_of_mass[0]),start+1.0,1.0e-4),"post-update COM")
		ck(near(float(q.details.inertia_tensor_body[1][1]),2.0),"post-update Iyy equals 2")
		ck(near(float(q.details.inertia_tensor_body[2][2]),2.0),"post-update Izz equals 2")
		ck(q.details.source_checksum==new_checksum and int(q.details.revision)==1,"post-update source identity")
	updated_after_rebase = updated.success and q.success

func fail_closed_bad_condition() -> void:
	var s := source("far-narrow",[part("a",0.0),part("b",1.0e8),part("c",1.0e8+1.0)])
	var idx = Index.new()
	ck(Snapshot.validate(s).success,"far narrow source validates")
	ck(idx.initialize(s).success,"far narrow index builds")
	var before := idx.status().duplicate(true)
	var narrow: Dictionary = idx.query_range(1,3)
	var safe_refusal: bool = not narrow.success and narrow.error_code=="R56_R2_RANGE_NUMERIC_PRECISION_UNSAFE"
	ck(safe_refusal,"unresolvable distant range rejects instead of false inertia",narrow)
	if safe_refusal:
		unsafe_ranges_rejected+=1
	ck(idx.status()==before,"numeric refusal never mutates index state")
	var full := idx.query_range(0,3)
	ck(full.success,"physically well-conditioned full span still works",full)
	if full.success:
		ck(float(full.details.inertia_tensor_body[1][1])>1.0e15,"full span has large true inertia",full)

func _initialize() -> void:
	for d in [1.0,1.0e5,1.0e7,1.0e8,1.0e9]:
		simple_pair(d)
	after_sparse_update()
	fail_closed_bad_condition()
	print("FABRIC_R56_R2_NUMERIC="+JSON.stringify({
		"schema":"fabric.r56_r2.numeric_conditioning.v1",
		"checks":checks,"failures":failures,
		"stable_offsets":tested_offsets,
		"sparse_update_ok":updated_after_rebase,
		"unsafe_ranges_rejected":unsafe_ranges_rejected,
	}))
	quit(0 if failures.is_empty() else 1)
