extends ConfirmationDialog

var track_title: String
var path_name: String

@onready var dir: DirAccess = DirAccess.open(Data.paths_dir)

func _ready():
	$Panel.self_modulate.a = 1.5
	
	for text_input: LineEdit in [$VBox/FileName/Input, $CopyConfirmation/VBox/Input, $FunscriptDialog/VBox/FileName/Input]:
		text_input.text_changed.connect(func(new_text: String):
				var disallowed_chars = ['/', '\\', ':', '*', '?', '"', '<', '>', '|']
				var filtered_text: String
				for char in text_input.text:
					if not disallowed_chars.has(char):
						filtered_text += char
				if filtered_text != new_text:
					text_input.set_text(filtered_text)
					text_input.set_caret_column(filtered_text.length()))
	
	$VBox/Actions/Delete.pressed.connect(func(): $DeleteConfirmation.popup_centered())
	$VBox/Actions/Copy.pressed.connect(func(): $CopyConfirmation.popup_centered())
	$VBox/Actions/ExportFunscript.pressed.connect(func(): $FunscriptDialog.popup_centered())

	$FunscriptDialog.confirmed.connect(export_funscript)
	$FunscriptDialog.canceled.connect(func(): $Panel.hide())
	$FunscriptDialog.about_to_popup.connect(func():
			$FunscriptDialog/VBox/FileName/Input.text = path_name
			$FunscriptDialog/VBox/Invert.button_pressed = false
			$Panel.show())
	
	$CopyConfirmation.confirmed.connect(copy_path)
	$CopyConfirmation.canceled.connect(func(): $Panel.hide())
	$CopyConfirmation.about_to_popup.connect(func():
			$CopyConfirmation/VBox/Input.text = path_name + " - copy"
			$Panel.show())
	
	$DeleteConfirmation.confirmed.connect(delete_path)
	$DeleteConfirmation.canceled.connect(func(): $Panel.hide())
	$DeleteConfirmation.about_to_popup.connect(func():
			$DeleteConfirmation.dialog_text = path_name
			$Panel.show())


func _path_exists(dir_path: String, name: String) -> bool:
	return FileAccess.file_exists(dir_path.path_join(name + ".bx"))


func delete_path() -> void:
	var dir_path: String = Data.paths_dir.path_join(track_title)
	dir.remove(dir_path.path_join(path_name + ".bx"))
	%Controls.load_paths(track_title)
	owner.path.clear()
	owner.frame = 0
	owner.define_path()
	$Panel.hide()
	hide()


func copy_path() -> void:
	var current_path: String = Data.get_file_path()
	var track_name   := current_path.get_base_dir().get_file()
	var base_name    := current_path.get_basename().get_file()
	var new_path_name: String = $CopyConfirmation/VBox/Input.text
	if new_path_name == base_name:
		new_path_name += " - copy"
	var dir_path: String = Data.paths_dir.path_join(track_name)
	if _path_exists(dir_path, new_path_name):
		$CopyConfirmation/VBox/Input.text = new_path_name + " - copy"
		return
	var src_file := current_path
	var dst_file := dir_path.path_join(new_path_name + ".bx")
	var src := FileAccess.open(src_file, FileAccess.READ)
	var dst := FileAccess.open(dst_file, FileAccess.WRITE)
	if src and dst:
		dst.store_buffer(src.get_buffer(src.get_length()))
	if src: src.close()
	if dst: dst.close()
	%Controls.load_paths(track_name, true)
	$Panel.hide()
	hide()


func export_funscript() -> void:
	var file_name: String = $FunscriptDialog/VBox/FileName/Input.text
	if file_name.is_empty():
		file_name = path_name + " - funscript"
	var invert: bool = $FunscriptDialog/VBox/Invert.button_pressed

	var duration := 0
	if owner.has_method("_get_track_duration"):
		duration = int(round(owner._get_track_duration()))

	var dir_path: String = Data.paths_dir.path_join(track_title)
	var out_path := dir_path.path_join(file_name + ".funscript")
	Funscript.export(owner.marker_data, owner.path_meta, out_path, invert, duration)

	$Panel.hide()
	hide()

	var dialog := AcceptDialog.new()
	dialog.title = "Export Complete"
	dialog.dialog_text = "Exported funscript.\n\n" + out_path
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.popup_centered()


func _on_confirmed():
	if not $VBox/PathCreator/Input.text.is_empty():
		owner.path_meta["path_creator"] = $VBox/PathCreator/Input.text
	if not $VBox/RelatedMedia/Input.text.is_empty():
		owner.path_meta["related_media"] = $VBox/RelatedMedia/Input.text
	Data.save_path()
	var new_path_name: String = $VBox/FileName/Input.text
	if new_path_name != path_name:
		var dir_path: String = Data.paths_dir.path_join(track_title)
		if _path_exists(dir_path, new_path_name):
			return
		dir.rename(dir_path.path_join(path_name + ".bx"), dir_path.path_join(new_path_name + ".bx"))
		# Only the name has changed. Rebuilding the list would unload the path
		# and read every marker back off disk to arrive at what is already
		# loaded, so rename the entry where it sits and leave the path alone.
		for item in %Controls/Paths.item_count:
			if %Controls/Paths.get_item_text(item) == path_name:
				%Controls/Paths.set_item_text(item, new_path_name)
				break
		path_name = new_path_name
