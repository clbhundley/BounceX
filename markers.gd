extends Control

var marker_list: Dictionary
var selected_marker: Sprite2D
var selected_multi_markers: Array

var clipboard: Dictionary

var selecting_to_edge: bool

const SEPARATION_MIN := 5

## How far past each edge of the screen a marker is shown, so that markers are
## already in place before they scroll into view.
const VISIBILITY_MARGIN := 400.0

## Markers read as targets to hit rather than points on a line in classic mode,
## so they are drawn larger and given a moment to register as they land. Size
## comes from a texture rasterised at that size: scaling a node resamples the
## bitmap it already has and softens it.
const CLASSIC_MARKER_TEXTURE := "res://textures/ball_large.svg"
const CLASSIC_RING_SCALE := 1.6
const CLASSIC_FLASH_FRAMES := 8

## What a marker fades to once it is behind the zone while recording, so that
## the shape of what has been laid down stays readable without competing with
## the markers still to come.
const CLASSIC_GHOST_ALPHA := 0.25

var _ghosting: bool
var _played_edge: int

var _default_texture: Texture2D
var _classic_texture: Texture2D
var _custom_texture: Texture2D
var custom_marker_name: String
var _flashing: Dictionary

var marker_color := Color.WHITE
var hold_breath_marker_color := Color.HOT_PINK

var _sorted_frames: Array
var _window_dirty := true
var _visible_lo := 0
var _visible_hi := 0

@onready var frame_input = %MarkersMenu/HBox/Frame/Input
@onready var depth_input = %MarkersMenu/HBox/Depth/Input

func _ready():
	_default_texture = $Marker.texture
	if ResourceLoader.exists(CLASSIC_MARKER_TEXTURE):
		_classic_texture = load(CLASSIC_MARKER_TEXTURE)
	var inputs = [frame_input.get_line_edit(), depth_input.get_line_edit()]
	for input in inputs:
		input.focus_entered.connect(input_focus_entered)
		input.focus_exited.connect(input_focus_exited)


func _physics_process(_delta: float) -> void:
	# A render carries the markers forward itself, one drawn frame at a time.
	if owner.rendering:
		return
	if is_visible_in_tree():
		update_visible_window()
	step_flashes()


## Markers off screen still cost a transform update every time this container
## moves, and every one of their buttons sits in the input picking set, so only
## the span either side of the playhead is left visible.
## Rebuilds the sorted frame list if markers have changed since it was last
## needed. Every marker lookup goes through here, so adding one marker costs a
## single sort however many lookups follow it.
func _refresh_frames() -> void:
	if not _window_dirty:
		return
	# Only what is actually on screen needs clearing; walking every marker here
	# would undo the point of the window while markers are dragged.
	for i in range(_visible_lo, _visible_hi):
		_set_marker_visible(i, false)
	_sorted_frames = marker_list.keys()
	_sorted_frames.sort()
	_visible_lo = 0
	_visible_hi = 0
	_window_dirty = false
	_apply_window()


func update_visible_window() -> void:
	_refresh_frames()
	_apply_window()


