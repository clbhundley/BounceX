extends Control

var TOP:float
var BOTTOM:float

var top_color:Color = Color.WHITE
var top_color_active:Color = Color.AQUAMARINE

var bottom_color:Color = Color.WHITE
var bottom_color_active:Color = Color.CORAL

var hold_breath_ball_color:Color = Color.DEEP_PINK
var hold_breath_path_color:Color = Color.PINK

@onready var audio = $Menu/Controls/AudioStreamPlayer
@onready var track_slider = $Menu/Controls/TrackSlider
@onready var play_button = $Menu/Controls/TrackControls/Play
@onready var record_button = $Menu/Controls/Record

var path:PackedFloat32Array
var path_max_length:int
var path_speed:float
var path_area:int

var marker_data:Dictionary

var frame:int
var step:int

func _init():
	Data.bx = self

func _ready():
	Data.load_config()
	$Path.gradient.offsets[1] = 1
	$Path.width = $Menu/Options/PathThickness.value
	$Menu.self_modulate.a = 1.65
	update_display()

func _physics_process(delta):
	if play_button.button_pressed:
		if not audio.stream_paused:
			if frame+1 < path.size() - 1:
				if sign(path[frame+1]) > -1:
					place_ball(path[frame+1])
					toggle_path_visible(true)
				elif $Menu/Controls/Paths.is_anything_selected():
					if not record_button.button_pressed:
						toggle_path_visible(false)
				if not record_button.button_pressed:
					frame += 1
				if $Markers.is_visible_in_tree():
					$Markers.position.x -= path_speed
			else:
				play_button.button_pressed = false
				$Header/Play.hide()
				$Header/Record.hide()
	line_colors($Ball, frame)
	$Path.add_point(Vector2($Ball.position.x + step, $Ball.position.y))
	$Path.position.x -= 1 * path_speed
	step += 1 * path_speed
	if record_button.button_pressed:
		if frame < path.size() - 1:
			frame += 1
		else:
			record_button.button_pressed = false
	while $Path.get_point_count() > path_max_length:
		$Path.remove_point(0)

func line_colors(ball:Sprite2D, point:int) -> void:
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
	var frames = ceil(audio.stream.get_length() * 60)
	path.clear()
	for i in frames:
		path.append(-1)
	if set_ball_pos:
		place_ball(0)
		var ball_pos = clamp(($Ball.position.y - BOTTOM) / (TOP - BOTTOM), 0, 1)
		set_ball_depth(ball_pos)

func get_ball_depth() -> float:
	return abs(($Ball.position.y - BOTTOM) / (TOP - BOTTOM))

func place_ball(depth:float) -> void:
	$Ball.position.y = BOTTOM + depth * (TOP - BOTTOM)

func set_pos(y_pos) -> void:
	if not record_button.button_pressed:
		return
	var depth = clamp((y_pos - BOTTOM) / (TOP - BOTTOM), 0, 1)
	set_ball_depth(depth)

func get_ease_direction(depth) -> int:
	var ease:int
	if depth >= get_ball_depth():
		return $MarkersMenu/HBox/EaseUp.selected
	else:
		return $MarkersMenu/HBox/EaseDown.selected

func set_ball_depth(depth:float) -> void:
	var easing = get_ease_direction(depth)
	marker_data[frame] = [depth, $MarkersMenu/HBox/Trans.selected, easing, 0]
	$Markers.add_marker(frame, depth)
	$Markers.connect_marker(frame)
	if record_button.button_pressed and $Header/MenuButton.button_pressed:
		$Header/MenuButton.button_pressed = false
	place_ball(depth)

func _on_gui_input(event):
	if not record_button.button_pressed:
		if audio.stream and event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_LEFT:
				connect_sliders_signal()
				var min = $TrackSliderLarge.min_value
				var max = $TrackSliderLarge.max_value
				var value = $TrackSliderLarge.value - event.relative.x * 0.00005
				$TrackSliderLarge.value = clamp(value, min, max)
	elif event is InputEventMouseButton and event.is_pressed():
		if event.button_mask & MOUSE_BUTTON_LEFT:
			set_pos(event.position.y)

var input_disabled:bool
func _input(event):
	if input_disabled:
		return
	elif event.is_action_pressed("record") and audio.stream:
		if record_button.button_pressed:
			record_button.button_pressed = false
		else:
			record_button.button_pressed = true
	elif event.is_action_pressed("cancel"):
		if record_button.button_pressed:
			record_button.set_pressed_no_signal(false)
			$Header/Record.hide()
		play_button.button_pressed = false
	elif event.is_action_pressed("play") and audio.stream:
		if record_button.button_pressed:
			record_button.button_pressed = false
		elif play_button.button_pressed:
			play_button.button_pressed = false
		else:
			play_button.button_pressed = true
	elif event.is_action_pressed("restart"):
		if audio.has_stream_playback():
			$Menu/Controls.scrub(0)
	elif event.is_action_pressed("render") and not play_button.button_pressed:
		if not $Menu/Controls/Render.disabled:
			_on_render_pressed()
	elif event.is_action_pressed("menu"):
		$Header/MenuButton.button_pressed = !$Header/MenuButton.button_pressed
	for position_number in 11:
		if event.is_action_pressed('p' + str(position_number)):
			position_input(int(str(position_number).lstrip('p')))
	for ease_number in 8:
		if event.is_action_pressed('e' + str(ease_number)):
			easing_input(int(str(ease_number).lstrip('e')))
	for trans_number in 11:
		if event.is_action_pressed('t' + str(trans_number)):
			trans_input(trans_number)

