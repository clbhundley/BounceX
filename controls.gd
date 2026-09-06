extends VBoxContainer

## Retains the shape of a funscript while dropping the sampling noise left
## behind by tracing curves out of linear steps.
const DEFAULT_SMOOTHING := 0.12

var last_path_index: int = -1
var _pending_file_dialog: FileDialog = null
var _video_scrub_timer: Timer
var _video_scrub_pending: float = -1.0


func _ready() -> void:
	_video_scrub_timer = Timer.new()
	_video_scrub_timer.wait_time = 0.06
	_video_scrub_timer.one_shot = true
	_video_scrub_timer.timeout.connect(_on_video_scrub_timeout)
	add_child(_video_scrub_timer)
	load_tracks()
	$Tracks/TrackSelection.get_popup().window_input.connect(_on_track_popup_input)
	get_window().files_dropped.connect(_on_files_dropped)


func _on_track_popup_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_RIGHT or not event.pressed:
		return
	var popup = $Tracks/TrackSelection.get_popup()
	var idx = popup.get_focused_item()
	if idx < 0:
		return
	var track_name = popup.get_item_text(idx)
	popup.hide()
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete Track"
	dialog.ok_button_text = " Delete "
	dialog.cancel_button_text = " Cancel "
	dialog.dialog_text = "Delete \"%s\"?\n\nThe audio file will be removed from your Tracks folder.\n\nPath files and renders for this track will be kept." % track_name
	add_child(dialog)
	dialog.confirmed.connect(func():
		var was_selected = $Tracks/TrackSelection.selected >= 0 \
			and $Tracks/TrackSelection.get_item_text($Tracks/TrackSelection.selected) == track_name
		DirAccess.remove_absolute(Data.tracks_dir.path_join(track_name))
		load_tracks()
		if was_selected:
			$AudioStreamPlayer.stream = null
			%VideoStreamPlayer.stream = null
			%VideoStreamPlayer.hide()
			owner.is_video_track = false
			$TrackControls/Play.button_pressed = false
			$TrackControls/Play.disabled = true
			$TrackControls/Play/Icon.self_modulate.a = 0.5
			$Record.disabled = true
			for slider in [$TrackSlider, %TrackSliderLarge]:
				slider.editable = false
			unload_all()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2(600,200))


func _physics_process(_delta: float) -> void:
	var is_playing: bool
	var playback_pos: float
	var track_length: float
	if owner.is_video_track:
		is_playing = %VideoStreamPlayer.is_playing()
		playback_pos = %VideoStreamPlayer.stream_position
		track_length = %VideoStreamPlayer.get_stream_length()
	else:
		is_playing = $AudioStreamPlayer.is_playing()
		var wv := get_tree().get_first_node_in_group("WaveformView")
		if wv:
			track_length = wv.get_track_duration()
		elif $AudioStreamPlayer.stream:
			track_length = $AudioStreamPlayer.stream.get_length()
		else:
			return
		var seek_offset: float = wv.get_seek_offset() if wv else 0.0
		playback_pos = $AudioStreamPlayer.get_playback_position() + seek_offset
	if is_playing:
		var seconds := str(int(playback_pos) % 60).lpad(2, "0")
		var minutes := str(int(playback_pos) / 60).lpad(2, "0")
		%TrackSliderLarge.get_node('TrackTime').text = minutes + ":" + seconds
		update_marker_menu()
		if _video_scrub_pending < 0.0:
			for slider:HSlider in [$TrackSlider, %TrackSliderLarge]:
				slider.set_value_no_signal(playback_pos / track_length)


