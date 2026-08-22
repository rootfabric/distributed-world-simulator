extends SceneTree

## EG4.5 L0 micro-proof for the SIM-SIDE synthetic effect journal.
## Predicate: CWIP_SYNTHETIC_EXACTLY_ONCE_EFFECT_PASS (journal core):
##   - exactly-once apply per operation id; replays return the PRIOR result;
##   - the per-authority canonical effect revision counter never advances on
##     a replay or a rejection;
##   - synthetic-only enforcement (product_canonical_mutation_allowed=false);
##   - explicit rejections leave NO partial effect behind.

const JournalScript = preload("res://tools/network/eg45_synthetic_effect_journal.gd")
const EffectRequestScript = preload("res://scripts/network/gateway/effect_commit_request.gd")
const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const AUTHORITY_A := "authority/eg45-journal-world-a"

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg45-journal][FAIL] %s" % message)


func _digest(seed: String) -> String:
	return NetworkUtilsScript.payload_hash({"seed": seed})


func _request(operation_id: String, synthetic_flag = false, effect_kind: String = "hit") -> Dictionary:
	var payload := {
		"product_canonical_mutation_allowed": synthetic_flag,
		"damage": 5,
	}
	return EffectRequestScript.create(
			"interaction/eg45-journal-i1",
			operation_id,
			_digest(operation_id),
			"entity/eg45-journal-target",
			AUTHORITY_A,
			3,
			effect_kind,
			"effect-definition/eg45-test-hit",
			payload)


func _commit_ok(journal, request: Dictionary, context: String) -> Dictionary:
	var outcome: Dictionary = journal.commit(request)
	_assert(bool(outcome.get("success", false)), "%s commit failed unexpectedly: %s" % [context, JSON.stringify(outcome)])
	return Dictionary(outcome.get("details", {}))


func _init() -> void:
	# --- configuration fail-closed -------------------------------------------
	var journal = JournalScript.new()
	_assert(String(journal.configure("not-canonical", 1).get("error_code", "")) == "INVALID_AUTHORITY_ID",
			"non-canonical authority id must be refused")
	_assert(String(journal.configure(AUTHORITY_A, 0).get("error_code", "")) == "INVALID_AUTHORITY_EPOCH",
			"epoch must be >= 1")
	_assert(bool(journal.configure(AUTHORITY_A, 7).get("success", false)), "valid configure failed")

	# --- exactly-once apply + idempotent replay -------------------------------
	var op_one := "operation/eg45-journal-op1"
	var first: Dictionary = _commit_ok(journal, _request(op_one), "first")
	_assert(String(first.get("status", "")) == "APPLIED" and bool(first.get("applied_now", false)),
			"first commit must APPLY the synthetic effect")
	_assert(int(first.get("canonical_effect_revision", 0)) == 1, "first applied revision must be 1")

	var replay_outcome: Dictionary = journal.commit(_request(op_one))
	var replay: Dictionary = Dictionary(replay_outcome.get("details", {}))
	_assert(bool(replay_outcome.get("success", false)), "idempotent replay must succeed")
	_assert(String(replay.get("status", "")) == "DUPLICATE_REPLAY" and not bool(replay.get("applied_now", true)),
			"replay of an applied operation must return DUPLICATE_REPLAY without re-applying")
	_assert(int(replay.get("canonical_effect_revision", 0)) == 1,
			"replay must return the PRIOR canonical effect revision")
	_assert(JSON.stringify(journal.result_for(op_one)) == JSON.stringify(replay.get("result", {})),
			"replay result must equal the stored prior result verbatim")
	_assert(journal.effect_count() == 1, "replay must not create a second effect")

	# A DIFFERENT operation applies normally and advances the counter once.
	var op_two := "operation/eg45-journal-op2"
	var second: Dictionary = _commit_ok(journal, _request(op_two), "second")
	_assert(int(second.get("canonical_effect_revision", 0)) == 2,
			"a genuinely new operation advances the canonical revision to 2")
	_assert(journal.effect_count() == 2, "journal must hold exactly two applied effects")

	# --- synthetic-only enforcement --------------------------------------------
	for bad_flag in [true, null, "false"]:
		var refused: Dictionary = journal.commit(_request("operation/eg45-journal-badflag", bad_flag))
		_assert(not bool(refused.get("success", false)) and String(refused.get("error_code", "")) == "SYNTHETIC_FLAG_REQUIRED",
				"commit without product_canonical_mutation_allowed=false must be refused (got %s)" % str(bad_flag))
	_assert(journal.effect_count() == 2, "refused synthetic-flag commits left partial effects behind")

	# --- domain validation refusal surfaces explicitly, no partial state ------
	journal.set_domain_validator(func(effect_payload: Dictionary) -> Dictionary:
		return {"allowed": false, "reason": "DOMAIN_VALIDATION_REJECTED"} if int(effect_payload.get("damage", 0)) > 100 \
				else {"allowed": true, "reason": ""})
	var op_rejected := "operation/eg45-journal-rejected"
	var rejected_request := _request(op_rejected)
	rejected_request["effect_payload"]["damage"] = 500
	var rejected: Dictionary = journal.commit(rejected_request)
	_assert(not bool(rejected.get("success", false)) and String(rejected.get("error_code", "")) == "DOMAIN_VALIDATION_REJECTED",
			"domain-validation refusal must surface the explicit reason")
	_assert(journal.rejection_reason(op_rejected) == "DOMAIN_VALIDATION_REJECTED",
			"rejected operation must be recorded as rejected")
	_assert(not journal.has_effect(op_rejected) and journal.effect_count() == 2,
			"rejected commit must leave NO partial effect")
	var rejected_replay: Dictionary = journal.commit(rejected_request)
	_assert(not bool(rejected_replay.get("success", false)),
			"re-committing a rejected operation stays rejected (no resurrection)")

	# --- routing/target mismatches stay fail-closed -----------------------------
	var foreign := _request("operation/eg45-journal-foreign")
	foreign["target_authority"] = "authority/eg45-somewhere-else"
	_assert(String(journal.commit(foreign).get("error_code", "")) == "WRONG_JOURNAL",
			"a commit addressed to another authority must be refused by this journal")
	var malformed := _request("operation/eg45-journal-malformed")
	malformed.erase("resolution_digest")
	_assert(String(journal.commit(malformed).get("error_code", "")) == "CONTRACT_VIOLATION",
			"contract-violating commit requests must fail closed before any effect")
	_assert(journal.effect_count() == 2 and int(journal.next_canonical_effect_revision()) == 3,
			"counter state intact after all refusals")

	_finish()


func _finish() -> void:
	var ok := failures.is_empty()
	print(JSON.stringify({
		"test": "eg45_synthetic_journal_l0",
		"verdict": "PASS" if ok else "FAIL",
		"assertions": assertions,
		"predicate": "CWIP_SYNTHETIC_EXACTLY_ONCE_EFFECT_PASS(journal-core)" if ok else "PREDICATE_NOT_DEMONSTRATED",
		"failures": failures,
	}))
	if ok:
		print("[eg45-journal] SYNTHETIC EFFECT JOURNAL PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg45-journal] SYNTHETIC EFFECT JOURNAL FAIL")
		quit(1)