func position_input(input:int):
	if record_button.button_pressed:
		set_ball_depth(float(input) / 10)
	elif $Markers.selected_marker:
		$MarkersMenu/HBox/Depth/Input.value = float(input) / 10
	else:
		place_ball(float(input) / 10)

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

func trans_input(input:int):
	$MarkersMenu/HBox/Trans.select(input)
	$MarkersMenu/HBox/Trans.emit_signal('item_selected', input)

func _on_record_toggled(active:bool):
	if active:
		$Menu/Controls/TrackControls/Play.button_pressed = true
		$Header/Play.hide()
		$Header/Record.show()
		var marker_node = $Markers.selected_marker
		if marker_node and is_instance_valid(marker_node):
			marker_node.get_node('Button').button_pressed = false
			$Markers.marker_toggled(false, marker_node)
		toggle_path_visible(true)
		if $Markers.marker_list.size() == 1:
			var depth = $Markers.marker_list[0].get_meta('depth')
			path[frame] = depth
			place_ball(depth)
	else:
		$Menu/Controls/TrackControls/Pause.button_pressed = true
		$Header/Record.hide()
		var track_list = $Menu/Controls/TrackSelection
		var track_title = track_list.get_item_text(track_list.selected)
		var path_name:String = Data.timestamp()
		Data.save_path('user://Paths/' + track_title + "/" + path_name + ".bx")
		$Menu/Controls.load_paths(track_title)
		var paths = $Menu/Controls/Paths
		if not paths.is_anything_selected():
			for i in paths.item_count:
				if paths.get_item_text(i) == path_name:
					paths.select(i)
					$Menu/Controls._on_path_selected(i)

func _on_play_toggled(button_pressed):
	if button_pressed:
		if audio.stream_paused:
			audio.stream_paused = false
		else:
			audio.play()
		$Menu/Controls/TrackControls/Play.button_pressed = true
		toggle_path_visible(true)
		$Header/Play.show()
		if $Markers.is_visible_in_tree():
			$Ball.show()
			$Markers.position_markers()
	else:
		if record_button.button_pressed:
			record_button.button_pressed = false
		$Menu/Controls/TrackControls/Pause.button_pressed = true
		$Markers.connect_all_markers()
		$Header/Play.hide()
		if $Markers.is_visible_in_tree():
			$Path.hide()

func _on_render_pressed():
	$Header/MenuButton.button_pressed = false
	await get_tree().create_timer(0.5).timeout
	render()

func toggle_path_visible(active:bool) -> void:
	for node in [$Ball, $Path]:
		node.self_modulate.a = max(float(active),0.3)

enum Effects {
	HOLD_BREATH = 1}