func scrub(value: float) -> void:
	if not owner._has_track_loaded():
		return
	for bar in [$TrackSlider, %TrackSliderLarge]:
		if bar.value != value:
			bar.value = value
	var track_duration: float
	if owner.is_video_track:
		track_duration = %VideoStreamPlayer.get_stream_length()
		var pos := maxf(track_duration * value, 0.05)
		_video_scrub_pending = pos
		_video_scrub_timer.start()
	else:
		var wv := get_tree().get_first_node_in_group("WaveformView")
		if wv:
			wv.seek_audio(value)
			track_duration = wv.get_track_duration()
		elif $AudioStreamPlayer.stream:
			track_duration = $AudioStreamPlayer.stream.get_length()
			var pos := track_duration * value
			if not $AudioStreamPlayer.playing:
				$AudioStreamPlayer.play(pos)
				$AudioStreamPlayer.stream_paused = true
			elif $AudioStreamPlayer.stream_paused:
				$AudioStreamPlayer.stream_paused = false
				$AudioStreamPlayer.seek(pos)
				$AudioStreamPlayer.stream_paused = true
			else:
				$AudioStreamPlayer.seek(pos)
	owner.frame = round((owner.path.size() - 1) * value)
	update_marker_menu()
	%Markers.position_markers()
	var stream_position := track_duration * value
	var seconds := str(int(stream_position) % 60).lpad(2, "0")
	var minutes := str(int(stream_position) / 60).lpad(2, "0")
	%TrackSliderLarge.get_node('TrackTime').text = minutes + ":" + seconds
	if sign(owner.path[owner.frame]) > -1:
		owner.place_ball(owner.path[owner.frame])
	elif $Paths.is_anything_selected():
		owner.toggle_ball_visible(false)


func video_seek_debounced(pos: float) -> void:
	_video_scrub_pending = pos
	_video_scrub_timer.start()


func _on_video_scrub_timeout() -> void:
	if _video_scrub_pending < 0.0:
		return
	var pos := _video_scrub_pending
	_video_scrub_pending = -1.0
	if not %VideoStreamPlayer.is_playing():
		%VideoStreamPlayer.play()
		%VideoStreamPlayer.set_stream_position(pos)
		%VideoStreamPlayer.paused = true
	elif %VideoStreamPlayer.paused:
		%VideoStreamPlayer.paused = false
		%VideoStreamPlayer.set_stream_position(pos)
		%VideoStreamPlayer.paused = true
	else:
		%VideoStreamPlayer.set_stream_position(pos)
	# Re-sync frame to where the video actually landed, but only for large jumps
	# (slider drags). Small scrubs (mouse wheel) already set frame correctly in
	# frame_scrub() — re-syncing those causes snap-back because the FFmpeg skip
	# loop lands 1 frame before the target.
	var stream_len: float = %VideoStreamPlayer.get_stream_length()
	if stream_len > 0.0 and owner.path.size() > 10:
		var t: float = %VideoStreamPlayer.stream_position / stream_len
		var video_frame := clampi(int(t * (owner.path.size() - 1)), 0, owner.path.size() - 10)
		if abs(owner.frame - video_frame) > 5:
			owner.frame = video_frame
			%Markers.position_markers()
		owner._video_resync = 20


func update_marker_menu() -> void:
	if not %Markers.selected_marker:
		%MarkersMenu/HBox/Frame/Input.value = owner.frame


func _on_volume_slider_value_changed(value: float) -> void:
	$Volume/Label.text = "Volume: %s" % int(value) + "%"
	var db := linear_to_db(value / 100.0) if value > 0.0 else -80.0
	$AudioStreamPlayer.volume_db = db
	%VideoStreamPlayer.volume_db = db
	Data.set_config('user', 'volume', value)


func _on_track_selection_toggled(button_pressed: bool) -> void:
	if button_pressed:
		load_tracks()


func load_tracks() -> void:
	var dir := DirAccess.open(Data.tracks_dir)
	var sel := $Tracks/TrackSelection
	var selected_name:String = sel.get_item_text(sel.selected) if sel.selected >= 0 else ""
	sel.clear()
	if not dir:
		return
	var files: PackedStringArray
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var ext := file_name.get_extension().to_lower()
		if ext in ["mp3", "wav", "ogg"] or ext in Data.VIDEO_EXTENSIONS:
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()
	for f in files:
		sel.add_item(f)
	for i in sel.item_count:
		if sel.get_item_text(i) == selected_name:
			sel.selected = i
			return
	sel.selected = -1
	$Paths.clear()
	_hide_waveforms()


