extends RefCounted
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
var _server_id="";var _cell_id="";var _gateway;var _transfer
func setup(server_id:String,cell_id:String,command_gateway,transfer_backend)->Dictionary:
 if not P.path_id(server_id,"server/") or not P.path_id(cell_id,"cell/"):return P.failure("INVALID_CONSTRUCTION_AUTHORITY_ENDPOINT_IDENTITY")
 if command_gateway==null or not command_gateway.has_method("submit"):return P.failure("CONSTRUCTION_AUTHORITY_ENDPOINT_GATEWAY_REQUIRED")
 if transfer_backend==null or not transfer_backend.has_method("export_construct_state") or not transfer_backend.has_method("import_construct_state") or not transfer_backend.has_method("get_construct_checksum"):return P.failure("CONSTRUCTION_AUTHORITY_ENDPOINT_TRANSFER_BACKEND_REQUIRED")
 _server_id=server_id;_cell_id=cell_id;_gateway=command_gateway;_transfer=transfer_backend;return P.success()
func submit(command:Dictionary)->Dictionary:return _gateway.submit(command)
func export_construct_state(construct_id:String)->Dictionary:return _transfer.export_construct_state(construct_id)
func import_construct_state(state:Dictionary,terminal_operations:Array=[])->Dictionary:return _transfer.import_construct_state(state,terminal_operations)
func get_construct_checksum(construct_id:String)->String:return String(_transfer.get_construct_checksum(construct_id))
func has_terminal_command(command_id:String,command_checksum:String)->bool:
 if _gateway.has_method("has_terminal_command"):return bool(_gateway.has_terminal_command(command_id,command_checksum))
 if _transfer.has_method("has_terminal_command"):return bool(_transfer.has_terminal_command(command_id,command_checksum))
 return false
func get_server_id()->String:return _server_id
func get_cell_id()->String:return _cell_id
