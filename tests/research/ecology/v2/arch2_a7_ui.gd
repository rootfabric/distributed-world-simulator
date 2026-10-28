extends SceneTree
const Scene = preload("res://scenes/labs/ecology/arch2_a7_observatory.tscn")
var assertions := 0
var failed := 0
func check(ok: bool,label: String) -> void:
 assertions+=1
 if not ok:failed+=1;print("FAIL: ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var ui=Scene.instantiate();root.add_child(ui)
 await process_frame
 check(ui.report.success and ui.panels.size()==3,"three real rendered sites")
 check(not ui.running and ui.model.step_index()==0,"starts paused")
 var before=ui.model.source_hashes()
 ui._process(10.0)
 check(before==ui.model.source_hashes(),"paused time does not simulate")
 ui.find_child("Step",true,false).pressed.emit()
 check(ui.model.step_index()==1,"actual STEP signal advances")
 before=ui.model.source_hashes()
 ui.select("dry","litter-donor")
 check(ui.selected_site=="dry" and ui.selected_id=="litter-donor","inspector selection")
 check(ui.inspector.text.contains("FROZEN_PROVENANCE_NOT_SPENDABLE"),"dead archive labelled")
 check(ui.model.source_hashes()==before,"selection does not mutate")
 ui.effects.button_pressed=false
 check(ui.model.source_hashes()==before,"pending treatment not live edit")
 ui.effects.button_pressed=true
 ui.select("wet","study")
 ui.find_child("Save",true,false).pressed.emit()
 check(ui.status.text.begins_with("SAVED"),"UI durable save")
 ui.find_child("Step",true,false).pressed.emit()
 check(ui.model.step_index()==2,"next tick")
 ui.find_child("Load",true,false).pressed.emit()
 check(ui.model.step_index()==1 and ui.model.source_hashes()==before,"UI anchored load")
 ui.find_child("Export",true,false).pressed.emit()
 check(FileAccess.file_exists("res://artifacts/a7/observatory-report.json"),"source-bound export exists")
 ui.find_child("Play",true,false).pressed.emit()
 check(ui.running,"play button")
 ui.speed=4.0;ui._process(0.26)
 check(ui.model.step_index()==2,"speed only schedules whole ticks")
 ui.find_child("Play",true,false).pressed.emit()
 check(not ui.running,"pause button")
 var old=ui.model.experiment_hash()
 ui.common.button_pressed=true
 ui.find_child("Reset",true,false).pressed.emit()
 check(ui.model.step_index()==0 and ui.model.experiment_hash()!=old,"common garden explicit reset")
 check(ui.report.treatment.common_garden,"UI shows active treatment")
 ui.find_child("Load",true,false).pressed.emit()
 check(ui.model.step_index()==0 and ui.status.text.begins_with("LOAD FAILED"),"different treatment rejected")
 ui.common.button_pressed=false
 ui.find_child("Reset",true,false).pressed.emit()
 for i in 6: ui.find_child("Step",true,false).pressed.emit()
 for i in 10:
  if not ui.model.advance():check(false,"horizon advance");break
 ui.refresh()
 await process_frame
 var sources=ui.model.source_hashes()
 for site in ui.report.sites:
  check(ui.panels[site.id].site.source_hash==sources[site.id],"render bound to source "+site.id)
  check(ui.panels[site.id].site.entries==site.entries,"all real phenotype entries "+site.id)
 for site in ui.report.sites:
  for entry in site.entries:
   if entry.id=="study":
    var bounds=ui.panels[site.id].visual_bounds(entry)
    check(Rect2(Vector2(8,8),ui.panels[site.id].size-Vector2(16,48)).encloses(bounds),"complete horizon body in viewport "+site.id)
 check(is_equal_approx(ui.panels.wet.projection_scale(),ui.panels.dry.projection_scale()) and is_equal_approx(ui.panels.wet.projection_scale(),ui.panels.dark.projection_scale()),"common scale at full horizon")
 var p=ui.panels.wet
 check(p.point([10,20,30])!=p.point([10,20,0]),"z changes actual projection")
 if "--capture" in OS.get_cmdline_user_args():
  await process_frame
  await RenderingServer.frame_post_draw
  var image=root.get_texture().get_image()
  check(not image.is_empty() and image.get_width()>=1160,"actual viewport image")
  var path="res://artifacts/a7/observatory.png"
  check(image.save_png(path)==OK,"viewport saved")
  print("A7_CAPTURE_SOURCE ",ui.model.experiment_hash()," ",ui.model.step_index())
  var f=FileAccess.open("res://artifacts/a7/capture-sources.json",FileAccess.WRITE)
  f.store_string(ui.model.export_report());f.close()
 else: print("A7_CAPTURE_NOT_REQUESTED headless UI test only")
 check(sources==ui.model.source_hashes(),"drawing does not advance ecology")
 print("EVO_ARCH2_A7_UI assertions=%d failed=%d" %[assertions,failed])
 ui.queue_free();await process_frame
 quit(1 if failed else 0)
