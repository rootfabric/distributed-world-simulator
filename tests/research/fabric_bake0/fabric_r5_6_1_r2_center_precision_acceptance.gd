extends SceneTree
## R5.6.1 R2 narrow COM representability RED->GREEN numeric contract.
## Two representable finite point masses at adjacent Float64 coordinates can
## have a midpoint not representable in one absolute Float64 descriptor.
const Index = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_index_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const COM_ABS_PRECISION_M := 1.0e-6
var checks := 0
var failures: Array = []
var rejected_centers := 0
var safe_centers := 0
var multi_axis_rejections := 0
var unchanged_state := true
var examples: Array = []

func ck(condition: bool, message: String, detail = null) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("R56_R2_COM_PRECISION: " + message + " " + JSON.stringify(detail))

func source(name: String, first_pos: Array, second_pos: Array) -> Dictionary:
	var a = Part.create("part/com/a", "item/com/a", "BEAM", "member", 1.0, first_pos)
	var b = Part.create("part/com/b", "item/com/b", "BEAM", "member", 1.0, second_pos)
	return Snapshot.create("construct/com/"+name, "item/com/root", 0, "OPERATIONAL", [a,b], [], {})

func check_midpoint(label: String, axis: int, offset: float, step: float, expect_reject: bool) -> void:
	var first := [0.0,0.0,0.0]
	var second := [0.0,0.0,0.0]
	first[axis] = offset
	second[axis] = offset + step
	var snapshot := source(label, first, second)
	ck(Snapshot.validate(snapshot).success, label + " canonical input accepted")
	var a: float = float(snapshot.parts[0].local_position_m[axis])
	var b: float = float(snapshot.parts[1].local_position_m[axis])
	var separation := b - a
	ck(separation > 0.0, label + " endpoints truly distinct")
	var index = Index.new()
	ck(index.initialize(snapshot).success, label + " index initialises")
	var before: Dictionary = index.status().duplicate(true)
	var q: Dictionary = index.query_range(0,2)
	var relative_expected := separation / 2.0
	var observed := (float(q.details.center_of_mass[axis]) - a) if q.success else NAN
	var error := absf(observed - relative_expected) if q.success else INF
	if expect_reject:
		ck(not q.success and q.error_code == "R56_R2_RANGE_CENTER_PRECISION_UNSAFE", label + " nonrepresentable COM fails closed", q)
		if not q.success and q.error_code == "R56_R2_RANGE_CENTER_PRECISION_UNSAFE":
			rejected_centers += 1
	else:
		ck(q.success and error <= COM_ABS_PRECISION_M, label + " representable or within tolerance COM accepted", q)
		if q.success:
			safe_centers += 1
	ck(index.status() == before, label + " query is read-only")
	unchanged_state = unchanged_state and index.status() == before
	if not q.success:
		ck(q.error_code != "R56_R2_RANGE_NUMERIC_PRECISION_UNSAFE", label + " reject for center, not inertia", q)
	else:
		ck(absf(float(q.details.inertia_tensor_body[0 if axis != 0 else 1][0 if axis != 0 else 1]) - separation*separation/2.0) <= 1.0e-6, label + " inertia still well-conditioned", q)
	if axis != 0 and expect_reject:
		multi_axis_rejections += 1
	examples.append({"label":label,"axis":axis,"offset":offset,"separation":separation,"expected_reject":expect_reject,"accepted":q.success,"error_code":q.get("error_code", "")})

func _initialize() -> void:
	# Adjacent source doubles: midpoint is mathematically valid but is not a
	# representable absolute Float64 for the four large coordinate offsets.
	check_midpoint("x-1e9",0,1.0e9,0.00000011920928955078125,false)
	check_midpoint("x-1e12",0,1.0e12,0.0001220703125,true)
	check_midpoint("x-1e13",0,1.0e13,0.001953125,true)
	check_midpoint("x-1e14",0,1.0e14,0.015625,true)
	check_midpoint("x-1e15",0,1.0e15,0.125,true)
	# Exact midpoints at large offsets must still be accepted.
	check_midpoint("x-safe-1e12",0,1.0e12,1.0,false)
	# Axis-aware and signed-coordinate behavior, no x-only special case.
	check_midpoint("y-negative-1e13",1,-1.0e13,0.001953125,true)
	check_midpoint("z-positive-1e13",2,1.0e13,0.001953125,true)
	ck(rejected_centers == 6, "six unrepresentable centers rejected")
	ck(safe_centers == 2, "two representable/accurate centers accepted")
	ck(multi_axis_rejections == 2, "y and z axis guard is active")
	ck(unchanged_state, "all numeric refusals preserve index state")
	print("FABRIC_R56_R2_COM_PRECISION=" + JSON.stringify({
		"schema":"fabric.r56_r2.center_precision.v1", "checks":checks,
		"failures":failures,"center_budget_m":COM_ABS_PRECISION_M,
		"unsafe_centers_rejected":rejected_centers,"safe_centers":safe_centers,
		"multi_axis_rejections":multi_axis_rejections,
		"state_unchanged":unchanged_state,"cases":examples,
	}))
	quit(0 if failures.is_empty() else 1)
