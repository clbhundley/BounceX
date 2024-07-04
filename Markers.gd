extends Control

var marker_list:Dictionary
var selected_marker:Sprite2D
var selected_multi_markers:Array

var clipboard:Dictionary

var selecting_to_edge:bool

const SEPARATION_MIN := 5

@onready var frame_input = %MarkersMenu/HBox/Frame/Input
@onready var depth_input = %MarkersMenu/HBox/Depth/Input

func _ready():
	var inputs = [frame_input.get_line_edit(), depth_input.get_line_edit()]
	for input in inputs:
		input.focus_entered.connect(input_focus_entered)
		input.focus_exited.connect(input_focus_exited)


func _input(event):
	if event.is_action_pressed('copy'):
		_on_copy_pressed()
	if event.is_action_pressed('paste'):
		_on_paste_pressed()
	if event.is_action_pressed('delete'):
		_on_delete_pressed()
	if event.is_action_pressed('insert'):
		_on_add_marker_pressed()
	if event.is_action_pressed('select_to_start') and not owner.shift_pressed:
		select_to(1)
	if event.is_action_pressed('select_to_end') and not owner.shift_pressed:
		select_to(-1)
	elif event is InputEventMouseButton and event.is_pressed():
		if event.button_mask & MOUSE_BUTTON_LEFT and not mouse_over_input:
			var i = [frame_input.get_line_edit(), depth_input.get_line_edit()]
			for node in i:
				node.release_focus()


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
			marker_data[frame][2],
			marker_data[frame][3])
		connect_marker(frame)


func add_marker(frame, depth, trans=null, ease=null, auxiliary=0):
	var marker:Sprite2D = $Marker.duplicate()
	marker.show()
	for node in marker_list.values():
		if node.get_meta('frame') == frame:
			node.queue_free()
	var index = get_marker_index(frame)
	if trans == null:
		trans = %MarkersMenu/HBox/Trans.selected
	if ease == null:
		ease = owner.get_ease_direction(depth)
	if auxiliary:
		if int(auxiliary) & 1 << 0:
			marker.self_modulate = Color.HOT_PINK
	marker_list[frame] = marker
	var marker_button = marker.get_node('Button')
	marker_button.toggled.connect(marker_toggled.bind(marker))
	marker_button.gui_input.connect(_on_marker_gui_input.bind(marker))
	var render_pos = owner.BOTTOM + depth * (owner.TOP - owner.BOTTOM)
	marker.set_meta('frame', frame)
	marker.set_meta('depth', depth)
	marker.set_meta('trans', trans)
	marker.set_meta('ease', ease)
	marker.set_meta('auxiliary', auxiliary)
	marker.position.y = render_pos
	marker.position.x = frame * owner.path_speed
	add_child(marker)


var mouse_movement:Vector2
func _on_marker_gui_input(event, input_marker):
	if %Play.button_pressed:
		return
	if not selected_marker or input_marker != selected_marker:
		if not selected_multi_markers.has(input_marker):
			return
	if event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_LEFT:
				depth_input.value -= event.relative.y / 200
				if marker_list.values().front():
					if selected_marker != marker_list.values().front():
						frame_input.value += event.relative.x / 5
				mouse_movement += event.relative
	elif not event.pressed and not mouse_over_marker:
		mouse_movement = Vector2(0, 0)


