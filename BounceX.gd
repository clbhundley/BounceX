extends Control

var TOP:float
var BOTTOM:float

var top_color:Color = Color.WHITE
var top_color_active:Color = Color.AQUAMARINE

var bottom_color:Color = Color.WHITE
var bottom_color_active:Color = Color.CORAL

@onready var audio = $Menu/Controls/AudioStreamPlayer
@onready var track_slider = $Menu/Controls/TrackSlider
@onready var play_button = $Menu/Controls/TrackControls/Play
@onready var record_button = $Menu/Controls/Record
@onready var edit_button = $Menu/Controls/Edit

var path_max_length:int
var path_area:int
var path_speed:float
var path:PackedFloat32Array
var frame:int
var step:int

var speed:float

var mouse_pos:float

func _ready():
	Data.load_config()
	$Path.gradient.offsets[1] = 1
	$Path.width = $Menu/Options/PathThickness.value
	$Menu.self_modulate.a = 1.65
	update_display()

func _physics_process(delta):
	if play_button.button_pressed:
		if not audio.stream_paused and not record_button.button_pressed:
			if frame < path.size() - 1:
				if sign(path[frame]) > -1:
					place_ball(path[frame])
					mouse_pos = $Ball.position.y
					$Circle.position.y = $Ball.position.y
					toggle_path_visible(true)
				elif $Menu/Controls/Paths.is_anything_selected():
					toggle_path_visible(false)
				if not record_button.button_pressed:
					frame += 1
			else:
				play_button.button_pressed = false
				$Header/Play.hide()
				$Header/Edit.hide()
				$Header/Record.hide()

	$Circle.position.y += (mouse_pos - $Circle.position.y) * speed*delta
	$Ball.position.y = clamp($Circle.position.y, TOP, BOTTOM)
	
	line_colors($Ball)
	
	$Path.add_point(Vector2($Ball.position.x + step, $Ball.position.y))
	$Path.position.x -= 1 * path_speed
	
	step += 1 * path_speed
	
	if record_button.button_pressed:
		if frame < path.size() - 1:
			path[frame] = ball_percentage()
			frame += 1
		else:
			record_button.button_pressed = false
	
	while $Path.get_point_count() > path_max_length:
		$Path.remove_point(0)

func line_colors(ball:Sprite2D) -> void:
	if ball.position.y == TOP:
		$TopLine.self_modulate = top_color_active
	else:
		$TopLine.self_modulate = top_color

	if ball.position.y == BOTTOM:
		$BottomLine.self_modulate = bottom_color_active
	else:
		$BottomLine.self_modulate = bottom_color

func define_path():
	var frames = ceil($Menu/Controls/AudioStreamPlayer.stream.get_length() * 60)
	for i in frames:
		path.append(-1)

func ball_percentage() -> float:
	var line_diff = TOP - BOTTOM
	return abs(($Ball.position.y - BOTTOM) / line_diff)

func place_ball(ball_percentage) -> void:
	var line_diff = TOP - BOTTOM
	$Ball.position.y = BOTTOM + ball_percentage * line_diff

func set_pos(y_pos) -> void:
	if edit_button.button_pressed:
		toggle_path_visible(true)
		$Menu/Controls/Record.button_pressed = true
		$Header/Edit.hide()
	mouse_pos = y_pos
	if $Header/MenuButton.button_pressed:
		if not $Header/OptionsButton.button_pressed:
			$Header/MenuButton.button_pressed = false

func _on_gui_input(event):
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_mask & MOUSE_BUTTON_LEFT:
			set_pos(event.position.y)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_LEFT:
			set_pos(event.position.y)

