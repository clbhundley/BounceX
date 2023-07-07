extends Control

var marker_list:Dictionary
var selected_marker:Node

@onready var menu = owner.get_node('MarkersMenu/HBox')
@onready var frame_input = menu.get_node('Frame/Input')
@onready var depth_input = menu.get_node('Depth/Input')

@onready var ease_input = menu.get_node('Ease')
@onready var ease_up_input = menu.get_node('EaseUp')
@onready var ease_down_input = menu.get_node('EaseDown')

@onready var delete_button = menu.get_node('Delete')

func set_markers():
	for node in marker_list.values():
		node.queue_free()
	marker_list.clear()
	var marker_data = owner.marker_data
	for frame in marker_data.keys():
		add_marker(
			frame,
			marker_data[frame][0],
			marker_data[frame][1],
			marker_data[frame][2])
		connect_marker(frame)

func add_marker(frame, depth, trans=null, ease=null):
	var marker = $Marker.duplicate()
	marker.show()
	for node in marker_list.values():
		if node.get_meta('frame') == frame:
			node.queue_free()
	var index = get_marker_index(frame)
	if trans == null:
		trans = owner.get_node('MarkersMenu/HBox/Trans').selected
	if ease == null:
		ease = owner.get_ease_direction(depth)
	marker_list[frame] = marker
	var marker_button = marker.get_node('Button')
	marker_button.toggled.connect(marker_toggled.bind(marker))
	marker_button.gui_input.connect(_on_marker_gui_input.bind(marker))
	var render_pos = owner.BOTTOM + depth * (owner.TOP - owner.BOTTOM)
	marker.set_meta('frame', frame)
	marker.set_meta('depth', depth)
	marker.set_meta('trans', trans)
	marker.set_meta('ease', ease)
	marker.position.y = render_pos
	marker.position.x = frame * owner.path_speed
	add_child(marker)

var mouse_movement:Vector2
func _on_marker_gui_input(event, input_marker):
	if owner.play_button.button_pressed:
		return
	if not selected_marker or input_marker != selected_marker:
		return
	if 'relative' in event:
		if event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_LEFT:
				depth_input.value -= event.relative.y / 200
				if marker_list.values().front():
					if selected_marker != marker_list.values().front():
						frame_input.value += event.relative.x / 5
				mouse_movement += event.relative
	elif event.pressed == false and not mouse_over_marker:
		mouse_movement = Vector2(0,0)

func marker_toggled(button_pressed:bool, marker:Node):
	if owner.play_button.button_pressed:
		if not owner.record_button.button_pressed:
			return
	if mouse_movement != Vector2(0,0):
		mouse_movement = Vector2(0,0)
		return
	if button_pressed:
		for node in marker_list.values():
			if node != marker:
				node.get_node('Button').set_pressed_no_signal(false)
				node.get_node('Button/Selected').hide()
		marker.get_node('Button/Selected').show()
		ease_input.show()
		ease_up_input.hide()
		ease_down_input.hide()
		
		var frame = marker.get_meta('frame')
		var index:int = get_marker_index(frame)
		
		if index != 0:
			delete_button.show()
		else:
			delete_button.hide()
		
		selected_marker = marker
		
		var min_distance:int = 5
		
		frame_input.value_changed.disconnect(_on_frame_value_changed)
		if index != 0:
			frame_input.editable = true
			var previous = get_previous_frame(frame)
			var min = marker_list[previous].get_meta('frame') + min_distance
			frame_input.min_value = min
		else:
			frame_input.editable = false
			frame_input.min_value = 0
		if index < marker_list.size() - 1:
			var next = get_next_frame(frame)
			var max = marker_list[next].get_meta('frame') - min_distance
			frame_input.max_value = max
		else:
			frame_input.max_value = owner.path.size() - 1
		
		frame_input.value = frame
		frame_input.value_changed.connect(_on_frame_value_changed)
		
		depth_input.value_changed.disconnect(_on_depth_value_changed)
		depth_input.value = marker.get_meta('depth')
		depth_input.value_changed.connect(_on_depth_value_changed)
		
		menu.get_node('Trans').select(marker.get_meta('trans'))
		menu.get_node('Ease').select(marker.get_meta('ease'))
	else:
		frame_input.value_changed.disconnect(_on_frame_value_changed)
		depth_input.value_changed.disconnect(_on_depth_value_changed)
		frame_input.value = owner.frame
		depth_input.value = owner.ball_percentage()
		frame_input.value_changed.connect(_on_frame_value_changed)
		depth_input.value_changed.connect(_on_depth_value_changed)
		marker.get_node('Button/Selected').hide()
		ease_input.hide()
		ease_up_input.show()
		ease_down_input.show()
		delete_button.hide()
		selected_marker = null

func marker_percentage(marker) -> float:
	return abs((marker.position.y - owner.BOTTOM) / (owner.TOP - owner.BOTTOM))

func get_marker_index(frame:int) -> int:
	var keys = marker_list.keys()
	keys.sort()
	return keys.find(frame)

func get_previous_frame(frame:int) -> int:
	var keys = marker_list.keys()
	keys.sort()
	var index = keys.find(frame)
	if index - 1 > 0:
		return keys[index - 1]
	else:
		return 0

func get_next_frame(frame:int) -> int:
	var keys = marker_list.keys()
	keys.sort()
	var index = keys.find(frame)
	if index + 1 < marker_list.size():
		return keys[index + 1]
	else:
		return 0

