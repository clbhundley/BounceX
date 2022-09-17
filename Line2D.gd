extends Line2D

var tweening_active:bool

var hold_breath_active:bool

var offset_positions:Array

var flash_duration:float
var flash_iteration:int

enum Mode {FLASH,WIPE,WIPE_REVERSE}
var tween_mode:int

func toggle_line_color():
	tweening_active = true
	tween_mode = Mode.FLASH
	flash_iteration = 0
	offset_speed = 1
	colors.invert()
	offsets.invert()
	flash_duration = 1 - time_curve(flash_iteration)
	tween_color()
	$Tween.start()

var PURPLE = Color('#7266ff')
var WHITE = Color('#ffffff')
var PINK = Color('#f366ff')
var color:Color
var colors = [PINK,WHITE,PURPLE]
func tween_color():
	$Tween.interpolate_property(
		self,
		'color',
		colors[0],
		colors[1],
		flash_duration,
		Tween.TRANS_BACK,
		Tween.EASE_IN)

var offset1:float
var offset2:float
var offsets = [1.0,0.0]
var offset_speed:float
func tween_offset():
	print("tween_offset")
	$Tween.interpolate_property(
		self,
		'offset1',
		offsets[1],
		offsets[0],
		offset_speed,
		Tween.TRANS_LINEAR,
		Tween.EASE_IN)
	$Tween.interpolate_property(
		self,
		'offset2',
		offsets[1],
		offsets[0],
		offset_speed,
		Tween.TRANS_LINEAR,
		Tween.EASE_IN,
		0.3)

var ball_center_active:bool
func _on_Tween_tween_step(object, key, elapsed, value):
	match tween_mode:
		Mode.FLASH:
			if flash_iteration == 5 and not ball_center_active:
				get_node("../Ball").toggle_breath(hold_breath_active)
				ball_center_active = true
			if flash_iteration < 7:
				if $Tween.tell() < flash_duration * 0.96:
					if hold_breath_active:
						
						gradient.colors[2] = value
					else:
						gradient.colors[0] = value
						gradient.colors[1] = value
				else:
					flash_iteration += 1
					flash_duration = max(1 - time_curve(flash_iteration),0)
					tween_color()
					$Tween.reset_all()
			else:
				ball_center_active = false
				if hold_breath_active:
					tween_mode = Mode.WIPE_REVERSE
					offset_speed = 0.5
				else:
					tween_mode = Mode.WIPE
				tween_offset()
				$Tween.start()
		Mode.WIPE:
			match str(key):
				':offset1':
					gradient.offsets[1] = value
				':offset2':
					gradient.offsets[2] = value
		Mode.WIPE_REVERSE:
			match str(key):
				':offset1':
					gradient.offsets[2] = value
				':offset2':
					gradient.offsets[1] = value

func _on_Tween_tween_completed(object, key):
	match tween_mode:
		Mode.WIPE:
			match str(key):
				':offset2':
					hold_breath_active = true
		Mode.WIPE_REVERSE:
			hold_breath_active = false

func time_curve(iteration):
	return (pow((iteration*0.1)+0.9,3.5)/6.7)+0.2
