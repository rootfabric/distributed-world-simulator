extends RefCounted
const P = preload("res://scripts/research/ecology/plant_catalog_persistence_v1.gd")
const C = preload("res://scripts/research/ecology/plant_accepted_e2_2_catalog_v1.gd")
const G = preload("res://scripts/research/ecology/plant_genome_v1.gd")
static func run(a:Dictionary, bytes:PackedByteArray)->Dictionary:
	var r:={}
	var text:=bytes.get_string_from_utf8(); var pp:=text.find("payload="); var cp:=text.find(":",pp); var mp:=cp+2
	var ch:=text.substr(mp,1); var corrupted:=text.substr(0,mp)+("A" if ch!="A" else "B")+text.substr(mp+1)
	r["byte_corruption"] = P.restore(corrupted.to_utf8_buffer()).is_empty()
	var hp:=cp-64; r["outer_hash"] = P.restore((text.substr(0,hp)+"0".repeat(64)+text.substr(cp)).to_utf8_buffer()).is_empty()
	var t:=a.duplicate(true); t["content_hash"]="0".repeat(64); r["content_hash"] = not P.validate_artifact(t)
	t=a.duplicate(true); var cat:Dictionary=Dictionary(t["species_catalog"]).duplicate(true); var es:Array=Array(cat["entries"]).duplicate(true); var e:Dictionary=Dictionary(es[0]).duplicate(true); var g:Dictionary=Dictionary(e["genome"]).duplicate(true)
	g["growth_rate"]=float(g["growth_rate"])+0.01; g["checksum"]=G.compute_checksum(g); e["genome"]=g; e["genome_checksum"]=String(g["checksum"]); e["entry_hash"]=C.compute_entry_hash(e); es[0]=e; cat["entries"]=es; cat["catalog_hash"]=C.compute_catalog_hash(cat); t["species_catalog"]=cat; t["content_hash"]=P.compute_content_hash(t)
	r["genome_rehash"] = P.restore(P.encode_unchecked(t)).is_empty()
	t=a.duplicate(true); cat=Dictionary(t["species_catalog"]).duplicate(true); es=Array(cat["entries"]).duplicate(true); e=Dictionary(es[0]).duplicate(true); e["lineage_id"]="eco-lineage/substituted"; e["research_species_id"]=C.research_species_id(String(e["lineage_id"])); e["ancestry_path"]=["eco-lineage/e22-root",e["lineage_id"]]; e["entry_hash"]=C.compute_entry_hash(e); es[0]=e; es.sort_custom(func(x:Dictionary,y:Dictionary)->bool:return String(x["research_species_id"])<String(y["research_species_id"])); cat["entries"]=es; cat["catalog_hash"]=C.compute_catalog_hash(cat); t["species_catalog"]=cat; t["content_hash"]=P.compute_content_hash(t)
	r["identity_rehash"] = P.restore(P.encode_unchecked(t)).is_empty()
	t=a.duplicate(true); var pv:Dictionary=Dictionary(t["provenance"]).duplicate(true); pv["e2_7_accepted_aggregate"]="1".repeat(64); t["provenance"]=pv; t["provenance_hash"]=P.hash_variant(pv); t["content_hash"]=P.compute_content_hash(t); r["provenance_rehash"] = P.restore(P.encode_unchecked(t)).is_empty()
	t=a.duplicate(true); t["unexpected"]=true; r["extra_field"] = not P.validate_artifact(t)
	t=a.duplicate(true); t.erase("provenance_hash"); r["missing_field"] = not P.validate_artifact(t)
	t=a.duplicate(true); cat=Dictionary(t["species_catalog"]).duplicate(true); es=Array(cat["entries"]).duplicate(true); e=Dictionary(es[0]).duplicate(true); e["unexpected"]=true; es[0]=e; cat["entries"]=es; t["species_catalog"]=cat; t["content_hash"]=P.compute_content_hash(t); r["entry_extra_field"] = P.restore(P.encode_unchecked(t)).is_empty()
	t=a.duplicate(true); t["schema"]="wrong.schema"; t["content_hash"]=P.compute_content_hash(t); r["wrong_schema"] = P.restore(P.encode_unchecked(t)).is_empty()
	t=a.duplicate(true); t["version"]="2.0.0"; t["content_hash"]=P.compute_content_hash(t); r["future_version"] = P.restore(P.encode_unchecked(t)).is_empty()
	t=a.duplicate(true); cat=Dictionary(t["species_catalog"]).duplicate(true); es=Array(cat["entries"]).duplicate(true); es.reverse(); cat["entries"]=es; cat["catalog_hash"]=C.compute_catalog_hash(cat); t["species_catalog"]=cat; t["content_hash"]=P.compute_content_hash(t); r["reordered_entries"] = P.restore(P.encode_unchecked(t)).is_empty()
	t=a.duplicate(true); cat=Dictionary(t["species_catalog"]).duplicate(true); cat["catalog_hash"]="2".repeat(64); t["species_catalog"]=cat; t["content_hash"]=P.compute_content_hash(t); r["catalog_identity"] = P.restore(P.encode_unchecked(t)).is_empty()
	return r
