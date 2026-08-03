extends RefCounted
const Command=preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const Grant=preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
var _gateway
func setup(gateway)->Dictionary:
 if gateway==null or not gateway.has_method("submit"):return _f("CONSTRUCTION_INTERACTION_GATEWAY_REQUIRED")
 _gateway=gateway;return _ok()
func build_stage(session:Dictionary,command_id:String,construct_id:String,construct_checksum:String,server_generation:int,plan_id:String,stage_index:int,operation_id:String,capabilities:Array,options:Dictionary={})->Dictionary:
 return _submit(Command.create(command_id,String(session.client_id),String(session.session_id),int(session.session_epoch),int(session.next_sequence),Grant.ACTION_BUILD,construct_id,construct_checksum,server_generation,int(session.permission_epoch),{"build_plan_id":plan_id,"stage_index":stage_index,"operation_id":operation_id,"provided_capabilities":capabilities,"options":options}))
func edit(session:Dictionary,command_id:String,construct_id:String,construct_checksum:String,server_generation:int,plan_id:String,request:Dictionary)->Dictionary:
 return _submit(Command.create(command_id,String(session.client_id),String(session.session_id),int(session.session_epoch),int(session.next_sequence),Grant.ACTION_EDIT,construct_id,construct_checksum,server_generation,int(session.permission_epoch),{"plan_id":plan_id,"request":request,"failure_mode":""}))
func repair(session:Dictionary,command_id:String,construct_id:String,construct_checksum:String,server_generation:int,plan_id:String,operation_id:String,repair_plan:Dictionary)->Dictionary:
 return _submit(Command.create(command_id,String(session.client_id),String(session.session_id),int(session.session_epoch),int(session.next_sequence),Grant.ACTION_REPAIR,construct_id,construct_checksum,server_generation,int(session.permission_epoch),{"plan_id":plan_id,"operation_id":operation_id,"repair_plan":repair_plan,"failure_mode":""}))
func _submit(command:Dictionary)->Dictionary:
 var e=Command.validate(command);if not e.success:return e
 var result:Dictionary=_gateway.submit(command);result["command"]=command.duplicate(true);return result
static func _ok():return {"success":true,"error_code":"","message":""}
static func _f(c):return {"success":false,"error_code":c,"message":c}
