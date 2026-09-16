extends SceneTree

const Journal = preload("res://scripts/network/prediction/predicted_item_interaction_journal.gd")
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _sealed(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	result.erase("checksum")
	result["checksum"] = JSON.stringify(result, "", true, true).sha256_text()
	return result

func _snapshot() -> Dictionary:
	return _sealed({"schema": Journal.SNAPSHOT_SCHEMA, "authority_owner_id": "authority/test", "authority_epoch": 1, "revision": 7, "tick": 11,
		"items": [
			{"item_id": "world/1", "definition_id": "ore", "quantity": 1, "location": {"kind": "WORLD"}},
			{"item_id": "world/2", "definition_id": "ore", "quantity": 1, "location": {"kind": "WORLD"}},
			{"item_id": "owned", "definition_id": "beacon", "quantity": 3, "location": {"kind": "INVENTORY", "player_id": "a"}}],
		"inventories": {"a": {"inventory": ["owned"], "hotbar": ["owned", ""], "selected_hotbar_index": 0}},
		"containers": [], "mounts": [], "open_containers": {}})

func _new_journal(snapshot: Dictionary):
	var journal = Journal.new()
	_check(journal.setup("a", {"timeout_ms": 100, "max_pending": 8}).get("success") == true, "fixture setup")
	_check(journal.adopt_authoritative(snapshot, 1000).get("success") == true, "fixture adoption")
	return journal

func _clean(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	result.erase("prediction_overlay")
	return result

func _row(snapshot: Dictionary, id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value.get("item_id") == id:
			return value
	return {}

func _run() -> void:
	var base := _snapshot()
	var before := JSON.stringify(base, "", true, true)
	for kind in ["item.pickup", "item.drop", "item.place", "item.transfer"]:
		var journal: Journal = _new_journal(base)
		var payload := {"item_id": "world/1"} if kind == "item.pickup" else {"item_id": "owned", "quantity": 1}
		if kind == "item.transfer":
			payload["target_container_id"] = "hotbar/a"
			payload["target_slot_index"] = 1
		_check(journal.begin_prediction(kind, payload, kind, 1010).get("success") == true, "prediction starts:" + kind)
		_check(_clean(journal.get_presentation_snapshot()) != base, "prediction is visible:" + kind)
		var result := journal.resolve_prediction(kind, {"success": false, "error_code": "DENIED"}, base, 1020)
		_check(result.get("success") == true and result.get("details", {}).get("resolution") == "ROLLED_BACK", "rejection resolved:" + kind)
		_check(_clean(journal.get_presentation_snapshot()) == base, "DUPLICATE_AUTHORITY_ROLLBACK:" + kind)
		_check(_clean(result.get("details", {}).get("presentation_snapshot", {})) == base, "returned view restored:" + kind)
		_check(journal.get_authoritative_snapshot() == base, "canonical authority unchanged:" + kind)
		_check(journal.get_pending_predictions().is_empty(), "resolved entry removed:" + kind)
		var replay := journal.resolve_prediction(kind, {"success": false}, base, 1030)
		_check(replay.get("details", {}).get("duplicate") == true and journal.get_report().get("rolled_back") == 1, "resolution replay idempotent:" + kind)
		_check(journal.get_report().get("confirmed_by_snapshot") == 0 and journal.get_report().get("rebases") == 1, "duplicate is not a new rebase:" + kind)
	var siblings: Journal = _new_journal(base)
	_check(siblings.begin_prediction("item.pickup", {"item_id": "world/1"}, "first", 1010).get("success") == true, "first pending starts")
	_check(siblings.begin_prediction("item.pickup", {"item_id": "world/2"}, "second", 1011).get("success") == true, "second pending starts")
	_check(siblings.resolve_prediction("first", {"success": false}, base, 1020).get("success") == true, "first pending rejected")
	_check(_row(siblings.get_presentation_snapshot(), "world/1").get("location", {}).get("kind") == "WORLD", "first projection removed")
	_check(_row(siblings.get_presentation_snapshot(), "world/2").get("location", {}).get("kind") == "INVENTORY", "unrelated pending preserved")
	_check(siblings.get_pending_predictions().size() == 1, "one survivor remains")
	_check(siblings.project_authoritative(base, 1030).get("success") == true, "duplicate project accepted")
	_check(siblings.get_pending_predictions().size() == 1, "duplicate cannot confirm survivor")
	_check(siblings.adopt_authoritative(base, 1200).get("success") == true, "duplicate expiry processed")
	_check(_clean(siblings.get_presentation_snapshot()) == base and siblings.get_pending_predictions().is_empty(), "expiry removes survivor view")
	_check(siblings.get_report().get("timed_out") == 1, "expiry counted once")
	var fresh: Journal = _new_journal(base)
	_check(fresh.begin_prediction("item.pickup", {"item_id": "world/1"}, "confirmed", 1010).get("success") == true, "new revision prediction starts")
	var changed := base.duplicate(true)
	changed["revision"] = 8
	changed["items"][0]["location"] = {"kind": "INVENTORY", "player_id": "a"}
	changed["inventories"]["a"]["inventory"].append("world/1")
	changed = _sealed(changed)
	_check(fresh.adopt_authoritative(changed, 1020).get("success") == true, "new revision adopted")
	_check(fresh.get_pending_predictions().is_empty() and fresh.get_report().get("confirmed_by_snapshot") == 1, "new revision confirms satisfied prediction")
	_check(_clean(fresh.get_presentation_snapshot()) == changed, "new revision view exact")
	_check(fresh.adopt_authoritative(base, 1030).get("error_code") == "STALE_AUTHORITATIVE_ITEM_GRAPH", "stale authority rejected")
	var conflict := changed.duplicate(true)
	conflict["checksum"] = "0".repeat(64)
	_check(fresh.adopt_authoritative(conflict, 1040).get("error_code") == "CONFLICTING_AUTHORITATIVE_ITEM_GRAPH_REVISION", "same revision conflict rejected")
	_check(fresh.get_authoritative_snapshot() == changed, "rejections cannot overwrite canonical state")
	_check(JSON.stringify(base, "", true, true) == before, "caller snapshot never mutated")
	var verdict := "PASS" if failures.is_empty() else "FAIL"
	print("V0_NX_SAME_REVISION_PROJECTION %s assertions=%d failed=%d" % [verdict, assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
