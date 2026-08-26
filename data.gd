extends Node

const VIDEO_EXTENSIONS := ["mp4", "mkv", "webm", "avi", "mov", "wmv", "flv"]

var bx: Node

var config_path: String
var config := ConfigFile.new()

var base_dir:    String
const SAVE_DEBOUNCE := 0.25
var _save_timer: Timer
var _save_pending := false

var tracks_dir:  String
var paths_dir:   String
var renders_dir: String
var markers_dir: String


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.wait_time = SAVE_DEBOUNCE
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_on_save_timeout)
	add_child(_save_timer)
	base_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("BounceX")
	tracks_dir  = base_dir.path_join("Tracks")
	paths_dir   = base_dir.path_join("Paths")
	renders_dir = base_dir.path_join("Renders")
	markers_dir = base_dir.path_join("Markers")
	DirAccess.make_dir_recursive_absolute(tracks_dir)
	DirAccess.make_dir_recursive_absolute(paths_dir)
	DirAccess.make_dir_recursive_absolute(renders_dir)
	DirAccess.make_dir_recursive_absolute(markers_dir)
	config_path = base_dir.path_join("Settings.cfg")
	# Silently migrate Settings.cfg on first launch after upgrade so
	# load_config() picks up the user's existing colors/easings/etc.
	if not FileAccess.file_exists(config_path) and FileAccess.file_exists("user://Settings.cfg"):
		var src := FileAccess.open("user://Settings.cfg", FileAccess.READ)
		var dst := FileAccess.open(config_path, FileAccess.WRITE)
		if src and dst: dst.store_buffer(src.get_buffer(src.get_length()))
		if src: src.close()
		if dst: dst.close()


func get_file_path() -> String:
	var track_selection := bx.get_node('Menu/Controls/Tracks/TrackSelection')
	var path_selection  := bx.get_node('Menu/Controls/Paths')
	if track_selection.selected == -1 or not path_selection.is_anything_selected():
		return ""
	var track = track_selection.get_item_text(track_selection.selected)
	var path  = path_selection.get_item_text(path_selection.get_selected_items()[0])
	return paths_dir.path_join(track).path_join(path + ".bx")


