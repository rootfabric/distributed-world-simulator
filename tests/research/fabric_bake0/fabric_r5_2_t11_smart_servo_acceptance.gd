extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Compiler = preload("res://scripts/research/fabric_bake0/r5_t11_smart_servo_compiler_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/r5_t11_smart_servo_runtime_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/smart_servo_descriptor_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t11_smart_servo_fixture.gd")

const DT_S:=0.002
const TICKS:=4096

var checks:=0
var failed:=false

func check(ok:bool,label:String,details=null)->void:
	checks+=1
	if not ok:
		failed=true
		push_error("R5.2-T11: "+label+" "+JSON.stringify(details))

func compile_servo(subsystems:Dictionary,graph:Dictionary,revision:int=0)->Dictionary:
	return Compiler.compile(
		graph,Fixture.build_request(graph,subsystems,revision),"capsule/r5-t11-smart-servo",
		subsystems.motor.descriptor,subsystems.gearbox.descriptor
	)

func reference_step(d:Dictionary,state:Dictionary,target_pos:float,target_vel:float,external_torque:float,dt:float)->Dictionary:
	var ratio:=float(d.gear_ratio)
	var motor_omega:=float(state.motor_angular_velocity_rad_s)
	var output_pos:=float(state.output_position_rad)
	var output_omega:=motor_omega*ratio
	var requested_output_torque:=float(d.position_kp_nm_rad)*(target_pos-output_pos)+float(d.velocity_kd_nm_s_rad)*(target_vel-output_omega)
	var requested_current:=requested_output_torque*ratio/float(d.torque_constant_nm_a)
	var current:=clampf(requested_current,-float(d.max_abs_current_a),float(d.max_abs_current_a))
	var em_torque:=float(d.torque_constant_nm_a)*current
	var reflected_external:=external_torque*ratio
	var next_motor_omega:=motor_omega+(em_torque+reflected_external)*dt/float(d.combined_input_inertia_kg_m2)
	if absf(next_motor_omega)>float(d.max_abs_motor_omega_rad_s):
		return U.failure("REFERENCE_NEXT_SPEED_OUT_OF_DOMAIN")
	var midpoint_motor:=0.5*(motor_omega+next_motor_omega)
	var midpoint_output:=midpoint_motor*ratio
	var next_pos:=output_pos+midpoint_output*dt
	var voltage:=current*float(d.motor_resistance_ohm)+float(d.torque_constant_nm_a)*midpoint_motor
	var electrical:=voltage*current*dt
	var heat:=current*current*float(d.motor_resistance_ohm)*dt
	var boundary:=external_torque*midpoint_output*dt
	var kinetic:=0.5*float(d.combined_input_inertia_kg_m2)*(next_motor_omega*next_motor_omega-motor_omega*motor_omega)
	return U.success({
		"current_command_a":current,
		"requested_current_a":requested_current,
		"current_command_saturated":absf(requested_current)>float(d.max_abs_current_a)+1.0e-12,
		"terminal_voltage_v":voltage,
		"electrical_energy_j":electrical,
		"resistive_heat_j":heat,
		"output_boundary_energy_j":boundary,
		"kinetic_energy_delta_j":kinetic,
		"energy_residual_j":electrical+boundary-heat-kinetic,
		"output_position_rad":next_pos,
		"output_velocity_rad_s":next_motor_omega*ratio,
		"next_state":{"output_position_rad":next_pos,"motor_angular_velocity_rad_s":next_motor_omega},
	})

