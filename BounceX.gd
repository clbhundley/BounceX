extends Control

var TOP:float
var BOTTOM:float

var top_color:Color = Color.WHITE
var top_color_active:Color = Color.AQUAMARINE

var bottom_color:Color = Color.WHITE
var bottom_color_active:Color = Color.CORAL

var hold_breath_ball_color:Color = Color.DEEP_PINK
var hold_breath_path_color:Color = Color.PINK

var path:PackedFloat32Array
var path_speed:float
var path_area:int

var marker_data:Dictionary

var frame:int
var step:int

const MOUSE_WHEEL_ACCELERATOR:int = 5
const DRAG_RESISTANCE:float = 4

var shift_pressed:bool
var control_pressed:bool

var input_disabled:bool

enum Effects {
	HOLD_BREATH = 1
}

func _init():
	Data.bx = self


func _ready():
	Data.load_config()
	$Path.gradient.offsets[1] = 1
	$Path.width = %Options/PathThickness.value
	$Menu.self_modulate.a = 1.65
	toggle_ball_visible(false)
	update_display()


func _physics_process(delta):
	if %Play.button_pressed:
		if not %AudioStreamPlayer.stream_paused:
			if frame+1 < path.size() - 1:
				if sign(path[frame+1]) > -1:
					place_ball(path[frame+1])
					toggle_ball_visible(true)
				elif $Menu/Controls/Paths.is_anything_selected():
					if not %Record.button_pressed:
						toggle_ball_visible(false)
				if not %Record.button_pressed:
					frame += 1
				if $Markers.is_visible_in_tree():
					$Markers.position.x -= path_speed
			else:
				%Play.button_pressed = false
				$Header/Play.hide()
				$Header/Record.hide()
	if not $Menu/Colors.is_visible_in_tree():
		line_colors(frame)
	if %Record.button_pressed:
		if frame < path.size() - 1:
			frame += 1
		else:
			%Record.button_pressed = false


func line_colors(point:int) -> void:
	if path.size() < 4:
		return
	var previous = [path[point], path[point-1], path[point-2], path[point-3]]
	if previous.has(1.0):
		$TopLine.self_modulate = top_color_active
	else:
		$TopLine.self_modulate = top_color
	if previous.has(0.0):
		$BottomLine.self_modulate = bottom_color_active
	else:
		$BottomLine.self_modulate = bottom_color


func define_path(set_ball_pos := true):
	var frames = ceil(%AudioStreamPlayer.stream.get_length() * 60)
	path.clear()
	for i in frames:
		path.append(-1)
	if set_ball_pos:
		place_ball(0)
		var ball_pos = clamp(($Ball.position.y - BOTTOM) / (TOP - BOTTOM), 0, 1)
		place_marker(ball_pos)


func save_path():
	var paths = %Controls.get_node('Paths')
	if paths.is_anything_selected():
		Data.save_path()
	else:
		var track_list = %Controls.get_node('TrackSelection')
		var track_title = track_list.get_item_text(track_list.selected)
		var path_name:String = Data.timestamp()
		Data.save_path('user://Paths/' + track_title + "/" + path_name + ".bx")
		%Controls.load_paths(track_title)
		for i in paths.item_count:
			if paths.get_item_text(i) == path_name:
				paths.select(i)
				%Controls._on_path_selected(i)


func get_ease_direction(depth) -> int:
	var ease:int
	if depth >= get_ball_depth():
		return $MarkersMenu/HBox/EaseUp.selected
	else:
		return $MarkersMenu/HBox/EaseDown.selected


func toggle_ball_visible(toggled:bool) -> void:
	$Ball.modulate.a = max(float(toggled), 0.3)


func get_ball_depth() -> float:
	return abs(($Ball.position.y - BOTTOM) / (TOP - BOTTOM))


func place_ball(depth:float) -> void:
	$Ball.position.y = BOTTOM + depth * (TOP - BOTTOM)
	if not $Markers.selected_marker:
		$MarkersMenu/HBox/Depth/Input.value = get_ball_depth()


func place_marker(depth:float) -> void:
	var easing = get_ease_direction(depth)
	var min_frames:int = $Markers.SEPARATION_MIN
	for i in range(frame - min_frames, frame + min_frames + 1):
		if marker_data.has(i):
			return
	marker_data[frame] = [depth, $MarkersMenu/HBox/Trans.selected, easing, 0]
	$Markers.add_marker(frame, depth)
	$Markers.connect_marker(frame)
	if %Record.button_pressed and $Header/MenuButton.button_pressed:
		$Header/MenuButton.button_pressed = false
	place_ball(depth)


