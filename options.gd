extends VBoxContainer

func _ready():
	var text_input_nodes = [
		%PathOptions/PathArea,
		%PathOptions/PathThickness,
		%PathOptions/RenderResolution/Values/X,
		%PathOptions/RenderResolution/Values/Y,
		%MarkersMenu/HBox/Frame/Input,
		%MarkersMenu/HBox/Depth/Input]
	for node in text_input_nodes:
		node.get_child(0, true).focus_mode = FOCUS_CLICK
	
	var options_text_input_nodes = [
		%PathOptions/PathArea,
		%PathOptions/PathThickness,
		%PathOptions/RenderResolution/Values/X,
		%PathOptions/RenderResolution/Values/Y]
	for node in options_text_input_nodes:
		node.get_child(0, true).connect(
			"focus_entered",
			_on_input_focus_entered.bind(node))
		node.get_child(0, true).connect(
			"focus_exited",
			_on_input_focus_exited.bind(node))
	
	var config:ConfigFile = Data.config
	config.load(Data.config_path)
	
	if config.has_section_key('path', 'path_thickness'):
		var value = config.get_value('path', 'path_thickness')
		_on_path_thickness_value_changed(value)
		%PathOptions/PathThickness.value = value
	else:
		_on_path_thickness_value_changed(%PathOptions/PathThickness.value)
	
	if config.has_section_key('path', 'path_fade'):
		var value = config.get_value('path', 'path_fade')
		_on_path_fade_value_changed(value)
		%PathOptions/PathFade/HSlider.value = value
	else:
		_on_path_fade_value_changed(%PathOptions/PathFade/HSlider.value)
		%PathOptions/PathFade/HSlider.value = %PathOptions/PathFade/HSlider.value
	
	if config.has_section_key('path', 'path_speed'):
		var value = config.get_value('path', 'path_speed')
		_on_path_speed_changed(value)
		%PathOptions/PathSpeed/HSlider.value = value
	else:
		_on_path_speed_changed(%PathOptions/PathSpeed/HSlider.value)
		%PathOptions/PathSpeed/HSlider.value = %PathOptions/PathSpeed/HSlider.value
	
	if config.has_section_key('path', 'path_area'):
		var value = config.get_value('path', 'path_area')
		_on_path_area_value_changed(value)
		%PathOptions/PathArea.value = value
	else:
		_on_path_area_value_changed(%PathOptions/PathArea.value)
	
	if config.has_section_key('path', 'action_zone'):
		var value = config.get_value('path', 'action_zone')
		owner.action_zone = value
		$ActionZone/HSlider.set_value_no_signal(value)
		$ActionZone/Label.text = "Action Zone: %d%%" % int(value * 100)
	if config.has_section_key('path', 'marker_image'):
		%Markers.custom_marker_name = config.get_value('path', 'marker_image')
	if config.has_section_key('path', 'classic_mode'):
		$ClassicMode.set_pressed_no_signal(config.get_value('path', 'classic_mode'))
	
	call_deferred("_apply_classic_mode")
	call_deferred("_load_waveform_config")


## Deferred so the markers exist by the time the mode is applied to them.
func _apply_classic_mode() -> void:
	var enabled: bool = $ClassicMode.button_pressed
	refresh_marker_images()
	owner.set_classic_mode(enabled)
	$ActionZone.visible = enabled
	$MarkerImage.visible = enabled


## Lists whatever is in the markers directory, keeping the current choice
## selected, or falling back to the built in marker if it has gone.
func refresh_marker_images() -> void:
	var button: OptionButton = $MarkerImage/OptionButton
	var chosen: String = %Markers.custom_marker_name
	button.clear()
	button.add_item("Default")
	var selected := 0
	for file_name in Data.marker_images():
		button.add_item(file_name)
		if file_name == chosen:
			selected = button.item_count - 1
	if selected == 0 and chosen != "":
		chosen = ""
	button.select(selected)
	%Markers.set_custom_marker(chosen)