func marker_toggled(button_pressed:bool, marker:Node):
	if button_pressed and %Play.button_pressed:
		return
	if mouse_movement != Vector2(0,0):
		mouse_movement = Vector2(0,0)
		if marker == selected_marker:
			marker.get_node('Button').set_pressed_no_signal(true)
		else:
			marker.get_node('Button').set_pressed_no_signal(false)
		return
	if not owner.control_pressed and not selecting_to_edge:
		for node in selected_multi_markers:
			node.get_node('Button/Selected').hide()
		selected_multi_markers.clear()
	if button_pressed:
		if owner.shift_pressed and selected_marker or selecting_to_edge:
			var end_marker = marker
			var index_a = get_marker_index(selected_marker.get_meta('frame'))
			var index_b = get_marker_index(marker.get_meta('frame'))
			var selected_range
			if index_a < index_b:
				selected_range = range(index_a, index_b + 1)
			elif index_a > index_b:
				selected_range = range(index_b, index_a + 1)
			var keys = marker_list.keys()
			keys.sort()
			for index in selected_range:
				if marker_list[keys[index]] != selected_marker:
					selected_multi_markers.append(marker_list[keys[index]])
			for node in selected_multi_markers:
				node.get_node('Button/Selected').self_modulate = Color.PURPLE
				node.get_node('Button/Selected').show()
				node.get_node('Button').set_pressed_no_signal(false)
			set_marker_movement_range()
			return
		elif owner.control_pressed and selected_marker:
			if not selected_multi_markers.has(marker):
				selected_multi_markers.append(marker)
				marker.get_node('Button/Selected').self_modulate = Color.PURPLE
				marker.get_node('Button/Selected').show()
				marker.get_node('Button').set_pressed_no_signal(false)
			else:
				selected_multi_markers.erase(marker)
				marker.get_node('Button/Selected').hide()
				marker.get_node('Button').set_pressed_no_signal(false)
			set_marker_movement_range()
			return
		for node in marker_list.values():
			if node != marker:
				node.get_node('Button').set_pressed_no_signal(false)
				node.get_node('Button/Selected').hide()
		marker.get_node('Button/Selected').self_modulate = Color.AQUAMARINE
		marker.get_node('Button/Selected').show()
		var frame = marker.get_meta('frame')
		var aux_list = %MarkersMenu/HBox/AuxiliaryFunctions.get_popup()
		for i in aux_list.item_count:
			if int(owner.marker_data[frame][3]) & 1 << i:
				aux_list.set_item_checked(i, true)
			else:
				aux_list.set_item_checked(i, false)
		var index:int = get_marker_index(frame)
		selected_marker = marker
		set_marker_menu_mode(MARKER_MENU.HAS_SELECTION)
		set_marker_movement_range()
		frame_input.value_changed.disconnect(_on_frame_value_changed)
		frame_input.value = frame
		frame_input.value_changed.connect(_on_frame_value_changed)
		depth_input.value_changed.disconnect(_on_depth_value_changed)
		depth_input.value = marker.get_meta('depth')
		depth_input.value_changed.connect(_on_depth_value_changed)
		%MarkersMenu/HBox/Trans.select(marker.get_meta('trans'))
		%MarkersMenu/HBox/Ease.select(marker.get_meta('ease'))
	else:
		frame_input.value_changed.disconnect(_on_frame_value_changed)
		depth_input.value_changed.disconnect(_on_depth_value_changed)
		frame_input.value = owner.frame
		depth_input.value = owner.get_ball_depth()
		frame_input.value_changed.connect(_on_frame_value_changed)
		depth_input.value_changed.connect(_on_depth_value_changed)
		marker.get_node('Button/Selected').hide()
		set_marker_menu_mode(MARKER_MENU.NOTHING_SELECTED)
		selected_marker = null


func set_marker_movement_range():
	if not selected_marker:
		return
	var markers:Array
	markers.append(selected_marker)
	for marker in selected_multi_markers:
		markers.append(marker)
	var keys = marker_list.keys()
	keys.sort()
	var indices:Array
	for i in markers:
		indices.append(keys.find(i.get_meta('frame')))
	indices.sort()
	var sequences:Array
	var _sequence:Array
	for i in indices.size():
		_sequence.append(keys[indices[i]])
		if i == indices.size() - 1 or indices[i] + 1 != indices[i + 1]:
			sequences.append(_sequence)
			_sequence = []
	var movement_min
	var movement_max
	for set in sequences:
		var min_frame
		var max_frame
		var previous_frame = get_previous_frame(set.front())
		if previous_frame == set.front():
			movement_min = 0
			movement_max = 0
		else:
			min_frame = previous_frame + SEPARATION_MIN
			var next_frame = get_next_frame(set.back())
			if next_frame != set.back():
				max_frame = get_next_frame(set.back()) - SEPARATION_MIN
			else:
				max_frame = owner.path.size() - 1
			var movement_left = set.front() - min_frame
			var movement_right = max_frame - set.back()
			if not movement_min or movement_left < movement_min:
				movement_min = movement_left
			if not movement_max or movement_right < movement_max:
				movement_max = movement_right
	var origin:int = selected_marker.get_meta('frame')
	if frame_input.is_connected('value_changed', _on_frame_value_changed):
		frame_input.value_changed.disconnect(_on_frame_value_changed)
	frame_input.min_value = origin - movement_min
	frame_input.max_value = origin + movement_max
	if not frame_input.is_connected('value_changed', _on_frame_value_changed):
		frame_input.value_changed.connect(_on_frame_value_changed)