func frame_scrub(frame_movement:float) -> void:
	connect_sliders_signal()
	frame = clamp(frame - frame_movement, 0, path.size() - 10)
	if sign(path[frame+1]) > -1:
		place_ball(path[frame+1])
	$Markers.position.x += path_speed * frame_movement
	%Controls.scrub(frame / float(path.size() - 1))
	var slider = $TrackSliderLarge
	if slider.is_connected("value_changed", %Controls.scrub):
		slider.disconnect("value_changed", %Controls.scrub)
	var track_length = %AudioStreamPlayer.stream.get_length()
	var playback_pos = %AudioStreamPlayer.get_playback_position()
	var seconds = str(int(playback_pos) % 60).lpad(2, "0")
	var minutes = str(int(playback_pos) / 60).lpad(2, "0")
	slider.get_node('TrackTime').text = minutes + ":" + seconds
	slider.set_value(playback_pos / track_length)


func _on_gui_input(event):
	if input_disabled:
		return
	if not %Record.button_pressed and %AudioStreamPlayer.stream:
		if event.is_action_pressed('mouse_wheel_up'):
			if $Markers.selected_marker:
				$MarkersMenu/HBox/Frame/Input.value -= 1
			else:
				frame_scrub(MOUSE_WHEEL_ACCELERATOR if shift_pressed else 1)
		elif event.is_action_pressed('mouse_wheel_down'):
			if $Markers.selected_marker:
				$MarkersMenu/HBox/Frame/Input.value += 1
			else:
				frame_scrub(-MOUSE_WHEEL_ACCELERATOR if shift_pressed else -1)
		elif event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_LEFT:
				frame_scrub(event.relative.x / DRAG_RESISTANCE)
	elif event is InputEventMouseButton and event.is_pressed():
		if event.button_mask & MOUSE_BUTTON_LEFT and %Record.button_pressed:
			var depth = (event.position.y - BOTTOM) / (TOP - BOTTOM)
			place_marker(clamp(depth, 0, 1))


func _input(event):
	if input_disabled:
		return
	
	elif event.is_action_pressed("record") and %AudioStreamPlayer.stream:
		%Record.button_pressed = !%Record.button_pressed
	
	elif event.is_action_pressed("cancel"):
		if $Markers.selected_marker:
			$Markers.selected_marker.get_node('Button').button_pressed = false
			$Markers.selected_multi_markers.clear()
		elif %Record.button_pressed:
			%Record.button_pressed = false
			$Header/Record.hide()
		else:
			%Play.button_pressed = false
	
	elif event.is_action_pressed("play") and %AudioStreamPlayer.stream:
		if %Record.button_pressed:
			%Record.button_pressed = false
		else:
			%Play.button_pressed = !%Play.button_pressed
	
	elif event.is_action_pressed("menu"):
		$Header/MenuButton.button_pressed = !$Header/MenuButton.button_pressed
	
	elif event.is_action_pressed('shift'):
		shift_pressed = true
	elif event.is_action_released('shift'):
		shift_pressed = false
	
	elif event.is_action_pressed('control'):
		control_pressed = true
	elif event.is_action_released('control'):
		control_pressed = false
	
	elif event.is_action_pressed("go_to_start"):
		if %AudioStreamPlayer.has_stream_playback():
			%Controls.scrub(0)
	elif event.is_action_pressed("go_to_end"):
		if %AudioStreamPlayer.has_stream_playback():
			%Controls.scrub(1)
	
	for depth in 11:
		if event.is_action_pressed('depth_' + str(depth)):
			depth_input(depth)
	for transition in 11:
		if event.is_action_pressed('trans_' + str(transition)):
			trans_input(transition)
	for easing in 8:
		if event.is_action_pressed('ease_' + str(easing)):
			easing_input(easing)


func depth_input(input:int):
	if %Record.button_pressed:
		place_marker(float(input) / 10)
	elif $Markers.selected_marker:
		$MarkersMenu/HBox/Depth/Input.value = float(input) / 10
	else:
		place_ball(float(input) / 10)


func trans_input(input:int):
	$MarkersMenu/HBox/Trans.select(input)
	$MarkersMenu/HBox/Trans.emit_signal('item_selected', input)