func _on_track_selected(index: int) -> void:
	var track_name = $Tracks/TrackSelection.get_item_text(index)
	var file_path:String = Data.tracks_dir.path_join(track_name)
	if Data.is_video_file(file_path):
		owner.is_video_track = true
		$AudioStreamPlayer.stream = null
		if not %VideoStreamPlayer.load_video(file_path):
			owner.is_video_track = false
			%VideoStreamPlayer.stream = null
			_show_decode_error(track_name)
			return
		%VideoStreamPlayer.show()
		var pcm := FFmpegVideoStream.extract_audio(file_path)
		if pcm.size() > 0:
			var audio := AudioStreamWAV.new()
			audio.format = AudioStreamWAV.FORMAT_16_BITS
			audio.stereo = true
			audio.mix_rate = 44100
			audio.data = pcm
			$AudioStreamPlayer.stream = audio
			_show_waveforms()
		else:
			_hide_waveforms()
	else:
		owner.is_video_track = false
		var stream = Data.load_audio_stream(file_path)
		if not stream:
			_show_decode_error(track_name)
			return
		$AudioStreamPlayer.stream = stream
		%VideoStreamPlayer.stream = null
		%VideoStreamPlayer.hide()
		_show_waveforms()
	var wv := get_tree().get_first_node_in_group("WaveformView")
	if wv:
		wv.invalidate_duration()
	for slider in [$TrackSlider, %TrackSliderLarge]:
		slider.editable = true
	if not Data.config.get_value('waveform', 'static_active', true):
		%TrackSliderLarge.show()
	$TrackControls/Play.button_pressed = false
	$TrackControls/Play.disabled = false
	$TrackControls/Play/Icon.self_modulate.a = 1
	$Record.disabled = false
	DirAccess.make_dir_recursive_absolute(Data.paths_dir.path_join(track_name))
	load_paths(track_name)
	Data.set_config('user', 'track', track_name)
	owner.frame = 0
	owner.define_path()
	scrub(0)


func load_paths(track_title: String, do_scrub := false) -> void:
	var dir  := DirAccess.open(Data.paths_dir.path_join(track_title))
	var list: PackedStringArray
	$Render.disabled = true
	$Paths.clear()
	%Markers.selected_multi_markers.clear()
	unload_all(do_scrub)
	last_path_index = -1
	if not dir:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		list.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	list.reverse()
	for title in list:
		if title.ends_with('.bx'):
			$Paths.add_item(title.trim_suffix('.bx'))


func _on_path_selected(index: int) -> void:
	if %Markers.selected_marker and is_instance_valid(%Markers.selected_marker):
		%Markers.marker_toggled(false, %Markers.selected_marker)
	if index == last_path_index:
		unload_all()
		owner.marker_data[0] = [0, 0, 0, 0]
		%Markers.add_marker(0, 0)
		last_path_index = -1
	else:
		for line in get_tree().get_nodes_in_group('lines'):
			line.queue_free()
		last_path_index = index
		$Render.disabled = false
		owner.set_ball_hidden(false)
		Data.load_path(Data.get_file_path())
		var path_value = owner.path[owner.frame]
		if path_value > -1:
			owner.place_ball(path_value)


func unload_all(do_scrub := false) -> void:
	$Paths.deselect_all()
	$Render.disabled = true
	owner.define_path(false)
	owner.marker_data.clear()
	%Markers.clear_markers()
	for line in get_tree().get_nodes_in_group('lines'):
		line.queue_free()
	if do_scrub:
		scrub(0)
		owner.place_marker(0)


