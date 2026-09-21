extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P8 checkpoint/fork/replay mandatory test
# (brief §17 scenarios). Runner: Godot headless --script.
# Coverage:
#   1. save/restore: state A (8 ticks) -> save -> advance 8 -> restore A ->
#      advance 8 -> hash == hash of the first 16 continuous ticks;
#   2. fork: checkpoint C -> branch A advance 8, branch B (env patch)
#      advance 8 -> different hashes (patch affects the field), both branches
#      parent == C, C immutable;
#   3. replay: same checkpoint + manifest + seed + tick commands -> exact
#      same final canonical hash (twice);
#   4. checkpoint serialization deterministic (same state -> same
#      snapshot_text digest); restored controller answers get_snapshot
#      identically to the original at the same tick.

const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Genome = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Branch = preload("res://scripts/ecology/workbench/experiment_branch_v1.gd")
const EnvironmentPatch = preload("res://scripts/ecology/workbench/environment_patch_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P8_FAIL " + message)

func _program() -> Dictionary:
	var actions := [
		P.action("extend", "support", [0, 100, 0], 10),
		P.action("differentiate", "collector", [0, 60, 0], 4, 20000),
	]
	return {"schema": P.SCHEMA, "entry": "r1", "max_age": 64, "max_depth": 4, "rules": [P.rule("r1", actions)]}

func _manifest(seed: int) -> Dictionary:
	var founder := Genome.create(_program(), "founder-a")
	return {
		"schema": "dws.ecology.workbench.experiment-manifest.v1",
		"experiment_id": "eco-polygon/exp-persist-p8",
		"seed": seed,
		"horizon_ticks": 32,
		"founders": [
			{"founder_id": "founder/a", "biological_hash": null, "genome": founder},
		],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 1, "depth": 1},
			"zones": [
				{"id": "zone/wet", "water_mg": 500000, "light": 700, "temperature": 500, "nutrient_mg": 1000, "organic_mg": 0},
			],
		},
		"placement": {
			"entries": [
				{"founder_ref": "founder/a", "zone_id": "zone/wet", "position_mm": [500, 0, 500]},
			],
		},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 8},
		"mode": "LAB",
	}

func _new_controller(manifest: Dictionary, label: String) -> Object:
	var ctl := Controller.new()
	var init_result: Dictionary = ctl.initialize(manifest)
	_check(bool(init_result.get("success", false)), "%s initialize succeeds" % label)
	return ctl

func _hash(ctl: Object) -> String:
	return String(ctl.get_snapshot().canonical_state_hash)