func easing_input(input:int):
	if $Markers.selected_marker:
		if input > 3:
			input -= 4
		$MarkersMenu/HBox/Ease.select(input)
		$MarkersMenu/HBox/Ease.emit_signal('item_selected', input)
	else:
		if input < 4:
			$MarkersMenu/HBox/EaseUp.select(input)
			$Markers._on_up_easing_selected(input)
		else:
			$MarkersMenu/HBox/EaseDown.select(input - 4)
			$Markers._on_down_easing_selected(input - 4)


func _on_record_toggled(active:bool):
	if active:
		%Play.button_pressed = true
		$Header/Play.hide()
		$Header/Record.show()
		var marker_node = $Markers.selected_marker
		if marker_node and is_instance_valid(marker_node):
			marker_node.get_node('Button').button_pressed = false
		toggle_ball_visible(true)
		if $Markers.marker_list.size() == 1:
			var depth = $Markers.marker_list[0].get_meta('depth')
			path[frame] = depth
			place_ball(depth)
	else:
		%Pause.button_pressed = true
		$Header/Record.hide()
		var paths = $Menu/Controls/Paths
		if not paths.is_anything_selected():
			var track_list = $Menu/Controls/TrackSelection
			var track_title = track_list.get_item_text(track_list.selected)
			var path_name:String = Data.timestamp()
			var f_name = 'user://Paths/' + track_title + "/" + path_name + ".bx"
			Data.save_path(f_name)
			%Controls.load_paths(track_title)
			for i in paths.item_count:
				if paths.get_item_text(i) == path_name:
					paths.select(i)
					%Controls._on_path_selected(i)
		else:
			Data.save_path()


func _on_play_toggled(button_pressed):
	if button_pressed:
		if %AudioStreamPlayer.stream_paused:
			%AudioStreamPlayer.stream_paused = false
		else:
			%AudioStreamPlayer.play()
		%Play.button_pressed = true
		$Header/Play.show()
		if $Markers.is_visible_in_tree():
			$Ball.show()
			$Markers.position_markers()
	else:
		toggle_ball_visible(false)
		if %Record.button_pressed:
			%Record.button_pressed = false
		%Pause.button_pressed = true
		$Header/Play.hide()
		if $Markers.is_visible_in_tree():
			$Path.hide()


func _on_render_pressed():
	$Header/MenuButton.button_pressed = false
	$RenderRange.popup_centered()


