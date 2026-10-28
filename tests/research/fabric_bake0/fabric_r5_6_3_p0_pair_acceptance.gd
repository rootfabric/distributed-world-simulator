extends SceneTree
const Pair = preload("res://scripts/research/fabric_bake0/r5_6_3_p0_coupled_pair_predictor_v1.gd")
var checks := 0
var failures: Array[String] = []
var denied := 0

func ck(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("R563_P0_FAIL " + description)

func close(a: float, b: float, tolerance: float = 1.0e-9) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= tolerance * maxf(1.0, maxf(absf(a), absf(b)))

func close_vec(a: Array, b: Array, tolerance: float = 1.0e-9) -> bool:
	if a.size() != 3 or b.size() != 3:
		return false
	for i in range(3):
		if not close(float(a[i]), float(b[i]), tolerance):
			return false
	return true

func body(id: String, mass: float, x: Array, v: Array) -> Dictionary:
	return {"part_id": id, "mass_kg": mass, "position_m": x, "velocity_mps": v}

func link(stiffness: float, rest: float, damping: float = 0.0) -> Dictionary:
	return {"stiffness_npm": stiffness, "rest_length_m": rest, "damping_nspm": damping}

func neg(result: Dictionary, code: String, description: String) -> void:
	var passed: bool = not bool(result.get("success", false)) and String(result.get("error_code", "")) == code
	ck(passed, description)
	if passed:
		denied += 1

func _initialize() -> void:
	var a := body("part/a", 2.0, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	var b := body("part/b", 3.0, [1.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	var equilibrium := Pair.predict(a, b, link(20.0, 1.0), 0.005)
	ck(equilibrium.success, "static equilibrium accepted")
	if equilibrium.success:
		ck(close_vec(equilibrium.details.part_a.position_m, a.position_m), "equilibrium a position")
		ck(close_vec(equilibrium.details.part_b.position_m, b.position_m), "equilibrium b position")
		ck(close(equilibrium.details.energy_before_j, 0.0), "zero equilibrium energy")
		ck(equilibrium.details.canonical_writes == 0 and equilibrium.details.authority == "DERIVED_PREDICTION_ONLY", "read-only publication")
	b.position_m = [1.3, 0.0, 0.0]
	var stretched := Pair.predict(a, b, link(20.0, 1.0), 0.005)
	ck(stretched.success, "stretched pair accepted")
	if stretched.success:
		ck(stretched.details.force_on_a_n[0] > 0.0 and stretched.details.force_on_b_n[0] < 0.0, "restoring force direction")
		ck(close_vec(stretched.details.force_on_a_n, [-stretched.details.force_on_b_n[0], -stretched.details.force_on_b_n[1], -stretched.details.force_on_b_n[2]]), "Newton third law")
		ck(close_vec(stretched.details.momentum_before_kgmps, stretched.details.momentum_after_kgmps), "linear momentum conservation")
		ck(close(2.0 * stretched.details.part_a.position_m[0] + 3.0 * stretched.details.part_b.position_m[0], 3.0*1.3), "fixed center of mass")
	var swapped := Pair.predict(b, a, link(20.0, 1.0), 0.005)
	ck(swapped.success, "reverse IDs accepted")
	if stretched.success and swapped.success:
		ck(close_vec(swapped.details.part_a.position_m, stretched.details.part_b.position_m), "permutation equivariance B")
		ck(close_vec(swapped.details.part_b.position_m, stretched.details.part_a.position_m), "permutation equivariance A")
	var shifted_a := a.duplicate(true)
	var shifted_b := b.duplicate(true)
	shifted_a.position_m = [100.0, -5.0, 9.0]
	shifted_b.position_m = [101.3, -5.0, 9.0]
	var shifted := Pair.predict(shifted_a, shifted_b, link(20.0, 1.0), 0.005)
	ck(shifted.success, "translation accepted")
	if stretched.success and shifted.success:
		ck(close(shifted.details.part_a.position_m[0] - stretched.details.part_a.position_m[0], 100.0), "x translation invariance")
		ck(close(shifted.details.energy_after_j, stretched.details.energy_after_j), "translation energy invariant")
	# Pure damping: initial radial motion toward each other, spring at rest.
	var damp_a := body("part/a", 2.0, [0.0,0.0,0.0], [0.5,0.0,0.0])
	var damp_b := body("part/b", 3.0, [1.0,0.0,0.0], [-0.5,0.0,0.0])
	var damp := Pair.predict(damp_a,damp_b,link(20.0,1.0,1.0),0.005)
	ck(damp.success, "damped moving pair accepted")
	if damp.success:
		ck(damp.details.energy_after_j < damp.details.energy_before_j, "damping removes energy in small dt scenario")
		ck(close_vec(damp.details.momentum_before_kgmps,damp.details.momentum_after_kgmps),"damped momentum conservation")
	var work_a := a.duplicate(true)
	var work_b := b.duplicate(true)
	var initial_e: float = float(stretched.details.energy_before_j) if stretched.success else 0.0
	var max_rel_energy: float = 0.0
	for i in range(200):
		var step := Pair.predict(work_a, work_b, link(20.0,1.0),0.001)
		ck(step.success,"bounded step %d accepted" % i)
		if not step.success:
			break
		max_rel_energy = maxf(max_rel_energy,absf(float(step.details.energy_after_j) - initial_e) / maxf(initial_e,1.0e-12))
		ck(close_vec(step.details.momentum_before_kgmps,step.details.momentum_after_kgmps,1.0e-8),"step %d momentum" % i)
		work_a.position_m = step.details.part_a.position_m
		work_a.velocity_mps = step.details.part_a.velocity_mps
		work_b.position_m = step.details.part_b.position_m
		work_b.velocity_mps = step.details.part_b.velocity_mps
	ck(max_rel_energy < 0.01,"bounded symplectic energy error (not exact conservation)")
	var bad_mass := a.duplicate(true)
	bad_mass.mass_kg=0.0
	neg(Pair.predict(bad_mass,b,link(20.0,1.0),0.005),"R563_MASS_UNSAFE","zero mass rejected")
	bad_mass.mass_kg=INF
	neg(Pair.predict(bad_mass,b,link(20.0,1.0),0.005),"R563_MASS_UNSAFE","nonfinite mass rejected")
	neg(Pair.predict(a,a,link(20.0,1.0),0.005),"R563_PART_IDS_INVALID","self-coupling rejected")
	neg(Pair.predict(a,b,link(20.0,1.0),NAN),"R563_DT_UNSAFE","NaN timestep rejected")
	neg(Pair.predict(a,b,link(20.0,1.0),0.0),"R563_DT_UNSAFE","zero timestep rejected")
	neg(Pair.predict(a,b,link(20.0,1.0),0.11),"R563_DT_UNSAFE","overbudget timestep rejected")
	neg(Pair.predict(a,b,link(1.0e12,1.0),0.05),"R563_UNSTABLE_STEP","stiff unstable pair rejected")
	neg(Pair.predict(a,b,link(20.0,1.0,1.0e12),0.005),"R563_UNSTABLE_STEP","overdamped explicit step rejected")
	var coincident := a.duplicate(true)
	coincident.part_id = "part/c"
	neg(Pair.predict(a,coincident,link(20.0,1.0),0.005),"R563_DIRECTION_DEGENERATE","coincident positions rejected")
	var bad_vec := b.duplicate(true)
	bad_vec.position_m=[1.0,2.0]
	neg(Pair.predict(a,bad_vec,link(20.0,1.0),0.005),"R563_VECTOR_INVALID","vector length rejected")
	bad_vec.position_m=[INF,0.0,0.0]
	neg(Pair.predict(a,bad_vec,link(20.0,1.0),0.005),"R563_VECTOR_UNSAFE","nonfinite position rejected")
	bad_vec.position_m=[1.0,0.0,0.0]
	bad_vec["forged_owner_receipt"]="PASS"
	neg(Pair.predict(a,bad_vec,link(20.0,1.0),0.005),"R563_BODY_FIELDS_INVALID","surplus authority field rejected")
	# 3-D coupling and 90-degree rigid rotation: the model must be isotropic.
	var three_a := body("part/a", 1.5, [0.0, 0.0, 0.0], [0.1, 0.2, -0.1])
	var three_b := body("part/b", 2.5, [1.0, 2.0, 2.0], [-0.2, 0.0, 0.3])
	var three := Pair.predict(three_a, three_b, link(13.0, 2.5, 0.2), 0.004)
	ck(three.success, "3D coupling accepted")
	if three.success:
		ck(close_vec(three.details.momentum_before_kgmps, three.details.momentum_after_kgmps), "3D momentum")
		ck(absf(three.details.force_on_a_n[1]) > 0.0 and absf(three.details.force_on_a_n[2]) > 0.0, "3D all axes coupled")
	var rot_a := three_a.duplicate(true)
	var rot_b := three_b.duplicate(true)
	rot_a.position_m = [-three_a.position_m[1], three_a.position_m[0], three_a.position_m[2]]
	rot_a.velocity_mps = [-three_a.velocity_mps[1], three_a.velocity_mps[0], three_a.velocity_mps[2]]
	rot_b.position_m = [-three_b.position_m[1], three_b.position_m[0], three_b.position_m[2]]
	rot_b.velocity_mps = [-three_b.velocity_mps[1], three_b.velocity_mps[0], three_b.velocity_mps[2]]
	var rotated := Pair.predict(rot_a, rot_b, link(13.0, 2.5, 0.2), 0.004)
	ck(rotated.success, "rotation input accepted")
	if three.success and rotated.success:
		ck(close_vec(rotated.details.force_on_a_n, [-three.details.force_on_a_n[1], three.details.force_on_a_n[0], three.details.force_on_a_n[2]]), "rotation-equivariant force")
		ck(close(rotated.details.energy_after_j, three.details.energy_after_j), "rotation-invariant energy")
	print("FABRIC_R563_P0_RESULT=" + JSON.stringify({"checks": checks, "failures": failures, "negatives": denied, "max_energy_drift_ratio": max_rel_energy}, "", false, true))
	quit(0 if failures.is_empty() else 1)