func get_marker_depth(marker) -> float:
	return abs((marker.position.y - owner.BOTTOM) / (owner.TOP - owner.BOTTOM))


func get_marker_index(frame:int) -> int:
	var keys = marker_list.keys()
	keys.sort()
	return keys.find(frame)


func get_previous_frame(frame:int, look_back:=1) -> int:
	var keys = marker_list.keys()
	keys.sort()
	return keys[max(keys.find(frame) - look_back, 0)]


func get_next_frame(frame:int, look_forward:=1) -> int:
	var keys = marker_list.keys()
	keys.sort()
	return keys[min(keys.find(frame) + look_forward, marker_list.size() - 1)]


func connect_marker(frame:int, connect_next:=true) -> void:
	if frame == 0 or not marker_list.has(frame):
		return
	var previous_frame = get_previous_frame(frame)
	var next_frame = get_next_frame(frame)
	var marker:Node = marker_list[frame]
	var previous:Node = marker_list[previous_frame]
	var starting_position = previous.position
	if connect_next and next_frame != frame:
		connect_marker(next_frame, false)
	if marker.has_meta('line'):
		var marker_line = marker.get_meta('line')
		if marker_line != null:
			remove_child(marker_line)
			marker_line.queue_free()
	var line = $Line.duplicate()
	add_child(line)
	line.add_to_group('lines')
	marker.set_meta('line', line)
	var tween = get_tree().create_tween()
	tween.set_trans(marker.get_meta('trans'))
	tween.set_ease(marker.get_meta('ease'))
	var steps = marker.get_meta('frame') - previous.get_meta('frame')
	tween.tween_property(previous, 'position:y', marker.position.y, steps)
	tween.pause()
	line.clear_points()
	var line_frame = previous.get_meta('frame')
	for i in steps + 1:
		owner.path[line_frame] = get_marker_depth(previous)
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
	var diff = center.x - (owner.frame * owner.path_speed) - position.x
	position.x = center.x - (owner.frame * owner.path_speed)


func select_to(index:int):
	if not selected_marker:
		return
	var selected_frame = selected_marker.get_meta('frame')
	if selected_frame == 0 and index == 1:
		return
	var selected_marker_copy = selected_marker
	selected_marker.get_node('Button').button_pressed = false
	selected_multi_markers.clear()
	selected_marker = selected_marker_copy
	selected_marker.get_node('Button').button_pressed = true
	var sorted_markers:Array = marker_list.keys()
	sorted_markers.sort()
	selecting_to_edge = true
	var target_frame = sorted_markers[index]
	if selected_frame != target_frame:
		marker_toggled(true, marker_list[target_frame])
	selecting_to_edge = false


func _on_frame_value_changed(value:int):
	if not selected_marker:
		return
	var movement = value - selected_marker.get_meta('frame')
	var markers:Array
	markers.append(selected_marker)
	for marker in selected_multi_markers:
		markers.append(marker)
	
	var orig_frames:Array
	var new_frames:Array
	for marker in markers:
		var orig_frame = marker.get_meta('frame')
		var new_frame = orig_frame + movement
		orig_frames.append(orig_frame)
		new_frames.append(orig_frame + movement)
	
	for frame in new_frames:
		if orig_frames.has(frame):
			return
	
	for marker in markers:
		var orig_frame = marker.get_meta('frame')
		if not owner.marker_data.has(orig_frame):
			return
		var orig_marker_data = owner.marker_data[orig_frame].duplicate()
		var new_frame = orig_frame + movement
		marker.position.x += movement * owner.path_speed
		marker.set_meta('frame', new_frame)
		owner.marker_data.erase(orig_frame)
		owner.marker_data[new_frame] = orig_marker_data
		marker_list.erase(orig_frame)
		marker_list[new_frame] = marker
	for marker in markers:
		var frame = marker.get_meta('frame')
		clear_ahead(frame)
		connect_marker(frame)
		place_ball_on_path()
	Data.save_path()


