extends "res://tests/matter/interest/test_mw7_matter_interest_replication_base.gd"

const FixtureCleanupScript = preload(
	"res://tests/matter/interest/mw7_test_fixture.gd"
)


func _finish() -> void:
	var cleanup: Dictionary = FixtureCleanupScript.shutdown_all()
	if not bool(cleanup.get("success", false)):
		var message := "MW7 interest fixture teardown failed: %s" % cleanup
		failures.append(message)
		push_error(message)
	else:
		print(
			"MW7 interest teardown: PASS (%d servers)"
			% int(cleanup.get("server_count", 0))
		)
	super._finish()