func _apply_window() -> void:
	if _sorted_frames.is_empty():
		return
	var speed: float = owner.path_speed
	if speed <= 0.0:
		return
	var width: float = get_viewport_rect().size.x
	var playhead: float = owner.playhead_position()
	var hi := int(owner.frame + (width - playhead + VISIBILITY_MARGIN) / speed)
	# Markers behind the zone have been played, and are dropped unless they are
	# being kept as a record of what has just been laid down.
	_ghosting = owner.classic_mode and not owner.rendering
	var lo: int
	if owner.classic_mode and not _ghosting:
		lo = owner.frame
	else:
		lo = int(owner.frame - (playhead + VISIBILITY_MARGIN) / speed)
	var new_lo: int = _sorted_frames.bsearch(lo, true)
	var new_hi: int = _sorted_frames.bsearch(hi + 1, true)
	# A flash marks a marker reaching the zone, so it belongs to a single marker
	# leaving at the near edge, not to markers dropped in bulk by a scrub or by
	# markers going back out of view ahead of the zone.
	var crossing: bool = not _ghosting \
		and mini(_visible_hi, new_lo) - _visible_lo == 1
	for i in range(_visible_lo, mini(_visible_hi, new_lo)):
		_set_marker_visible(i, false, crossing)
	for i in range(maxi(_visible_lo, new_hi), _visible_hi):
		_set_marker_visible(i, false)
	for i in range(new_lo, mini(new_hi, _visible_lo)):
		_set_marker_visible(i, true)
	for i in range(maxi(new_lo, _visible_hi), new_hi):
		_set_marker_visible(i, true)
	_visible_lo = new_lo
	_visible_hi = new_hi
	if not _ghosting:
		_played_edge = 0
		return
	# Markers behind the zone are held back rather than dropped, so reaching it
	# is no longer a marker leaving. Raise the flash off that crossing instead,
	# and let it settle into a ghost rather than fade away entirely.
	var played: int = clampi(
		_sorted_frames.bsearch(owner.frame, true), new_lo, new_hi)
	if owner.is_advancing() and played - _played_edge == 1:
		var landing = marker_list.get(_sorted_frames[played - 1])
		if is_instance_valid(landing):
			_flashing[landing] = CLASSIC_FLASH_FRAMES
	_played_edge = played
	for i in range(new_lo, new_hi):
		var node = marker_list.get(_sorted_frames[i])
		if is_instance_valid(node) and not _flashing.has(node):
			node.modulate.a = CLASSIC_GHOST_ALPHA if i < played else 1.0


## Placing a marker used to invalidate the whole sorted list, so recording onto
## a long path paid for a full sort per marker. One frame can be slotted in.
func _window_insert(frame: int) -> void:
	if _window_dirty:
		return
	var index: int = _sorted_frames.bsearch(frame, true)
	if index >= _sorted_frames.size() or _sorted_frames[index] != frame:
		_sorted_frames.insert(index, frame)
		if index < _visible_lo:
			_visible_lo += 1
			_visible_hi += 1
		elif index < _visible_hi:
			_visible_hi += 1
			_set_marker_visible(index, true)
	elif index >= _visible_lo and index < _visible_hi:
		_set_marker_visible(index, true)
	_apply_window()


func _set_marker_visible(index: int, value: bool, flash := false) -> void:
	var node = marker_list.get(_sorted_frames[index])
	if not is_instance_valid(node):
		return
	if _flashing.has(node):
		_flashing.erase(node)
		node.scale = Vector2.ONE
	node.modulate = Color.WHITE
	if value or not flash or not owner.is_advancing():
		node.visible = value
		return
	_flashing[node] = CLASSIC_FLASH_FRAMES


## Carries every marker leaving the zone one frame further through its flash.
## Counted in frames rather than seconds so that a render, which draws frames
## far slower than they play, sends markers off over the same span either way.
func step_flashes() -> void:
	for marker in _flashing.keys():
		if not is_instance_valid(marker):
			_flashing.erase(marker)
			continue
		var remaining: int = _flashing[marker] - 1
		var settles_to: float = CLASSIC_GHOST_ALPHA if _ghosting else 0.0
		if remaining <= 0:
			_flashing.erase(marker)
			marker.scale = Vector2.ONE
			marker.modulate.a = settles_to
			marker.visible = _ghosting
			continue
		_flashing[marker] = remaining
		var progress := 1.0 - float(remaining) / float(CLASSIC_FLASH_FRAMES)
		marker.modulate.a = lerpf(1.0, settles_to, progress)
		marker.scale = Vector2.ONE * (1.0 + 0.8 * progress)


## The ring and the selection dot are editing affordances that never reach a
## render, so they are scaled to keep up with the larger marker.
func style_marker(marker: Sprite2D) -> void:
	if int(marker.get_meta('auxiliary')) & 1 << 0:
		marker.self_modulate = hold_breath_marker_color
	else:
		marker.self_modulate = marker_color
	if owner.classic_mode and _custom_texture != null:
		marker.texture = _custom_texture
	elif owner.classic_mode and _classic_texture != null:
		marker.texture = _classic_texture
	else:
		marker.texture = _default_texture
	# The ring and the selection dot are Controls under a Node2D, so their
	# offsets were resolved against whichever marker texture was in place when
	# the scene was laid out. Moving the anchors alone leaves those offsets
	# describing the old texture, so the offsets have to be worked out again
	# with them, at the size the nodes already have.
	var button: Control = marker.get_node('Button')
	button.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	# Every ring sits a layer above every marker, so a large image cannot bury
	# the ring belonging to the marker beside it.
	button.z_index = 1
	# Scaled about its own centre, which the preset has just settled, so the
	# ring keeps up with the larger marker without drifting off it.
	if owner.classic_mode:
		button.scale = Vector2.ONE * CLASSIC_RING_SCALE
	else:
		button.scale = Vector2.ONE