func _run() -> void:
	var manifest := _manifest(31337)

	# --- 1. save/restore equivalence -------------------------------------------
	var ctl := _new_controller(manifest, "P8 save/restore")
	_check(bool(ctl.run(8).get("success", false)), "P8 run(8) succeeds")
	var saved: Dictionary = ctl.serialize_state()
	_check(bool(saved.get("success", false)), "P8 serialize_state succeeds: " + str(saved))
	var snapshot_at_8: Dictionary = ctl.get_snapshot()
	_check(bool(ctl.run(8).get("success", false)), "P8 advance 8 more succeeds")
	_check(int(ctl.get_snapshot().tick) == 16, "P8 tick 16 after advance")
	var reference := _new_controller(manifest, "P8 reference-16")
	_check(bool(reference.run(16).get("success", false)), "P8 reference run(16) succeeds")
	var hash_reference := _hash(reference)
	_check(_hash(ctl) == hash_reference, "P8 save branch == continuous 16-tick reference")
	var missing_anchor: Dictionary = ctl.load_state(String(saved.state_text), String(saved.manifest_hash))
	_check(not bool(missing_anchor.get("success", false)) and String(missing_anchor.get("error", "")).contains("EXTERNAL_ANCHOR"), "P8 load_state requires caller-owned state checksum")
	var restored: Dictionary = ctl.load_state(String(saved.state_text), String(saved.manifest_hash), String(saved.state_checksum))
	_check(bool(restored.get("success", false)), "P8 load_state succeeds: " + str(restored))
	_check(int(ctl.get_snapshot().tick) == 8, "P8 restored tick == 8")
	var snapshot_restored: Dictionary = ctl.get_snapshot()
	_check(String(snapshot_restored.canonical_state_hash) == String(snapshot_at_8.canonical_state_hash), "P8 restored snapshot hash identical at tick 8")
	_check(String(snapshot_restored.field_hash) == String(snapshot_at_8.field_hash), "P8 restored field hash identical")
	_check(snapshot_restored.population == snapshot_at_8.population, "P8 restored population hashes identical")
	_check(bool(ctl.run(8).get("success", false)), "P8 run(8) after restore succeeds")
	_check(_hash(ctl) == hash_reference, "P8 restore + 8 == first 16 continuous ticks (same path)")
	# Manifest mismatch fails closed.
	var mismatch: Dictionary = ctl.load_state(String(saved.state_text), "0".repeat(64), String(saved.state_checksum))
	_check(not bool(mismatch.get("success", false)), "P8 load_state rejects foreign manifest hash")
	# Garbage fails closed.
	_check(not bool(ctl.load_state("not json", "", "0".repeat(64)).get("success", false)), "P8 load_state rejects garbage text")

	# --- 2. checkpoint determinism ---------------------------------------------
	var twin_a := _new_controller(manifest, "P8 twin a")
	var twin_b := _new_controller(manifest, "P8 twin b")
	twin_a.run(8)
	twin_b.run(8)
	var manager_a := Branch.new()
	_check(bool(manager_a.setup(twin_a).get("success", false)), "P8 branch manager setup succeeds")
	var manager_b := Branch.new()
	manager_b.setup(twin_b)
	var cp_a: Dictionary = manager_a.create_checkpoint("", {"run": "a"}, {"note": "determinism"})
	var cp_b: Dictionary = manager_b.create_checkpoint("", {"run": "b"}, {"note": "determinism"})
	_check(bool(cp_a.get("success", false)) and bool(cp_b.get("success", false)), "P8 checkpoints created")
	_check(String(cp_a.checkpoint.snapshot_text) == String(cp_b.checkpoint.snapshot_text), "P8 same state -> same snapshot_text (deterministic serialization)")
	_check(String(cp_a.checkpoint.checkpoint_id) == String(cp_b.checkpoint.checkpoint_id), "P8 same state -> same checkpoint_id")
	# created_at is deterministic (no wall-clock).
	_check(cp_a.checkpoint.created_at == cp_b.checkpoint.created_at, "P8 created_at deterministic (tick + derived id)")

	# --- 3. fork -----------------------------------------------------------------
	var fork_ctl := _new_controller(manifest, "P8 fork source")
	fork_ctl.run(8)
	var fork_manager := Branch.new()
	fork_manager.setup(fork_ctl)
	var cp_result: Dictionary = fork_manager.create_checkpoint("", {"run": "fork-source"}, {})
	_check(bool(cp_result.get("success", false)), "P8 source checkpoint created")
	var checkpoint: Dictionary = cp_result.checkpoint
	var checkpoint_digest := C.digest(checkpoint)
	var checkpoint_anchor := fork_manager.trusted_checkpoint_anchor(String(checkpoint.checkpoint_id))
	_check(checkpoint_anchor == checkpoint_digest, "P8 manager retains caller-owned checkpoint anchor")

	# Adversarial checkpoint admission. A different valid runtime state may be
	# fully rehashed into a structurally valid record, but it cannot replace the
	# manager's trusted checkpoint without also possessing the external anchor.
	var foreign_ctl := _new_controller(manifest, "P8 adversarial source")
	_check(bool(foreign_ctl.run(9).get("success", false)), "P8 adversarial source reaches tick 9")
	var foreign_saved: Dictionary = foreign_ctl.serialize_state()
	var text_swapped := checkpoint.duplicate(true)
	text_swapped.snapshot_text = foreign_saved.state_text
	text_swapped.state_checksum = foreign_saved.state_checksum
	text_swapped.runtime_checkpoint_checksum = foreign_saved.checkpoint_checksum
	_check(not Branch.validate_checkpoint(text_swapped).is_empty(), "P8 changed snapshot text cannot keep the old canonical state hash")
	var rehashed := checkpoint.duplicate(true)
	rehashed.tick = int(foreign_saved.tick)
	rehashed.canonical_state_hash = String(foreign_saved.state_hash)
	rehashed.snapshot_text = String(foreign_saved.state_text)
	rehashed.state_checksum = String(foreign_saved.state_checksum)
	rehashed.runtime_checkpoint_checksum = String(foreign_saved.checkpoint_checksum)
	rehashed.checkpoint_id = Branch.checkpoint_id_for(String(rehashed.manifest_hash), int(rehashed.tick), String(rehashed.canonical_state_hash))
	rehashed.created_at = {"tick": int(rehashed.tick), "checkpoint_id": String(rehashed.checkpoint_id)}
	_check(Branch.validate_checkpoint(rehashed).is_empty(), "P8 fully rehashed alternate state is structurally self-consistent")
	var rehashed_restore: Dictionary = fork_manager.restore(rehashed)
	_check(not bool(rehashed_restore.get("success", false)) and String(rehashed_restore.get("error", "")).contains("EXTERNAL_ANCHOR"), "P8 manager rejects fully rehashed checkpoint without caller-owned anchor")
	var branch_a: Dictionary = fork_manager.fork(checkpoint, {}, "branch-a")
	_check(bool(branch_a.get("success", false)), "P8 fork A succeeds: " + str(branch_a))
	var branch_b: Dictionary = fork_manager.fork(checkpoint, EnvironmentPatch.patch("zone/wet", "light", 100), "branch-b")
	_check(bool(branch_b.get("success", false)), "P8 fork B (env patch light 700->100) succeeds: " + str(branch_b))
	if bool(branch_a.get("success", false)) and bool(branch_b.get("success", false)):
		var ctl_a: Object = branch_a.controller
		var ctl_b: Object = branch_b.controller
		_check(bool(ctl_a.run(8).get("success", false)), "P8 branch A run(8) succeeds")
		_check(bool(ctl_b.run(8).get("success", false)), "P8 branch B run(8) succeeds")
		var hash_a := _hash(ctl_a)
		var hash_b := _hash(ctl_b)
		_check(hash_a != hash_b, "P8 patched branch diverges (patch affects the canonical field)")
		# The unpatched fork A must equal the source branch continuing.
		_check(bool(fork_ctl.run(8).get("success", false)), "P8 source branch advances 8 more")
		_check(hash_a == _hash(fork_ctl), "P8 unpatched fork A == source branch continuing (shared parent state)")
		# Both branches point at the SAME immutable parent checkpoint C.
		var registry: Dictionary = fork_manager.branch_registry()
		var parents_ok := true
		for branch_id in registry:
			if String(branch_id) == String(fork_manager.root_branch_id()):
				continue
			if String(registry[branch_id].parent_checkpoint_id) != String(checkpoint.checkpoint_id):
				parents_ok = false
		_check(parents_ok, "P8 every fork branch parent == checkpoint C")
		# C itself is immutable (digest unchanged after both forks ran).
		_check(C.digest(fork_manager.get_checkpoint(String(checkpoint.checkpoint_id))) == checkpoint_digest, "P8 checkpoint C immutable after forks")
		_check(C.digest(checkpoint) == checkpoint_digest, "P8 returned checkpoint copy unchanged")

		# --- 4. replay -----------------------------------------------------------
		var replay_one: Dictionary = Branch.replay(checkpoint, manifest, {}, [4, 4], checkpoint_anchor)
		var replay_two: Dictionary = Branch.replay(checkpoint, manifest, {}, [8], checkpoint_anchor)
		var replay_three: Dictionary = Branch.replay(checkpoint, manifest, {}, [4, 4], checkpoint_anchor)
		_check(bool(replay_one.get("success", false)), "P8 replay [4,4] succeeds: " + str(replay_one))
		_check(bool(replay_two.get("success", false)), "P8 replay [8] succeeds: " + str(replay_two))
		_check(bool(replay_three.get("success", false)), "P8 replay [4,4] again succeeds")
		if bool(replay_one.get("success", false)) and bool(replay_two.get("success", false)):
			_check(String(replay_one.canonical_state_hash) == String(replay_three.canonical_state_hash), "P8 replay twice -> exact same final canonical hash")
			_check(String(replay_one.canonical_state_hash) == String(replay_two.canonical_state_hash), "P8 replay command batching never affects the hash")
			_check(String(replay_one.canonical_state_hash) == hash_a, "P8 replay == fork A continuous advance (same manifest+seed+commands)")
		# Bad commands fail closed.
		_check(not bool(Branch.replay(checkpoint, manifest, {}, [0], checkpoint_anchor).get("success", false)), "P8 replay rejects zero-tick command")
		var tampered := checkpoint.duplicate(true)
		tampered.tick = 9
		_check(not bool(Branch.replay(tampered, manifest, {}, [8], checkpoint_anchor).get("success", false)), "P8 replay rejects a tampered checkpoint id binding")

	# --- 5. restore through the branch manager ----------------------------------
	var manager_restore: Dictionary = fork_manager.restore(checkpoint)
	_check(bool(manager_restore.get("success", false)), "P8 manager.restore succeeds: " + str(manager_restore))
	_check(int(fork_ctl.get_snapshot().tick) == 8, "P8 manager.restore returns controller to tick 8")
	_check(String(fork_ctl.get_snapshot().canonical_state_hash) == String(checkpoint.canonical_state_hash), "P8 restored hash == checkpoint canonical_state_hash")
	_check(bool(fork_ctl.run(8).get("success", false)), "P8 manager restore + 8 recomputes")
	if bool(branch_a.get("success", false)):
		_check(_hash(fork_ctl) == _hash(branch_a.controller), "P8 manager restore + 8 == branch A hash (deterministic continuation)")

	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_5_PERSISTENCE_P8 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_PERSISTENCE_P8 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P8_FAILURE " + failure)
		quit(1)
