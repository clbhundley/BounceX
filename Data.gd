extends Node

var config_path := 'user://Settings.cfg'
var config := ConfigFile.new()

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

func save_path(file_path:String) -> void:
	var file:FileAccess
	file = FileAccess.open(file_path, FileAccess.WRITE)
	var node_path = get_tree().get_root().get_node('BounceX').path
	for line in node_path:
		file.store_float(line)
	file.close()

func load_path(file_path:String) -> void:
	var file:FileAccess
	file = FileAccess.open(file_path, FileAccess.READ)
	var path = get_tree().get_root().get_node('BounceX').path
	path.clear()
	while file.get_position() < file.get_length():
		var value = file.get_float()
		path.append(value)
	file.close()

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

func load_config() -> void:
	var bx = get_tree().get_root().get_node('BounceX')
	config.load(config_path)
	
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
	
	if config.has_section_key('user', 'speed'):
		bx.get_node('Speed').value = config.get_value('user', 'speed')
		bx._on_speed_value_changed(config.get_value('user', 'speed'))
	else:
		bx.get_node('Speed').value = 2
		bx._on_speed_value_changed(2)
	
	if config.has_section_key('user', 'render_resolution:x'):
		var x_value = config.get_value('user', 'render_resolution:x')
		bx.get_node('Menu/Options/RenderResolution/Values/X').value = x_value
	
	if config.has_section_key('user', 'render_resolution:y'):
		var y_value = config.get_value('user', 'render_resolution:y')
		bx.get_node('Menu/Options/RenderResolution/Values/Y').value = y_value
	
	for setting in [
		'Ball',
		'Path',
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
				'Top Line':
					bx.top_color = color
				'Top Active':
					bx.top_color_active = color
				'Bottom Line':
					bx.bottom_color = color
				'Bottom Active':
					bx.bottom_color_active = color
