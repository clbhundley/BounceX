extends Panel

var positions: Array
var phase: int

func _ready():
	self_modulate.a = 1.6


func _on_bpm_value_changed(value):
	$Inputs/Interval/FrameInterval/SpinBox.value = 60 / (value / 60)


func _on_frame_interval_value_changed(value):
	$Inputs/Interval/BPM/SpinBox.value = 60 / (value / 60)


func _on_generate_pressed():
	var bpm = $Inputs/Interval/BPM/SpinBox.value
	var frame_interval: float = 3600.0 / bpm
	var length = $Inputs/Length/SpinBox.value
	var height = $Inputs/Positions/Height/SpinBox.value
	var depth = $Inputs/Positions/Depth/SpinBox.value
	var starting_frame: int = owner.frame
	var current_frame: int = starting_frame
	phase = $Inputs/StartingPosition/Positions/OptionButton.selected
	if $Inputs/StartingPosition/Flat/CheckBox.button_pressed:
		if phase == 0:
			positions = [height, height]
		elif phase == 1:
			positions = [depth, depth]
	else:
		positions = [height, depth]
	create_marker(current_frame, positions[phase])
	var accumulator: float = 0.0
	for i in length - 1:
		accumulator += frame_interval
		current_frame = starting_frame + roundi(accumulator)
		create_marker(current_frame, positions[phase])
	owner.input_disabled = false
	owner.save_path()
	hide()


func create_marker(frame: int, depth):
	phase = abs(phase - 1)
	if frame >= owner.path.size():
		return
	var min_frames:int = %Markers.SEPARATION_MIN
	for i in range(frame - min_frames + 1, frame + min_frames + 1):
		if owner.marker_data.has(i):
			return
	var trans = %MarkersMenu/HBox/Trans.selected
	var ease
	if phase == 0:
		ease = %MarkersMenu/HBox/EaseDown.selected
	elif phase == 1:
		ease = %MarkersMenu/HBox/EaseUp.selected
	owner.marker_data[frame] = [depth, trans, ease, 0]
	%Markers.add_marker(frame, depth, trans, ease)
	%Markers.connect_marker(frame)


func _on_cancel_pressed():
	owner.input_disabled = false
	hide()