func _on_depth_value_changed(value):
	if not selected_marker:
		return
	var movement = value - selected_marker.get_meta('depth')
	var markers:Array
	var marker_movement:Dictionary
	markers.append(selected_marker)
	for marker in selected_multi_markers:
		markers.append(marker)
	var confined_movement:float = movement
	for marker in markers:
		var marker_depth = marker.get_meta('depth')
		var new_pos = marker_depth + movement
		if new_pos > 1 and 1 - marker_depth < confined_movement:
			confined_movement = 1 - marker_depth
		elif new_pos < 0 and -marker_depth > confined_movement:
			confined_movement = -marker_depth
	for marker in markers:
		var marker_frame:int = marker.get_meta('frame')
		if not owner.marker_data.has(marker_frame):
			return
		var marker_depth = marker.get_meta('depth')
		var new_pos = marker_depth + confined_movement
		marker.position.y = owner.BOTTOM + new_pos * (owner.TOP - owner.BOTTOM)
		marker.set_meta('depth', new_pos)
		owner.marker_data[marker_frame][0] = new_pos
		if marker_frame == 0:
			connect_marker(get_next_frame(0))
		connect_marker(marker_frame)
		place_ball_on_path()
		Data.save_path()


func _on_trans_selected(index):
	Data.set_config('easings', 'trans', index)
	if not selected_marker:
		return
	var markers:Array
	markers.append(selected_marker)
	for marker in selected_multi_markers:
		markers.append(marker)
	for marker in markers:
		marker.set_meta('trans', index)
		var frame = marker.get_meta('frame')
		owner.marker_data[frame][1] = index
		connect_marker(frame)
		place_ball_on_path()
		Data.save_path()


func _on_easing_selected(index):
	if not selected_marker:
		return
	var markers:Array
	markers.append(selected_marker)
	for marker in selected_multi_markers:
		markers.append(marker)
	for marker in markers:
		marker.set_meta('ease', index)
		var frame = marker.get_meta('frame')
		owner.marker_data[frame][2] = index
		connect_marker(frame)
		place_ball_on_path()
		Data.save_path()


func _on_up_easing_selected(index):
	Data.set_config('easings', 'up', index)


func _on_down_easing_selected(index):
	Data.set_config('easings', 'down', index)


enum MARKER_MENU {NOTHING_SELECTED, HAS_SELECTION}
func set_marker_menu_mode(mode:int):
	if not selected_marker:
		mode = MARKER_MENU.NOTHING_SELECTED
	match mode:
		MARKER_MENU.NOTHING_SELECTED:
			%MarkersMenu/HBox/Ease.hide()
			%MarkersMenu/HBox/EaseUp.show()
			%MarkersMenu/HBox/EaseDown.show()
			%MarkersMenu/HBox/AuxiliaryFunctions.hide()
			%MarkersMenu/HBox/Delete.hide()
			frame_input.min_value = 0
			frame_input.max_value = owner.path.size() - 1
			frame_input.editable = false
			depth_input.editable = false
		MARKER_MENU.HAS_SELECTION:
			%MarkersMenu/HBox/Ease.show()
			%MarkersMenu/HBox/EaseUp.hide()
			%MarkersMenu/HBox/EaseDown.hide()
			%MarkersMenu/HBox/AuxiliaryFunctions.show()
			frame_input.editable = true
			depth_input.editable = true
			var markers:Array
			markers.append(selected_marker)
			for marker in selected_multi_markers:
				markers.append(marker)
			if markers.any(frame_is_zero):
				%MarkersMenu/HBox/Delete.hide()
			else:
				%MarkersMenu/HBox/Delete.show()


func frame_is_zero(marker) -> bool:
	if marker.get_meta('frame') == 0:
		return true
	return false


func _on_add_marker_mouse_entered():
	%MarkersMenu/HBox/Create/AddMarker.self_modulate = '4fd6d6'


func _on_add_marker_mouse_exited():
	%MarkersMenu/HBox/Create/AddMarker.self_modulate = Color.WHITE


func _on_add_marker_pressed():
	if owner.path.is_empty():
		return
	owner.place_marker(owner.get_ball_depth())
	_on_add_marker_mouse_exited()
	owner.save_path()


func _on_generate_cycle_mouse_entered():
	%MarkersMenu/HBox/Create/GenerateCycle.self_modulate = '39d443'