## Loads a marker image a user has supplied, by file name within the markers
## directory. An empty name, or one that will not load, leaves the built in
## marker in place rather than leaving the path unreadable.
func set_custom_marker(file_name: String) -> void:
	custom_marker_name = file_name
	_custom_texture = null
	if file_name != "":
		var image := _read_marker_image(Data.markers_dir.path_join(file_name))
		if image != null and not image.is_empty():
			_custom_texture = ImageTexture.create_from_image(image)
		else:
			custom_marker_name = ""
			printerr("could not read marker image: " + file_name)
	apply_marker_style()


## Vectors are rasterised at the size they describe, the same way the built in
## markers are, so an SVG sizes a marker by its own dimensions like any other
## image does.
func _read_marker_image(file_path: String) -> Image:
	if file_path.get_extension().to_lower() != "svg":
		return Image.load_from_file(file_path)
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return null
	var source := file.get_buffer(file.get_length())
	file.close()
	var image := Image.new()
	if image.load_svg_from_buffer(source) != OK:
		return null
	return image


## Hides the ring and the selection dot, which belong to editing rather than to
## the path itself and have no place in a render.
func set_buttons_visible(value: bool) -> void:
	for node in marker_list.values():
		if is_instance_valid(node):
			node.get_node('Button').visible = value


## Clearing the markers from outside has to invalidate the window along with
## them, or the sorted frames keep describing markers that no longer exist.
func clear_markers() -> void:
	for node in marker_list.values():
		if is_instance_valid(node):
			node.queue_free()
	marker_list.clear()
	_window_dirty = true


func apply_marker_style() -> void:
	for node in marker_list.values():
		if is_instance_valid(node):
			style_marker(node)


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
	_window_dirty = true
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
	var marker: Sprite2D = $Marker.duplicate()
	# Left hidden: update_visible_window() owns marker visibility and reveals
	# this one on the next tick if it falls inside the window.
	if marker_list.has(frame) and is_instance_valid(marker_list[frame]):
		marker_list[frame].queue_free()
	if trans == null:
		trans = %MarkersMenu/HBox/Trans.selected
	if ease == null:
		ease = owner.get_ease_direction(depth)
	marker_list[frame] = marker
	_window_insert(frame)
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
	# Styled once in the tree: a Control settles its offsets against its parent
	# on entering, which would undo any worked out before it got there.
	style_marker(marker)


var mouse_movement: Vector2
var _drag_frame_remainder: float = 0.0

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
						_drag_frame_remainder += event.relative.x / owner.path_speed
						var step := int(_drag_frame_remainder)
						if step != 0:
							_drag_frame_remainder -= step
							frame_input.value += step
				mouse_movement += event.relative
	elif not event.pressed and not mouse_over_marker:
		mouse_movement = Vector2(0, 0)
		_drag_frame_remainder = 0.0


func marker_toggled(button_pressed: bool, marker: Node):
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
		var index: int = get_marker_index(frame)
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
	var markers: Array
	markers.append(selected_marker)
	for marker in selected_multi_markers:
		markers.append(marker)
	var keys = marker_list.keys()
	keys.sort()
	var indices: Array
	for i in markers:
		indices.append(keys.find(i.get_meta('frame')))
	indices.sort()
	var sequences: Array
	var _sequence: Array
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
	var origin: int = selected_marker.get_meta('frame')
	if frame_input.is_connected('value_changed', _on_frame_value_changed):
		frame_input.value_changed.disconnect(_on_frame_value_changed)
	frame_input.min_value = origin - movement_min
	frame_input.max_value = origin + movement_max
	if not frame_input.is_connected('value_changed', _on_frame_value_changed):
		frame_input.value_changed.connect(_on_frame_value_changed)


func get_marker_depth(marker) -> float:
	return abs((marker.position.y - owner.BOTTOM) / (owner.TOP - owner.BOTTOM))


