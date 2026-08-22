extends SceneTree

## EG2 L0 auth/session service: one-time ticket lifecycle (mint -> authenticate
## -> exchange), reuse/unknown/expired rejection, session creation identity
## grants, and resume semantics: NEW gateway_session_id + NEW resume token with
## the SAME logical player identity; wrong-ticket and stale-token resumes fail.

const AuthService = preload("res://scripts/network/gateway/runtime/eg2_auth_session_service.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg2-auth-l0][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _details(result: Dictionary) -> Dictionary:
	return result.get("details", {})


func _mint_ok(service, client_session_id: String) -> String:
	var minted: Dictionary = service.mint_auth_ticket(client_session_id)
	_assert(bool(minted.get("success", false)), "mint failed for %s: %s" % [client_session_id, _err(minted)])
	return String(_details(minted).get("ticket_id", ""))


func _auth_ok(service, ticket_id: String) -> void:
	var authenticated: Dictionary = service.authenticate(ticket_id)
	_assert(bool(authenticated.get("success", false)), "authenticate(%s) failed: %s" % [ticket_id, _err(authenticated)])


func _init() -> void:
	# --- configure validation ---
	var service := AuthService.new()
	_assert(_err(service.configure({"max_ticket_age_ms": -1})) == "INVALID_OPTION",
			"negative ticket age accepted by configure")
	_assert(_err(service.configure({"unknown_option": 1})) == "UNKNOWN_OPTION",
			"unknown option accepted by configure")
	_assert(bool(service.configure({}).get("success", false)), "default configure failed")

	# --- mint + authenticate happy path ---
	var ticket_a := _mint_ok(service, "client-session/eg2/alpha")
	_assert(ticket_a == "auth-ticket/eg2/1", "first ticket id unexpected: %s" % ticket_a)
	var mint_duplicate := service.mint_auth_ticket("client-session/eg2/alpha")
	_assert(String(_details(mint_duplicate).get("ticket_id", "")) == "auth-ticket/eg2/2",
			"ticket ids are not unique per mint")
	var bad_mint := service.mint_auth_ticket("entity/not-a-client-session")
	_assert(_err(bad_mint) == "INVALID_CLIENT_SESSION_ID", "cross-namespace mint was accepted")
	var bad_auth := service.authenticate("auth-ticket/eg2/999")
	_assert(_err(bad_auth) == "UNKNOWN_TICKET", "unknown ticket authenticated")

	var ok_auth: Dictionary = service.authenticate(ticket_a)
	_assert(bool(ok_auth.get("success", false)), "fresh ticket failed to authenticate")
	if bool(ok_auth.get("success", false)):
		_assert(String(_details(ok_auth)["status"]) == "OK", "authentication did not report OK")
		_assert(String(_details(ok_auth)["client_session_id"]) == "client-session/eg2/alpha",
				"authentication lost the bound client session")
	var reused_auth := service.authenticate(ticket_a)
	_assert(_err(reused_auth) == "TICKET_REUSED", "one-time ticket authenticated twice")

	# --- create session ---
	var created: Dictionary = service.create_or_resume_session("client-session/eg2/alpha", ticket_a)
	_assert(bool(created.get("success", false)), "session creation failed: %s" % _err(created))
	var create_details := _details(created)
	# Mirror of the injective identity-suffix derivation (sanitized remainder +
	# short digest of the full canonical client session id).
	var alpha_suffix := "eg2-alpha-%s" % "client-session/eg2/alpha".sha256_text().substr(0, 10)
	if bool(created.get("success", false)):
		_assert(String(create_details["action"]) == "CREATED", "creation did not report CREATED")
		_assert(String(create_details["gateway_session_id"]) == "gateway-session/eg2/%s/1" % alpha_suffix,
				"minted gateway session id unexpected: %s" % str(create_details.get("gateway_session_id", "")))
		_assert(String(create_details["gateway_session_id"]).begins_with("gateway-session/")
				and not String(create_details["gateway_session_id"]).contains("player/"),
				"gateway session id leaked into the player namespace")
		_assert(String(create_details["logical_player_id"]) == "player/eg2-%s" % alpha_suffix,
				"identity grant unexpected: %s" % str(create_details.get("logical_player_id", "")))
		_assert(String(create_details["player_entity_id"]) == "entity/eg2-player-%s" % alpha_suffix,
				"entity grant unexpected: %s" % str(create_details.get("player_entity_id", "")))
		_assert(String(create_details["resume_token"]).begins_with("resume-token/eg2/"),
				"resume token outside its namespace")
		_assert(bool(create_details["resumed"]) == false, "creation reported resumed=true")

	var resume_token_one := String(create_details.get("resume_token", ""))
	_assert(service.is_resume_token_live(resume_token_one), "fresh resume token is not live")

	# --- ticket is single-use across the whole lifecycle ---
	var exchange_again := service.create_or_resume_session("client-session/eg2/alpha", ticket_a)
	_assert(_err(exchange_again) == "TICKET_REUSED", "exchanged ticket was accepted again")
	var unauthenticated := service.create_or_resume_session("client-session/eg2/alpha",
			_mint_ok(service, "client-session/eg2/alpha"))
	_assert(_err(unauthenticated) == "TICKET_NOT_AUTHENTICATED",
			"unauthenticated ticket was exchanged for a session")
	var wrong_binding_ticket := _mint_ok(service, "client-session/eg2/beta")
	_auth_ok(service, wrong_binding_ticket)
	var wrong_binding := service.create_or_resume_session("client-session/eg2/alpha", wrong_binding_ticket)
	_assert(_err(wrong_binding) == "TICKET_CLIENT_SESSION_MISMATCH",
			"ticket minted for another client session was accepted")

	# --- resume: new gateway session id, new resume token, SAME identity ---
	var ticket_resume := _mint_ok(service, "client-session/eg2/alpha")
	_auth_ok(service, ticket_resume)
	var resumed: Dictionary = service.create_or_resume_session(
			"client-session/eg2/alpha", ticket_resume, resume_token_one)
	_assert(bool(resumed.get("success", false)), "resume failed: %s" % _err(resumed))
	var resume_details := _details(resumed)
	if bool(resumed.get("success", false)):
		_assert(String(resume_details["action"]) == "RESUMED", "resume did not report RESUMED")
		_assert(String(resume_details["gateway_session_id"]) != String(create_details["gateway_session_id"]),
				"resume did not mint a NEW gateway session id")
		_assert(String(resume_details["gateway_session_id"]).begins_with("gateway-session/eg2/"),
				"resumed gateway session id outside its namespace")
		var resume_token_two := String(resume_details["resume_token"])
		_assert(resume_token_two != resume_token_one,
				"resume did not rotate the resume token")
		_assert(service.is_resume_token_live(resume_token_two), "rotated resume token is not live")
		_assert(not service.is_resume_token_live(resume_token_one),
				"old resume token stayed live after rotation")
		_assert(String(resume_details["logical_player_id"]) == String(create_details["logical_player_id"])
				and String(resume_details["player_entity_id"]) == String(create_details["player_entity_id"]),
				"resume did not preserve the logical player identity")
		_assert(String(resume_details["previous_gateway_session_id"]) == String(create_details["gateway_session_id"]),
				"resume lost the previous gateway session linkage")

	# --- accounting hygiene: superseded rows are pruned, live counts are live ---
	var superseded_lookup := service.get_session(String(create_details["gateway_session_id"]))
	_assert(_err(superseded_lookup) == "UNKNOWN_GATEWAY_SESSION",
			"superseded session row survived the resume")
	var hygiene_report: Dictionary = service.get_report()
	_assert(int(hygiene_report["live_sessions"]) == 1,
			"live_sessions does not count LIVE rows only: %s" % str(hygiene_report.get("live_sessions")))
	_assert(int(hygiene_report["live_resume_tokens"]) == 1,
			"live_resume_tokens does not count LIVE tokens only")

	# --- stale/wrong resume rejections ---
	var probe_ticket := _mint_ok(service, "client-session/eg2/alpha")
	_auth_ok(service, probe_ticket)
	var stale_resume := service.create_or_resume_session("client-session/eg2/alpha", probe_ticket, resume_token_one)
	_assert(_err(stale_resume) == "UNKNOWN_RESUME_TOKEN", "stale resume token was accepted")
	var ghost_probe := _mint_ok(service, "client-session/eg2/alpha")
	_auth_ok(service, ghost_probe)
	var unknown_token := service.create_or_resume_session("client-session/eg2/alpha", ghost_probe, "resume-token/eg2/nope")
	_assert(_err(unknown_token) == "UNKNOWN_RESUME_TOKEN", "unknown resume token was accepted")
	var cross_identity := _mint_ok(service, "client-session/eg2/beta")
	_auth_ok(service, cross_identity)
	var mismatched := service.create_or_resume_session(
			"client-session/eg2/beta", cross_identity,
			String(_details(resumed).get("resume_token", "")))
	_assert(_err(mismatched) == "RESUME_IDENTITY_MISMATCH",
			"resume of another client session's token was accepted")

	# --- age-based expiry (optional feature) ---
	var aging := AuthService.new()
	_assert(bool(aging.configure({"max_ticket_age_ms": 20}).get("success", false)),
			"aging configure failed")
	var short_lived := _mint_ok(aging, "client-session/eg2/exp")
	OS.delay_msec(45)
	var expired := aging.authenticate(short_lived)
	_assert(_err(expired) == "TICKET_EXPIRED", "aged ticket was still authenticated")
	var expired_again := aging.authenticate(short_lived)
	_assert(_err(expired_again) == "TICKET_REUSED", "expired ticket was not consumed")
	var fresh_after := _mint_ok(aging, "client-session/eg2/exp")
	_assert(bool(aging.authenticate(fresh_after).get("success", false)),
			"fresh ticket expired immediately under age policy")

	# --- injective identity suffix regression ---
	# These two canonical ids collapse to the SAME sanitized remainder
	# ("eg3-x-y"); the suffix derivation must still keep their grants apart.
	var collision_a := AuthService.new()
	var ticket_ca := _mint_ok(collision_a, "client-session/eg3/x-y")
	_auth_ok(collision_a, ticket_ca)
	var created_a := collision_a.create_or_resume_session("client-session/eg3/x-y", ticket_ca)
	var ticket_cb := _mint_ok(collision_a, "client-session/eg3-x-y")
	_auth_ok(collision_a, ticket_cb)
	var created_b := collision_a.create_or_resume_session("client-session/eg3-x-y", ticket_cb)
	if bool(created_a.get("success", false)) and bool(created_b.get("success", false)):
		var details_a := _details(created_a)
		var details_b := _details(created_b)
		_assert(String(details_a["logical_player_id"]) != String(details_b["logical_player_id"]),
				"distinct client sessions collided onto one logical player id")
		_assert(String(details_a["player_entity_id"]) != String(details_b["player_entity_id"]),
				"distinct client sessions collided onto one player entity id")
		_assert(String(details_a["gateway_session_id"]) != String(details_b["gateway_session_id"]),
				"distinct client sessions collided onto one gateway session id")
	else:
		_assert(false, "identity-collision probe sessions failed: %s / %s" % [_err(created_a), _err(created_b)])

	# --- report surface: counters only, no endpoints, no domain payloads ---
	var report: Dictionary = service.get_report()
	var report_text := JSON.stringify(report)
	for forbidden in ["127.0.0.1", "localhost", "host", "port", "endpoint"]:
		_assert(not report_text.contains(forbidden), "service report leaked endpoint-ish token '%s'" % forbidden)
	_assert(int(report["counters"]["tickets_minted"]) > 0, "ticket counter never advanced")
	_assert(int(report["counters"]["sessions_resumed"]) == 1, "resume counter mismatch")

	_finish()


func _finish() -> void:
	var summary := {
		"test": "eg2_auth_session_service_l0",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg2-auth-l0] L0 PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg2-auth-l0] L0 FAIL")
		quit(1)
