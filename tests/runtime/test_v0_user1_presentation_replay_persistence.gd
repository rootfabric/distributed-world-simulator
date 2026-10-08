extends SceneTree

# USER1 R4 falsifier regression.
#
# Error class being locked:
#   "presentation replay repair must not perturb the durable Item Graph".
#
# Chain under test:
#   1. create world state and mutate the canonical Item Graph;
#   2. perform a presentation operation while movement is owned by the
#      secondary seam authority (region B);
#   3. cross A -> B -> A through the real SM1 seam;
#   4. retry the same presentation operation -> must be a replay, never a
#      second presentation mutation;
#   5. persist (durable + replay state), restore into a fresh authority;
#   6. retry the same presentation operation again -> still a replay;
#   7. Item Graph revision and checksum must be identical before the
#      presentation, after retries, and after restore.

const SeamService = preload(
	"res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd"
)

const PLAYER := "user1-r4-presentation-player"
const SESSION_A := "transport-session/user1-r4/a"
const PRESENTATION_OPERATION := "operation/user1/r4/presentation/1"
const HOTBAR_OPERATION := "operation/user1/r4/hotbar/1"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = SeamService.new()
	var setup: Dictionary = service.setup(
		"authority/product/user1-r4-test",
		1,
		0,
		{
			"profile": "MULTIPLAYER_CORE",
			"topology_adapter": "ENET",
			"region_id": "region/m3/single-server",
			"playable_sandbox": true,
			"fixed_tick_authority": true,
		}
	)
	_ok(setup, "seam service setup")
	_ok(
		service.join(PLAYER, SESSION_A, "operation/user1/r4/join"),
		"join"
	)
	var player: Dictionary = service.get_player(PLAYER)
	var ownership_epoch := int(player.get("ownership_epoch", 0))
	_check(ownership_epoch >= 1, "ownership epoch is usable")

	var graph_before: Dictionary = service.create_canonical_item_graph_snapshot()
	var graph_checksum_before := String(graph_before.get("checksum", ""))
	var graph_revision_before := int(graph_before.get("revision", -1))

	var hotbar: Dictionary = service.handle_canonical_item_command(
		PLAYER,
		SESSION_A,
		ownership_epoch,
		HOTBAR_OPERATION,
		"inventory.select_hotbar",
		{"selected_hotbar_index": 2}
	)
	_ok(hotbar, "canonical Item Graph mutation succeeds")
	var graph_after_mutation: Dictionary = service.create_canonical_item_graph_snapshot()
	var graph_checksum_mutated := String(graph_after_mutation.get("checksum", ""))
	var graph_revision_mutated := int(graph_after_mutation.get("revision", -1))
	_check(
		graph_checksum_mutated != graph_checksum_before
		and graph_revision_mutated == graph_revision_before + 1,
		"Item Graph mutation advances revision exactly once"
	)

	var crossed := _drive_roundtrip(service, ownership_epoch)
	_check(crossed, "player completed a real A->B->A seam roundtrip")
	if not crossed:
		return _finish(service)

	var seam_state: Dictionary = service.get_product_seam_state(PLAYER)
	_check(
		String(seam_state.get("region_id", "")) == "region/user1/a",
		"player is back on primary region A before the presentation retry"
	)

	# The first presentation application happened while movement was owned by
	# the secondary authority (region B) inside _drive_roundtrip().
	var graph_after_presentation: Dictionary = service.create_canonical_item_graph_snapshot()
	_check(
		String(graph_after_presentation.get("checksum", "")) == graph_checksum_mutated
		and int(graph_after_presentation.get("revision", -1)) == graph_revision_mutated,
		"presentation does not perturb the canonical Item Graph"
	)

	var retry_presentation: Dictionary = service.set_player_presentation(
		PLAYER,
		SESSION_A,
		ownership_epoch,
		0.75,
		true,
		PRESENTATION_OPERATION
	)
	_ok(retry_presentation, "presentation retry after B->A succeeds")
	_check(
		bool(retry_presentation.get("replay", false))
		or bool(Dictionary(retry_presentation.get("details", {})).get("replay", false)),
		"presentation retry after B->A is a replay, not a second mutation"
	)

	var conflicting_presentation: Dictionary = service.set_player_presentation(
		PLAYER,
		SESSION_A,
		ownership_epoch,
		-0.5,
		false,
		PRESENTATION_OPERATION
	)
	_check(
		not bool(conflicting_presentation.get("success", false))
		and String(conflicting_presentation.get("error_code", ""))
			== "OPERATION_REPLAY_CONFLICT",
		"different presentation payload with the same operation id is rejected"
	)

	var graph_before_persist: Dictionary = service.create_canonical_item_graph_snapshot()
	var durable: Dictionary = service.export_durable_state()
	_check(not durable.is_empty(), "durable state exports after the roundtrip")
	_ok(service.validate_durable_state(durable), "durable state validates")
	var replay_state: Dictionary = service.export_replay_state()
	_check(not replay_state.is_empty(), "replay state exports after the roundtrip")
	service.shutdown()

	var restored = SeamService.new()
	var restored_setup: Dictionary = restored.setup(
		"authority/product/user1-r4-test",
		1,
		0,
		{
			"profile": "MULTIPLAYER_CORE",
			"topology_adapter": "ENET",
			"region_id": "region/m3/single-server",
			"playable_sandbox": true,
			"fixed_tick_authority": true,
		}
	)
	_ok(restored_setup, "restored authority setup")
	var restore_result: Dictionary = restored.restore_durable_state(durable)
	_ok(restore_result, "durable state restores into a fresh authority")
	_ok(restored.restore_replay_state(replay_state), "replay state restores")

	var restored_graph: Dictionary = restored.create_canonical_item_graph_snapshot()
	_check(
		String(restored_graph.get("checksum", "")) == String(graph_before_persist.get("checksum", ""))
		and int(restored_graph.get("revision", -1)) == int(graph_before_persist.get("revision", -1)),
		"restore preserves the canonical Item Graph revision and checksum"
	)

	var restored_retry: Dictionary = restored.set_player_presentation(
		PLAYER,
		SESSION_A,
		ownership_epoch,
		0.75,
		true,
		PRESENTATION_OPERATION
	)
	_ok(restored_retry, "presentation retry after restart succeeds")
	_check(
		bool(restored_retry.get("replay", false))
		or bool(Dictionary(restored_retry.get("details", {})).get("replay", false)),
		"presentation retry after restart is a replay, not a new operation"
	)

	# Authority routing metadata is transient. If a later recovery bumps the
	# authority epoch, the same logical presentation operation must still
	# replay: the idempotency fingerprint may not depend on routing state.
	restored._authority_epoch = int(restored._authority_epoch) + 1
	var epoch_bumped_retry: Dictionary = restored.set_player_presentation(
		PLAYER,
		SESSION_A,
		ownership_epoch,
		0.75,
		true,
		PRESENTATION_OPERATION
	)
	_check(
		bool(epoch_bumped_retry.get("replay", false))
		or bool(Dictionary(epoch_bumped_retry.get("details", {})).get("replay", false)),
		"presentation replay does not depend on transient authority epoch"
	)

	var final_graph: Dictionary = restored.create_canonical_item_graph_snapshot()
	_check(
		String(final_graph.get("checksum", "")) == String(graph_before_persist.get("checksum", ""))
		and int(final_graph.get("revision", -1)) == int(graph_before_persist.get("revision", -1)),
		"restart presentation replay does not create an extra canonical mutation"
	)
	restored.shutdown()
	_finish(null)