func _on_generate_cycle_mouse_exited():
	%MarkersMenu/HBox/Create/GenerateCycle.self_modulate = Color.WHITE


func _on_generate_cycle_pressed():
	if owner.path.is_empty():
		return
	owner.input_disabled = true
	owner.get_node('GenerateCycle').show()


func _on_copy_mouse_entered():
	%MarkersMenu/HBox/Clipboard/Copy.self_modulate = '4fd6d6'


func _on_copy_mouse_exited():
	%MarkersMenu/HBox/Clipboard/Copy.self_modulate = Color.WHITE


func _on_copy_pressed():
	if not selected_marker:
		return
	
	clipboard.clear()
	
	var selection:Array
	var frame_list:Array
	
	selection.append(selected_marker)
	frame_list.append(selected_marker.get_meta('frame'))
	if not selected_multi_markers.is_empty():
		for marker in selected_multi_markers:
			selection.append(marker)
			frame_list.append(marker.get_meta('frame'))
	
	frame_list.sort()
	var starting_frame = frame_list.front()
	
	for marker in selection:
		clipboard[marker.get_meta('frame') - starting_frame] = [
			marker.get_meta('depth'),
			marker.get_meta('trans'),
			marker.get_meta('ease'),
			marker.get_meta('auxiliary')]


func _on_paste_mouse_entered():
	%MarkersMenu/HBox/Clipboard/Paste.self_modulate = '39d443'


func _on_paste_mouse_exited():
	%MarkersMenu/HBox/Clipboard/Paste.self_modulate = Color.WHITE


func _on_paste_pressed():
	for marker in clipboard:
		var frame = owner.frame + marker
		var depth = clipboard[marker][0]
		var trans = clipboard[marker][1]
		var ease = clipboard[marker][2]
		var auxiliary = clipboard[marker][3]
		
		var collision:bool
		if frame >= owner.path.size():
			collision = true
		for i in range(frame - SEPARATION_MIN + 1, frame + SEPARATION_MIN + 1):
			if owner.marker_data.has(i):
				collision = true
		
		if not collision:
			owner.marker_data[frame] = [depth, trans, ease, 0]
			add_marker(frame, depth, trans, ease)
			connect_marker(frame)
	
	if selected_marker:
		selected_marker.get_node('Button').button_pressed = false
		for node in selected_multi_markers:
			node.get_node('Button/Selected').hide()
		selected_multi_markers.clear()
	
	owner.save_path()


func _on_delete_mouse_entered():
	%MarkersMenu/HBox/Delete.self_modulate = 'ff7474d7'


func _on_delete_mouse_exited():
	%MarkersMenu/HBox/Delete.self_modulate = Color.WHITE


func _on_delete_pressed():
	if not selected_marker and selected_multi_markers.is_empty():
		return
	if selected_multi_markers.is_empty():
		var frame:int = selected_marker.get_meta('frame')
		if frame == 0:
			return
		var next_frame = get_next_frame(frame)
		clear_ahead(frame)
		marker_list.erase(frame)
		owner.marker_data.erase(frame)
		owner.path[frame] = -1
		var line = selected_marker.get_meta('line')
		if line != null:
			remove_child(line)
			line.queue_free()
		selected_marker.queue_free()
		connect_marker(next_frame, false)
	else:
		var del_markers:Array
		if selected_marker:
			if selected_marker.get_meta('frame') != 0:
				del_markers.append(selected_marker)
		for marker in selected_multi_markers:
			marker.get_node('Button/Selected').hide()
			if marker.get_meta('frame') != 0:
				del_markers.append(marker)
		for marker in del_markers:
			var frame:int = marker.get_meta('frame')
			var previous_frame = get_previous_frame(frame)
			var next_frame = get_next_frame(frame)
			marker_list.erase(frame)
			owner.marker_data.erase(frame)
			for point in range(previous_frame, next_frame + 1):
				owner.path[point] = -1
			var line = marker.get_meta('line')
			if line != null:
				remove_child(line)
				line.queue_free()
			marker.queue_free()
			connect_marker(next_frame, false)
		selected_multi_markers.clear()
	place_ball_on_path()
	Data.save_path()
	_on_delete_mouse_exited()
	set_marker_menu_mode(MARKER_MENU.NOTHING_SELECTED)
	selected_marker = null


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