var active_effects:Dictionary
@export var flash_curve:Curve
func render():
	var selected_take = $Menu/Controls/Paths.get_selected_items()[0]
	var path_name = $Menu/Controls/Paths.get_item_text(selected_take)
	var selected_track = $Menu/Controls/TrackSelection.selected
	var track_name = $Menu/Controls/TrackSelection.get_item_text(selected_track)
	var x_size = $Menu/Options/RenderResolution/Values/X.value
	var y_size = $Menu/Options/RenderResolution/Values/Y.value
	var window_starting_mode = DisplayServer.window_get_mode()
	var window_starting_size = DisplayServer.window_get_size()
	var window_starting_pos = DisplayServer.window_get_position()
	var resize_disabled = DisplayServer.WINDOW_FLAG_RESIZE_DISABLED
	var borderless = DisplayServer.WINDOW_FLAG_BORDERLESS
	var folder_name = path_name.trim_suffix('.bin')

	var ball_color_a:Color = Color.WHITE
	var ball_color_b:Color = hold_breath_ball_color
	var line_color_a:Color = Color.WHITE
	var line_color_b:Color = hold_breath_path_color
	var flash_total := 120
	var flash_frames := 120
	var flash_active:bool
	
	const _auxiliary_functions := 8
	
	#parse aux data
	var _aux_data:Dictionary
	for i in _auxiliary_functions:
		_aux_data[i + 1] = []
	for marker_frame in marker_data:
		var auxiliary:int = marker_data[marker_frame][3]
		for i in _auxiliary_functions:
			if auxiliary & 1 << i:
				var marker_list = marker_data.keys()
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
			var start_frame = marker_data.keys()[sequence[0]]
			var end_frame = marker_data.keys()[sequence[-1]]
			aux_effects[section][start_frame] = end_frame - start_frame
	
	print("!=----- ",aux_effects)
	if audio.playing:
		audio.stop()
	
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
	var render_ball = $Ball.duplicate()
	add_child(render_ball)
	
	$Ball.position.x = get_rect().size.x
	$Path.position.x = offset
	$Path.clear_points()
	$Ball.hide()
	
	$Path.gradient.offsets[1] = 0.5
	$TrackSliderLarge.hide()
	
	$Header/MenuButton.hide()
	
	var distance_adjust:int #f it im over it
	match int(path_speed):
		7:
			distance_adjust = -1
		4:
			distance_adjust = 1
		3:
			distance_adjust = 2
		2:
			distance_adjust = 3
		1:
			distance_adjust = 9
	var ball_distance = $Ball.position.x - render_ball.position.x
	var distance = ceil(ball_distance / path_speed) + distance_adjust
	
	var cutoff_adjust:int
	match int(path_speed):
		10:
			cutoff_adjust = -8
		9, 8:
			cutoff_adjust = -7
		7, 6, 5:
			cutoff_adjust = -6
		4:
			cutoff_adjust = -5
		3:
			cutoff_adjust = -3
		2:
			cutoff_adjust = 0
		1:
			cutoff_adjust = 8
	var path_distance = x_size + (offset * path_speed)
	var cutoff = floor(path_distance / path_speed) + cutoff_adjust
	
	place_ball(path[0])
	render_ball.position.y = $Ball.position.y
	
	step = 0
	
	while $Path.get_point_count() < cutoff:
		$Path.add_point(Vector2($Ball.position.x + step, $Ball.position.y))
		$Path.position.x -= 1 * path_speed
		step += 1 * path_speed
	
	$Path.show()
	$Markers.hide()
	$MarkersMenu.hide()
	
	var total_frames:int = path.size() + cutoff
	for point in total_frames:
		print("SAVING: ",point," / ", total_frames)
		if point+1 < path.size() and path[point+1] > -1:
			place_ball(path[point+1])
		if point - distance < path.size() and point > distance:
			if path[point-distance] > -1:
				var render_pos = BOTTOM + path[point-distance] * (TOP - BOTTOM)
				render_ball.position.y = render_pos
				line_colors(render_ball, point-distance)
		for effect in aux_effects:
			for trigger in aux_effects[effect]:
				if point - distance == int(trigger):
					match int(effect):
						Effects.HOLD_BREATH:
							var effect_length = aux_effects[effect][trigger]
							if effect_length > flash_frames * 2:
								active_effects[1] = effect_length
							else:
								print("effect must last at least 240 frames")
		for effect in active_effects:
			match effect:
				Effects.HOLD_BREATH:
					var effect_time = active_effects[effect]
					var total_time:int = flash_frames
					if effect_time > flash_total:
						if flash_frames > 0:
							var count = 1 - flash_frames / float(flash_total)
							var sample = flash_curve.sample(count)
							var blend = ball_color_a.lerp(ball_color_b, sample)
							render_ball.self_modulate = blend
							flash_frames -= 1
						elif flash_frames == 0:
							$Path.self_modulate = line_color_b
					elif effect_time <= flash_total:
						var count = 1 - effect_time / float(flash_total)
						var sample = flash_curve.sample(count)
						var blend = ball_color_b.lerp(ball_color_a,sample)
						render_ball.self_modulate = blend
					if effect_time > 0:
						active_effects[effect] -= 1
					elif effect_time == 0:
						$Path.self_modulate = line_color_a
						flash_frames = flash_total
						active_effects.erase(effect)
			
		await get_tree().process_frame
		await get_tree().process_frame
		$Path.add_point(Vector2($Ball.position.x + step, $Ball.position.y))
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
	$Ball.show()
	$Path.hide()
	$Markers.show()
	$MarkersMenu.show()
	
	set_physics_process(true)
	remove_child(render_ball)
	render_ball.queue_free()
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
	$Menu/Controls.scrub(0)
	
	$RenderComplete.track_name = track_name
	$RenderComplete.folder_name = folder_name
	$RenderComplete.popup_centered()

func connect_sliders_signal():
	for slider in [$Menu/Controls/TrackSlider, $TrackSliderLarge]:
		if not slider.is_connected("value_changed", $Menu/Controls.scrub):
			slider.connect("value_changed", $Menu/Controls.scrub)

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
		var render_pos = BOTTOM + marker.get_meta('depth') * (TOP - BOTTOM)
		marker.position.y = render_pos
	$Markers.connect_all_markers()
	await get_tree().process_frame
	$Markers.position_markers()
	if not path.is_empty():
		place_ball(frame)
