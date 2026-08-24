extends RefCounted

## EG2 auth/session service (MVP, in-gateway): mints one-time auth tickets,
## authenticates them, and creates/resumes client sessions with a stable
## logical player identity across transport loss.
##
## Ownership discipline: this module owns the AUTH truth for the EG2 stage —
## tickets are single-use opaque ids and resume tokens are rotated on every
## successful resume. It never hands out endpoints (host/port): every returned
## identifier lives in a canonical namespace
## (auth-ticket/*, resume-token/*, gateway-session/*, player/*, entity/*).
##
## Identity grant: on first session creation the service derives and records
## the logical identity from the canonical client_session_id INJECTIVELY
## (sanitized readable suffix + short digest of the full canonical id), so two
## distinct client sessions can never collide onto one logical player identity.
## Resumes return exactly that recorded grant, no matter what the caller
## claims afterwards.

const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.eg2_auth_session_service.v1"

const TICKET_PREFIX := "auth-ticket/eg2/"
const RESUME_TOKEN_PREFIX := "resume-token/eg2/"
const GATEWAY_SESSION_PREFIX := "gateway-session/eg2/"
const CLIENT_SESSION_PREFIX := "client-session/"

const TICKET_STATE_ISSUED := "ISSUED"
const TICKET_STATE_AUTHENTICATED := "AUTHENTICATED"
const TICKET_STATE_EXCHANGED := "EXCHANGED"
const TICKET_STATE_CONSUMED := "CONSUMED"

var _tickets: Dictionary = {}
var _sessions_by_gateway_session_id: Dictionary = {}
var _live_resume_tokens: Dictionary = {}
var _ticket_counter: int = 0
var _session_counter: int = 0
var _resume_token_counter: int = 0
var _max_ticket_age_ms: int = 0
var _time_override_ms: int = -1
var _counters := {
	"tickets_minted": 0,
	"authentications_ok": 0,
	"authentications_unknown_ticket": 0,
	"authentications_reused": 0,
	"authentications_expired": 0,
	"sessions_created": 0,
	"sessions_resumed": 0,
	"resumes_rejected": 0,
}


func configure(options: Dictionary) -> Dictionary:
	for key in options.keys():
		match String(key):
			"max_ticket_age_ms":
				var value = options[key]
				if not NetworkUtilsScript.is_json_integer(value) or int(value) < 0:
					return _failure("INVALID_OPTION", {"option": "max_ticket_age_ms"})
				_max_ticket_age_ms = int(value)
			_:
				return _failure("UNKNOWN_OPTION", {"option": String(key)})
	return _success({})


## Mint a one-time ticket bound to one canonical client_session_id.
func mint_auth_ticket(client_session_id: String) -> Dictionary:
	if not _is_canonical_client_session_id(client_session_id):
		return _failure("INVALID_CLIENT_SESSION_ID", {"client_session_id": client_session_id})
	_ticket_counter += 1
	var ticket_id := "%s%d" % [TICKET_PREFIX, _ticket_counter]
	_tickets[ticket_id] = {
		"ticket_id": ticket_id,
		"client_session_id": client_session_id,
		"state": TICKET_STATE_ISSUED,
		"issued_at_ms": _now_ms(),
		"authenticated_at_ms": 0,
	}
	_counters["tickets_minted"] = int(_counters["tickets_minted"]) + 1
	return _success({"ticket_id": ticket_id})


## Consume a ticket exactly once. OK / expired / reused / unknown.
func authenticate(ticket_id: String) -> Dictionary:
	if not _tickets.has(ticket_id):
		_counters["authentications_unknown_ticket"] = int(_counters["authentications_unknown_ticket"]) + 1
		return _failure("UNKNOWN_TICKET", {"ticket_id": ticket_id})
	var ticket: Dictionary = _tickets[ticket_id]
	if String(ticket["state"]) != TICKET_STATE_ISSUED:
		_counters["authentications_reused"] = int(_counters["authentications_reused"]) + 1
		return _failure("TICKET_REUSED", {"ticket_id": ticket_id})
	if _is_expired(ticket):
		ticket["state"] = TICKET_STATE_CONSUMED
		_counters["authentications_expired"] = int(_counters["authentications_expired"]) + 1
		return _failure("TICKET_EXPIRED", {"ticket_id": ticket_id})
	ticket["state"] = TICKET_STATE_AUTHENTICATED
	ticket["authenticated_at_ms"] = _now_ms()
	_counters["authentications_ok"] = int(_counters["authentications_ok"]) + 1
	return _success({
		"status": "OK",
		"ticket_id": ticket_id,
		"client_session_id": String(ticket["client_session_id"]),
	})