func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--preflight":
			var ps:=Fixture.compile_subsystems()
			if not ps.success:
				print("FABRIC_R5_2_T11_PREFLIGHT=FAIL");quit(1);return
			var pg:=Fixture.make_graph(ps.details)
			var pc:=compile_servo(ps.details,pg)
			print("FABRIC_R5_2_T11_PREFLIGHT="+("PASS" if pc.success else "FAIL"))
			quit(0 if pc.success else 1);return

	var subsystems:=Fixture.compile_subsystems()
	check(subsystems.success,"T5/T7 subsystems compile",subsystems)
	if not subsystems.success:_finish();return
	var s:Dictionary=subsystems.details
	var graph:=Fixture.make_graph(s)
	var compiled:=compile_servo(s,graph)
	check(compiled.success,"smart servo compile",compiled)
	if not compiled.success:_finish();return
	var descriptor:Dictionary=compiled.details.descriptor
	var artifact:Dictionary=compiled.details.artifact
	var capsule:Dictionary=compiled.details.capsule

	check(int(descriptor.source_component_count)==495,"hierarchical leaf component count",{"count":descriptor.source_component_count})
	check(int(descriptor.source_operation_count)==2846,"hierarchical source operation count",{"count":descriptor.source_operation_count})
	check(int(descriptor.compiled_operation_count)==24,"compiled servo operation count")
	check(float(capsule.operation_compression_ratio)>100.0,"hierarchical compression",{"ratio":capsule.operation_compression_ratio})
	check(int(capsule.runtime_source_traversals_per_execute)==0,"zero source traversal contract")
	check(absf(float(descriptor.gear_ratio)+1.0/36.0)<=1.0e-15,"gear ratio inherited exactly")
	var expected_j:=float(s.motor.descriptor.rotor_inertia_kg_m2)+float(s.gearbox.descriptor.equivalent_input_inertia_kg_m2)
	check(absf(float(descriptor.combined_input_inertia_kg_m2)-expected_j)<=1.0e-15,"combined inertia includes gearbox")
	var expected_current:=minf(
		float(s.motor.descriptor.max_abs_current_a),
		float(s.gearbox.descriptor.max_abs_input_torque_nm)/float(s.motor.descriptor.torque_constant_nm_a)
	)
	check(absf(float(descriptor.max_abs_current_a)-expected_current)<=1.0e-12,"safe current limit derived from both children")

	var inconsistent:=descriptor.duplicate(true)
	inconsistent.combined_input_inertia_kg_m2*=1.01
	var payload:=inconsistent.duplicate(true);payload.erase("descriptor_hash");payload.erase("checksum")
	inconsistent.descriptor_hash=U.canonical_hash(payload);inconsistent.checksum=U.compute_checksum(inconsistent)
	var inconsistent_check:=Descriptor.validate(inconsistent)
	check(not inconsistent_check.success and String(inconsistent_check.error_code)=="SMART_SERVO_DESCRIPTOR_INERTIA_RELATION_MISMATCH","rehash cannot fake combined inertia",inconsistent_check)

	var runtime=Runtime.new()
	var live:=Fixture.live_from(artifact)
	var prep:=runtime.prepare(capsule,artifact,descriptor,live)
	check(prep.success,"runtime prepare",prep)
	if not prep.success:_finish();return

	var state:=runtime.initial_state(0.0,0.0)
	var reference_state:=state.duplicate(true)
	var max_current_error:=0.0
	var max_voltage_error:=0.0
	var max_position_error:=0.0
	var max_velocity_error:=0.0
	var max_energy_residual:=0.0
	var saturation_seen:=false
	var unsaturated_seen:=false
	var settled_seen:=false
	var max_abs_position:=0.0
	for tick in range(TICKS):
		var target_pos:=0.0
		var target_vel:=0.0
		var external_torque:=0.0
		if tick>=256 and tick<1800:
			target_pos=0.75
			external_torque=-8.0
		elif tick>=1800 and tick<3000:
			target_pos=-0.35
			external_torque=5.0
		elif tick>=3000:
			target_pos=0.10
		var fast:=runtime.execute(live,state,target_pos,target_vel,external_torque,DT_S)
		var ref:=reference_step(descriptor,reference_state,target_pos,target_vel,external_torque,DT_S)
		check(fast.success and ref.success,"servo/reference step",{"tick":tick,"fast":fast,"ref":ref})
		if not fast.success or not ref.success:break
		max_current_error=maxf(max_current_error,absf(float(fast.details.current_command_a)-float(ref.details.current_command_a)))
		max_voltage_error=maxf(max_voltage_error,absf(float(fast.details.terminal_voltage_v)-float(ref.details.terminal_voltage_v)))
		max_position_error=maxf(max_position_error,absf(float(fast.details.output_position_rad)-float(ref.details.output_position_rad)))
		max_velocity_error=maxf(max_velocity_error,absf(float(fast.details.output_velocity_rad_s)-float(ref.details.output_velocity_rad_s)))
		max_energy_residual=maxf(max_energy_residual,absf(float(fast.details.energy_residual_j)))
		saturation_seen=saturation_seen or bool(fast.details.current_command_saturated)
		unsaturated_seen=unsaturated_seen or not bool(fast.details.current_command_saturated)
		settled_seen=settled_seen or bool(fast.details.settled)
		max_abs_position=maxf(max_abs_position,absf(float(fast.details.output_position_rad)))
		state=fast.details.next_state
		reference_state=ref.details.next_state

	check(max_current_error==0.0,"current command exact parity")
	check(max_voltage_error<=1.0e-12,"terminal voltage parity",{"error":max_voltage_error})
	check(max_position_error<=1.0e-12,"position state parity",{"error":max_position_error})
	check(max_velocity_error<=1.0e-12,"velocity state parity",{"error":max_velocity_error})
	check(max_energy_residual<=1.0e-10,"servo energy audit",{"residual":max_energy_residual})
	check(unsaturated_seen,"linear controller regime observed")
	check(settled_seen,"settled state observed")
	check(max_abs_position>0.2,"servo actually moves output")

	# Large step must saturate rather than exceed child current envelope.
	var sat:=runtime.execute(live,runtime.initial_state(),10.0,0.0,0.0,DT_S)
	check(sat.success and bool(sat.details.current_command_saturated),"large target saturates safely",sat)
	if sat.success:
		saturation_seen = saturation_seen or bool(sat.details.current_command_saturated)
	check(saturation_seen,"saturated controller regime observed")
	if sat.success:
		check(absf(float(sat.details.current_command_a))<=float(descriptor.max_abs_current_a)+1.0e-12,"saturated current remains inside derived envelope")

	# Gearbox inertia must materially reduce acceleration versus a fake bare-motor model.
	var probe_state:=runtime.initial_state()
	var probe:=runtime.execute(live,probe_state,0.10,0.0,0.0,DT_S)
	check(probe.success,"coupled inertia probe")
	var coupled_accel:=0.0
	var bare_accel:=0.0
	var coupled_to_bare_ratio:=-1.0
	if probe.success:
		var motor_delta:=float(probe.details.next_state.motor_angular_velocity_rad_s)-float(probe_state.motor_angular_velocity_rad_s)
		coupled_accel=motor_delta/DT_S
		var input_torque:=float(descriptor.torque_constant_nm_a)*float(probe.details.current_command_a)
		bare_accel=input_torque/float(descriptor.motor_rotor_inertia_kg_m2)
		coupled_to_bare_ratio=absf(coupled_accel/bare_accel)
		check(coupled_to_bare_ratio>0.0 and coupled_to_bare_ratio<1.0,"gearbox reflected inertia lowers acceleration",{"ratio":coupled_to_bare_ratio})

	# Aluminum gearbox changes only mechanical mass/inertia floor and should accelerate faster for same small command.
	var light_subsystems:=Fixture.compile_subsystems(1.0,"ALUMINUM")
	check(light_subsystems.success,"light gearbox subsystem compiles",light_subsystems)
	var light_accel_ratio:=-1.0
	if light_subsystems.success:
		var ls:Dictionary=light_subsystems.details
		var lg:=Fixture.make_graph(ls)
		var lc:=compile_servo(ls,lg,1)
		check(lc.success,"light gearbox servo compiles",lc)
		if lc.success:
			var lr=Runtime.new()
			var llive:=Fixture.live_from(lc.details.artifact)
			var lp:=lr.prepare(lc.details.capsule,lc.details.artifact,lc.details.descriptor,llive)
			check(lp.success,"light servo prepare")
			if lp.success:
				var lst:=lr.initial_state()
				var lstep:=lr.execute(llive,lst,0.10,0.0,0.0,DT_S)
				check(lstep.success,"light servo probe")
				if lstep.success and probe.success:
					var light_accel:=(float(lstep.details.next_state.motor_angular_velocity_rad_s)-float(lst.motor_angular_velocity_rad_s))/DT_S
					light_accel_ratio=absf(light_accel/coupled_accel)
					check(light_accel_ratio>1.0,"lower gearbox inertia accelerates faster",{"ratio":light_accel_ratio})

	# Child descriptor mismatch must fail hierarchy compile.
	var mismatch:=Compiler.compile(
		graph,Fixture.build_request(graph,s,2),"capsule/r5-t11-smart-servo",
		s.motor.descriptor,
		light_subsystems.details.gearbox.descriptor if light_subsystems.success else {}
	)
	check(not mismatch.success and String(mismatch.error_code)=="SMART_SERVO_GEARBOX_DESCRIPTOR_BINDING_MISMATCH","child descriptor mismatch rejected",mismatch)

	# Snapshot replay proves no hidden controller/runtime state.
	var replay_a:=runtime.initial_state(0.2,0.0)
	var replay_b:=replay_a.duplicate(true)
	var replay_error:=0.0
	for tick in range(256):
		var a:=runtime.execute(live,replay_a,-0.15,0.0,-2.0,DT_S)
		var b:=runtime.execute(live,replay_b,-0.15,0.0,-2.0,DT_S)
		check(a.success and b.success,"snapshot replay",{"tick":tick})
		if not a.success or not b.success:break
		replay_error=maxf(replay_error,absf(float(a.details.output_position_rad)-float(b.details.output_position_rad)))
		replay_error=maxf(replay_error,absf(float(a.details.output_velocity_rad_s)-float(b.details.output_velocity_rad_s)))
		replay_a=a.details.next_state;replay_b=b.details.next_state
	check(replay_error==0.0,"snapshot replay exact")

	var stale:=live.duplicate(true);stale.artifact_state="STALE"
	check(not runtime.execute(stale,runtime.initial_state(),0.1,0.0,0.0,DT_S).success,"STALE rejected")
	var invalid:=live.duplicate(true);invalid.invalidations=[{"synthetic":true}]
	check(not runtime.execute(invalid,runtime.initial_state(),0.1,0.0,0.0,DT_S).success,"invalidation rejected")

	var deterministic:={
		"schema":"planet_simulator.fabric_r5_2_t11_smart_servo_result.v1",
		"graph_hash":graph.graph_hash,
		"descriptor_hash":descriptor.descriptor_hash,
		"capsule_checksum":capsule.checksum,
		"leaf_source_components":int(descriptor.source_component_count),
		"leaf_source_operations":int(descriptor.source_operation_count),
		"compiled_operations":int(descriptor.compiled_operation_count),
		"operation_compression_ratio":float(capsule.operation_compression_ratio),
		"runtime_source_component_traversals":0,
		"gear_ratio":float(descriptor.gear_ratio),
		"combined_input_inertia_kg_m2":float(descriptor.combined_input_inertia_kg_m2),
		"max_abs_current_a":float(descriptor.max_abs_current_a),
		"max_abs_output_torque_nm":float(descriptor.max_abs_output_torque_nm),
		"sequence_ticks":TICKS,
		"maximum_current_command_error_a":max_current_error,
		"maximum_terminal_voltage_error_v":max_voltage_error,
		"maximum_position_state_error_rad":max_position_error,
		"maximum_velocity_state_error_rad_s":max_velocity_error,
		"maximum_energy_residual_j":max_energy_residual,
		"saturation_seen":saturation_seen,
		"settled_seen":settled_seen,
		"coupled_to_bare_acceleration_ratio":coupled_to_bare_ratio,
		"light_gearbox_acceleration_ratio":light_accel_ratio,
		"snapshot_replay_error":replay_error,
		"descriptor_inertia_relation_error":String(inconsistent_check.get("error_code","")),
		"child_descriptor_binding_error":String(mismatch.get("error_code","")),
	}
	print("FABRIC_R5_2_T11_RESULT="+JSON.stringify(deterministic))
	if not failed:
		print("FABRIC R5.2 T11 SMART SERVO: PASS (%d assertions)"%checks)
	quit(1 if failed else 0)

func _finish()->void:
	print("FABRIC R5.2 T11 SMART SERVO: FAIL (%d assertions)"%checks)
	quit(1)