func upgrade_path_file(file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	var changed := false
	# Ensure path is using v2 file format
	if not parsed.has("markers"):
		var markers := {}
		for key in parsed:
			var m = parsed[key]
			if m.size() < 4:
				m.append(0)  # original .bx files didn't include auxiliary field
			markers[str(int(key))] = [m[0], int(m[1]), int(m[2]), int(m[3])]
		var related_media := file_path.get_base_dir().get_file().get_basename()
		parsed = {
			"meta": {
				"version": 2.0,
				"marker_fields": ["depth", "trans", "ease", "auxiliary"],
				"related_media": related_media
				},
			"markers": markers
		}
		changed = true
	# Ensure meta has required fields
	var meta: Dictionary = parsed.get("meta", {})
	if not meta.has("version"):
		meta["version"] = 2.0
		changed = true
	elif meta["version"] is String:
		meta["version"] = maxf(float(meta["version"]), 2.0)
		changed = true
	if not meta.has("marker_fields"):
		meta["marker_fields"] = ["depth", "trans", "ease", "auxiliary"]
		changed = true
	if changed:
		parsed["meta"] = meta
		var new_file := FileAccess.open(file_path, FileAccess.WRITE)
		if new_file:
			new_file.store_line(JSON.stringify(parsed))
			new_file.close()


## Writing a path serialises every marker in it, which is far too much work to
## repeat for each marker of a selection or each frame of a drag. Callers that
## fire repeatedly ask for a save instead of performing one.
func save_path_debounced() -> void:
	_save_pending = true
	_save_timer.start()


func _on_save_timeout() -> void:
	flush_path_save()


## Performs a requested save immediately. Anything that abandons the current
## path has to call this first, or the last edits to it are lost.
func flush_path_save() -> void:
	if _save_pending:
		_save_pending = false
		save_path()


func save_path(file_path: String = get_file_path()) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return
	var data := {"meta": bx.path_meta, "markers": bx.marker_data}
	data.merge(bx.path_extra)
	file.store_line(JSON.stringify(data))
	file.close()


func load_path(file_path: String) -> void:
	flush_path_save()
	upgrade_path_file(file_path)
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.has("markers"):
		return
	bx.path_meta = parsed.get("meta", {})
	if bx.path_meta.get("related_media", "") == "":
		bx.path_meta["related_media"] = \
			file_path.get_base_dir().get_file().get_basename()
	bx.path_extra = {}
	for key in parsed:
		if key != "meta" and key != "markers":
			bx.path_extra[key] = parsed[key]
	var marker_data := {}
	for key in parsed["markers"]:
		marker_data[int(key)] = parsed["markers"][key]
	bx.marker_data = marker_data
	if marker_data.is_empty():
		bx.marker_data[0] = [0, 0, 0, 0]
	bx.define_path(false)
	bx.get_node('Markers').set_markers()


const MARKER_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg"]

static func is_marker_image(file_path: String) -> bool:
	return file_path.get_extension().to_lower() in MARKER_EXTENSIONS


## The marker images a user has brought in, by file name.
func marker_images() -> PackedStringArray:
	var found: PackedStringArray
	var dir := DirAccess.open(markers_dir)
	if not dir:
		return found
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and is_marker_image(file_name):
			found.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


static func is_video_file(file_path: String) -> bool:
	return file_path.get_extension().to_lower() in VIDEO_EXTENSIONS


## Load an audio file from an absolute path into an AudioStream.
## Supports .mp3, .ogg, and .wav (PCM 8/16/24/32-bit and 32/64-bit float).
func load_audio_stream(file_path: String) -> AudioStream:
	var ext  := file_path.get_extension().to_lower()
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	match ext:
		"mp3":
			var stream := AudioStreamMP3.new()
			stream.data = bytes
			if stream.get_length() <= 0.0:
				return null
			return stream
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			return _parse_wav(bytes)
	return null


func wav_needs_conversion(file_path: String) -> bool:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return false
	var bytes := file.get_buffer(64)
	file.close()
	var offset := 12
	while offset + 8 <= bytes.size():
		var id   := (bytes[offset] << 24) | (bytes[offset+1] << 16) | (bytes[offset+2] << 8) | bytes[offset+3]
		var size := bytes[offset+4] | (bytes[offset+5] << 8) | (bytes[offset+6] << 16) | (bytes[offset+7] << 24)
		if id == 0x666D7420:  # "fmt "
			var bps := bytes[offset+22] | (bytes[offset+23] << 8)
			return bps != 16
		offset += 8 + size + (size & 1)
	return false


func _parse_wav(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44:
		return null
	# Verify RIFF/WAVE header
	var riff := (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
	var wave := (bytes[8] << 24) | (bytes[9] << 16) | (bytes[10] << 8) | bytes[11]
	if riff != 0x52494646 or wave != 0x57415645:  # "RIFF" / "WAVE"
		return null
	var audio_format    := 0
	var channels        := 0
	var sample_rate     := 0
	var bits_per_sample := 0
	var data_start      := 0
	var data_size       := 0
	var offset          := 12
	while offset + 8 <= bytes.size():
		var id   := (bytes[offset] << 24) | (bytes[offset+1] << 16) | (bytes[offset+2] << 8) | bytes[offset+3]
		var size := bytes[offset+4] | (bytes[offset+5] << 8) | (bytes[offset+6] << 16) | (bytes[offset+7] << 24)
		if id == 0x666D7420:  # "fmt "
			audio_format    = bytes[offset+8]  | (bytes[offset+9]  << 8)
			channels        = bytes[offset+10] | (bytes[offset+11] << 8)
			sample_rate     = bytes[offset+12] | (bytes[offset+13] << 8) | (bytes[offset+14] << 16) | (bytes[offset+15] << 24)
			bits_per_sample = bytes[offset+22] | (bytes[offset+23] << 8)
			# WAVE_FORMAT_EXTENSIBLE (0xFFFE): read actual subformat code from GUID bytes
			if audio_format == 0xFFFE and offset + 34 <= bytes.size():
				audio_format = bytes[offset+32] | (bytes[offset+33] << 8)
		elif id == 0x64617461:  # "data"
			data_start = offset + 8
			data_size  = size
			break
		offset += 8 + size + (size & 1)  # word-align
	# Support PCM (1) and IEEE 754 float (3)
	if data_start == 0 or (audio_format != 1 and audio_format != 3):
		return null
	var raw := bytes.slice(data_start, data_start + data_size)
	var stream := AudioStreamWAV.new()
	stream.stereo   = channels >= 2
	stream.mix_rate = sample_rate
	match bits_per_sample:
		8:
			# WAV 8-bit is unsigned (silence=128); Godot FORMAT_8_BITS expects signed (silence=0)
			stream.format = AudioStreamWAV.FORMAT_8_BITS
			var out := raw.duplicate()
			for i in out.size():
				out[i] ^= 0x80
			stream.data = out
		16:
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			stream.data   = raw
		24:
			# Downconvert to 16-bit: drop LSB, keep middle and high bytes
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			var n := raw.size() / 3
			var out := PackedByteArray()
			out.resize(n * 2)
			for i in n:
				out[i * 2]     = raw[i * 3 + 1]
				out[i * 2 + 1] = raw[i * 3 + 2]
			stream.data = out
		32:
			# Downconvert to 16-bit
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			var n := raw.size() / 4
			var out := PackedByteArray()
			out.resize(n * 2)
			if audio_format == 3:  # IEEE 754 float → int16
				for i in n:
					var s := clampi(int(raw.decode_float(i * 4) * 32767.0), -32768, 32767)
					if s < 0: s += 65536
					out[i * 2]     = s & 0xFF
					out[i * 2 + 1] = (s >> 8) & 0xFF
			else:  # 32-bit integer PCM: drop bottom 2 bytes
				for i in n:
					out[i * 2]     = raw[i * 4 + 2]
					out[i * 2 + 1] = raw[i * 4 + 3]
			stream.data = out
		64:
			# 64-bit float WAV → int16
			stream.format = AudioStreamWAV.FORMAT_16_BITS
			var n := raw.size() / 8
			var out := PackedByteArray()
			out.resize(n * 2)
			for i in n:
				var s := clampi(int(raw.decode_double(i * 8) * 32767.0), -32768, 32767)
				if s < 0: s += 65536
				out[i * 2]     = s & 0xFF
				out[i * 2 + 1] = (s >> 8) & 0xFF
			stream.data = out
		_:
			return null  # unsupported bit depth
	return stream


func timestamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	for section in t:
		if str(t[section]).length() < 2:
			t[section] = "0" + str(t[section])
	var year := str(t.year).right(2)
	return "%s_%s_%s - %s.%s.%s" % [t.month, t.day, year, t.hour, t.minute, t.second]


func set_config(section: String, key: String, value) -> void:
	config.load(config_path)
	config.set_value(section, key, value)
	config.save(config_path)


func load_config() -> void:
	config.load(config_path)
	
	if config.get_value('user', 'version', "") != '2.5':
		set_config('user', 'version', '2.5')
		bx.get_node('Menu/Version/Button/Notification').show()
		bx.get_node('Header/MenuButton').button_pressed = true
	
	if config.has_section_key('user', 'display_mode'):
		var display := bx.get_node('Menu/Options/DisplayMode')
		var mode    = config.get_value('user', 'display_mode')
		display._on_option_button_item_selected(mode)
		display.get_node('OptionButton').selected = mode
	
	if config.has_section_key('user', 'track'):
		var track_title: String = config.get_value('user', 'track')
		if FileAccess.file_exists(tracks_dir.path_join(track_title)):
			var track_selection := bx.get_node('Menu/Controls/Tracks/TrackSelection')
			for item in track_selection.item_count:
				if track_selection.get_item_text(item) == track_title:
					bx.get_node('Menu/Controls')._on_track_selected(item)
					track_selection.selected = item
					break
	
	var volume_slider := bx.get_node('Menu/Controls/Volume/Slider')
	volume_slider.value = config.get_value('user', 'volume', 60)
	volume_slider.value_changed.emit(volume_slider.value)
	
	if config.has_section_key('user', 'render_resolution:x'):
		var res_x_input = bx.get_node('Menu/Options/RenderResolution/Values/X')
		res_x_input.value = config.get_value('user', 'render_resolution:x')
	
	if config.has_section_key('user', 'render_resolution:y'):
		var res_y_input = bx.get_node('Menu/Options/RenderResolution/Values/Y')
		res_y_input.value = config.get_value('user', 'render_resolution:y')
	
	for direction in ['up', 'down']:
		if config.has_section_key('easings', direction):
			bx.get_node('MarkersMenu/HBox/Ease' + direction.capitalize()).selected = config.get_value('easings', direction)
	
	if config.has_section_key('easings', 'trans'):
		bx.get_node('MarkersMenu/HBox/Trans').selected = config.get_value('easings', 'trans')
	
	load_colors()
	_load_gamepad_bindings()


func _load_gamepad_bindings() -> void:
	const ACTIONS := [
		"record", "play", "menu", "go_to_start",
		"depth_0", "depth_1", "depth_2", "depth_3", "depth_4",
		"depth_5", "depth_6", "depth_7", "depth_8", "depth_9", "depth_10",
	]
	const DEFAULTS := {
		"record":      {"deadzone": 0.5, "events": [{"type": "button", "index": 11}, {"type": "button", "index": 4}]},
		"play":        {"deadzone": 0.5, "events": [{"type": "button", "index": 14}, {"type": "button", "index": 6}]},
		"menu":        {"deadzone": 0.5, "events": [{"type": "button", "index": 12}]},
		"go_to_start": {"deadzone": 0.5, "events": [{"type": "button", "index": 13}]},
		"depth_0":     {"deadzone": 0.1, "events": [{"type": "button", "index": 9},  {"type": "motion", "axis": 3, "value": 1.0}]},
		"depth_2":     {"deadzone": 0.1, "events": [{"type": "button", "index": 2},  {"type": "motion", "axis": 4, "value": 1.0}]},
		"depth_5":     {"deadzone": 0.1, "events": [{"type": "button", "index": 0},  {"type": "motion", "axis": 3, "value": -1.0}, {"type": "motion", "axis": 1, "value": 1.0}]},
		"depth_8":     {"deadzone": 0.1, "events": [{"type": "button", "index": 1},  {"type": "motion", "axis": 5, "value": 1.0}]},
		"depth_10":    {"deadzone": 0.1, "events": [{"type": "button", "index": 10}, {"type": "motion", "axis": 1, "value": -1.0}]},
	}
	if not config.has_section('gamepad'):
		for action in DEFAULTS:
			set_config('gamepad', action, DEFAULTS[action])
		config.load(config_path)
	for action in ACTIONS:
		if not config.has_section_key('gamepad', action):
			continue
		var saved = config.get_value('gamepad', action)
		if not saved:
			continue
		for old in InputMap.action_get_events(action):
			if old is InputEventJoypadButton or old is InputEventJoypadMotion:
				InputMap.action_erase_event(action, old)
		# New combined format: {"events": [...], "deadzone": float}
		# Old formats: Array of dicts, or single dict — events only, no deadzone
		var event_list: Array
		if saved is Dictionary and saved.has("events"):
			event_list = saved["events"]
			if saved.has("deadzone"):
				InputMap.action_set_deadzone(action, saved["deadzone"])
		elif saved is Array:
			event_list = saved
		else:
			event_list = [saved]
		for ev_data in event_list:
			var ev: InputEvent = null
			match ev_data.get("type", ""):
				"button":
					var b := InputEventJoypadButton.new()
					b.button_index = ev_data["index"]
					ev = b
				"motion":
					var m := InputEventJoypadMotion.new()
					m.axis       = ev_data["axis"]
					m.axis_value = ev_data["value"]
					ev = m
			if ev:
				InputMap.action_add_event(action, ev)
		# Fallback: load deadzone from old separate section if present
		if config.has_section_key('gamepad_deadzone', action):
			var dz = config.get_value('gamepad_deadzone', action)
			if dz != null:
				InputMap.action_set_deadzone(action, dz)


func check_migration() -> void:
	if not config.get_value('user', 'show_migration_popup', true):
		return
	var path_count   := _count_files_recursive("user://Paths", "bx")
	var render_count := _count_files_recursive("user://Renders", "")
	if path_count == 0 and render_count == 0:
		config.set_value('user', 'show_migration_popup', false)
		config.save(config_path)
		return
	
	var file_counts: Array[String]
	if path_count > 0:
		file_counts.append("%d path file%s" % [path_count, "s" if path_count != 1 else ""])
	if render_count > 0:
		file_counts.append("%d render file%s" % [render_count, "s" if render_count != 1 else ""])
	
	var dialog           := bx.get_node("MigrationDialog")
	var label            := dialog.get_node("VBox/Label")
	var paths_check      := dialog.get_node("VBox/ImportPathsCheckBox")
	var renders_check    := dialog.get_node("VBox/ImportRendersCheckBox")
	var delete_check     := dialog.get_node("VBox/DeleteCheckBox")
	var no_show_check    := dialog.get_node("VBox/DisplayCheckBox")
	var open_folder_btn  := dialog.get_node("VBox/OpenLegacyFolder")
	var progress_bar     := dialog.get_node("VBox/ProgressBar") as ProgressBar
	var status_label     := dialog.get_node("VBox/StatusLabel") as RichTextLabel
	
	var base_text:String = "Found %s from a previous version.\n\nImport to [b]Documents/BounceX[/b]?"
	label.text = base_text % ", ".join(file_counts)
	
	open_folder_btn.pressed.connect(func():
		OS.shell_open(ProjectSettings.globalize_path('user://'))
	)
	
	paths_check.pressed.connect(func():
		if paths_check.button_pressed or renders_check.button_pressed:
			dialog.get_ok_button().disabled = false
		else:
			dialog.get_ok_button().disabled = true
	)
	
	renders_check.pressed.connect(func():
		if paths_check.button_pressed or renders_check.button_pressed:
			dialog.get_ok_button().disabled = false
		else:
			dialog.get_ok_button().disabled = true
	)
	
	# Self-disconnecting so a second OK press (after "Done") doesn't re-trigger
	var on_confirmed:Callable = func():
		paths_check.disabled = true
		renders_check.disabled = true
		delete_check.disabled = true
		label.hide()
		no_show_check.hide()
		progress_bar.show()
		status_label.show()
		dialog.get_ok_button().disabled = true
		dialog.get_cancel_button().disabled = true
		progress_bar.max_value = \
			(path_count if paths_check.button_pressed else 0) + \
			(render_count if renders_check.button_pressed else 0)
		_run_migration_async(
				paths_check.button_pressed,
				renders_check.button_pressed,
				delete_check.button_pressed,
				dialog,
				progress_bar,
				status_label)
	dialog.confirmed.connect(on_confirmed, CONNECT_ONE_SHOT)
	
	dialog.canceled.connect(func():
		if no_show_check.button_pressed:
			config.set_value('user', 'show_migration_popup', false)
			config.save(config_path)
		dialog.queue_free()
	)
	
	dialog.popup_centered()

func _count_files_recursive(dir_path: String, extension: String) -> int:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return 0
	var count := 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			count += _count_files_recursive(dir_path.path_join(name), extension)
		elif not name.begins_with(".") and (extension == "" or name.get_extension() == extension):
			count += 1
		name = dir.get_next()
	dir.list_dir_end()
	return count


func _run_migration_async(
			import_paths: bool,
			import_renders: bool,
			delete_originals: bool,
			dialog: Node,
			progress_bar: ProgressBar,
			status_label: RichTextLabel) -> void:
	if import_paths:
		await _copy_dir_recursive_async("user://Paths", paths_dir, progress_bar, status_label)
	if import_renders:
		await _copy_dir_recursive_async("user://Renders", renders_dir, progress_bar, status_label)
	if delete_originals:
		progress_bar.value = 0
		status_label.text  = "Deleting originals..."
		await get_tree().process_frame
		await _delete_dir_recursive_async("user://Paths", progress_bar, status_label)
		await _delete_dir_recursive_async("user://Renders", progress_bar, status_label)
	config.set_value('user', 'show_migration_popup', false)
	config.save(config_path)
	if is_instance_valid(bx):
		bx.get_node("Menu/Controls").load_tracks()
	status_label.text = "Import complete!\nFiles are now in [b]Documents/BounceX[/b]"
	dialog.get_ok_button().text     = "Done"
	dialog.get_ok_button().disabled = false
	dialog.get_ok_button().pressed.connect(func(): dialog.hide(), CONNECT_ONE_SHOT)


func _copy_dir_recursive_async(
		src: String,
		dst: String,
		progress_bar: ProgressBar,
		status_label: RichTextLabel) -> void:
	var dir := DirAccess.open(src)
	if not dir:
		return
	DirAccess.make_dir_recursive_absolute(dst)
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var src_path := src.path_join(name)
			var dst_path := dst.path_join(name)
			if dir.current_is_dir():
				await _copy_dir_recursive_async(src_path, dst_path, progress_bar, status_label)
			else:
				var src_file := FileAccess.open(src_path, FileAccess.READ)
				var dst_file := FileAccess.open(dst_path, FileAccess.WRITE)
				if src_file and dst_file:
					dst_file.store_buffer(src_file.get_buffer(src_file.get_length()))
				if src_file: src_file.close()
				if dst_file: dst_file.close()
				progress_bar.value += 1
				status_label.text   = name
				await get_tree().process_frame
		name = dir.get_next()
	dir.list_dir_end()


func _delete_dir_recursive_async(dir_path: String, progress_bar: ProgressBar, status_label: RichTextLabel) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	
	var path_count   := _count_files_recursive("user://Paths", "bx")
	var render_count := _count_files_recursive("user://Renders", "")
	progress_bar.max_value = path_count + render_count
	
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var full := dir_path.path_join(name)
			if dir.current_is_dir():
				await _delete_dir_recursive_async(full, progress_bar, status_label)
			else:
				DirAccess.remove_absolute(full)
				progress_bar.value += 1
				status_label.text   = "Deleting: " + name
				await get_tree().process_frame
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


func load_colors() -> void:
	for setting in [
		'Ball', 'Path', 'Backdrop', 'Action Zone',
		'Top Line', 'Top Active',
		'Bottom Line', 'Bottom Active',
		'Hold Breath Ball', 'Hold Breath Path',
		'Markers', 'Hold Breath Markers']:
		if config.has_section_key('colors', setting):
			var color: Color = config.get_value('colors', setting)
			match setting:
				'Path':
					bx.get_node('Path').self_modulate = color
					bx.get_node('Markers/Line').self_modulate = color
				'Ball':              bx.get_node('Ball').self_modulate = color
				'Backdrop':          bx.get_node('Backdrop').self_modulate = color
				'Action Zone':       bx.get_node('ActionZone').self_modulate = color
				'Top Line':
					bx.top_color = color
					bx.get_node('TopLine').self_modulate = color
				'Top Active':        bx.top_color_active = color
				'Bottom Line':
					bx.bottom_color = color
					bx.get_node('BottomLine').self_modulate = color
				'Bottom Active':     bx.bottom_color_active = color
				'Hold Breath Ball':  bx.hold_breath_ball_color = color
				'Hold Breath Path':  bx.hold_breath_path_color = color
				'Markers':           bx.get_node('Markers').marker_color = color
				'Hold Breath Markers':
					bx.get_node('Markers').hold_breath_marker_color = color


func _exit_tree() -> void:
	flush_path_save()