## Brings a newly added image into the list and switches to it.
func select_marker_image(file_name: String) -> void:
	%Markers.custom_marker_name = file_name
	refresh_marker_images()
	Data.set_config('path', 'marker_image', file_name)


func _on_marker_image_selected(index: int) -> void:
	var button: OptionButton = $MarkerImage/OptionButton
	var file_name := "" if index == 0 else button.get_item_text(index)
	%Markers.set_custom_marker(file_name)
	Data.set_config('path', 'marker_image', file_name)


func _on_classic_mode_toggled(toggled: bool) -> void:
	if toggled:
		refresh_marker_images()
	owner.set_classic_mode(toggled)
	$ActionZone.visible = toggled
	$MarkerImage.visible = toggled
	Data.set_config('path', 'classic_mode', toggled)


func _on_action_zone_changed(value: float) -> void:
	owner.action_zone = value
	$ActionZone/Label.text = "Action Zone: %d%%" % int(value * 100)
	owner.update_action_zone()
	%Markers.position_markers()
	Data.set_config('path', 'action_zone', value)


func _on_path_speed_changed(value):
	owner.path_speed = value
	%PathOptions/PathSpeed/Label.text = "Path Speed: " + str(int(value))
	Data.set_config('path', 'path_speed', value)
	for marker in %Markers.marker_list.values():
		marker.position.x = marker.get_meta('frame') * value
	%Markers.connect_all_markers()
	%Markers.position_markers()


func _on_path_fade_value_changed(value):
	%PathOptions/PathFade/Label.text = "Rendered Path Edge Fade: " + str(value)
	# Reading colors hands back a copy of the array, so assigning into it
	# changes nothing that is kept. The gradient has to be told.
	var gradient: Gradient = owner.get_node('Path').gradient
	for edge in [0, 2]:
		gradient.set_color(edge, Color(gradient.get_color(edge), 1.0 - value))
	Data.set_config('path', 'path_fade', value)


func _on_path_area_value_changed(value):
	owner.path_area = value
	owner.update_display()
	Data.set_config('path', 'path_area', value)
	$DebounceTimer.start()


func _on_path_thickness_value_changed(value):
	owner.get_node('Path').width = value
	%Markers.get_node('Line').width = value
	Data.set_config('path', 'path_thickness', value)
	$DebounceTimer.start()


func _on_debounce_timer_timeout():
	%Markers.connect_all_markers()


func _load_waveform_config() -> void:
	var wv_nodes := get_tree().get_nodes_in_group("WaveformView")
	var wv_scroll: Node = null
	var wv_static: Node = null
	for n in wv_nodes:
		if   n.display_mode == 1: wv_scroll = n
		elif n.display_mode == 0: wv_static = n
	
	var config: ConfigFile = Data.config
	
	if wv_scroll:
		if config.has_section_key('waveform', 'scroll_active'):
			wv_scroll.visible = config.get_value('waveform', 'scroll_active')
		if config.has_section_key('waveform', 'scroll_show_peak'):
			wv_scroll.show_peak = config.get_value('waveform', 'scroll_show_peak')
		if config.has_section_key('waveform', 'scroll_show_rms'):
			wv_scroll.show_rms = config.get_value('waveform', 'scroll_show_rms')
		if config.has_section_key('waveform', 'scroll_peak_color'):
			wv_scroll._peak_col = config.get_value('waveform', 'scroll_peak_color')
		if config.has_section_key('waveform', 'scroll_rms_color'):
			wv_scroll._rms_col = config.get_value('waveform', 'scroll_rms_color')
	
	if wv_static:
		if config.has_section_key('waveform', 'static_active'):
			var on: bool = config.get_value('waveform', 'static_active')
			wv_static.visible = on
			owner.get_node("%TrackSliderLarge").visible = not on
		if config.has_section_key('waveform', 'static_show_peak'):
			wv_static.show_peak = config.get_value('waveform', 'static_show_peak')
		if config.has_section_key('waveform', 'static_show_rms'):
			wv_static.show_rms = config.get_value('waveform', 'static_show_rms')
		if config.has_section_key('waveform', 'static_peak_color'):
			wv_static._peak_col = config.get_value('waveform', 'static_peak_color')
		if config.has_section_key('waveform', 'static_rms_color'):
			wv_static._rms_col = config.get_value('waveform', 'static_rms_color')


