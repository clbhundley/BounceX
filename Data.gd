extends Node

var config_path := 'user://Settings.cfg'
var config := ConfigFile.new()
var bx:Node

func _ready():
	var dir = DirAccess.open('res://')
	if not dir.dir_exists('Tracks'):
		dir.make_dir('Tracks')
	var renders_dir = ProjectSettings.globalize_path("user://Renders")
	if not dir.dir_exists(renders_dir):
		dir.make_dir(renders_dir)
	var paths_dir = ProjectSettings.globalize_path("user://Paths")
	if not dir.dir_exists(paths_dir):
		dir.make_dir(paths_dir)

func get_file_path() -> String:
	var track_selection = bx.get_node('Menu/Controls/TrackSelection')
	var path_selection = bx.get_node('Menu/Controls/Paths')
	var selected_track = track_selection.selected
	if selected_track == -1 or not path_selection.is_anything_selected():
		return ""
	var selected_path = path_selection.get_selected_items()[0]
	var track:String = track_selection.get_item_text(selected_track)
	var file_path := 'user://Paths/' + track + '/'
	var path:String = path_selection.get_item_text(selected_path)
	return 'user://Paths/' + track + '/' + path

func save_path(file_path:String = get_file_path()) -> void:
	if not file_path.ends_with('.bx'):
		file_path += '.bx'
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_line(JSON.stringify(bx.marker_data))
	for line in bx.path:
		file.store_float(line)
	file.close()

func load_path(file_path:String) -> void:
	var file:FileAccess
	file = FileAccess.open(file_path + '.bx', FileAccess.READ)
	var marker_data:Dictionary = JSON.parse_string(file.get_line())
	var keys = marker_data.keys()
	for i in keys:
		marker_data[int(i)] = marker_data[i]
		marker_data.erase(i)
	bx.marker_data = marker_data
	if marker_data.is_empty():
		bx.marker_data[0] = [0, 0, 0]
	bx.define_path(false)
	bx.get_node('Markers').set_markers()
	bx.get_node('Markers').connect_all_markers()
	file.close()

func copy_file(new_name:String):
	var dir = DirAccess.open('user://Paths/')
	var path = get_file_path()
	var track_name = path.split('/')[-2]
	var current_path = path + '.bx'
	if new_name == path.split('/')[-1]:
		new_name += "-Copy"
	var new_path =  'user://Paths/' + track_name + '/' + new_name + '.bx'
	dir.copy(current_path, new_path)
	bx.get_node('Menu/Controls').load_paths(track_name, true)

func timestamp() -> String:
	var t = Time.get_datetime_dict_from_system()
	for section in t:
		if str(t[section]).length() < 2:
			t[section] = "0" + str(t[section])
	var dt_format = "%s_%s_%s - %s.%s.%s"
	var year = str(t.year).right(2)
	return dt_format%[t.month, t.day, year, t.hour, t.minute, t.second]

func set_config(section:String, key:String, value):
	config.load(config_path)
	config.set_value(section, key, value)
	config.save(config_path)

func reset_config():
	config.load(config_path)
	config.clear()
	config.set_value('user', 'version', '2.1')
	config.save(config_path)

func load_config() -> void:
	config.load(config_path)
	
	if config.get_value('user', 'version', "") != '2.1':
		reset_config()
		await get_tree().create_timer(0.3).timeout
		bx.get_node('Menu/Version/Button/Notification').show()
		bx.get_node('Header/MenuButton').button_pressed = true
		return
	
	if config.has_section_key('user', 'display_mode'):
		var display = bx.get_node('Menu/Options/DisplayMode')
		var mode = config.get_value('user', 'display_mode')
		display._on_option_button_item_selected(mode)
		display.get_node('OptionButton').selected = mode
	
	if config.has_section_key('user', 'track'):
		var track_title = config.get_value('user', 'track')
		var track_path = 'res://Tracks/' + track_title
		if DirAccess.open('res://').file_exists(track_path):
			bx.audio.stream = load(track_path)
			var track_selection = bx.get_node('Menu/Controls/TrackSelection')
			for item in track_selection.item_count:
				if track_selection.get_item_text(item) == track_title:
					bx.get_node('Menu/Controls')._on_track_selected(item)
					track_selection.selected = item
	
	if config.has_section_key('user', 'render_resolution:x'):
		var x_value = config.get_value('user', 'render_resolution:x')
		bx.get_node('Menu/Options/RenderResolution/Values/X').value = x_value
	
	if config.has_section_key('user', 'render_resolution:y'):
		var y_value = config.get_value('user', 'render_resolution:y')
		bx.get_node('Menu/Options/RenderResolution/Values/Y').value = y_value
	
	for direction in ['up', 'down']:
		if config.has_section_key('easings', direction):
			var selected = config.get_value('easings', direction)
			var d_text:String = direction.capitalize()
			bx.get_node('MarkersMenu/HBox/Ease' + d_text).selected = selected
	
	if config.has_section_key('easings', 'trans'):
		var selected = config.get_value('easings', 'trans')
		bx.get_node('MarkersMenu/HBox/Trans').selected = selected
	
	for setting in [
		'Ball',
		'Path',
		'Backdrop',
		'Top Line',
		'Top Active',
		'Bottom Line',
		'Bottom Active']:
		if config.has_section_key('colors', setting):
			var color:Color = config.get_value('colors', setting)
			match setting:
				'Ball':
					bx.get_node('Ball').self_modulate = color
				'Path':
					bx.get_node('Path').self_modulate = color
					bx.get_node('Markers/Line').self_modulate = color
				'Backdrop':
					bx.get_node('Backdrop').self_modulate = color
				'Top Line':
					bx.top_color = color
				'Top Active':
					bx.top_color_active = color
				'Bottom Line':
					bx.bottom_color = color
				'Bottom Active':
					bx.bottom_color_active = color
