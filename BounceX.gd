extends "res://Input.gd"

var recording_active:bool
var playback_active:bool
var preview_active:bool
var starting_values:Dictionary
var record_preview:Array
var record_preview_orig_size:int
var record_path:String
var record:Array

enum {UP,DOWN}
var direction

var line_flipped:bool

var bpm:float setget set_bpm
func set_bpm(value,update_display=true):
	bpm = value
	step = bpm/3600
	if update_display:
		$Header/BPM/SpinBox.get_line_edit().set_text(str(stepify(bpm,0.01)))

var step = bpm/3600

#toggle_breath timing seems to depend on cpu performance

var pause:bool

func _ready():
	load_config()
	get_tree().get_root().connect('size_changed',self,'resize')
	OS.set_window_size(Vector2(OS.get_screen_size().x,400))
	get_viewport().set_transparent_background(true)
	$Header/BPM/SpinBox.set_value(bpm)
	$Ball/Read.hide()
	set_tween()

var frame = 0
var lock_up:bool
var ball_pos_history:Array
var action_queue:Dictionary
func _process(delta):
	if pause:
		return
	ball_pos_history.append($Ball/Write.position.y)
	if ball_pos_history.size() >= 206:
		$Ball/Read.position.y = ball_pos_history.pop_front()
	
	var time = frame*step
	$Tween.seek(time)
	trace_line()
	
	for action in action_queue:
		if action is String and action == "_":
			if clamp(time,0,1) == 1 or clamp(time,0,1) == 0:
				for input in action_queue[action]:
					if time > 1:
						frame += 1
					parse_action(input)
				action_queue.erase(action)
		elif clamp(time,0,1) == action:
			for input in action_queue[action]:
				parse_action(input)
			action_queue.erase(action)
	
	var action:Array
	if Input.is_action_pressed("up"):
		if time >= 1:
			lock_up = true
		action.append("up")
		direction = UP
	else:
		lock_up = false
	if Input.is_action_pressed("cycle"):
		action.append("cycle")
		if time <= 0:
			direction = UP
	elif Input.is_action_pressed("slam_in"):
		action.append("slam_in")
		if time <= 0:
			direction = UP
			self.bpm *= 4
			action_queue = {1:["shift_left","shift_left","adjust_frame"]}
	elif Input.is_action_pressed("slam_out"):
		action.append("slam_out")
		if time <= 0:
			direction = UP
			action_queue = {
				1:["shift_right","shift_right"],
				0:["shift_left","shift_left"]}
	for input in pressed_inputs:
		if Input.is_action_just_pressed(input) and input != last_parsed:
			action.append(input)
	if recording_active:
		record.append(action)
	
	if playback_active:
		if not record.empty():
			var recorded_action = record.pop_front()
			for input in held_inputs:
				if recorded_action.has(input):
					Input.action_press(input)
				else:
					Input.action_release(input)
			for input in pressed_inputs:
				if recorded_action.has(input):
					parse_action(input)
			screen_capture()
		else:
			$Header.show()
			$Ball/Read.hide()
			$Ball/Write.position.x -= 150
			playback_active = false
			index = 0
			display_print("PLAYBACK CAPTURE COMPLETE")
			OS.set_borderless_window(false)
			OS.set_window_size(Vector2(OS.get_screen_size().x,400))
			yield(get_tree(),"idle_frame")
			$ExitPanel.popup_centered()
			OS.request_attention()
	
	if preview_active:
		if not record_preview.empty():
			var recorded_action = record_preview.pop_front()
			for input in held_inputs:
				if recorded_action.has(input):
					Input.action_press(input)
				else:
					Input.action_release(input)
			for input in pressed_inputs:
				if recorded_action.has(input):
					parse_action(input)
		else:
			$Ball/Read.hide()
			$Ball/Write.position.x -= 150
			preview_active = false
			display_print("PREVIEW COMPLETE")
			OS.set_window_size(Vector2(OS.get_screen_size().x,400))
	
	if lock_up:
		return
	match direction:
		UP:
			if time >= 1:
				direction = DOWN
				frame -= 1
			else:
				frame += 1
		DOWN:
			if time <= 0:
				direction = null
			else:
				frame -= 1

var last_parsed
func parse_action(input):
	var event = InputEventAction.new()
	event.action = input
	event.pressed = true
	last_parsed = input
	Input.parse_input_event(event)

var line_active:bool
const MAX_LINE_LENGTH = 1000
func trace_line():
	if line_active:
		$Line2D.add_point($Ball/Write.position)
		if $Line2D.get_point_count() > MAX_LINE_LENGTH:
			$Line2D.remove_point(0)
	for point in $Line2D.get_point_count():
		var pos = $Line2D.get_point_position(point)-Vector2(5,0)
		$Line2D.set_point_position(point,pos)

enum Transitions {
	TRANS_LINEAR
	TRANS_SINE
	TRANS_QUINT
	TRANS_QUART
	TRANS_QUAD
	TRANS_EXPO
	#TRANS_ELASTIC
	TRANS_CUBIC
	TRANS_CIRC
	#TRANS_BOUNCE 
	TRANS_BACK}
var transition = Transitions.TRANS_SINE setget set_transition
func set_transition(value):
	transition = posmod(value,Transitions.size())
	$Header/Display/Transition/Value.set_text(Transitions.keys()[transition])
	set_tween()

enum Easings {
	EASE_IN
	EASE_OUT
	EASE_IN_OUT
	EASE_OUT_IN}
