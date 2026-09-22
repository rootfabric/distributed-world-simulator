extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_t10_laser_cannon_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t10_laser_cannon_runtime_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/laser_cannon_descriptor_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t10_laser_cannon_fixture.gd")

const PowerRuntime = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_runtime_v1.gd")
const EmitterRuntime = preload("res://scripts/research/fabric_bake0/r5_t9_laser_emitter_runtime_v1.gd")
const CoolingRuntime = preload("res://scripts/research/fabric_bake0/r5_t8_cooling_loop_runtime_v1.gd")

const DT_S:=0.002
const TICKS:=2048

var checks:=0
var failed:=false

func check(ok:bool,label:String,details=null)->void:
	checks+=1
	if not ok:
		failed=true
		push_error("R5.2-T10: "+label+" "+JSON.stringify(details))

func _compile(subsystems:Dictionary,graph:Dictionary,revision:int=0)->Dictionary:
	return Compiler.compile(
		graph,
		Fixture.build_request(graph,subsystems,revision),
		"capsule/r5-t10-laser-cannon",
		subsystems.power.descriptor,
		subsystems.emitter.descriptor,
		subsystems.cooling.descriptor
	)

func _manual_prepare(subsystems:Dictionary)->Dictionary:
	var p=PowerRuntime.new()
	var e=EmitterRuntime.new()
	var c=CoolingRuntime.new()
	var pb:=Fixture.subsystem_bundle(subsystems.power,"power")
	var eb:=Fixture.subsystem_bundle(subsystems.emitter,"emitter")
	var cb:=Fixture.subsystem_bundle(subsystems.cooling,"cooling")
	var r:=p.prepare(pb.capsule,pb.artifact,pb.descriptor,pb.live)
	if not r.success:return r
	r=e.prepare(eb.capsule,eb.artifact,eb.descriptor,eb.live)
	if not r.success:return r
	r=c.prepare(cb.capsule,cb.artifact,cb.descriptor,cb.live)
	if not r.success:return r
	return U.success({"power":p,"emitter":e,"cooling":c,"pb":pb,"eb":eb,"cb":cb})

func _manual_step(manual:Dictionary,descriptor:Dictionary,state:Dictionary,bus_v:float,current:float,pwm:float,flow:float,ambient:float,range_m:float,dt:float)->Dictionary:
	var t:=float(state.plate_temperature_k)
	var emitter: Dictionary = manual.emitter.execute(manual.eb.live,current,t,dt)
	if not emitter.success:return emitter
	var pd:Dictionary=manual.pb.descriptor
	var factor:=1.0+float(pd.resistance_temp_coefficient_per_k)*(t-float(pd.reference_temperature_k))
	var path_r:=float(pd.positive_path_resistance_ref_ohm)*maxf(factor,0.05)
	var duty:=(float(emitter.details.terminal_voltage_v)+current*path_r)/bus_v
	var stage: Dictionary = manual.power.execute(manual.pb.live,bus_v,duty,current,pwm,t,dt)
	if not stage.success:return stage
	var muzzle:=float(emitter.details.optical_energy_j)*float(descriptor.optics_total_transmission_ratio)
	var optics_heat:=float(emitter.details.optical_energy_j)-muzzle
	var divergence:=float(emitter.details.beam_divergence_half_angle_rad)/float(descriptor.optical_expansion_ratio)
	var output_radius:=0.5*float(descriptor.clear_aperture_diameter_m)
	var spot_radius:=sqrt(output_radius*output_radius+pow(range_m*divergence,2.0))
	var spot_fluence:=muzzle/(PI*spot_radius*spot_radius)
	var stage_heat:=float(stage.details.conduction_heat_j)+float(stage.details.switching_heat_j)
	var total_heat:=stage_heat+float(emitter.details.waste_heat_j)+optics_heat
	var cooling: Dictionary = manual.cooling.execute(manual.cb.live,state,total_heat/dt,flow,ambient,dt)
	if not cooling.success:return cooling
	return U.success({
		"duty_ratio":duty,
		"bus_input_energy_j":stage.details.electrical_input_energy_j,
		"muzzle_optical_energy_j":muzzle,
		"optics_absorbed_heat_j":optics_heat,
		"total_internal_heat_j":total_heat,
		"cooling_pump_hydraulic_energy_j":cooling.details.pump_hydraulic_energy_j,
		"beam_divergence_half_angle_rad":divergence,
		"spot_radius_m":spot_radius,
		"spot_fluence_j_m2":spot_fluence,
		"wavelength_m":emitter.details.wavelength_m,
		"next_state":cooling.details.next_state,
	})