var active_effects:Dictionary
@export var flash_curve:Curve
@export var path_flash_curve:Curve
func render(starting_frame:int, ending_frame:int):
	var selected_take = $Menu/Controls/Paths.get_selected_items()[0]
	var path_name = $Menu/Controls/Paths.get_item_text(selected_take)
	var selected_track = $Menu/Controls/TrackSelection.selected
	var track_name = $Menu/Controls/TrackSelection.get_item_text(selected_track)
	
	var x_size = %Options/RenderResolution/Values/X.value
	var y_size = %Options/RenderResolution/Values/Y.value
	
	var window_starting_mode = DisplayServer.window_get_mode()
	var window_starting_size = DisplayServer.window_get_size()
	var window_starting_pos = DisplayServer.window_get_position()
	var resize_disabled = DisplayServer.WINDOW_FLAG_RESIZE_DISABLED
	var borderless = DisplayServer.WINDOW_FLAG_BORDERLESS
	var folder_name = path_name.trim_suffix('.bin')

	var ball_color_a:Color = $Ball.self_modulate
	var ball_color_b:Color = hold_breath_ball_color
	
	var path_color_a:Color = $Path.self_modulate
	var path_color_b:Color = hold_breath_path_color
	
	var flash_total := 120
	var flash_frames := 120
	
	var flash_active:bool
	
	const _auxiliary_functions := 8
	
	#parse aux data
	var _aux_data:Dictionary
	for i in _auxiliary_functions:
		_aux_data[i + 1] = []
	var marker_list = marker_data.keys()
	marker_list.sort()
	for marker_frame in marker_list:
		var auxiliary:int = marker_data[marker_frame][3]
		for i in _auxiliary_functions:
			if auxiliary & 1 << i:
				var index:int = marker_list.find(marker_frame)
				for marker in range(index, marker_list.size()):
					if not _aux_data[i + 1].has(index):
						if int(marker_data[marker_list[marker]][3]) & 1 << i:
							index = marker
							if not _aux_data[i + 1].has(index):
								_aux_data[i + 1].append(index)
						else:
							break
	var _empty_sections:Array
	for section in _aux_data:
		if _aux_data[section].is_empty():
			_empty_sections.append(section)
	for section in _empty_sections:
		_aux_data.erase(section)
	
	#sequence aux data
	var _aux_sequenced:Dictionary
	for section in _aux_data:
		var sequences:Array
		var current_sequence:Array
		var input_array = _aux_data[section]
		for i in input_array.size():
			if i == 0 or input_array[i] == input_array[i - 1] + 1:
				current_sequence.append(input_array[i])
			else:
				sequences.append(current_sequence)
				current_sequence = [input_array[i]]
		if current_sequence.size() > 0:
			sequences.append(current_sequence)
		_aux_sequenced[section] = sequences
	
	#format aux data
	var aux_effects:Dictionary
	for section in _aux_sequenced:
		aux_effects[section] = {}
		for sequence in _aux_sequenced[section]:
			var marker_keys = 1
			var start_frame = marker_list[sequence[0]]
			var end_frame = marker_list[sequence[-1]]
			aux_effects[section][start_frame] = end_frame - start_frame
	
	if %AudioStreamPlayer.playing:
		%AudioStreamPlayer.stop()
	
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_position(Vector2(0, 200))
	DisplayServer.window_set_flag(resize_disabled, true)
	DisplayServer.window_set_flag(borderless, true)
	DisplayServer.window_set_size(Vector2(x_size, y_size))
	get_viewport().set_transparent_background(true)
	await get_tree().process_frame
	await get_tree().process_frame
	update_display()
	disconnect("resized", update_display)
	
	input_disabled = true
	set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	
	DirAccess.open("user://Renders").make_dir(track_name)
	DirAccess.open("user://Renders/" + track_name + "/").make_dir(folder_name)
	var path_string = "user://Renders/%s/%s/%s.png"
	
	var offset = 10
	
	toggle_ball_visible(true)
	var path_origin := Vector2(get_rect().size.x, $Ball.position.y)
	
	$Path.position.x = offset
	$Path.clear_points()
	
	$Path.gradient.offsets[1] = 0.5
	$TrackSliderLarge.hide()
	
	$Header/MenuButton.hide()
	
	var _distance_adjust:int
	match int(path_speed):
		7:
			_distance_adjust = -1
		4:
			_distance_adjust = 1
		3:
			_distance_adjust = 2
		2:
			_distance_adjust = 3
		1:
			_distance_adjust = 9
	var _ball_distance = path_origin.x - $Ball.position.x
	var distance = ceil(_ball_distance / path_speed) + _distance_adjust
	
	var _cutoff_adjust:int
	match int(path_speed):
		10:
			_cutoff_adjust = -8
		9, 8:
			_cutoff_adjust = -7
		7, 6, 5:
			_cutoff_adjust = -6
		4:
			_cutoff_adjust = -5
		3:
			_cutoff_adjust = -3
		2:
			_cutoff_adjust = 0
		1:
			_cutoff_adjust = 8
	var _path_distance = x_size + (offset * path_speed)
	var cutoff = floor(_path_distance / path_speed) + _cutoff_adjust
	
	place_ball(path[starting_frame])
	path_origin.y = $Ball.position.y
	
	step = 0
	
	while $Path.get_point_count() < cutoff:
		$Path.add_point(Vector2(path_origin.x + step, path_origin.y))
		$Path.position.x -= 1 * path_speed
		step += 1 * path_speed
	
	$Path.show()
	$Markers.hide()
	$MarkersMenu.hide()
	
	for point in range(starting_frame, ending_frame + cutoff):
		print("SAVING: ",point," / ", (ending_frame + cutoff) - starting_frame)
		if point+1 < path.size() and path[point+1] > -1:
			path_origin.y = BOTTOM + path[point+1] * (TOP - BOTTOM)
		if point - distance < path.size() and point > distance:
			if path[point-distance] > -1 and point-distance >= starting_frame:
				var render_pos = BOTTOM + path[point-distance] * (TOP - BOTTOM)
				$Ball.position.y = render_pos
				line_colors(point - distance)
		for effect in aux_effects:
			for trigger in aux_effects[effect]:
				if point - distance == int(trigger):
					match int(effect):
						Effects.HOLD_BREATH:
							var length = aux_effects[effect][trigger]
							var required_length = flash_total * 2
							if length >= required_length:
								active_effects[Effects.HOLD_BREATH] = length
							else:
								var err = "effect must last at least %s frames"
								print(err%required_length)
		for effect in active_effects:
			match effect:
				Effects.HOLD_BREATH:
					var effect_time = active_effects[effect]
					var total_time:int = flash_frames
					if effect_time > flash_total:
						if flash_frames > 0:
							var count = 1 - flash_frames / float(flash_total)
							var s1 = flash_curve.sample(count)
							var s2 = path_flash_curve.sample(count)
							var ball_blend = ball_color_a.lerp(ball_color_b, s1)
							var path_blend = path_color_a.lerp(path_color_b, s2)
							$Ball.self_modulate = ball_blend
							$Path.self_modulate = path_blend
							flash_frames -= 1
					elif effect_time <= flash_total:
						var count = 1 - effect_time / float(flash_total)
						var s1 = flash_curve.sample(count)
						var s2 = path_flash_curve.sample(count)
						var ball_blend = ball_color_b.lerp(ball_color_a, s1)
						var path_blend = path_color_b.lerp(path_color_a, s2)
						$Ball.self_modulate = ball_blend
						$Path.self_modulate = path_blend
					if effect_time > 0:
						active_effects[effect] -= 1
					elif effect_time == 0:
						flash_frames = flash_total
						active_effects.erase(effect)
			
		await get_tree().process_frame
		await get_tree().process_frame
		$Path.add_point(Vector2(path_origin.x + step, path_origin.y))
		$Path.position.x -= 1 * path_speed
		step += 1 * path_speed
		while $Path.get_point_count() > cutoff:
			$Path.remove_point(0)
		var image = get_viewport().get_texture().get_image()
		image.save_png(path_string % [track_name, folder_name, point])
	
	get_viewport().set_transparent_background(false)
	$Path.gradient.offsets[1] = 1
	$Header/MenuButton.show()
	$TrackSliderLarge.show()
	$Path.hide()
	$Markers.show()
	$MarkersMenu.show()
	
	set_physics_process(true)
	DisplayServer.window_set_flag(resize_disabled, false)
	connect("resized", update_display)
	
	DisplayServer.window_set_flag(borderless, false)
	DisplayServer.window_set_mode(window_starting_mode)
	DisplayServer.window_set_size(window_starting_size)
	DisplayServer.window_set_position(window_starting_pos)
	update_display()
	input_disabled = false
	await get_tree().process_frame
	await get_tree().process_frame
	%Controls.scrub(0)
	
	$RenderComplete.track_name = track_name
	$RenderComplete.folder_name = folder_name
	$RenderComplete.popup_centered()