## Exchange an authenticated ticket for a session handle.
## resume_token == "" creates a fresh session; otherwise resumes the session
## that owns the token: NEW gateway_session_id + NEW resume_token, SAME
## recorded logical identity. The ticket must be authenticated, unconsumed and
## bound to the same client_session_id as the session being resumed.
func create_or_resume_session(client_session_id: String, ticket_id: String, resume_token: String = "") -> Dictionary:
	if not _is_canonical_client_session_id(client_session_id):
		return _failure("INVALID_CLIENT_SESSION_ID", {"client_session_id": client_session_id})
	var ticket_check := _require_exchangeable_ticket(ticket_id, client_session_id)
	if not bool(ticket_check.get("success", false)):
		return ticket_check
	var ticket: Dictionary = _tickets[ticket_id]
	if resume_token.is_empty():
		return _create_session(client_session_id, ticket)
	return _resume_session(client_session_id, ticket, resume_token)


func get_session(gateway_session_id: String) -> Dictionary:
	if not _sessions_by_gateway_session_id.has(gateway_session_id):
		return _failure("UNKNOWN_GATEWAY_SESSION", {"gateway_session_id": gateway_session_id})
	return _success({"session": Dictionary(_sessions_by_gateway_session_id[gateway_session_id]).duplicate(true)})


func is_resume_token_live(resume_token: String) -> bool:
	return _live_resume_tokens.has(resume_token)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"counters": _counters.duplicate(true),
		"outstanding_tickets": _count_outstanding_tickets(),
		"live_sessions": _sessions_by_gateway_session_id.size(),
		"live_resume_tokens": _live_resume_tokens.size(),
	}


## ---- internals -------------------------------------------------------------


func _create_session(client_session_id: String, ticket: Dictionary) -> Dictionary:
	var suffix := _identity_suffix(client_session_id)
	var minted := _mint_gateway_session_id(suffix)
	var gateway_session_id: String = minted["gateway_session_id"]
	var resume_token := _mint_resume_token()
	var session := {
		"gateway_session_id": gateway_session_id,
		"client_session_id": client_session_id,
		"logical_player_id": "player/eg2-%s" % suffix,
		"player_entity_id": "entity/eg2-player-%s" % suffix,
		"resume_token": resume_token,
		"created_at_ms": _now_ms(),
		"resumed": false,
	}
	ticket["state"] = TICKET_STATE_EXCHANGED
	_sessions_by_gateway_session_id[gateway_session_id] = session
	_live_resume_tokens[resume_token] = gateway_session_id
	_counters["sessions_created"] = int(_counters["sessions_created"]) + 1
	return _success({
		"action": "CREATED",
		"gateway_session_id": gateway_session_id,
		"resume_token": resume_token,
		"client_session_id": client_session_id,
		"logical_player_id": String(session["logical_player_id"]),
		"player_entity_id": String(session["player_entity_id"]),
		"resumed": false,
	})


func _resume_session(client_session_id: String, ticket: Dictionary, resume_token: String) -> Dictionary:
	if not _live_resume_tokens.has(resume_token):
		_counters["resumes_rejected"] = int(_counters["resumes_rejected"]) + 1
		return _failure("UNKNOWN_RESUME_TOKEN", {"resume_token": resume_token})
	var previous_gateway_session_id := String(_live_resume_tokens[resume_token])
	var previous: Dictionary = _sessions_by_gateway_session_id[previous_gateway_session_id]
	if String(previous["client_session_id"]) != client_session_id:
		_counters["resumes_rejected"] = int(_counters["resumes_rejected"]) + 1
		return _failure("RESUME_IDENTITY_MISMATCH", {
			"resume_token": resume_token,
			"client_session_id": client_session_id,
		})
	var suffix := _identity_suffix(client_session_id)
	var minted := _mint_gateway_session_id(suffix)
	var gateway_session_id: String = minted["gateway_session_id"]
	var next_resume_token := _mint_resume_token()
	var session := {
		"gateway_session_id": gateway_session_id,
		"client_session_id": client_session_id,
		# Identity preservation: copied verbatim from the original grant.
		"logical_player_id": String(previous["logical_player_id"]),
		"player_entity_id": String(previous["player_entity_id"]),
		"resume_token": next_resume_token,
		"created_at_ms": _now_ms(),
		"resumed": true,
	}
	ticket["state"] = TICKET_STATE_EXCHANGED
	_live_resume_tokens.erase(resume_token)
	# Accounting hygiene: the previous session row is SUPERSEDED by the resumed
	# one (its resume token was already rotated away), so it is pruned instead
	# of accumulating as a dead row; live_sessions counts LIVE rows only.
	_sessions_by_gateway_session_id.erase(previous_gateway_session_id)
	_sessions_by_gateway_session_id[gateway_session_id] = session
	_live_resume_tokens[next_resume_token] = gateway_session_id
	_counters["sessions_resumed"] = int(_counters["sessions_resumed"]) + 1
	return _success({
		"action": "RESUMED",
		"gateway_session_id": gateway_session_id,
		"resume_token": next_resume_token,
		"previous_gateway_session_id": previous_gateway_session_id,
		"client_session_id": client_session_id,
		"logical_player_id": String(session["logical_player_id"]),
		"player_entity_id": String(session["player_entity_id"]),
		"resumed": true,
	})