func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--preflight":
			var ps:=Fixture.compile_subsystems()
			if not ps.success:
				print("FABRIC_R5_2_T10_PREFLIGHT=FAIL")
				quit(1)
				return
			var pg:=Fixture.make_graph(ps.details)
			var pc:=_compile(ps.details,pg)
			if not pc.success:
				print("FABRIC_R5_2_T10_PREFLIGHT=FAIL")
				quit(1)
				return
			print("FABRIC_R5_2_T10_PREFLIGHT=PASS")
			quit(0)
			return
	var subsystems:=Fixture.compile_subsystems()
	check(subsystems.success,"subsystems compile",subsystems)
	if not subsystems.success:
		_finish();return
	var s:Dictionary=subsystems.details
	var graph:=Fixture.make_graph(s)
	var compiled:=_compile(s,graph)
	check(compiled.success,"T10 compile",compiled)
	if not compiled.success:
		_finish();return
	var descriptor:Dictionary=compiled.details.descriptor
	var artifact:Dictionary=compiled.details.artifact
	var capsule:Dictionary=compiled.details.capsule
	check(int(descriptor.source_component_count)==642,"hierarchical leaf component count",{"count":descriptor.source_component_count})
	check(int(descriptor.source_operation_count)==3848,"hierarchical full operation count",{"count":descriptor.source_operation_count})
	check(int(descriptor.compiled_operation_count)==24,"assembly operation count")
	check(float(capsule.operation_compression_ratio)>100.0,"hierarchical operation compression",{"ratio":capsule.operation_compression_ratio})
	check(int(capsule.runtime_source_traversals_per_execute)==0,"zero assembly source traversals")
	check(float(descriptor.optical_expansion_ratio)==4.0,"4x optical expansion")
	check(float(descriptor.input_clear_aperture_area_m2)>=float(descriptor.emitter_aperture_area_m2),"input optic does not clip emitter")

	var inconsistent:Dictionary=descriptor.duplicate(true)
	inconsistent.optics_total_transmission_ratio*=1.01
	var payload:=inconsistent.duplicate(true)
	payload.erase("descriptor_hash");payload.erase("checksum")
	inconsistent.descriptor_hash=U.canonical_hash(payload)
	inconsistent.checksum=U.compute_checksum(inconsistent)
	var inconsistent_check:=Descriptor.validate(inconsistent)
	check(not inconsistent_check.success and String(inconsistent_check.error_code)=="LASER_CANNON_DESCRIPTOR_TRANSMISSION_RELATION_MISMATCH","rehashed transmission inconsistency rejected",inconsistent_check)

	var runtime=Runtime.new()
	var live:=Fixture.live_from(artifact)
	var prep:=runtime.prepare(
		capsule,artifact,descriptor,live,
		Fixture.subsystem_bundle(s.power,"power"),
		Fixture.subsystem_bundle(s.emitter,"emitter"),
		Fixture.subsystem_bundle(s.cooling,"cooling")
	)
	check(prep.success,"T10 runtime prepare",prep)
	var manual:=_manual_prepare(s)
	check(manual.success,"manual hierarchy prepare",manual)
	if not prep.success or not manual.success:
		_finish();return
	var state:=runtime.initial_state(300.0)
	var manual_state: Dictionary = manual.details.cooling.initial_state(300.0)
	check(JSON.stringify(state)==JSON.stringify(manual_state),"initial caller-owned state parity")

	var max_muzzle_error:=0.0
	var max_heat_error:=0.0
	var max_spot_error:=0.0
	var max_state_error:=0.0
	var max_energy_residual:=0.0
	var emitted_energy:=0.0
	var pump_energy:=0.0
	var max_plate_temperature:=float(state.plate_temperature_k)
	var zero_drive_zero_optical:=false
	for tick in range(TICKS):
		var cycle:=tick%128
		var current:=400.0 if cycle<32 else 0.0
		var range_m:=500.0+1000.0*float(tick%257)/256.0
		var bus_v:=480.0
		var pwm:=20000.0
		var flow:=0.25
		var ambient:=294.0+2.0*sin(float(tick)*0.007)
		var fast:=runtime.execute(live,state,bus_v,current,pwm,flow,ambient,range_m,DT_S)
		var direct:=_manual_step(manual.details,descriptor,manual_state,bus_v,current,pwm,flow,ambient,range_m,DT_S)
		check(fast.success and direct.success,"hierarchical/manual execute",{"tick":tick,"fast":fast,"direct":direct})
		if not fast.success or not direct.success:break
		max_muzzle_error=maxf(max_muzzle_error,absf(float(fast.details.muzzle_optical_energy_j)-float(direct.details.muzzle_optical_energy_j)))
		max_heat_error=maxf(max_heat_error,absf(float(fast.details.total_internal_heat_j)-float(direct.details.total_internal_heat_j)))
		max_spot_error=maxf(max_spot_error,absf(float(fast.details.spot_radius_m)-float(direct.details.spot_radius_m)))
		for field in ["plate_temperature_k","hot_coolant_temperature_k","radiator_temperature_k","cold_coolant_temperature_k"]:
			max_state_error=maxf(max_state_error,absf(float(fast.details.next_state[field])-float(direct.details.next_state[field])))
		max_energy_residual=maxf(max_energy_residual,absf(float(fast.details.energy_residual_j)))
		emitted_energy+=float(fast.details.muzzle_optical_energy_j)
		pump_energy+=float(fast.details.cooling_pump_hydraulic_energy_j)
		max_plate_temperature=maxf(max_plate_temperature,float(fast.details.next_state.plate_temperature_k))
		if current==0.0 and float(fast.details.muzzle_optical_energy_j)==0.0:
			zero_drive_zero_optical=true
		check(int(fast.details.runtime_source_component_traversals)==0,"assembly traversal zero",{"tick":tick})
		check(int(fast.details.subsystem_runtime_source_traversals.power_stage)==0 and int(fast.details.subsystem_runtime_source_traversals.laser_emitter)==0 and int(fast.details.subsystem_runtime_source_traversals.cooling)==0,"subcapsule source traversal zero",{"tick":tick})
		state=fast.details.next_state
		manual_state=direct.details.next_state

	check(max_muzzle_error<=1.0e-12,"manual muzzle parity",{"error":max_muzzle_error})
	check(max_heat_error<=1.0e-12,"manual heat parity",{"error":max_heat_error})
	check(max_spot_error<=1.0e-12,"manual spot parity",{"error":max_spot_error})
	check(max_state_error<=1.0e-12,"manual state parity",{"error":max_state_error})
	check(max_energy_residual<=1.0e-8,"whole-cannon energy audit",{"residual":max_energy_residual})
	check(emitted_energy>0.0 and pump_energy>0.0,"emission and cooling work both observed")
	check(zero_drive_zero_optical,"zero drive produces zero muzzle energy")
	check(max_plate_temperature>300.0,"thermal state responds to firing")

	# Beam expander must reduce far-field divergence relative to bare emitter.
	var emitter_runtime=EmitterRuntime.new()
	var eb:=Fixture.subsystem_bundle(s.emitter,"emitter")
	var ep:=emitter_runtime.prepare(eb.capsule,eb.artifact,eb.descriptor,eb.live)
	check(ep.success,"emitter probe prepare")
	var bare:=emitter_runtime.execute(eb.live,400.0,300.0,DT_S)
	var cannon_probe:=runtime.execute(live,runtime.initial_state(300.0),480.0,400.0,20000.0,0.25,294.0,1000.0,DT_S)
	check(bare.success and cannon_probe.success,"divergence probes execute")
	var divergence_ratio:=-1.0
	if bare.success and cannon_probe.success:
		divergence_ratio=float(cannon_probe.details.beam_divergence_half_angle_rad)/float(bare.details.beam_divergence_half_angle_rad)
		check(absf(divergence_ratio-0.25)<=1.0e-12,"4x expander quarters divergence",{"ratio":divergence_ratio})

	# Lower-transmission optics trade muzzle energy for additional absorbed heat.
	var lossy_graph:=Fixture.make_graph(s,0.98)
	var lossy_compiled:=_compile(s,lossy_graph,1)
	check(lossy_compiled.success,"lossy optics variant compiles",lossy_compiled)
	var lossy_muzzle_ratio:=-1.0
	if lossy_compiled.success:
		var lossy_runtime=Runtime.new()
		var lp:=lossy_runtime.prepare(
			lossy_compiled.details.capsule,lossy_compiled.details.artifact,lossy_compiled.details.descriptor,Fixture.live_from(lossy_compiled.details.artifact),
			Fixture.subsystem_bundle(s.power,"power"),Fixture.subsystem_bundle(s.emitter,"emitter"),Fixture.subsystem_bundle(s.cooling,"cooling")
		)
		check(lp.success,"lossy runtime prepare")
		if lp.success:
			var base_step:=runtime.execute(live,runtime.initial_state(300.0),480.0,400.0,20000.0,0.25,294.0,1000.0,DT_S)
			var lossy_step:=lossy_runtime.execute(Fixture.live_from(lossy_compiled.details.artifact),lossy_runtime.initial_state(300.0),480.0,400.0,20000.0,0.25,294.0,1000.0,DT_S)
			check(base_step.success and lossy_step.success,"lossy probes execute")
			if base_step.success and lossy_step.success:
				lossy_muzzle_ratio=float(lossy_step.details.muzzle_optical_energy_j)/float(base_step.details.muzzle_optical_energy_j)
				check(lossy_muzzle_ratio<1.0,"lossier optics reduce muzzle energy")
				check(float(lossy_step.details.optics_absorbed_heat_j)>float(base_step.details.optics_absorbed_heat_j),"lossier optics raise optics heat")

	# Geometry that clips the emitter must fail at compile time.
	var clipped_graph:=Fixture.make_graph(s,0.995,50000.0,0.04,0.05,0.20)
	var clipped:=_compile(s,clipped_graph,2)
	check(not clipped.success and String(clipped.error_code)=="LASER_CANNON_INPUT_APERTURE_CLIPS_EMITTER","clipped optical train fails closed",clipped)

	# An intentionally fragile optic can compile but fail a firing pulse by fluence.
	var fragile_graph:=Fixture.make_graph(s,0.995,1.0,0.12,0.05,0.20)
	var fragile_compiled:=_compile(s,fragile_graph,3)
	check(fragile_compiled.success,"fragile optic compiles as valid low-fluence part")
	var fluence_limit_error:=""
	if fragile_compiled.success:
		var fragile_runtime=Runtime.new()
		var fp:=fragile_runtime.prepare(
			fragile_compiled.details.capsule,fragile_compiled.details.artifact,fragile_compiled.details.descriptor,Fixture.live_from(fragile_compiled.details.artifact),
			Fixture.subsystem_bundle(s.power,"power"),Fixture.subsystem_bundle(s.emitter,"emitter"),Fixture.subsystem_bundle(s.cooling,"cooling")
		)
		check(fp.success,"fragile runtime prepare")
		if fp.success:
			var shot:=fragile_runtime.execute(Fixture.live_from(fragile_compiled.details.artifact),fragile_runtime.initial_state(300.0),480.0,400.0,20000.0,0.25,294.0,1000.0,DT_S)
			fluence_limit_error=String(shot.get("error_code",""))
			check(not shot.success and fluence_limit_error=="LASER_CANNON_RUNTIME_OPTICS_FLUENCE_LIMIT","fragile optics reject firing fluence",shot)

	# Caller-owned state replay must be exact.
	var snapshot:=runtime.initial_state(300.0)
	var replay_a:Dictionary=snapshot.duplicate(true)
	var replay_b:Dictionary=snapshot.duplicate(true)
	var replay_error:=0.0
	for tick in range(128):
		var a:=runtime.execute(live,replay_a,480.0,400.0,20000.0,0.25,294.0,750.0,DT_S)
		var b:=runtime.execute(live,replay_b,480.0,400.0,20000.0,0.25,294.0,750.0,DT_S)
		check(a.success and b.success,"snapshot replay execute",{"tick":tick})
		if not a.success or not b.success:break
		replay_error=maxf(replay_error,absf(float(a.details.muzzle_optical_energy_j)-float(b.details.muzzle_optical_energy_j)))
		replay_error=maxf(replay_error,absf(float(a.details.next_state.plate_temperature_k)-float(b.details.next_state.plate_temperature_k)))
		replay_a=a.details.next_state
		replay_b=b.details.next_state
	check(replay_error==0.0,"snapshot replay exact",{"error":replay_error})

	var stale:=live.duplicate(true);stale.artifact_state="STALE"
	check(not runtime.execute(stale,runtime.initial_state(300.0),480.0,400.0,20000.0,0.25,294.0,1000.0,DT_S).success,"STALE rejected")
	var invalid:=live.duplicate(true);invalid.invalidations=[{"synthetic":true}]
	check(not runtime.execute(invalid,runtime.initial_state(300.0),480.0,400.0,20000.0,0.25,294.0,1000.0,DT_S).success,"invalidation rejected")

	var deterministic:={
		"schema":"planet_simulator.fabric_r5_2_t10_laser_cannon_result.v1",
		"graph_hash":graph.graph_hash,
		"descriptor_hash":descriptor.descriptor_hash,
		"capsule_checksum":capsule.checksum,
		"leaf_source_components":int(descriptor.source_component_count),
		"leaf_source_operations":int(descriptor.source_operation_count),
		"assembly_operations":int(descriptor.compiled_operation_count),
		"operation_compression_ratio":float(capsule.operation_compression_ratio),
		"runtime_source_component_traversals":0,
		"optical_expansion_ratio":float(descriptor.optical_expansion_ratio),
		"optics_total_transmission_ratio":float(descriptor.optics_total_transmission_ratio),
		"sequence_ticks":TICKS,
		"maximum_manual_muzzle_error_j":max_muzzle_error,
		"maximum_manual_heat_error_j":max_heat_error,
		"maximum_manual_spot_radius_error_m":max_spot_error,
		"maximum_manual_state_error_k":max_state_error,
		"maximum_whole_energy_residual_j":max_energy_residual,
		"total_muzzle_optical_energy_j":emitted_energy,
		"total_pump_hydraulic_energy_j":pump_energy,
		"max_plate_temperature_k":max_plate_temperature,
		"divergence_ratio_vs_bare_emitter":divergence_ratio,
		"lossy_optics_muzzle_ratio":lossy_muzzle_ratio,
		"clipped_geometry_error":String(clipped.get("error_code","")),
		"fluence_limit_error":fluence_limit_error,
		"snapshot_replay_error":replay_error,
		"descriptor_relation_error":String(inconsistent_check.get("error_code","")),
	}
	print("FABRIC_R5_2_T10_RESULT="+JSON.stringify(deterministic))
	if not failed:
		print("FABRIC R5.2 T10 LASER CANNON: PASS (%d assertions)"%checks)
	quit(1 if failed else 0)

func _finish()->void:
	print("FABRIC R5.2 T10 LASER CANNON: FAIL (%d assertions)"%checks)
	quit(1)