func connect_sliders_signal():
	for slider in [$Menu/Controls/TrackSlider, $TrackSliderLarge]:
		if not slider.is_connected("value_changed", %Controls.scrub):
			slider.connect("value_changed", %Controls.scrub)


func update_display() -> void:
	var center:Vector2 = get_viewport_rect().size / 2
	var line_offset:Vector2
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED:
		line_offset = Vector2(21, 15)
	else:
		line_offset = Vector2(20, 16)
	$TopLine.position.y = center.y - (path_area / 2)
	$BottomLine.position.y = center.y + (path_area / 2)
	$TopLine.set_end(Vector2(get_end().x, $TopLine.get_end().y))
	$BottomLine.set_end(Vector2(get_end().x, $BottomLine.get_end().y))
	$Ball.position.x = center.x
	$Ball.position.y = center.y
	TOP = $TopLine.position.y
	BOTTOM = $BottomLine.position.y
	$TopLine.position.y -= line_offset.x
	$BottomLine.position.y += line_offset.y
	$Backdrop.set_begin($TopLine.get_begin())
	$Backdrop.set_end($BottomLine.get_end())
	for marker in $Markers.marker_list.values():
		var orig_pos = marker.position.y
		var render_pos = BOTTOM + marker.get_meta('depth') * (TOP - BOTTOM)
		var position_difference = render_pos - orig_pos
		marker.position.y = render_pos
		if marker.has_meta('line') and marker.get_meta('line'):
			marker.get_meta('line').position.y += position_difference
	await get_tree().process_frame
	$Markers.position_markers()
	if not path.is_empty() and sign(path[frame+1]) > -1:
		place_ball(path[frame+1])
	else:
		place_ball(0)
