extends SceneTree
## Reviewer-created adversarial test: the exact same journal accepted at
## bootstrap MUST survive cold recovery. No product source is modified.
const Life = preload("res://scripts/research/fabric_bake0/r5_6_2_r1_event_lifecycle_v1.gd")
const Store = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const Mutation = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const Bond = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_adapter_v1.gd")
const MatterBatch = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const Composition = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
var checks := 0
var failures: Array = []

func ck(ok: bool, label: String, actual = null) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("REVIEW_FAIL="+label+" actual="+JSON.stringify(actual))

func _initialize() -> void:
	var parts: Array = []
	var bonds: Array = []
	var total := 0.0
	for i in range(4):
		var mass := 1.0 + 0.25*float(i)
		total += mass
		parts.append(Part.create("part/review-r562/%02d"%i, "item/review-r562-%02d"%i,
			"BEAM", "fabric_boundary" if i in [0,3] else "member",
			mass, [float(i), 0.2*float(i), 0.0]))
	for i in range(3):
		bonds.append(Bond.create("bond/review-r562/%02d"%i,
			String(parts[i].part_id), String(parts[i+1].part_id), "GENERIC_COUPLING", 50.0))
	var source := Snapshot.create("construct/review-r562/bootstrap", "item/review-r562-root",
		0, "OPERATIONAL", parts, bonds, {"review":"genesis-event-cap"})
	var matter := MatterBatch.create({
		"batch_id":"batch/review-r562/bootstrap", "container_id":"container/review-r562/bootstrap",
		"source_body_id":"body/review-r562/bootstrap",
		"source_operation_id":"operation/review-r562/bootstrap",
		"total_mass_kg":total, "bulk_volume_m3":0.1,
		"composition":Composition.create([{"material_id":"material/steel", "mass_fraction":1.0}]),
		"temperature_k":293.15})
	var authority := Adapter.authority_for(source, matter, "server/review-r562", 30)
	var store = Store.new()
	ck(store.apply_mutation(Mutation.create(Mutation.OP_CREATE, String(source.construct_id),
		{}, source)).success, "owner source created")
	var event_ids: Array = []
	for i in range(17):
		event_ids.append("event/review-r562/%02d"%i)
	var over = Life.new()
	var admission: Dictionary = over.bootstrap(store, String(source.construct_id),
		matter, authority, event_ids)
	if admission.success:
		var res := Life.new().recover(store, String(source.construct_id),
			matter, authority, admission.details.journal)
		print("REVIEW_OVERSIZE_BOOTSTRAP=ACCEPTED RECOVER_SUCCESS="+str(res.success)+
			" CODE="+String(res.get("error_code","")))
		ck(res.success, "successful bootstrap must cold-recover", res)
	else:
		ck(String(admission.get("error_code",""))=="R562_EVENT_BUDGET_EXCEEDED",
			"overbudget bootstrap must reject at admission", admission)
	var boundary := Life.new().bootstrap(store, String(source.construct_id),
		matter, authority, event_ids.slice(0,16))
	ck(boundary.success, "16-event genesis accepted", boundary)
	if boundary.success:
		var res2 := Life.new().recover(store, String(source.construct_id),
			matter, authority, boundary.details.journal)
		ck(res2.success, "16-event genesis cold recovers", res2)
	print("FABRIC_R562_BUDGET_REVIEW_RESULT="+JSON.stringify({
		"schema":"fabric.r562.review.initial_event_budget.v1",
		"checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
