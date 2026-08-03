extends SceneTree
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const F=preload("res://tests/construction/fixtures/c17_distributed_authority_fixture.gd")
const Record=preload("res://scripts/construction/distributed/construction_authority_record.gd")
const Section=preload("res://scripts/construction/distributed/construction_authority_section_projection.gd")
const Routed=preload("res://scripts/construction/distributed/construction_distributed_command.gd")
const Plan=preload("res://scripts/construction/distributed/construction_authority_migration_plan.gd")
const Handoff=preload("res://scripts/construction/distributed/construction_authority_handoff.gd")
const Registry=preload("res://scripts/construction/distributed/construction_authority_registry.gd")
const Replica=preload("res://scripts/construction/distributed/construction_authority_read_replica.gd")
const Endpoint=preload("res://scripts/construction/distributed/construction_authority_server_endpoint.gd")
const Transfer=preload("res://scripts/construction/distributed/construction_cross_zone_item_transfer.gd")
const AuthorityState=preload("res://scripts/construction/distributed/construction_distributed_authority_state.gd")
var assertions=0;var failures:Array[String]=[]
func _init():_record();_section();_command();_migration();_registry();_replica();_endpoint_and_transfer();_finish()
func _record():
 var state=F.state();var r=F.record(String(state.checksum));_ok(Record.validate(r),"record");_assert(r.replica_server_ids==[F.SERVER_B,F.SERVER_C],"replica order");_assert(r.state==Record.ACTIVE,"active");_assert(r.checksum.length()==64,"checksum");_assert(not Utils.canonical_json(r).is_empty(),"json")
 var extra=r.duplicate(true);extra["unknown"]=1;_err(Record.validate(extra),"UNEXPECTED_FIELD","extra")
 var bad=r.duplicate(true);bad.owner_server_id="alpha";bad.checksum=Record.compute_checksum(bad);_err(Record.validate(bad),"INVALID_CONSTRUCTION_AUTHORITY_SERVER_ID","owner")
 var duplicate=r.duplicate(true);duplicate.replica_server_ids=[F.SERVER_B,F.SERVER_B];duplicate.checksum=Record.compute_checksum(duplicate);_err(Record.validate(duplicate),"NON_CANONICAL_CONSTRUCTION_AUTHORITY_REPLICAS","duplicate replica")
 var fenced=Record.create(F.CONSTRUCT,F.SERVER_A,F.CELL_A,1,String(state.checksum),[F.SERVER_B],10,F.SERVER_A,{},Record.MIGRATING,"authority-migration/c17/x",F.SERVER_B);_ok(Record.validate(fenced),"fenced")
 var invalid=Record.create(F.CONSTRUCT,F.SERVER_A,F.CELL_A,1,String(state.checksum),[F.SERVER_B],10,F.SERVER_A,{},Record.ACTIVE,"authority-migration/c17/x",F.SERVER_B);_err(Record.validate(invalid),"INVALID_ACTIVE_CONSTRUCTION_AUTHORITY_FENCE","active fence")
func _section():
 var state=F.state();var s=Section.create("section/c17/east",F.CONSTRUCT,F.SERVER_A,F.SERVER_B,F.CELL_B,1,String(state.checksum),{"bounds":[0,0,0,10,5,10]});_ok(Section.validate(s),"section");_assert(s.mode==Section.READ_ONLY,"read only");_assert(s.coordinator_server_id==F.SERVER_A,"coordinator")
 var bad=s.duplicate(true);bad.mode="WRITE";bad.checksum=Section.compute_checksum(bad);_err(Section.validate(bad),"INVALID_CONSTRUCTION_AUTHORITY_SECTION_MODE","section write")
func _command():
 var c=F.routed(0,F.SERVER_A,1);_ok(Routed.validate(c),"routed");_assert(c.command.construct_id==F.CONSTRUCT,"inner target");_assert(c.authority_epoch==1,"epoch")
 var bad=c.duplicate(true);bad.authority_epoch=0;bad.checksum=Routed.compute_checksum(bad);_err(Routed.validate(bad),"INVALID_CONSTRUCTION_DISTRIBUTED_AUTHORITY_EPOCH","epoch invalid")
 var tamper=c.duplicate(true);tamper.source_server_id=F.SERVER_B;_err(Routed.validate(tamper),"CONSTRUCTION_DISTRIBUTED_COMMAND_CHECKSUM_MISMATCH","tamper")
func _migration():
 var state=F.state();var r=F.record(String(state.checksum));var p=Plan.create("authority-migration/c17/a-to-b",F.CONSTRUCT,F.SERVER_A,F.SERVER_B,F.CELL_A,F.CELL_B,1,String(r.checksum),String(state.checksum),[F.SERVER_A,F.SERVER_C],{"reason":"cell-crossing"});_ok(Plan.validate(p),"plan");_assert(p.target_authority_epoch==2,"target epoch");_assert(p.replica_server_ids==[F.SERVER_A,F.SERVER_C],"plan replicas")
 var same=p.duplicate(true);same.target_server_id=F.SERVER_A;same.checksum=Plan.compute_checksum(same);_err(Plan.validate(same),"CONSTRUCTION_AUTHORITY_MIGRATION_OWNER_UNCHANGED","same owner")
 var h=Handoff.create("authority-transfer/c17/a-to-b",p,state,[{"operation_id":"operation/c17/0","command_checksum":"a".repeat(64),"result":{"success":true}}],5);_ok(Handoff.validate(h),"handoff");_assert(h.terminal_operations.size()==1,"handoff ops")
 var mismatch=h.duplicate(true);mismatch.construct_state=F.state(F.CHILD);mismatch.checksum=Handoff.compute_checksum(mismatch);_err(Handoff.validate(mismatch),"CONSTRUCTION_AUTHORITY_HANDOFF_STATE_MISMATCH","handoff mismatch")
