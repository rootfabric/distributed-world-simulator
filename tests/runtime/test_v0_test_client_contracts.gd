extends SceneTree

const SeamClient = preload("res://tests/fixtures/v0_playable_seamless/client/v0_test_client_seam.gd")
const ItemsClient = preload("res://tests/fixtures/v0_playable_seamless/client/v0_test_client_items.gd")
const Sm1Client = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_graphical_client.gd")
const M3Client = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")

var _assertions := 0
var _failures: Array[String] = []


func _init() -> void:
	_assert(SeamClient != null, "test seam client parses")
	_assert(ItemsClient != null, "test Item Graph client parses")
	_assert(Sm1Client != null, "accepted SM1 graphical client dependency parses")
	_assert(M3Client != null, "accepted M3 graphical client dependency parses")
	_assert(
		FileAccess.file_exists("res://tests/runtime/test_v0_test_client_seam_processes.gd"),
		"seam process gate exists"
	)
	_assert(
		FileAccess.file_exists("res://tests/runtime/test_v0_test_client_items_processes.gd"),
		"items process gate exists"
	)
	_assert(
		not FileAccess.file_exists("res://scripts/runtime/networked_gameplay/p7/v0_test_client.gd"),
		"test client did not create a P7 production runtime owner"
	)
	print("V0 test client contracts: %d assertions, %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _assert(ok: bool, message: String) -> void:
	_assertions += 1
	if ok:
		print("PASS: %s" % message)
	else:
		_failures.append(message)
		push_error("FAIL: %s" % message)