func get_marker_index(frame: int) -> int:
	_refresh_frames()
	var index: int = _sorted_frames.bsearch(frame, true)
	if index < _sorted_frames.size() and _sorted_frames[index] == frame:
		return index
	return -1


func get_previous_frame(frame: int, look_back := 1) -> int:
	_refresh_frames()
	return _sorted_frames[maxi(get_marker_index(frame) - look_back, 0)]


func get_next_frame(frame:int, look_forward := 1) -> int:
	_refresh_frames()
	return _sorted_frames[mini(
		get_marker_index(frame) + look_forward, _sorted_frames.size() - 1)]


func connect_marker(frame: int, connect_next := true) -> void:
	if frame == 0 or not marker_list.has(frame):
		return
	var previous_frame = get_previous_frame(frame)
	var next_frame = get_next_frame(frame)
	var marker: Sprite2D = marker_list[frame]
	var previous: Sprite2D = marker_list[previous_frame]
	if connect_next and next_frame != frame:
		connect_marker(next_frame, false)
	if marker.has_meta('line'):
		var marker_line = marker.get_meta('line')
		if marker_line != null:
			remove_child(marker_line)
			marker_line.queue_free()
	var line = $Line.duplicate()
	line.visible = not owner.classic_mode
	add_child(line)
	line.add_to_group('lines')
	marker.set_meta('line', line)
	var steps: int = marker.get_meta('frame') - previous.get_meta('frame')
	var line_frame: int = previous.get_meta('frame')
	var start := previous.position
	var span: float = marker.position.y - start.y
	var bottom: float = owner.BOTTOM
	var height: float = owner.TOP - bottom
	var speed: float = owner.path_speed
	var last_frame: int = owner.path.size()
	# Evaluating the easing directly, rather than stepping a Tween a frame at a
	# time, keeps this proportional to the gap without the per step cost. The
	# gap between two markers can run to tens of thousands of frames, so
	# everything that does not vary across it is read once.
	var points := PackedVector2Array()
	if steps == 0 or is_zero_approx(span):
		# The markers sit at the same depth, so the path holds and the line
		# between them is straight: it needs no easing and only two points.
		var depth: float = absf((start.y - bottom) / height)
		for i in range(line_frame, mini(line_frame + steps + 1, last_frame)):
			owner.path[i] = depth
		points.append(start)
		if steps > 0:
			points.append(Vector2(start.x + steps * speed, start.y))
	else:
		var trans = marker.get_meta('trans')
		var ease = marker.get_meta('ease')
		var duration := float(steps)
		var fill_limit: int = clampi(last_frame - line_frame, 0, steps + 1)
		points.resize(steps + 1)
		for i in steps + 1:
			var y: float = Tween.interpolate_value(
				start.y, span, float(i), duration, trans, ease)
			points[i] = Vector2(start.x + i * speed, y)
			if i < fill_limit:
				owner.path[line_frame + i] = absf((y - bottom) / height)
	line.points = points


func connect_all_markers():
	for marker in marker_list.keys():
		connect_marker(marker)


func clear_ahead(frame: int):
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
	position.x = owner.playhead_position() - (owner.frame * owner.path_speed)
	update_visible_window()


func select_to(index: int):
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
	var sorted_markers: Array = marker_list.keys()
	sorted_markers.sort()
	selecting_to_edge = true
	var target_frame = sorted_markers[index]
	if selected_frame != target_frame:
		marker_toggled(true, marker_list[target_frame])
	selecting_to_edge = false


func _on_frame_value_changed(value: int):
	if not selected_marker:
		return
	var movement = value - selected_marker.get_meta('frame')
	var markers: Array
	markers.append(selected_marker)
	for marker in selected_multi_markers:
		markers.append(marker)
	
	var orig_frames: Array
	var new_frames: Array
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
		_window_dirty = true
	for marker in markers:
		var frame = marker.get_meta('frame')
		clear_ahead(frame)
		connect_marker(frame)
		place_ball_on_path()
	Data.save_path_debounced()