var input_zone_active: bool
var input_zone_begin:  Vector2
var input_zone_end:    Vector2

func _on_input_focus_entered(node: Control):
	owner.input_disabled = true
	input_zone_active = true
	var global_pos = node.global_position
	input_zone_begin = global_pos
	input_zone_end = global_pos + node.size


func _on_input_focus_exited(node: Control):
	owner.input_disabled = false
	input_zone_active = false


func _input(event):
	if not input_zone_active:
		return
	var release_focus: bool
	if event is InputEventMouseButton and event.is_pressed():
		var pos = event.global_position
		if pos.x < input_zone_begin.x or pos.x > input_zone_end.x:
			release_focus = true
		if pos.y < input_zone_begin.y or pos.y > input_zone_end.y:
			release_focus = true
	elif event.is_action_pressed('ui_accept'):
		get_viewport().set_input_as_handled()
		release_focus = true
	if release_focus:
		get_viewport().gui_get_focus_owner().release_focus()


func _on_gamepad_remapping_pressed() -> void:
	$GamepadRemapping/GamepadRemapDialog.popup_centered()


func _on_waveform_options_pressed() -> void:
	$WaveformOptions/WaveformOptionsDialog.popup_centered()


func _on_path_settings_pressed() -> void:
	$PathSettings/PathSettingsDialog.popup_centered()
	$PathSettings/PathSettingsDialog.position = Vector2(8, 100)


func _on_change_colors_pressed():
	$ChangeColors/ColorOptionsDialog.popup_centered()
	$ChangeColors/ColorOptionsDialog.position = Vector2(8, 100)


func _on_export_funscripts_pressed() -> void:
	if not $ExportFunscripts/FileDialog.files_selected.is_connected(_on_funscript_files_selected):
		$ExportFunscripts/FileDialog.files_selected.connect(_on_funscript_files_selected)
	$ExportFunscripts/FileDialog.current_dir = Data.paths_dir
	$ExportFunscripts/FileDialog.popup_centered()


func _on_funscript_files_selected(paths: PackedStringArray) -> void:
	var invert: bool = $ExportFunscripts/FileDialog.get_selected_options()["Inverted:"] == 1
	var count := 0
	var exported_paths := []
	for bx_path in paths:
		var file := FileAccess.open(bx_path, FileAccess.READ)
		if not file:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		file.close()
		if not parsed is Dictionary:
			continue
		
		var marker_data := {}
		var path_meta := {}
		
		if parsed.has("markers"):
			path_meta = parsed.get("meta", {})
			for key in parsed["markers"]:
				marker_data[int(key)] = parsed["markers"][key]
		else:
			for key in parsed:
				marker_data[int(key)] = parsed[key]
		
		if marker_data.is_empty():
			continue
		
		var base_name := bx_path.get_basename()
		var out_path := base_name + ".funscript"
		Funscript.export(marker_data, path_meta, out_path, invert)
		exported_paths.append(out_path)
		count += 1
	
	if count > 0:
		var text := "Exported %d funscript%s.\n" % [count, "" if count == 1 else "s"]
		for i in mini(count, 5):
			text += "\n" + exported_paths[i]
		if count > 5:
			text += "\n... and %d more" % (count - 5)
		var dialog := AcceptDialog.new()
		dialog.title = "Export Complete"
		dialog.dialog_text = text
		add_child(dialog)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.popup_centered()


func _on_open_resources_folder_pressed() -> void:
	OS.shell_open(Data.base_dir)
