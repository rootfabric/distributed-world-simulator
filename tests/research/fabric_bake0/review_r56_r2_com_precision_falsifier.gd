extends SceneTree
## Fresh independent numeric falsifier. 2026-10-20.
## Frozen target: FABRIC R5.6.1 R2 @ 1b2e707c3605c502280efe157ed112816f85c6df.
## The source stores finite canonical Float64 endpoints exactly. Reconstructing
## the relative centroid from the published world-coordinate result can erase
## a physically significant sub-ULP fraction. The inertia guard alone misses it.
const Index = preload("res://scripts/research/fabric_bake0/r5_6_1_r2_dynamic_aggregate_index_v1.gd")
const Snapshot = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const Part = preload("res://scripts/construction/contracts/construction_part_record.gd")
const COM_ABS_TARGET_M := 1.0e-6  # Provisional adversarial accuracy goal; no current R2 contract for COM.
var checks := 0
var failures: Array = []
var cases: Array = []
func ck(ok: bool, label: String, detail = null) -> void:
    checks += 1
    if not ok:
        failures.append(label)
        push_error("REVIEW_R56_R2_COM: " + label + "; " + JSON.stringify(detail))
func run_case(offset: float, step: float) -> void:
    var a = Part.create("part/reviewer/a", "item/reviewer/a", "BEAM", "member", 1.0, [offset, 0.0, 0.0])
    var b = Part.create("part/reviewer/b", "item/reviewer/b", "BEAM", "member", 1.0, [offset + step, 0.0, 0.0])
    var input := Snapshot.create("construct/reviewer", "item/reviewer-root", 0, "OPERATIONAL", [a, b], [], {})
    var validation: Dictionary = Snapshot.validate(input)
    ck(validation.success, "canonical source valid at " + str(offset), validation)
    if not validation.success: return
    var actual_separation := float(b.local_position_m[0]) - float(a.local_position_m[0])
    ck(actual_separation > 0.0, "both endpoints remain distinct representable canonical values", actual_separation)
    var i = Index.new()
    var built: Dictionary = i.initialize(input)
    ck(built.success, "index construction at " + str(offset), built)
    if not built.success: return
    var q: Dictionary = i.query_range(0, 2)
    var expected_relative_center := actual_separation / 2.0
    var observed_relative_center := (float(q.details.center_of_mass[0]) - float(a.local_position_m[0])) if q.success else NAN
    var abs_error := absf(expected_relative_center - observed_relative_center) if q.success else 0.0
    var inertia := float(q.details.inertia_tensor_body[1][1]) if q.success else NAN
    cases.append({"offset":offset,"step":step,"query_success":q.success,"error_code":q.get("error_code",""),"relative_expected_com":expected_relative_center,"relative_published_com":observed_relative_center,"absolute_com_error_m":abs_error,"published_iyy":inertia})
    ck(not q.success or abs_error <= COM_ABS_TARGET_M,
       "reject or faithfully represent center of mass at " + str(offset),cases[-1])
func _initialize() -> void:
    # The high-offset sources are all accepted by real ConstructionSnapshot.
    # Choose the exact Float64 spacing at each exponent (no unrepresentable inputs).
    run_case(1.0e9, 0.00000011920928955078125)
    run_case(1.0e12, 0.0001220703125)
    run_case(1.0e13, 0.001953125)
    run_case(1.0e14, 0.015625)
    run_case(1.0e15, 0.125)
    print("FABRIC_R56_R2_INDEPENDENT_COM_PRECISION_FALSIFIER=" + JSON.stringify({"checks":checks,"failures":failures,"cases":cases}))
    quit(0 if failures.is_empty() else 1)
