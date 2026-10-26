extends SceneTree
## Independently authored R2F frozen-product hostile generation verifier.
## NEVER change product source; verify exact original errors, cancellable
## worker lifetime, source immutability and fail-closed policy drift.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Runtime = preload("res://scripts/research/ecology/v2/ecology_runtime_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Fixture = preload("res://validation/ecology/evo_arch2_a14_7/a147_scale_fixture.gd")
const Lab = preload("res://scripts/labs/ecology/eco_arch2_polygon_lab.gd")
const Checkpoint = preload("res://scripts/research/ecology/v2/ecology_runtime_checkpoint_v1.gd")
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("A147_R2F_FRESH_FAIL " + msg)

func make_controller(source: Dictionary) -> Object:
	var h = Lab.new()
	h._build_manifest()
	var manifest: Dictionary = h.manifest.duplicate(true)
	h.free()
	manifest.seed = 20261015
	manifest.mutation.mutations_enabled = false
	var c = Controller.new()
	var r: Dictionary = c.initialize(manifest,{})
	check(bool(r.get("success", false)), "true LAB Controller initialized")
	if bool(r.get("success", false)):
		c._runtime = source.duplicate(true)
	return c

func _run() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() != 2 or String(argv[0]) != "--population" \
			or not String(argv[1]) in ["32","96"]:
		check(false,"require independent 32/96 exact")
		_finish()
		return
	var n: int = int(argv[1])
	var src: Dictionary = Fixture.new().create_population(n)
	check(not src.is_empty(), "canonical original source present")
	if src.is_empty():
		_finish()
		return
	var source_bytes: String = C.encode(src)
	var c = make_controller(src)
	var options: Dictionary = c._canonical_step_options().options
	var ref: Dictionary = Runtime.step_spatial_parallel_advance(
		src,options,4,64,4,4)
	check(bool(ref.get("success", false)), "original authoritative A13 reference")
	if not bool(ref.get("success", false)):
		_finish()
		return
	var bad: Dictionary = src.duplicate(true)
	bad.field.owner_epoch = int(bad.field.owner_epoch)+1
	var expected: String = Runtime.validate(bad)
	var invalid_source: Dictionary = Runtime.resume_staged_global_tick(
		bad,options,{},1,4096,8388608,1)
	var invalid_cursor: Dictionary = Runtime.resume_staged_global_tick(
		src,options,{},1,4096,8388608,1)
	check(not expected.is_empty() \
		and String(invalid_source.get("error","")) == expected \
		and String(invalid_cursor.get("error","")) == "RUNTIME_STAGED_CURSOR_SCHEMA",
		"full source error PRECEDES untrusted cursor schema failure")
	check(C.encode(src) == source_bytes, "invalid direct attempts cannot mutate state")

	var controlled = make_controller(src)
	var original: Dictionary = controlled._runtime.duplicate(true)
	var t: Dictionary = controlled.run_staged_frame(
		1000000000,1,1,64,8388608,true,4096,
		true,false,true,true,16,4)
	check(bool(t.get("success", false)) \
		and controlled.has_pending_staged_tick() \
		and not bool(t.get("complete", true)) and controlled.tick()==0,
		"genuine E3 16/4 worker dispatched, no speculative publication")
	var changed_batch: Dictionary = controlled.run_staged_frame(
		1000000000,1,1,64,8388608,true,4096,
		true,false,true,true,1,4)
	check(not bool(changed_batch.get("success",true)) \
		and String(changed_batch.get("error","")).contains(
			"R2B_WORKSET_BATCH_CHANGED") \
		and controlled.tick()==0,
		"changing workset batch in-flight fails closed")
	var cancelled: Dictionary = controlled.cancel_staged_tick()
	check(bool(cancelled.get("cancelled",false)), "failed policy generation can be cancelled")
	await _drain(controlled)
	check(int(controlled.get_staged_telemetry().off_main.jobs_committed)==0 \
		and C.encode(controlled._runtime)==C.encode(original),
		"cancelled changed-batch worker cannot publish original global A4")
	var different = make_controller(src)
	var first: Dictionary = different.run_staged_frame(
		1000000000,1,1,64,8388608,true,4096,
		true,false,true,true,16,4)
	check(bool(first.get("success",false)) and different.has_pending_staged_tick(),
		"separate full E3 16/4 worker starts")
	var changed_threads: Dictionary = different.run_staged_frame(
		1000000000,1,1,64,8388608,true,4096,
		true,false,true,true,16,1)
	check(not bool(changed_threads.get("success",true)) \
		and String(changed_threads.get("error","")).contains(
			"R2C_WORKER_BOUND_CHANGED"),
		"changing nested workers mid-tick is denied")
	different.cancel_staged_tick()
	await _drain(different)
	check(different.tick()==0 and int(
		different.get_staged_telemetry().off_main.jobs_committed)==0,
		"cancelled changed-worker generation publishes no canonical tick")

	# Fresh new full generation after denial must reproduce the ORIGINAL A13,
	# not a partially updated source or unsealed old A4.
	var restored = make_controller(src)
	var ready := false
	for i in 12000:
		var response: Dictionary = restored.run_staged_frame(
			1000000000,1,1,64,8388608,true,4096,
			true,false,true,true,16,4)
		if not bool(response.get("success",false)):
			check(false,"fresh restored worker failure:"+String(response.get("error","?")))
			break
		if bool(response.get("complete",false)):
			ready = true
			break
		check(restored.tick()==0, "fresh pending tick is not partially published")
		await create_timer(0.02).timeout
	check(ready and restored.tick()==1,"only successful new generation is adopted")
	if not ready:
		_finish()
		return
	var finished: Dictionary = restored.debug_state().runtime
	check(C.encode(finished)==C.encode(ref.state) \
		and Runtime.state_hash(finished)==Runtime.state_hash(ref.state),
		"full A13 original field/pop/grants/feedback/outbox exact")
	var anchor: String = C.digest({
		"schema":"dws.ecology.a147-r2f-independent.v1",
		"population":n})
	var cp_original: Dictionary = Checkpoint.create(anchor,ref.state)
	var cp_actual: Dictionary = Checkpoint.create(anchor,finished)
	var ck_exact: bool = not cp_original.is_empty() and not cp_actual.is_empty() \
		and Checkpoint.serialize(cp_original)==Checkpoint.serialize(cp_actual)
	check(ck_exact,"original and composed CPU full A8 serialized bytes equal")
	var st: Dictionary = restored.get_staged_telemetry().off_main
	check(int(st.last_worker_worksets_per_resume)==16 \
		and int(st.last_r2c_parallel_workset_workers)==4 \
		and int(st.last_worker_phase_profile.get(
			"r2e3_original_global_a4_barriers",-1))==1 \
		and int(st.last_worker_source_validate_wall_us)>0 \
		and int(st.last_worker_candidate_validate_wall_us)>0 \
		and int(st.jobs_committed)==1 and int(st.tasks_joined)==1,
		"integrated 16/4 source/candidate fully validated and single A4")
	check(C.encode(src)==source_bytes,
		"every failed/successful task source independent and unchanged")
	print("A147_R2F_FRESH_JSON " + JSON.stringify({
		"schema":"dws.ecology.a147-r2f-fresh-lease.v1",
		"population":n,"original_runtime_exact":C.encode(finished)==C.encode(ref.state),
		"checkpoint_exact":ck_exact,"batch_change_rejected":true,
		"thread_change_rejected":true,"source_error_first":true,
		"cancelled_jobs_uncommitted":true,"single_a4":true,
		"source_fully_validated":true,"candidate_fully_validated":true,
		"recovered_generation_committed_once":true,
	}))
	_finish()

func _drain(c: Object) -> void:
	var drained := false
	for i in 12000:
		c.reap_cancelled_staged_worker()
		var status: Dictionary = c.get_staged_telemetry().off_main
		if not bool(status.abandoned_draining):
			drained = true
			break
		await create_timer(0.02).timeout
	check(drained,"abandoned worker must be joined after cancel")

func _finish() -> void:
	print("A147_R2F_FRESH checks=%d failed=%d" % [checks,failed])
	print("A147_R2F_FRESH " + ("PASS" if failed==0 else "FAIL"))
	quit(0 if failed==0 else 1)