func _registry():
 var state=F.state();var r=F.record(String(state.checksum));var store=Registry.new();var first=store.publish(r);_ok(first,"publish");_assert(not first.replay and store.get_generation()==1,"publish generation");var replay=store.publish(r);_ok(replay,"record replay");_assert(replay.replay and store.get_generation()==1,"replay generation")
 var stale=Record.create(F.CONSTRUCT,F.SERVER_B,F.CELL_B,1,String(state.checksum),[F.SERVER_C],20);_err(store.publish(stale),"CONSTRUCTION_AUTHORITY_EPOCH_NOT_MONOTONIC","stale")
 var p=Plan.create("authority-migration/c17/registry",F.CONSTRUCT,F.SERVER_A,F.SERVER_B,F.CELL_A,F.CELL_B,1,String(r.checksum),String(state.checksum),[F.SERVER_A,F.SERVER_C]);_ok(store.begin_migration(p),"begin");_assert(store.get_record(F.CONSTRUCT).state==Record.MIGRATING,"fenced state");_ok(store.abort_migration(p),"abort");_assert(store.get_record(F.CONSTRUCT).state==Record.ACTIVE,"abort active")
 _ok(store.begin_migration(p),"begin 2");_ok(store.commit_migration(p,String(state.checksum),30),"commit");var moved=store.get_record(F.CONSTRUCT);_assert(moved.owner_server_id==F.SERVER_B and moved.authority_epoch==2,"moved")
 var exported=store.export_state();_ok(Registry.validate_state(exported),"registry state");var restored=Registry.new();_ok(restored.load_state(exported),"registry load");_assert(restored.get_record(F.CONSTRUCT).checksum==moved.checksum,"registry roundtrip")
func _replica():
 var state=F.state();var r=F.record(String(state.checksum));var replica=Replica.new();_ok(replica.configure(F.SERVER_B),"configure");_ok(replica.apply(r,state,1),"apply");_assert(not replica.can_write(),"replica write");_ok(Replica.validate_state(replica.get_state()),"replica state")
 var rollback=Record.create(F.CONSTRUCT,F.SERVER_A,F.CELL_A,1,String(state.checksum),[F.SERVER_B],10);_err(replica.apply(rollback,state,0),"CONSTRUCTION_AUTHORITY_REPLICA_TICK_ROLLBACK","tick rollback")
 var tamper=replica.get_state();tamper.construct_checksum="b".repeat(64);_err(Replica.validate_state(tamper),"CONSTRUCTION_AUTHORITY_REPLICA_CHECKSUM_MISMATCH","replica tamper")

func _endpoint_and_transfer():
 var gateway=F.FakeGateway.new();var endpoint=Endpoint.new();_ok(endpoint.setup(F.SERVER_A,F.CELL_A,gateway,gateway),"endpoint");_assert(endpoint.get_server_id()==F.SERVER_A and endpoint.get_cell_id()==F.CELL_A,"endpoint identity")
 _err(Endpoint.new().setup("bad",F.CELL_A,gateway,gateway),"INVALID_CONSTRUCTION_AUTHORITY_ENDPOINT_IDENTITY","endpoint bad id")
 var transfer=Transfer.create("cross-zone-transfer/c17/materials","operation/c17/materials",["item-instance/c17/a","item-instance/c17/b"],F.SERVER_A,F.SERVER_C,F.CELL_A,F.CELL_C,F.CONSTRUCT,F.CHILD,1,{"purpose":"split-rebind"});_ok(Transfer.validate(transfer),"transfer");_assert(transfer.item_instance_ids==["item-instance/c17/a","item-instance/c17/b"],"transfer items")
 var duplicate=transfer.duplicate(true);duplicate.item_instance_ids=["item-instance/c17/a","item-instance/c17/a"];duplicate.checksum=Transfer.compute_checksum(duplicate);_err(Transfer.validate(duplicate),"NON_CANONICAL_CONSTRUCTION_CROSS_ZONE_TRANSFER_ITEMS","transfer duplicate")
 var same=transfer.duplicate(true);same.target_server_id=F.SERVER_A;same.checksum=Transfer.compute_checksum(same);_err(Transfer.validate(same),"CONSTRUCTION_CROSS_ZONE_TRANSFER_SERVER_UNCHANGED","transfer same server")
 var registry=Registry.new();_ok(registry.publish(F.record(String(F.state().checksum))),"state registry");var replica=Replica.new();_ok(replica.configure(F.SERVER_B),"state replica config");_ok(replica.apply(registry.get_record(F.CONSTRUCT),F.state(),1),"state replica apply")
 var state=AuthorityState.create(registry.export_state(),[replica.get_state()],1);_ok(AuthorityState.validate(state),"authority state");var tamper=state.duplicate(true);tamper.tick=2;_err(AuthorityState.validate(tamper),"CONSTRUCTION_DISTRIBUTED_AUTHORITY_STATE_CHECKSUM_MISMATCH","authority state tamper")

func _ok(r,m):_assert(bool(r.get("success",false)),"%s: %s"%[m,r])
func _err(r,c,m):_assert(not bool(r.get("success",false)) and String(r.get("error_code",""))==c,"%s: %s"%[m,r])
func _assert(v,m):assertions+=1;if not v:failures.append(m)
func _finish():
 if failures.is_empty():print("C17 distributed authority contracts: PASS (%d assertions)"%assertions);quit(0);return
 for f in failures:push_error(f)
 print("C17 distributed authority contracts: FAIL (%d failures, %d assertions)"%[failures.size(),assertions]);quit(1)