var easing = Easings.EASE_IN_OUT setget set_easing
func set_easing(value):
	easing = posmod(value,Easings.size())
	$Header/Display/Easing/Value.set_text(Easings.keys()[easing])
	set_tween()

var limit = 1 setget set_limit
func set_limit(value):
	limit = value
	print("")
	print("Limit: ",limit)
	print("")
	set_tween()

var height := 1.0 setget set_height
func set_height(value):
	height = value
	$Header/Display/Height/Value.set_text(str(height))
	set_tween()

var depth := 0.0 setget set_depth
func set_depth(value):
	depth = value
	$Header/Display/Depth/Value.set_text(str(depth))
	set_tween()

var fix_height_flip_active:bool
func fix_height_flip(reset:=false):
	if fix_height_flip_active or reset:
		depth_base = 324
		height_base = 123
		fix_height_flip_active = false
	else:
		depth_base -= 1
		height_base += 1
		fix_height_flip_active = true

var depth_base:float = 324
var height_base:float = 123
func set_tween():
	$Tween.interpolate_property(
	$Ball/Write,
	'position:y',
	depth_base - (200*depth),
	height_base + (200*(1-height)),
	limit,
	transition,
	easing)

var index:int
func screen_capture():
	print("SAVING: ",record.size())
	var image = get_viewport().get_texture().get_data()
	image.flip_y()
	image.save_png("user://Captures/%s/%s.png"%[output_name,index])
	index += 1

var output_name
func set_output_name():
	var t = OS.get_datetime()
	for section in t:
		if str(t[section]).length() < 2:
			t[section] = "0"+str(t[section])
	var dt_format = "%s_%s_%s - %s.%s.%s"
	output_name = dt_format%[t.month,t.day,t.year,t.hour,t.minute,t.second]

func create_capture_dir():
	var dir = Directory.new()
	if not dir.dir_exists("user://Captures"):
		dir.make_dir("user://Captures")
	dir.open("user://Captures")
	set_output_name()
	dir.make_dir(output_name)

func save_record(overwrite:=false):
	var dir = Directory.new()
	if not dir.dir_exists("user://Records"):
		dir.make_dir("user://Records")
		dir.make_dir("user://Records/Active")
	set_output_name()
	var file = File.new()
	if overwrite:
		file.open(record_path,File.WRITE)
	else:
		file.open("user://Records/%s.json"%output_name,File.WRITE)
	var data = {
		'starting_values':starting_values,
		'record':record}
	file.store_line(JSON.print(data,"  "))
	file.close()
	if overwrite:
		display_print("MARKED")
	else:
		display_print("RECORD SAVED")

func load_record():
	var path = "user://Records/Active"
	var dir = Directory.new()
	var active_file
	dir.open(path)
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			active_file = path+"/"+file_name
		file_name = dir.get_next()
	if not active_file:
		display_print("NO ACTIVE RECORD")
		return
	else:
		record_path = active_file
		display_print("ACTIVE RECORD LOADED")
	record.clear()
	var file = File.new()
	file.open(active_file,File.READ)
	var data = file.get_as_text()
	var parsed_data = JSON.parse(data).result
	for property in parsed_data.starting_values:
		set(property,parsed_data.starting_values[property])
	starting_values = parsed_data.starting_values
	record = parsed_data.record

var config := ConfigFile.new()
func load_config():
	var path = 'user://config.cfg'
	if not config_is_valid(path):
		config = ConfigFile.new()
		config.set_value('General','baseline_bpm',120)
		config.set_value('General','no_numpad',false)
		config.save(path)
	if config.get_value('General','no_numpad'):
		$Menu/VBoxContainer/NoNumpad.set_pressed(true)
	var loaded_baseline_bpm = config.get_value('General','baseline_bpm')
	$Menu/VBoxContainer/BaselineBPM/SpinBox.value = loaded_baseline_bpm
	set_bpm(loaded_baseline_bpm)
	set_transition(1)
	set_easing(2)
	set_height(1)
	set_depth(0)

func config_is_valid(path) -> bool:
	if config.load(path) != OK:
		return false
	if not config.has_section('General'):
		return false
	for key in ['baseline_bpm','no_numpad']:
		if not key in config.get_section_keys('General'):
			return false
	for key in config.get_sections():
		if not key in ['General']:
			return false
	return true

var H1 = load("res://Fonts/Rubik-Light-H1.tres")
var H2 = load("res://Fonts/Rubik-Light-H2.tres")
func resize():
	if playback_active or preview_active:
		return
	var window_width = get_tree().get_root().get_size().x
	$Ball/Write.position.x = window_width - 72.5
	if window_width < 1500:
		$Header/Display.set('custom_constants/separation',25)
		for node in get_tree().get_nodes_in_group('ResizeText'):
			node.set("custom_fonts/font",H1)
	else:
		$Header/Display.set('custom_constants/separation',50)
		for node in get_tree().get_nodes_in_group('ResizeText'):
			node.set("custom_fonts/font",H2)

#func _notification(event):
#	if event == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
#		config.set_value('baseline','bpm',bpm)
#		config.save('user://config.cfg')

func display_print(text):
	var edges = floor(floor(float(text.length())/2)/2)*2
	var middle = text.length() - edges
	var line:String
	for i in edges/2:
		line += "-"
	for i in middle:
		line += "="
	for i in edges/2:
		line += "-"
	print("")
	print(line)
	print(text)
	print(line)
