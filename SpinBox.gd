extends SpinBox

func _ready():        
	get_line_edit().connect("text_entered", self, "_on_text_entered")            
	connect("value_changed", self, "_on_value_changed")

func _on_text_entered(new_text):        
	get_line_edit().release_focus()

func _on_value_changed(value):        
	get_line_edit().release_focus()

func _input(event):
	if event is InputEventMouseButton and event.is_pressed():
		var rect = get_global_rect()
		var axes = ['x','y']
		var p = 'position'
		for i in axes:
			if event[p][i] < rect[p][i] or event[p][i] > rect['end'][i]:
				get_line_edit().release_focus()
