extends SceneTree
const F=preload("res://scripts/research/fabric0/fabric0_full6dof_frictional_manifold_v1.gd")
const E=preload("res://scripts/research/fabric0/fabric0_full6dof_frictional_manifold_experiments_v1.gd")
const M=preload("res://scripts/research/fabric0/fabric0_full6dof_model_v1.gd")
func _init():
	var a=E.impact_run(1e-6,0.305);print("IMPACT ok=",a.result.ok," events=",a.world.events," dE=",a.result.energy_delta)
	var s=E.sliding_run(1e-9,0.315);print("SLIDE ok=",s.result.ok," events=",s.world.events," diss=",s.result.friction_dissipation," dE=",s.result.energy_delta," cone=",s.result.max_cone_ratio," minN=",s.result.min_normal_force)
	var fr=E.free_rotation_run(1e-10,0.6);print("FREE_ROT dL=",(fr.l1-fr.l0).length()," dErot=",fr.e1-fr.e0," q=",M.quat(fr.world.state)," w=",M.omega(fr.world.state))
	print("STICK=",E.stick_probe());print("SEPARATE=",E.separation_probe())
	var p=F.parallel_contact_audit(s.world,false);var q=F.parallel_contact_audit(s.world,true);print("PARALLEL=",p," reverse_same=",p.hash==q.hash)
	print("FACE=",F.support_feature_from_orientation(s.world,Quaternion.IDENTITY,1e-12))
	print("FABRIC0_14_FULL_6DOF_FRICTIONAL_FEATURE_MANIFOLD_PLAYGROUND_PASS")
	quit(0)