func connect_marker(frame:int) -> void:
	if frame == 0:
		return
	var index = get_marker_index(frame)
	if index == -1:
		return
	var previous_frame = get_previous_frame(frame)
	var marker:Node = marker_list[frame]
	var previous:Node = marker_list[previous_frame]
	var starting_position = previous.position
	for line in get_tree().get_nodes_in_group('lines'):
		if line.get_meta('index') == index:
			line.queue_free()
	var line = $Line.duplicate()
	line.add_to_group('lines')
	line.set_meta('index', index)
	add_child(line)
	var tween = get_tree().create_tween()
	tween.set_trans(marker.get_meta('trans'))
	tween.set_ease(marker.get_meta('ease'))
	var steps = marker.get_meta('frame') - previous.get_meta('frame')
	tween.tween_property(previous, 'position:y', marker.position.y, steps)
	tween.pause()
	line.clear_points()
	var line_frame = previous.get_meta('frame')
	for i in steps + 1:
		owner.path[line_frame] = marker_percentage(previous)
		line.add_point(previous.position)
		tween.custom_step(1)
		previous.position.x += owner.path_speed
		line_frame += 1
	previous.position = starting_position

func connect_all_markers():
	for marker in marker_list.keys():
		connect_marker(marker)

func clear_ahead(frame:int):
	var start_frame = get_previous_frame(frame)
	var end_frame = get_next_frame(frame)
	if end_frame == 0:
		end_frame = owner.path.size()
	for i in range(start_frame, end_frame):
		owner.path[i] = -1

func place_ball_on_path():
	var path_value = owner.path[owner.frame]
	if path_value > -1:
		owner.place_ball(path_value)

func position_markers():
	var center:Vector2 = get_viewport_rect().size / 2
	position.x = center.x - (owner.frame * owner.path_speed)

func _on_frame_value_changed(value:int):
	if not selected_marker:
		return
	var marker = selected_marker
	var current_frame = marker.get_meta('frame')
	marker.position.x = value * owner.path_speed
	marker.set_meta('frame', value)
	var orig_frame = owner.marker_data[current_frame].duplicate()
	owner.marker_data.erase(current_frame)
	owner.marker_data[value] = orig_frame
	marker_list.erase(current_frame)
	marker_list[value] = marker
	clear_ahead(value)
	connect_marker(value)
	connect_marker(get_next_frame(value))
	place_ball_on_path()

func _on_depth_value_changed(value):
	if not selected_marker:
		return
	var marker = selected_marker
	var marker_frame:int = selected_marker.get_meta('frame')
	marker.position.y = owner.BOTTOM + value * (owner.TOP - owner.BOTTOM)
	marker.set_meta('depth', value)
	owner.marker_data[marker_frame][0] = value
	connect_marker(marker_frame)
	connect_marker(get_next_frame(marker_frame))
	place_ball_on_path()
	Data.save_path()

func _on_trans_selected(index):
	Data.set_config('easings', 'trans', index)
	if not selected_marker:
		return
	selected_marker.set_meta('trans', index)
	var frame = selected_marker.get_meta('frame')
	owner.marker_data[frame][1] = index
	connect_marker(frame)
	place_ball_on_path()
	Data.save_path()

func _on_easing_selected(index):
	if not selected_marker:
		return
	selected_marker.set_meta('ease', index)
	var frame = selected_marker.get_meta('frame')
	owner.marker_data[frame][2] = index
	connect_marker(frame)
	place_ball_on_path()
	Data.save_path()

func _on_up_easing_selected(index):
	Data.set_config('easings', 'up', index)

func _on_down_easing_selected(index):
	Data.set_config('easings', 'down', index)

func _on_delete_pressed():
	var frame:int = selected_marker.get_meta('frame')
	clear_ahead(frame)
	marker_list.erase(frame)
	owner.marker_data.erase(frame)
	selected_marker.queue_free()
	selected_marker = null
	for line in get_tree().get_nodes_in_group('lines'):
		line.queue_free()
	connect_all_markers()
	place_ball_on_path()
	Data.save_path()
	_on_delete_mouse_exited()
	delete_button.hide()

func _on_delete_mouse_entered():
	delete_button.self_modulate = 'ff7474d7'

func _on_delete_mouse_exited():
	delete_button.self_modulate = Color.WHITE

var mouse_over_marker:bool
func _on_marker_mouse_entered():
	mouse_over_marker = true

func _on_marker_mouse_exited():
	mouse_over_marker = false

var mouse_over_input:bool
func _on_input_mouse_entered():
	mouse_over_input = true

func _on_input_mouse_exited():
	mouse_over_input = false

func input_focus_entered():
	owner.input_disabled = true

func input_focus_exited():
	owner.input_disabled = false

func _ready():
	var inputs = [frame_input.get_line_edit(), depth_input.get_line_edit()]
	for input in inputs:
		input.focus_entered.connect(input_focus_entered)
		input.focus_exited.connect(input_focus_exited)

func _input(event):
	if event.is_action_pressed('cancel') and selected_marker:
		selected_marker.get_node('Button').button_pressed = false
	if event.is_action_pressed('delete') and selected_marker:
		_on_delete_pressed()
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_mask & MOUSE_BUTTON_LEFT and not mouse_over_input:
			var i = [frame_input.get_line_edit(), depth_input.get_line_edit()]
			for node in i:
				node.release_focus()