func _on_depth_value_changed(value):
	if not selected_marker:
		return
	var movement = value - selected_marker.get_meta('depth')
	var markers: Array
	var marker_movement: Dictionary
	markers.append(selected_marker)
	for marker in selected_multi_markers:
		markers.append(marker)
	var confined_movement: float = movement
	for marker in markers:
		var marker_depth = marker.get_meta('depth')
		var new_pos = marker_depth + movement
		if new_pos > 1 and 1 - marker_depth < confined_movement:
			confined_movement = 1 - marker_depth
		elif new_pos < 0 and -marker_depth > confined_movement:
			confined_movement = -marker_depth
	for marker in markers:
		var marker_frame: int = marker.get_meta('frame')
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
	Data.save_path_debounced()


func _on_trans_selected(index):
	Data.set_config('easings', 'trans', index)
	if not selected_marker:
		return
	var markers: Array
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
	var markers: Array
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
func set_marker_menu_mode(mode: int):
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
			var markers: Array
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
	# The ball follows a path that classic mode does not show, so placing
	# against it there puts markers at a depth there is no way to see. Start
	# them at the middle instead, where the zone is.
	if owner.classic_mode:
		owner.place_marker(0.5)
	else:
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


var _copy_tween: Tween
func _on_copy_pressed():
	if not selected_marker:
		return
	
	if _copy_tween and _copy_tween.is_valid():
		_copy_tween.kill()
	var sprite: Sprite2D = owner.get_node("MarkersCopied")
	sprite.position.x = get_viewport_rect().size.x / 2
	sprite.modulate.a = 1.0
	sprite.show()
	_copy_tween = create_tween()
	_copy_tween.tween_property(sprite, "modulate:a", 0.0, 1.6)
	_copy_tween.tween_callback(sprite.hide)
	
	clipboard.clear()
	
	var selection: Array
	var frame_list: Array
	
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

var _paste_tween: Tween
func _on_paste_pressed():
	if clipboard.is_empty():
		return
	
	if _paste_tween and _paste_tween.is_valid():
		_paste_tween.kill()
	var sprite: Sprite2D = owner.get_node("MarkersPasted")
	sprite.position.x = get_viewport_rect().size.x / 2
	sprite.modulate.a = 1.0
	sprite.show()
	_paste_tween = create_tween()
	_paste_tween.tween_property(sprite, "modulate:a", 0.0, 1.6)
	_paste_tween.tween_callback(sprite.hide)
	
	for marker in clipboard:
		var frame = owner.frame + marker
		var depth = clipboard[marker][0]
		var trans = clipboard[marker][1]
		var ease = clipboard[marker][2]
		var auxiliary = clipboard[marker][3]
		
		var collision: bool
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
	
	place_ball_on_path()
	owner.save_path()


func _on_delete_mouse_entered():
	%MarkersMenu/HBox/Delete.self_modulate = 'ff7474d7'


func _on_delete_mouse_exited():
	%MarkersMenu/HBox/Delete.self_modulate = Color.WHITE


func _on_delete_pressed():
	if not selected_marker and selected_multi_markers.is_empty():
		return
	if selected_multi_markers.is_empty():
		var frame: int = selected_marker.get_meta('frame')
		if frame == 0:
			return
		var next_frame = get_next_frame(frame)
		clear_ahead(frame)
		marker_list.erase(frame)
		_window_dirty = true
		owner.marker_data.erase(frame)
		owner.path[frame] = -1
		var line = selected_marker.get_meta('line')
		if line != null:
			remove_child(line)
			line.queue_free()
		selected_marker.queue_free()
		connect_marker(next_frame, false)
	else:
		var del_markers: Array
		if selected_marker:
			if selected_marker.get_meta('frame') != 0:
				del_markers.append(selected_marker)
		for marker in selected_multi_markers:
			marker.get_node('Button/Selected').hide()
			if marker.get_meta('frame') != 0:
				del_markers.append(marker)
		for marker in del_markers:
			var frame: int = marker.get_meta('frame')
			var previous_frame = get_previous_frame(frame)
			var next_frame = get_next_frame(frame)
			marker_list.erase(frame)
			_window_dirty = true
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


var mouse_over_marker: bool
func _on_marker_mouse_entered():
	mouse_over_marker = true


func _on_marker_mouse_exited():
	mouse_over_marker = false


var mouse_over_input: bool
func _on_input_mouse_entered():
	mouse_over_input = true


func _on_input_mouse_exited():
	mouse_over_input = false


func input_focus_entered():
	owner.input_disabled = true


func input_focus_exited():
	owner.input_disabled = false
