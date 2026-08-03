extends Control
var title_label:Label;var status_label:Label;var material_label:Label;var progress:ProgressBar
func _init():
 name="ConstructionInteractionOverlay";title_label=Label.new();title_label.name="Title";add_child(title_label);status_label=Label.new();status_label.name="Status";add_child(status_label);material_label=Label.new();material_label.name="Materials";add_child(material_label);progress=ProgressBar.new();progress.name="Progress";progress.min_value=0;progress.max_value=1;add_child(progress)
func show_placement(solution:Dictionary)->void:title_label.text="Размещение";status_label.text="Допустимо" if bool(solution.get("valid",false)) else "Нет подходящей привязки";progress.value=1.0 if bool(solution.get("valid",false)) else 0.0
func show_materials(model:Dictionary)->void:
 var missing=int(model.get("summary",{}).get("missing_count",0));var total=int(model.get("summary",{}).get("required_count",0));material_label.text="Материалы: %d/%d, отсутствует %d"%[total-missing,total,missing];progress.value=1.0 if total==0 else float(total-missing)/float(total)
func show_command_result(result:Dictionary)->void:status_label.text="Команда принята" if bool(result.get("success",false)) else "Отказ: %s"%String(result.get("error_code","UNKNOWN"))