func _on_paths_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if index == last_path_index and mouse_button_index == 2:
		var track_title = $Tracks/TrackSelection.get_item_text($Tracks/TrackSelection.selected)
		$Paths/EditPathFile.track_title = track_title
		$Paths/EditPathFile.path_name = $Paths.get_item_text(index)
		$Paths/EditPathFile/VBox/FileName/Input.text = $Paths.get_item_text(index)
		$Paths/EditPathFile/VBox/PathCreator/Input.text = owner.path_meta.get("path_creator", "")
		$Paths/EditPathFile/VBox/RelatedMedia/Input.text = owner.path_meta.get("related_media", "")
		$Paths/EditPathFile.popup_centered()


# ── Track file importer ───────────────────────────────────────────────────────

## A track is what gives a path its length and somewhere to be saved, so making
## one out of silence is how a path gets built with no media to build against.
func _on_load_tracks_pressed() -> void:
	if _pending_file_dialog:
		return
	var dialog := ConfirmationDialog.new()
	dialog.theme = load("res://theme_basic.tres")
	dialog.title = "Add Track"
	dialog.ok_button_text = "  Create Blank  "
	dialog.cancel_button_text = "  Cancel  "
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override('separation', 10)
	dialog.add_child(vbox)
	
	var blurb := Label.new()
	blurb.text = "A blank track is silence of a chosen length,\nfor building a path without any media."
	vbox.add_child(blurb)
	
	var name_box := HBoxContainer.new()
	name_box.add_theme_constant_override('separation', 20)
	var name_label := Label.new()
	name_label.text = "Name:"
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_box.add_child(name_label)
	var name_input := LineEdit.new()
	name_input.custom_minimum_size.x = 220
	name_input.text = "Blank"
	name_box.add_child(name_input)
	vbox.add_child(name_box)
	
	var length_box := HBoxContainer.new()
	length_box.add_theme_constant_override('separation', 20)
	var length_label := Label.new()
	length_label.text = "Length:"
	length_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	length_box.add_child(length_label)
	var length_input := SpinBox.new()
	length_input.custom_minimum_size.x = 100
	length_input.min_value = 1.0
	length_input.max_value = 480.0
	length_input.value = 60.0
	length_input.suffix = "min"
	length_box.add_child(length_input)
	vbox.add_child(length_box)
	
	dialog.add_button("  Load Files  ", true, "load")
	dialog.custom_action.connect(func(action: StringName) -> void:
		dialog.queue_free()
		if action == &"load":
			_open_track_file_dialog())
	dialog.confirmed.connect(func() -> void:
		_create_blank_track(name_input.text, length_input.value * 60.0)
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
	name_input.grab_focus()
	name_input.select_all()


func _create_blank_track(track_name: String, seconds: float) -> void:
	var file_path: String = Data.create_blank_track(track_name, seconds)
	if file_path == "":
		_show_notice("Could not write the blank track.")
		return
	load_tracks()
	_select_track_by_name(file_path.get_file())


func _open_track_file_dialog() -> void:
	if _pending_file_dialog:
		return
	_pending_file_dialog = FileDialog.new()
	_pending_file_dialog.min_size = Vector2(300, 500)
	_pending_file_dialog.theme = load("res://theme_basic.tres")
	_pending_file_dialog.set('theme_override_constants/thumbnail_size', 40)
	_pending_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_pending_file_dialog.access    = FileDialog.ACCESS_FILESYSTEM
	var video_globs := ",".join(Data.VIDEO_EXTENSIONS.map(func(e): return "*." + e))
	_pending_file_dialog.filters   = PackedStringArray([
		"*.mp3,*.wav,*.ogg," + video_globs + " ; Audio & Video Files",
		"*.mp3,*.wav,*.ogg ; Audio Files",
		video_globs + " ; Video Files",
	])
	_pending_file_dialog.use_native_dialog = true
	add_child(_pending_file_dialog)
	var prev_file_path = Data.config.get_value('user', 'load_file_path', "")
	if prev_file_path != "" and DirAccess.dir_exists_absolute(prev_file_path):
		_pending_file_dialog.current_dir = prev_file_path
	else:
		_pending_file_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	_pending_file_dialog.files_selected.connect(_on_track_files_selected)
	_pending_file_dialog.canceled.connect(_dismiss_file_dialog)
	_pending_file_dialog.popup_centered(Vector2i(800, 500))


func _dismiss_file_dialog() -> void:
	if _pending_file_dialog:
		_pending_file_dialog.queue_free()
		_pending_file_dialog = null


func _on_files_dropped(paths: PackedStringArray) -> void:
	var valid_exts:Array = ["mp3", "wav", "ogg"] + Data.VIDEO_EXTENSIONS
	var tracks: PackedStringArray
	var path_files: PackedStringArray
	var marker_images: PackedStringArray
	for p in paths:
		var ext := p.get_extension().to_lower()
		if ext in valid_exts:
			tracks.append(p)
		elif ext == "bx" or ext == "funscript":
			path_files.append(p)
		elif Data.is_marker_image(p):
			marker_images.append(p)
	if not tracks.is_empty():
		_on_track_files_selected(tracks)
	if not path_files.is_empty():
		_on_path_files_dropped(path_files)
	if not marker_images.is_empty():
		_on_marker_images_dropped(marker_images)


## Marker images only mean anything where markers are what is being read, so
## they are taken while classic mode is on and turned away otherwise.
func _on_marker_images_dropped(source_paths: PackedStringArray) -> void:
	if not owner.classic_mode:
		_show_notice("Marker images are only used in classic mode.")
		return
	DirAccess.make_dir_recursive_absolute(Data.markers_dir)
	var last_name := ""
	for source_path in source_paths:
		var file_name := source_path.get_file()
		var dest_path: String = Data.markers_dir.path_join(file_name)
		if not FileAccess.file_exists(dest_path) \
				or FileAccess.get_md5(source_path) != FileAccess.get_md5(dest_path):
			var base := file_name.get_basename()
			var ext := "." + file_name.get_extension()
			var n := 2
			while FileAccess.file_exists(dest_path) \
					and FileAccess.get_md5(source_path) != FileAccess.get_md5(dest_path):
				file_name = "%s (%d)%s" % [base, n, ext]
				dest_path = Data.markers_dir.path_join(file_name)
				n += 1
			var source := FileAccess.open(source_path, FileAccess.READ)
			var dest := FileAccess.open(dest_path, FileAccess.WRITE)
			if not source or not dest:
				_show_notice("Could not copy that marker image.")
				continue
			dest.store_buffer(source.get_buffer(source.get_length()))
			source.close()
			dest.close()
		last_name = file_name
	if last_name != "":
		%Options.select_marker_image(last_name)


func _on_track_files_selected(source_paths: PackedStringArray) -> void:
	_dismiss_file_dialog()
	var last_name := ""
	
	for source_path in source_paths:
		var file_name  := source_path.get_file()
		var dest_path:String = Data.tracks_dir.path_join(file_name)
		var final_name := file_name
		
		if FileAccess.file_exists(dest_path):
			if FileAccess.get_md5(source_path) == FileAccess.get_md5(dest_path):
				last_name = file_name
				continue
			var base := file_name.get_basename()
			var ext  := "." + file_name.get_extension()
			var n    := 2
			while FileAccess.file_exists(Data.tracks_dir.path_join("%s (%d)%s" % [base, n, ext])):
				n += 1
			final_name = "%s (%d)%s" % [base, n, ext]
			dest_path  = Data.tracks_dir.path_join(final_name)
		
		var src := FileAccess.open(source_path, FileAccess.READ)
		var dst := FileAccess.open(dest_path, FileAccess.WRITE)
		if src and dst:
			dst.store_buffer(src.get_buffer(src.get_length()))
		if src: src.close()
		if dst: dst.close()
		
		last_name = final_name
		if final_name != file_name:
			_show_import_notification(file_name, final_name)
	
	if last_name != "":
		load_tracks()
		_select_track_by_name(last_name)
		Data.set_config('user', 'load_file_path', source_paths[0].get_base_dir())
		var has_mp3 := false
		var has_ogg := false
		var has_wav_conversion := false
		for source_path in source_paths:
			var ext := source_path.get_extension().to_lower()
			if ext   == "mp3": has_mp3 = true
			elif ext == "ogg": has_ogg = true
			elif ext == "wav" and Data.wav_needs_conversion(source_path): has_wav_conversion = true
		var comp_shown := _show_compression_notice(has_mp3, has_ogg)
		var wav_shown  := _show_wav_conversion_notice() if has_wav_conversion else false
		if comp_shown and wav_shown:
			$Tracks/LoadTracks/ConversionNotice.position.x  += 220
			$Tracks/LoadTracks/CompressionNotice.position.x -= 220


func _select_track_by_name(name: String) -> void:
	for i in $Tracks/TrackSelection.item_count:
		if $Tracks/TrackSelection.get_item_text(i) == name:
			$Tracks/TrackSelection.selected = i
			_on_track_selected(i)
			return


func _show_decode_error(file_name: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title       = "Failed to Load Track"
	dialog.dialog_text = "\"%s\" could not be decoded.\n\nThe file may be corrupted or in an unsupported format." % file_name
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func _show_import_notification(original: String, imported_as: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title       = "Track Imported"
	dialog.dialog_text = "\"%s\" already exists with different content.\nImported as: \"%s\"" % [original, imported_as]
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func _show_wav_conversion_notice() -> bool:
	if not Data.config.get_value('user', 'display_wav_notification', true):
		return false
	var notice: AcceptDialog = $Tracks/LoadTracks/ConversionNotice
	var notice_label: Label  = $Tracks/LoadTracks/ConversionNotice/VBox/Label
	var checkbox: CheckBox   = $Tracks/LoadTracks/ConversionNotice/VBox/DoNotShowCheckBox
	checkbox.button_pressed = false
	notice.title      = "WAV Conversion Notice"
	notice_label.text = "WAV encodings other than 16-bit PCM require\nconversion when loading.\n\nIf you want to avoid the extra loading time,\nsave your file with 16-bit PCM encoding."
	notice.confirmed.connect(func():
		if checkbox.button_pressed:
			Data.set_config('user', 'display_wav_notification', false), CONNECT_ONE_SHOT)
	notice.popup_centered()
	return true


func _show_compression_notice(has_mp3: bool, has_ogg: bool) -> bool:
	if not Data.config.get_value('user', 'display_mp3_notification', true):
		has_mp3 = false
	if not Data.config.get_value('user', 'display_ogg_notification', true):
		has_ogg = false
	if not has_mp3 and not has_ogg:
		return false
	var notice: AcceptDialog = $Tracks/LoadTracks/CompressionNotice
	var notice_label: Label  = $Tracks/LoadTracks/CompressionNotice/VBox/Label
	var checkbox: CheckBox   = $Tracks/LoadTracks/CompressionNotice/VBox/DoNotShowCheckBox
	checkbox.button_pressed = false
	if has_mp3 and has_ogg:
		notice.title      = "Compressed Audio Notice"
		notice_label.text = "Compressed audio files require more\nresources than uncompressed WAV files.\n\nMP3 files can experience slow waveform\nloading and lag when scrubbing through\nlonger tracks, and OGG files can\nexperience slow waveform loading.\n\nConsider converting your tracks to a\n16-bit PCM WAV format for instant\nloading and smooth performance."
		notice.size.y     = 415
	elif has_mp3:
		notice.title      = "MP3 Performance Notice"
		notice_label.text = "Compressed MP3 files require more\nresources than uncompressed WAV files.\n\nIf you experience slow waveform loading\nor lag when scrubbing through longer tracks,\nconsider converting to a 16-bit PCM WAV\nformat for instant loading and\nsmooth performance."
		notice.size.y     = 330
	else:
		notice.title      = "OGG Performance Notice"
		notice_label.text = "Compressed OGG files require additional\ntime to load the waveform display.\n\nFor instant waveform loading, consider\nconverting to a 16-bit PCM WAV format."
		notice.size.y     = 250
	notice.confirmed.connect(func():
		if checkbox.button_pressed:
			if has_mp3: Data.set_config('user', 'display_mp3_notification', false)
			if has_ogg: Data.set_config('user', 'display_ogg_notification', false),
			CONNECT_ONE_SHOT)
	notice.popup_centered()
	return true


func _hide_waveforms() -> void:
	owner.get_node("WaveformStatic").hide()
	owner.get_node("WaveformScrolling").hide()
	%TrackSliderLarge.show()


func _show_waveforms() -> void:
	if Data.config.get_value('waveform', 'static_active', true):
		owner.get_node("WaveformStatic").show()
		%TrackSliderLarge.hide()
	if Data.config.get_value('waveform', 'scroll_active', true):
		owner.get_node("WaveformScrolling").show()


# ── Path file importer ────────────────────────────────────────────────────────

func _on_path_files_dropped(source_paths: PackedStringArray) -> void:
	var track_selection: OptionButton = $Tracks/TrackSelection
	if track_selection.selected == -1:
		_show_notice("Select a track before importing paths.")
		return
	var track_title: String = track_selection.get_item_text(track_selection.selected)
	var funscripts: PackedStringArray
	var imported := 0
	for source_path in source_paths:
		if source_path.get_extension().to_lower() == "funscript":
			funscripts.append(source_path)
		elif _copy_path_file(source_path, track_title) != "":
			imported += 1
	if imported:
		load_paths(track_title)
	if not funscripts.is_empty():
		_show_funscript_import(funscripts[0], track_title)


func _copy_path_file(source_path: String, track_title: String) -> String:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if not source:
		return ""
	var contents := source.get_buffer(source.get_length())
	source.close()
	var dest_path := _unique_path_file(track_title, source_path.get_file().get_basename())
	var dest := FileAccess.open(dest_path, FileAccess.WRITE)
	if not dest:
		return ""
	dest.store_buffer(contents)
	dest.close()
	return dest_path


func _unique_path_file(track_title: String, base_name: String) -> String:
	var dir_path: String = Data.paths_dir.path_join(track_title)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file_name := base_name
	var n := 2
	while FileAccess.file_exists(dir_path.path_join(file_name + ".bx")):
		file_name = "%s (%d)" % [base_name, n]
		n += 1
	return dir_path.path_join(file_name + ".bx")


func _show_funscript_import(source_path: String, track_title: String) -> void:
	var file := FileAccess.open(source_path, FileAccess.READ)
	if not file:
		_show_notice("Could not read that funscript.")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("actions") is Array:
		_show_notice("That file is not a valid funscript.")
		return
	
	var dialog := ConfirmationDialog.new()
	dialog.theme = load("res://theme_basic.tres")
	dialog.title = "Import Funscript"
	dialog.ok_button_text = "  Import  "
	dialog.cancel_button_text = "  Cancel  "
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override('separation', 10)
	dialog.add_child(vbox)
	
	var separation_min: int = %Markers.SEPARATION_MIN
	var max_frame: int = owner.path.size()
	var track_seconds: float = max_frame / 60.0
	var first_at := INF
	var last_at := 0.0
	for action in parsed["actions"]:
		if action is Dictionary and action.has("at"):
			first_at = minf(first_at, float(action["at"]))
			last_at = maxf(last_at, float(action["at"]))
	if first_at == INF:
		first_at = 0.0
	
	var source_label := Label.new()
	vbox.add_child(source_label)
	
	# Where the funscript's own beginning is placed on this track. It starts
	# where the funscript says, so importing without touching it keeps the times
	# the script was written with.
	var start_box := HBoxContainer.new()
	start_box.add_theme_constant_override('separation', 20)
	var start_label := Label.new()
	start_label.text = "Start at:"
	start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	start_box.add_child(start_label)
	var start_input := SpinBox.new()
	start_input.custom_minimum_size.x = 100
	start_input.min_value = 0.0
	start_input.max_value = maxf(track_seconds, 0.0)
	start_input.step = 0.01
	start_input.suffix = "s"
	start_input.value = clampf(first_at / 1000.0, 0.0, maxf(track_seconds, 0.0))
	start_box.add_child(start_input)
	vbox.add_child(start_box)
	
	var threshold_box := HBoxContainer.new()
	threshold_box.add_theme_constant_override('separation', 20)
	var threshold_label := Label.new()
	threshold_label.text = "Smoothing:"
	threshold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	threshold_box.add_child(threshold_label)
	var threshold_input := SpinBox.new()
	threshold_input.min_value = 0.0
	threshold_input.max_value = 0.5
	threshold_input.step = 0.01
	threshold_input.value = DEFAULT_SMOOTHING
	threshold_box.add_child(threshold_input)
	vbox.add_child(threshold_box)
	
	var preview := Label.new()
	vbox.add_child(preview)
	
	# Lambdas capture locals by value, so the preview mutates this dictionary
	# in place rather than reassigning it, keeping the confirm handler in sync.
	var markers := {}
	var refresh := func(_value := 0.0) -> void:
		var offset: float = start_input.value * 1000.0 - first_at
		markers.clear()
		markers.merge(Funscript.to_marker_data(
			parsed, threshold_input.value, separation_min, max_frame, offset))
		var span: float = (last_at - first_at) / 1000.0
		source_label.text = "%s\n%d actions  ·  %s - %s\nTrack length: %s" % [
			source_path.get_file(),
			parsed["actions"].size(),
			_format_time(start_input.value),
			_format_time(start_input.value + span),
			_format_time(track_seconds)]
		preview.text = "%d actions  ->  %d markers" % [
			parsed["actions"].size(), markers.size()]
		var beyond := 0
		for action in parsed["actions"]:
			if action is Dictionary and action.has("at") \
					and roundi((float(action["at"]) + offset) * 60.0 / 1000.0) >= max_frame:
				beyond += 1
		if beyond:
			preview.text += "\n%d actions land past the end of the track." % beyond
	start_input.value_changed.connect(refresh)
	threshold_input.value_changed.connect(refresh)
	refresh.call()
	
	dialog.confirmed.connect(func() -> void:
		_write_imported_path(
			source_path, track_title, markers, Funscript.source_meta(parsed))
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _write_imported_path(
		source_path: String,
		track_title: String,
		markers: Dictionary,
		source_meta: Dictionary) -> void:
	if markers.is_empty():
		_show_notice("That funscript produced no markers.")
		return
	var dest_path := _unique_path_file(
		track_title, source_path.get_file().get_basename())
	var data := {
		"meta": {
			"version": 2.0,
			"marker_fields": ["depth", "trans", "ease", "auxiliary"],
			"related_media": track_title.get_basename(),
		},
		"markers": markers,
		"funscript_source": source_meta,
	}
	var file := FileAccess.open(dest_path, FileAccess.WRITE)
	if not file:
		_show_notice("Could not write the imported path.")
		return
	file.store_line(JSON.stringify(data))
	file.close()
	load_paths(track_title)
	var path_name := dest_path.get_file().get_basename()
	for i in $Paths.item_count:
		if $Paths.get_item_text(i) == path_name:
			$Paths.select(i)
			_on_path_selected(i)
			break


func _show_notice(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.theme = load("res://theme_basic.tres")
	dialog.ok_button_text = "  OK  "
	dialog.dialog_text = message
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]