var input_disabled:bool
func _input(event):
	if input_disabled:
		return
	elif event.is_action("ui_left") and event.is_pressed():
		$Speed.value -= $Speed.step
	elif event.is_action("ui_right") and event.is_pressed():
		$Speed.value += $Speed.step
	elif event.is_action_pressed("record"):
		if record_button.button_pressed:
			record_button.button_pressed = false
		else:
			record_button.button_pressed = true
	elif event.is_action_pressed("cancel"):
		if record_button.button_pressed:
			record_button.set_pressed_no_signal(false)
			$Header/Record.hide()
		if edit_button.button_pressed:
			edit_button.set_pressed_no_signal(false)
			$Header/Edit.hide()
		play_button.button_pressed = false
	elif event.is_action_pressed("play"):
		if record_button.button_pressed:
			record_button.button_pressed = false
		elif play_button.button_pressed:
			play_button.button_pressed = false
		else:
			play_button.button_pressed = true
	elif event.is_action_pressed("restart"):
		if $Menu/Controls/AudioStreamPlayer.has_stream_playback():
			$Menu/Controls.scrub(0)
	elif event.is_action_pressed("edit"):
		if not edit_button.disabled:
			if record_button.button_pressed:
				edit_button.button_pressed = false
			elif edit_button.button_pressed:
				edit_button.button_pressed = false
			else:
				edit_button.button_pressed = true
	elif event.is_action_pressed("render"):
		if not $Menu/Controls/Render.disabled:
			_on_render_pressed()
	elif event.is_action_pressed("menu"):
		$Header/MenuButton.button_pressed = !$Header/MenuButton.button_pressed

func _on_record_toggled(active:bool):
	if active:
		$Menu/Controls/TrackControls/Play.button_pressed = true
		$Header/Play.hide()
		$Header/Record.show()
		toggle_path_visible(true)
	else:
		$Menu/Controls/TrackControls/Pause.button_pressed = true
		edit_button.button_pressed = false
		$Header/Record.hide()
		var track_list = $Menu/Controls/TrackSelection
		var track_title = track_list.get_item_text(track_list.selected)
		var path_name:String = Data.timestamp() + ".bin"
		Data.save_path('user://Paths/' + track_title + "/" + path_name)
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
	else:
		if record_button.button_pressed:
			record_button.button_pressed = false
		$Menu/Controls/TrackControls/Pause.button_pressed = true
		$Header/Play.hide()

func _on_edit_toggled(button_pressed):
	if edit_button.button_pressed:
		$Menu/Controls/TrackControls/Play.button_pressed = true
		$Header/Play.hide()
		$Header/Edit.show()
	else:
		$Header/Edit.hide()

func _on_render_pressed():
	$Header/MenuButton.button_pressed = false
	await get_tree().create_timer(0.5).timeout
	render()

func _on_speed_value_changed(value):
	$Speed/Label.text = "Speed: " + str(value)
	Data.set_config('user', 'speed', value)
	speed = value

func toggle_path_visible(active:bool) -> void:
	for node in [$Ball, $Circle, $Path]:
		node.self_modulate.a = max(float(active),0.3)

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
	var folder_name = path_name.trim_suffix('.bin')
	
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	update_display()
	DisplayServer.window_set_position(Vector2(0, 200))
	DisplayServer.window_set_size(Vector2(x_size, y_size))
	DisplayServer.window_set_flag(resize_disabled, true)
	get_viewport().set_transparent_background(true)
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
	$TrackSliderClone.hide()
	$Speed.hide()
	$Circle.hide()
	
	$Header/MenuButton.hide()
	
	var distance_adjust:int #f it im over it
	match int(path_speed):
		8, 7, 6, 4:
			distance_adjust = 1
		5, 3:
			distance_adjust = 2
		2:
			distance_adjust = 4
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
	
	var total_frames:int = path.size() + cutoff
	for point in total_frames:
		print("SAVING: ",point," / ", total_frames)
		if point < path.size() and path[point] > -1:
			place_ball(path[point])
		if point - distance < path.size() and point > distance:
			if path[point-distance] > -1:
				var render_pos = BOTTOM + path[point-distance] * (TOP - BOTTOM)
				render_ball.position.y = render_pos
		line_colors(render_ball)
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
	$TrackSliderClone.show()
	$Speed.show()
	$Circle.show()
	$Ball.show()
	
	set_physics_process(true)
	remove_child(render_ball)
	render_ball.queue_free()
	DisplayServer.window_set_flag(resize_disabled, false)
	connect("resized", update_display)
	
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
	$Circle.position.x = center.x
	$Circle.position.y = center.y
	$Ball.position.x = center.x
	$Ball.position.y = center.y
	mouse_pos = center.y
	TOP = $TopLine.position.y
	BOTTOM = $BottomLine.position.y
	$TopLine.position.y -= line_offset.x
	$BottomLine.position.y += line_offset.y
