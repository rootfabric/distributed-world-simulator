extends RefCounted
const Catalog = preload("res://scripts/research/ecology/plant_accepted_e2_2_catalog_v1.gd")
const Provenance = preload("res://scripts/research/ecology/plant_evo2_provenance_v1.gd")
const SCHEMA := "distributed_world_simulator.ecology.evo2_catalog_persistence.v1"
const VERSION := "1.0.0"
const ENCODING := "GODOT_VARIANT_BINARY_CANONICAL_V1"
const MAGIC := "DWS-ECO-EVO2-E2.8-CATALOG-PERSISTENCE-V1"
const KNOWN_COMPATIBLE_VERSIONS: Array[String] = []
const FIELDS: Array[String] = ["schema","version","encoding","research_only","production_save_authority_claimed","distributed_durability_claimed","canonical_taxonomy_claimed","world_transaction_semantics_claimed","species_catalog","provenance","provenance_hash","content_hash"]
static func expected_provenance()->Dictionary:return Provenance.expected()
static func build_artifact() -> Dictionary:
	var c:=Catalog.build(); var p:=Provenance.expected()
	if c.is_empty() or p.is_empty(): return {}
	var a:={"schema":SCHEMA,"version":VERSION,"encoding":ENCODING,"research_only":true,"production_save_authority_claimed":false,"distributed_durability_claimed":false,"canonical_taxonomy_claimed":false,"world_transaction_semantics_claimed":false,"species_catalog":c,"provenance":p,"provenance_hash":hash_variant(p)}
	a["content_hash"]=compute_content_hash(a)
	return a if validate_artifact(a) else {}
static func validate_artifact(a:Dictionary)->bool:
	if not _exact(a,FIELDS) or String(a.get("schema",""))!=SCHEMA or String(a.get("version",""))!=VERSION or String(a.get("encoding",""))!=ENCODING: return false
	if typeof(a.get("research_only"))!=TYPE_BOOL or not bool(a["research_only"]): return false
	for f in ["production_save_authority_claimed","distributed_durability_claimed","canonical_taxonomy_claimed","world_transaction_semantics_claimed"]:
		if typeof(a.get(f))!=TYPE_BOOL or bool(a[f]): return false
	if typeof(a.get("species_catalog"))!=TYPE_DICTIONARY or not Catalog.validate(Dictionary(a["species_catalog"])): return false
	if typeof(a.get("provenance"))!=TYPE_DICTIONARY or not Provenance.validate(Dictionary(a["provenance"])): return false
	if String(a.get("provenance_hash",""))!=hash_variant(a["provenance"]): return false
	return String(a.get("content_hash",""))==compute_content_hash(a) and _hex64(String(a["content_hash"]))
static func compute_content_hash(a:Dictionary)->String:
	var c:={}
	for f in FIELDS:
		if f!="content_hash": c[f]=a.get(f)
	return hash_variant(c)
static func serialize(a:Dictionary)->PackedByteArray:
	return _encode(a) if validate_artifact(a) else PackedByteArray()
static func restore(bytes:PackedByteArray)->Dictionary:
	if bytes.is_empty(): return {}
	var text:=bytes.get_string_from_utf8()
	if text.to_utf8_buffer()!=bytes: return {}
	var l:=text.split("\n",true)
	if l.size()!=6 or String(l[5])!="" or String(l[0])!=MAGIC or String(l[1])!="schema="+SCHEMA or String(l[2])!="version="+VERSION or String(l[3])!="encoding="+ENCODING or not String(l[4]).begins_with("payload="): return {}
	var r:=String(l[4]).substr(8); var sep:=r.find(":")
	if sep!=64: return {}
	var h:=r.substr(0,sep); var b64:=r.substr(sep+1)
	if not _hex64(h) or b64.is_empty(): return {}
	var binary:=Marshalls.base64_to_raw(b64)
	if binary.is_empty() or Marshalls.raw_to_base64(binary)!=b64 or sha256_bytes(binary)!=h: return {}
	var v=bytes_to_var(binary)
	if typeof(v)!=TYPE_DICTIONARY: return {}
	var a:Dictionary=v
	if not validate_artifact(a) or _encode(a)!=bytes: return {}
	return a.duplicate(true)
static func encode_unchecked(a:Dictionary)->PackedByteArray: return _encode(a)
static func encode_transport_unchecked(a:Dictionary)->PackedByteArray: return _encode(a)
static func _encode(a:Dictionary)->PackedByteArray:
	var binary:=var_to_bytes(_canon(a)); var h:=sha256_bytes(binary); var b64:=Marshalls.raw_to_base64(binary)
	return "\n".join(PackedStringArray([MAGIC,"schema="+SCHEMA,"version="+VERSION,"encoding="+ENCODING,"payload=%s:%s"%[h,b64],""])).to_utf8_buffer()
static func classify_version(schema:String,version:String)->String:
	if schema!=SCHEMA:return "WRONG_SCHEMA"
	var v:=_semver(version)
	if v.is_empty():return "MALFORMED"
	if version==VERSION:return "CURRENT_VERSION"
	if version in KNOWN_COMPATIBLE_VERSIONS:return "KNOWN_COMPATIBLE"
	var c:=_semver(VERSION)
	for i in range(3):
		if int(v[i])>int(c[i]):return "UNKNOWN_NEWER"
		if int(v[i])<int(c[i]):return "UNDECLARED_OLDER"
	return "MALFORMED"
static func _semver(s:String)->Array:
	var p:=s.split(".",false); if p.size()!=3:return []
	var out:=[]
	for x in p:
		var t:=String(x); if t.is_empty() or (t.length()>1 and t.begins_with("0")):return []
		for ch in t:
			if not String(ch) in ["0","1","2","3","4","5","6","7","8","9"]:return []
		out.append(int(t))
	return out
static func _canon(v):
	match typeof(v):
		TYPE_DICTIONARY:
			var keys:Array[String]=[]
			for k in Dictionary(v).keys():
				if typeof(k) not in [TYPE_STRING,TYPE_STRING_NAME]:return null
				keys.append(String(k))
			keys.sort(); var o:={}
			for k in keys:o[k]=_canon(Dictionary(v)[k])
			return o
		TYPE_ARRAY:
			var o:=[]
			for x in Array(v):o.append(_canon(x))
			return o
		TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING,TYPE_STRING_NAME:return v
		_:return null
static func hash_variant(v)->String:return sha256_bytes(var_to_bytes(_canon(v)))
static func sha256_bytes(b:PackedByteArray)->String:
	var c:=HashingContext.new(); if c.start(HashingContext.HASH_SHA256)!=OK:return ""
	if c.update(b)!=OK:return ""
	return c.finish().hex_encode()
static func transport_sha256(b:PackedByteArray)->String:return sha256_bytes(b)
static func _exact(v:Dictionary,f:Array[String])->bool:
	if v.keys().size()!=f.size():return false
	for x in f:
		if not v.has(x):return false
	for k in v.keys():
		if not String(k) in f:return false
	return true
static func _hex64(s:String)->bool:
	if s.length()!=64 or s!=s.to_lower():return false
	for ch in s:
		if not String(ch) in ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"]:return false
	return true
