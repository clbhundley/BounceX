extends AcceptDialog

var _top_line_color: Color
var _bottom_line_color: Color


func _ready() -> void:
	var basic_theme := load("res://theme_basic.tres")
	for picker in find_children("ColorPicker", "ColorPickerButton"):
		picker.get_picker().theme = basic_theme
		picker.get_child(0, true).get_child(0, true).self_modulate.a = 2
		picker.color_changed.connect(_on_color_changed.bind(picker.get_parent().name))
	$VBox/TopLine/TopLineActive/ColorPicker.popup_closed.connect(_restore_line_colors)
	$VBox/BottomLine/BottomLineActive/ColorPicker.popup_closed.connect(_restore_line_colors)
	about_to_popup.connect(_init_colors)


## Classic mode draws neither the ball nor the path, and draws a zone that the
## other mode does not, so the dialog offers what is actually on screen.
func _match_mode() -> void:
	var classic: bool = owner.classic_mode
	$VBox/Ball.visible = not classic
	$VBox/Path.visible = not classic
	$VBox/ActionZone.visible = classic
	$VBox/Markers.visible = classic


func _init_colors() -> void:
	_match_mode()
	_top_line_color = owner.get_node("TopLine").self_modulate
	_bottom_line_color = owner.get_node("BottomLine").self_modulate
	$VBox/Backdrop/ColorPicker.color = owner.get_node("Backdrop").self_modulate
	$VBox/ActionZone/ColorPicker.color = owner.get_node("ActionZone").self_modulate
	$VBox/Markers/MarkerBase/ColorPicker.color = %Markers.marker_color
	$VBox/Markers/MarkerHoldBreath/ColorPicker.color = %Markers.hold_breath_marker_color
	$VBox/Ball/BallBase/ColorPicker.color = owner.get_node("Ball").self_modulate
	$VBox/Ball/BallHoldBreath/ColorPicker.color = owner.hold_breath_ball_color
	$VBox/Path/PathBase/ColorPicker.color = owner.get_node("Path").self_modulate
	$VBox/Path/PathHoldBreath/ColorPicker.color = owner.hold_breath_path_color
	$VBox/TopLine/TopLineBase/ColorPicker.color = owner.top_color
	$VBox/TopLine/TopLineActive/ColorPicker.color = owner.top_color_active
	$VBox/BottomLine/BottomLineBase/ColorPicker.color = owner.bottom_color
	$VBox/BottomLine/BottomLineActive/ColorPicker.color = owner.bottom_color_active


func _on_color_changed(color: Color, key: StringName) -> void:
	match key:
		&"Backdrop":
			owner.get_node("Backdrop").self_modulate = color
			Data.set_config("colors", "Backdrop", color)
		&"ActionZone":
			owner.get_node("ActionZone").self_modulate = color
			Data.set_config("colors", "Action Zone", color)
		&"MarkerBase":
			%Markers.marker_color = color
			%Markers.apply_marker_style()
			Data.set_config("colors", "Markers", color)
		&"MarkerHoldBreath":
			%Markers.hold_breath_marker_color = color
			%Markers.apply_marker_style()
			Data.set_config("colors", "Hold Breath Markers", color)
		&"BallBase":
			owner.get_node("Ball").self_modulate = color
			Data.set_config("colors", "Ball", color)
		&"BallHoldBreath":
			owner.hold_breath_ball_color = color
			Data.set_config("colors", "Hold Breath Ball", color)
		&"PathBase":
			_change_path_color(color)
			Data.set_config("colors", "Path", color)
		&"PathHoldBreath":
			owner.hold_breath_path_color = color
			Data.set_config("colors", "Hold Breath Path", color)
		&"TopLineBase":
			owner.top_color = color
			Data.set_config("colors", "Top Line", color)
		&"TopLineActive":
			owner.top_color_active = color
			owner.get_node("TopLine").self_modulate = color
			Data.set_config("colors", "Top Active", color)
		&"BottomLineBase":
			owner.bottom_color = color
			Data.set_config("colors", "Bottom Line", color)
		&"BottomLineActive":
			owner.bottom_color_active = color
			owner.get_node("BottomLine").self_modulate = color
			Data.set_config("colors", "Bottom Active", color)


func _restore_line_colors() -> void:
	owner.get_node("TopLine").self_modulate = _top_line_color
	owner.get_node("BottomLine").self_modulate = _bottom_line_color


func _change_path_color(color: Color) -> void:
	owner.get_node("Path").self_modulate = color
	for node in get_tree().get_nodes_in_group("lines"):
		node.self_modulate = color
