extends RefCounted

## ECO.EVO7 PERF1-PAR0 — worker transport for persistent OS worker processes.
##
## Two planes:
##   control plane  — persistent worker stdin/stdout pipes (same Godot
##                    executable) carrying small framed messages only.
##   bulk plane     — bounded filesystem inbox/outbox mailboxes under the
##                    session directory carrying JOB request/response payloads.
##
## Windows evidence recorded by the PAR0 transport probe:
##   - small pipe frames (<= ~3KB) are reliable in both directions;
##   - single pipe writes above ~4KB are delivered PARTIALLY by this runtime
##     (PIPE_TRANSPORT_PARTIAL), so bulk payloads never travel over pipes;
##   - Godot hash() is process-seeded and must not be used cross-process;
##     integrity uses SHA-256 (HashingContext).
##
## The transport carries no ecology authority: it moves opaque canonical
## dictionaries and never mutates simulation state.

const PROTOCOL_VERSION := "par0.v1"
const WRITE_CHUNK := 3072
const CHECKSUM_LEN := 16
const FILE_EXT_REQUEST := ".req"
const FILE_EXT_RESPONSE := ".res"

## ---------- framing ----------

class FrameParser:
	var _buf := PackedByteArray()

	func feed(chunk: PackedByteArray) -> void:
		## CR/LF never occur inside a legitimate frame (header and base64 are
		## CR/LF-free); chunked print()/store_line() newline additions and the
		## engine banner are tolerated by dropping CR/LF at ingestion and
		## re-syncing to the next '#'.
		for b in chunk:
			if b != 10 and b != 13:
				_buf.append(b)

	func try_parse() -> Dictionary:
		_resync()
		if _buf.size() == 0 or _buf[0] != 35: # '#'
			return {}
		var header_end := _find(_buf, 124, 1) # first '|'
		if header_end < 0:
			return {}
		var crc_pos := _find(_buf, 124, header_end + 1) # second '|'
		if crc_pos < 0:
			return {}
		var len_text := _buf.slice(1, header_end).get_string_from_ascii()
		var crc_text := _buf.slice(header_end + 1, crc_pos).get_string_from_ascii()
		if not len_text.is_valid_int() or crc_text.length() != CHECKSUM_LEN or not _is_hex(crc_text):
			_buf.remove_at(0)
			return try_parse()
		var want := int(len_text)
		if want < 0 or want > 67108864:
			_buf.remove_at(0)
			return try_parse()
		var b64_len := ((want + 2) / 3) * 4
		var payload_start := crc_pos + 1
		if _buf.size() < payload_start + b64_len:
			return {}
		var b64 := _buf.slice(payload_start, payload_start + b64_len).get_string_from_ascii()
		var raw := Marshalls.base64_to_raw(b64)
		_buf = _buf.slice(payload_start + b64_len)
		var crc_ok: bool = raw.size() == want and _checksum_local(raw) == crc_text
		return {"payload": raw, "crc_ok": crc_ok, "declared": want}

	## Inner classes cannot resolve the outer script's statics by name; keep
	## a local copy of the checksum here.
	static func _checksum_local(raw: PackedByteArray) -> String:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(raw)
		return ctx.finish().hex_encode().substr(0, CHECKSUM_LEN)

	## Drop noise (engine banner bytes) before the next candidate frame.
	func _resync() -> void:
		while _buf.size() > 0 and _buf[0] != 35:
			_buf.remove_at(0)

	func debug_prefix(count: int) -> String:
		var out := ""
		for i in mini(count, _buf.size()):
			out += "%02x " % _buf[i]
		return out

	func _find(buf: PackedByteArray, byte_value: int, from: int) -> int:
		for i in range(from, buf.size()):
			if buf[i] == byte_value:
				return i
		return -1

	func _is_hex(text: String) -> bool:
		for i in text.length():
			var c := text.unicode_at(i)
			var ok := (c >= 48 and c <= 57) or (c >= 97 and c <= 102) or (c >= 65 and c <= 70)
			if not ok:
				return false
		return true

static func checksum(raw: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(raw)
	return ctx.finish().hex_encode().substr(0, CHECKSUM_LEN)

static func frame_text(payload: PackedByteArray) -> String:
	return "#%d|%s|%s" % [payload.size(), checksum(payload), Marshalls.raw_to_base64(payload)]

static func encode_frame(payload: PackedByteArray) -> PackedByteArray:
	return frame_text(payload).to_utf8_buffer()

## Split a frame into bounded pipe-write chunks. Single pipe writes above
## ~4KB are delivered partially by this Windows runtime (probe evidence), so
## senders must always go through this helper.
static func chunks_of(frame: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var offset := 0
	while offset < frame.size():
		var take := mini(WRITE_CHUNK, frame.size() - offset)
		out.append(frame.slice(offset, offset + take))
		offset += take
	return out

static func parse_lines(parser: FrameParser) -> Array[String]:
	var out: Array[String] = []
	while true:
		var msg: Dictionary = parser.try_parse()
		if msg.is_empty():
			break
		if not bool(msg["crc_ok"]):
			out.append("@CORRUPT")
			continue
		out.append((msg["payload"] as PackedByteArray).get_string_from_utf8())
	return out

## ---------- mailbox bulk plane ----------

## Payload dictionaries travel as var_to_bytes with a SHA-256 guard file.
## Both files live in the session directory; outbox entries are removed by
## the coordinator after consumption, keeping the mailbox bounded.

static func write_mailbox_message(session_dir: String, plane: String, job_id: String, payload: Dictionary) -> String:
	var dir := session_dir.path_join(plane)
	DirAccess.make_dir_recursive_absolute(dir)
	var raw: PackedByteArray = var_to_bytes(payload)
	var extension := FILE_EXT_REQUEST if plane == "inbox" else FILE_EXT_RESPONSE
	var path := dir.path_join(job_id + extension)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_32(raw.size())
	file.store_line(checksum(raw))
	file.store_buffer(raw)
	file.flush()
	file.close()
	return path

static func read_mailbox_message(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var size := file.get_32()
	var crc := file.get_line().strip_edges()
	var raw := file.get_buffer(size)
	file.close()
	if raw.size() != size or checksum(raw) != crc:
		return {}
	var decoded = bytes_to_var(raw)
	if typeof(decoded) != TYPE_DICTIONARY:
		return {}
	return decoded

static func mailbox_response_path(session_dir: String, job_id: String) -> String:
	return session_dir.path_join("outbox").path_join(job_id + FILE_EXT_RESPONSE)

static func mailbox_request_path(session_dir: String, job_id: String) -> String:
	return session_dir.path_join("inbox").path_join(job_id + FILE_EXT_REQUEST)

static func remove_quiet(path: String) -> void:
	if path.is_empty():
		return
	DirAccess.remove_absolute(path)
