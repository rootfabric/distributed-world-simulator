extends SceneTree

# Regression: M6 recovery restores the primary product authority to a durable
# server_tick far ahead of the USER1 seam secondary authority's construction
# tick. Without a resync, every later advance_fixed_server_tick fails
# USER1_SECONDARY_FIXED_TICK_FAILED (NON_MONOTONIC_FIXED_SERVER_TICK) and the
# dedicated server stops processing movement input until the slot is erased.

const SeamService = preload(
	"res://scripts/runtime/networked_gameplay/user1/user1_product_seam_gameplay_service.gd"
)

const PLAYER := "user1-recovery-player"
const SESSION := "transport-session/user1-recovery/a"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var first = SeamService.new()
	var setup: Dictionary = first.setup(
		"authority/product/user1-recovery",
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
	_ok(setup, "first service setup")
	_ok(first.join(PLAYER, SESSION, "operation/user1/recovery/join"), "player joins first service")
	var tick := 0
	for _step in range(5):
		tick += 1
		_ok(
			first.advance_fixed_server_tick(tick),
			"first service fixed tick %d" % tick
		)
	var durable: Dictionary = first.export_durable_state()
	_check(not durable.is_empty(), "durable state exported at tick %d" % tick)
	_check(
		int(durable.get("server_tick", -1)) == tick,
		"durable state carries the live server tick"
	)
	_ok(first.shutdown(), "first service shutdown")

	# A restarted dedicated server constructs the seam service from launch
	# options (server_tick 0) and only afterwards restores the checkpoint.
	var restarted = SeamService.new()
	var restart_setup: Dictionary = restarted.setup(
		"authority/product/user1-recovery",
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
	_ok(restart_setup, "restarted service setup")
	var restored: Dictionary = restarted.restore_durable_state(durable)
	_ok(restored, "durable state restored after restart")
	var recovered_tick := int(
		restored.get("details", {}).get("server_tick", durable.get("server_tick", 0))
	)
	_check(recovered_tick == tick, "restored primary tick is the durable tick")

	var advanced: Dictionary = restarted.advance_fixed_server_tick(recovered_tick + 1)
	_check(
		bool(advanced.get("success", false)),
		"first fixed tick after recovery advances without USER1_SECONDARY_FIXED_TICK_FAILED (error=%s)"
		% String(advanced.get("error_code", ""))
	)
	_ok(restarted.shutdown(), "restarted service shutdown")

	if failures.is_empty():
		print("USER1 SEAM RECOVERY TICK RESYNC: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		print("USER1 SEAM RECOVERY TICK RESYNC: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)


func _ok(result: Dictionary, label: String) -> void:
	assertions += 1
	if not bool(result.get("success", false)):
		failures.append("FAIL: %s (%s)" % [label, String(result.get("error_code", ""))])


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append("FAIL: %s" % label)