func _drive_roundtrip(service, ownership_epoch: int) -> bool:
	var tick := 0
	var sequence := 0
	var saw_secondary := false
	var performed_presentation := false
	for _step in range(1800):
		tick += 1
		var advanced: Dictionary = service.advance_fixed_server_tick(tick)
		if not bool(advanced.get("success", false)):
			return false
		var seam: Dictionary = service.get_product_seam_state(PLAYER)
		var on_secondary := String(seam.get("region_id", "")) == "region/user1/b"
		if on_secondary:
			saw_secondary = true
			if not performed_presentation:
				performed_presentation = true
				var presentation: Dictionary = service.set_player_presentation(
					PLAYER,
					SESSION_A,
					ownership_epoch,
					0.75,
					true,
					PRESENTATION_OPERATION
				)
				if not bool(presentation.get("success", false)):
					return false
		var move_x := -1.0 if on_secondary else 1.0
		sequence += 1
		var moved: Dictionary = service.simulate_fixed_movement_tick(
			PLAYER,
			SESSION_A,
			ownership_epoch,
			sequence,
			{
				"move_x": move_x,
				"move_z": 0.0,
				"look_yaw": 0.4251206143591745,
				"look_pitch": 0.0,
				"jump_pressed": false,
				"sprint": true,
				"delta_seconds": 1.0 / 60.0,
			},
			1.0 / 60.0
		)
		if not bool(moved.get("success", false)):
			return false
		seam = service.get_product_seam_state(PLAYER)
		if (
			saw_secondary
			and String(seam.get("region_id", "")) == "region/user1/a"
			and int(seam.get("roundtrips", 0)) >= 1
		):
			return true
	return false


func _finish(service) -> void:
	if service != null:
		service.shutdown()
	if failures.is_empty():
		print("USER1 R4 PRESENTATION REPLAY PERSISTENCE: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("USER1 R4 PRESENTATION REPLAY PERSISTENCE: FAIL (%d assertions, %d failures)" % [
		assertions,
		failures.size(),
	])
	quit(1)


func _ok(result: Dictionary, message: String) -> void:
	_check(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
