extends Panel

const FRAMES_PER_MINUTE := 60.0 * 60.0

var positions: Array
var phase: int

var interval_frames: float

@onready var bpm_input = $Inputs/Interval/BPM/SpinBox
@onready var frame_interval_input = $Inputs/Interval/FrameInterval/SpinBox

func _ready():
	self_modulate.a = 1.33
	interval_frames = FRAMES_PER_MINUTE / bpm_input.value


func _on_bpm_value_changed(value):
	interval_frames = FRAMES_PER_MINUTE / value
	frame_interval_input.set_value_no_signal(interval_frames)


func _on_frame_interval_value_changed(value):
	interval_frames = value
	bpm_input.set_value_no_signal(FRAMES_PER_MINUTE / value)


func _on_generate_pressed():
	var length: int = int($Inputs/Length/SpinBox.value)
	var height = $Inputs/Positions/Height/SpinBox.value
	var depth = $Inputs/Positions/Depth/SpinBox.value
	var starting_frame: int = owner.frame
	phase = $Inputs/StartingPosition/Positions/OptionButton.selected
	if $Inputs/StartingPosition/FlatCheckBox.button_pressed:
		if phase == 0:
			positions = [height, height]
		elif phase == 1:
			positions = [depth, depth]
	else:
		positions = [height, depth]
	create_marker(starting_frame, positions[phase])
	for i in range(1, length):
		var current_frame: int = starting_frame + roundi(interval_frames * i)
		create_marker(current_frame, positions[phase])
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