func _require_exchangeable_ticket(ticket_id: String, client_session_id: String) -> Dictionary:
	if not _tickets.has(ticket_id):
		return _failure("UNKNOWN_TICKET", {"ticket_id": ticket_id})
	var ticket: Dictionary = _tickets[ticket_id]
	var state := String(ticket["state"])
	if state == TICKET_STATE_ISSUED:
		return _failure("TICKET_NOT_AUTHENTICATED", {"ticket_id": ticket_id})
	if state != TICKET_STATE_AUTHENTICATED:
		return _failure("TICKET_REUSED", {"ticket_id": ticket_id})
	if String(ticket["client_session_id"]) != client_session_id:
		return _failure("TICKET_CLIENT_SESSION_MISMATCH", {"ticket_id": ticket_id})
	return _success({"ticket": ticket.duplicate(true)})


func _is_expired(ticket: Dictionary) -> bool:
	if _max_ticket_age_ms <= 0:
		return false
	return _now_ms() - int(ticket["issued_at_ms"]) > _max_ticket_age_ms


func _mint_gateway_session_id(identity_suffix: String) -> Dictionary:
	# Mirror of the route-table mint convention: the counter commits only when
	# the caller actually records the session, so failed exchanges never burn
	# gateway-session ids.
	var candidate := "%s%s/%d" % [GATEWAY_SESSION_PREFIX, identity_suffix, _session_counter + 1]
	while _sessions_by_gateway_session_id.has(candidate):
		_session_counter += 1
		candidate = "%s%s/%d" % [GATEWAY_SESSION_PREFIX, identity_suffix, _session_counter + 1]
	_session_counter += 1
	return {"gateway_session_id": candidate}


func _mint_resume_token() -> String:
	_resume_token_counter += 1
	var token := "%s%d-%s" % [RESUME_TOKEN_PREFIX, _resume_token_counter, _random_hex(8)]
	while _live_resume_tokens.has(token):
		token = "%s%d-%s" % [RESUME_TOKEN_PREFIX, _resume_token_counter, _random_hex(8)]
	return token


func _random_hex(length: int) -> String:
	var alphabet := "0123456789abcdef"
	var out := ""
	for index in range(length):
		out += alphabet[randi() % alphabet.length()]
	return out


## Injective identity-suffix derivation. The naive sanitize-and-dash scheme
## ("a/b" -> "a-b") is NOT injective: "client-session/x/a-b" and
## "client-session/x-a-b" both collapse to "x-a-b" and would grant two distinct
## client sessions ONE shared logical player identity (cross-identity data
## leak). The short lowercase-hex digest of the FULL canonical id disambiguates
## every collision while keeping the suffix deterministic and readable.
func _identity_suffix(client_session_id: String) -> String:
	var sanitized := client_session_id.trim_prefix(CLIENT_SESSION_PREFIX).replace("/", "-")
	return "%s-%s" % [sanitized, _identity_digest(client_session_id)]


func _identity_digest(client_session_id: String) -> String:
	return client_session_id.sha256_text().substr(0, 10)


func _is_canonical_client_session_id(client_session_id: String) -> bool:
	var check: Dictionary = GatewayUtilsScript.require_id(
			{"client_session_id": client_session_id}, "client_session_id", "client-session")
	return bool(check.get("success", false))


func _count_outstanding_tickets() -> int:
	var count := 0
	for ticket_value in _tickets.values():
		if String(Dictionary(ticket_value)["state"]) == TICKET_STATE_ISSUED:
			count += 1
	return count


func _now_ms() -> int:
	if _time_override_ms >= 0:
		return _time_override_ms
	return Time.get_ticks_msec()


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
