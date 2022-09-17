extends Control

var pressed_inputs := [
	"double_bpm",
	"half_bpm",
	"limit_1",
	"limit_2",
	"limit_3",
	"limit_4",
	"limit_5",
	"limit_6",
	"limit_7",
	"limit_8",
	"height_0",
	"height_1",
	"height_2",
	"height_3",
	"height_4",
	"height_5",
	"height_6",
	"height_7",
	"height_8",
	"height_9",
	"height_10",
	"depth_0",
	"depth_1",
	"depth_2",
	"depth_3",
	"depth_4",
	"depth_5",
	"depth_6",
	"depth_7",
	"depth_8",
	"depth_9",
	"depth_10",
	"reset_h_d",
	"flip_h_d",
	"transition_1",
	"transition_2",
	"transition_3",
	"transition_4",
	"transition_5",
	"transition_6",
	"transition_7",
	"transition_8",
	"transition_9",
	"easing_1",
	"easing_2",
	"easing_3",
	"easing_4",
	"toggle_line",
	"toggle_breath",
	"MARK!!!!!!!!!!!!!!!!!!",
	"pause"]

var held_inputs := [
	"up",
	"cycle",
	"slam_in",
	"slam_out"]

func _unhandled_input(event):
	
	if event.is_action_pressed('pause'):
		self.pause = !self.pause
		if self.pause:
			print("PLAYBACK PAUSED")
		else:
			print("PLAYBACK RESUMED")
	
	elif event.is_action_pressed("MARK!!!!!!!!!!!!!!!!!!"):
		for i in 206:
			yield(get_tree(),"idle_frame")
		print("MARK!!!!!!!!!!!!!!!!!!")
	
	elif event.is_action_pressed("set_mark"):
		if self.preview_active:
			var pos = self.record_preview_orig_size - self.record_preview.size()
			pos = max(pos - 206, 0)
			self.record[pos].append("MARK!!!!!!!!!!!!!!!!!!")
			call('save_record',true)
	
	elif event.is_action_pressed("double_bpm"):
		if self.bpm * 2 > 9999.99:
			return
		var time = clamp(self.frame*self.step,0,1)
		if self.lock_up:
			self.bpm *= 2
			self.frame = ceil(1.0/self.step)
		elif time != 1 and time != 0:
			if self.action_queue.has("_"):
				self.action_queue["_"].append("double_bpm")
			else:
				self.action_queue = {"_":["double_bpm"]}
		else:
			self.bpm *= 2
			self.frame /= 2
	elif event.is_action_pressed("half_bpm"):
		if self.bpm / 2 < 0.01:
			return
		var time = clamp(self.frame*self.step,0,1)
		if self.lock_up:
			self.bpm /= 2
			self.frame = ceil(1.0/self.step)
		elif time != 1 and time != 0:
			if self.action_queue.has("_"):
				self.action_queue["_"].append("half_bpm")
			else:
				self.action_queue = {"_":["half_bpm"]}
		else:
			self.bpm /= 2
			self.frame *= 2
	elif event.is_action_pressed("shift_right"):
		self.bpm *= 2
		self.frame /= 2
	elif event.is_action_pressed("shift_left"):
		self.bpm /= 2
		self.frame *= 2
	
	elif event.is_action_pressed("adjust_frame"):
		self.frame -= 3
	
	elif event.is_action_pressed("limit_1"):
		self.limit = 1
	elif event.is_action_pressed("limit_2"):
		self.limit = 1.25
	elif event.is_action_pressed("limit_3"):
		self.limit = 1.5
	elif event.is_action_pressed("limit_4"):
		self.limit = 1.75
	elif event.is_action_pressed("limit_5"):
		self.limit = 2
	elif event.is_action_pressed("limit_6"):
		self.limit = 3
	elif event.is_action_pressed("limit_7"):
		self.limit = 4
	elif event.is_action_pressed("limit_8"):
		self.limit = 5
	
	elif event.is_action_pressed("height_0"):
		if self.height == self.depth:
			self.frame = 0
		if self.frame != 0:
			self.action_queue = {0:["height_0"]}
		else:
			self.height = 0
	elif event.is_action_pressed("height_1"):
		if self.height == self.depth:
			self.frame = 0
		if self.frame != 0:
			self.action_queue = {0:["height_1"]}
		else:
			self.height = 0.1
	elif event.is_action_pressed("height_2"):
		if self.height == self.depth:
			self.frame = 0
		if self.frame != 0:
			self.action_queue = {0:["height_2"]}
		else:
			self.height = 0.2
	elif event.is_action_pressed("height_3"):
		if self.height == self.depth:
			self.frame = 0
		if self.frame != 0:
			self.action_queue = {0:["height_3"]}
		else:
			self.height = 0.3
	elif event.is_action_pressed("height_4"):
		if self.height == self.depth:
			self.frame = 0
		if self.frame != 0:
			self.action_queue = {0:["height_4"]}
		else:
			self.height = 0.4
	elif event.is_action_pressed("height_5"):
		if self.height == self.depth:
			self.frame = 0
		if self.frame != 0:
			self.action_queue = {0:["height_5"]}
		else:
			self.height = 0.5
	elif event.is_action_pressed("height_6"):
		if self.height == self.depth:
			self.frame = 0
		if self.frame != 0:
			self.action_queue = {0:["height_6"]}
		else:
			self.height = 0.6
	elif event.is_action_pressed("height_7"):
		if self.height == self.depth:
			self.frame = 0
		if self.frame != 0:
			self.action_queue = {0:["height_7"]}
		else:
			self.height = 0.7
	elif event.is_action_pressed("height_8"):
		if self.height == self.depth:
			self.frame = 0
		if self.frame != 0:
			self.action_queue = {0:["height_8"]}
		else:
			self.height = 0.8
	elif event.is_action_pressed("height_9"):
		if self.height == self.depth:
			self.frame = 0
		if self.frame != 0:
			self.action_queue = {0:["height_9"]}
		else:
			self.height = 0.9
	elif event.is_action_pressed("height_10"):
		if self.height == self.depth:
			self.frame = 0
		if self.frame != 0:
			self.action_queue = {0:["height_10"]}
		else:
			self.height = 1
	
	elif event.is_action_pressed("depth_0"):
		if self.height == self.depth:
			self.frame = ceil(1.0/self.step)
		if clamp(self.frame*self.step,0,1) != 1:
			self.action_queue = {1:["depth_0"]}
		else:
			self.depth = 0
	elif event.is_action_pressed("depth_1"):
		if self.height == self.depth:
			self.frame = ceil(1.0/self.step)
		if clamp(self.frame*self.step,0,1) != 1:
			self.action_queue = {1:["depth_1"]}
		else:
			self.depth = 0.1
	elif event.is_action_pressed("depth_2"):
		if self.height == self.depth:
			self.frame = ceil(1.0/self.step)
		if clamp(self.frame*self.step,0,1) != 1:
			self.action_queue = {1:["depth_2"]}
		else:
			self.depth = 0.2
	elif event.is_action_pressed("depth_3"):
		if self.height == self.depth:
			self.frame = ceil(1.0/self.step)
		if clamp(self.frame*self.step,0,1) != 1:
			self.action_queue = {1:["depth_3"]}
		else:
			self.depth = 0.3
	elif event.is_action_pressed("depth_4"):
		if self.height == self.depth:
			self.frame = ceil(1.0/self.step)
		if clamp(self.frame*self.step,0,1) != 1:
			self.action_queue = {1:["depth_4"]}
		else:
			self.depth = 0.4
	elif event.is_action_pressed("depth_5"):
		if self.height == self.depth:
			self.frame = ceil(1.0/self.step)
		if clamp(self.frame*self.step,0,1) != 1:
			self.action_queue = {1:["depth_5"]}
		else:
			self.depth = 0.5
	elif event.is_action_pressed("depth_6"):
		if self.height == self.depth:
			self.frame = ceil(1.0/self.step)
		if clamp(self.frame*self.step,0,1) != 1:
			self.action_queue = {1:["depth_6"]}
		else:
			self.depth = 0.6
	elif event.is_action_pressed("depth_7"):
		if self.height == self.depth:
			self.frame = ceil(1.0/self.step)
		if clamp(self.frame*self.step,0,1) != 1:
			self.action_queue = {1:["depth_7"]}
		else:
			self.depth = 0.7
	elif event.is_action_pressed("depth_8"):
		if self.height == self.depth:
			self.frame = ceil(1.0/self.step)
		if clamp(self.frame*self.step,0,1) != 1:
			self.action_queue = {1:["depth_8"]}
		else:
			self.depth = 0.8
	elif event.is_action_pressed("depth_9"):
		if self.height == self.depth:
			self.frame = ceil(1.0/self.step)
		if clamp(self.frame*self.step,0,1) != 1:
			self.action_queue = {1:["depth_9"]}
		else:
			self.depth = 0.9
	elif event.is_action_pressed("depth_10"):
		if self.height == self.depth:
			self.frame = ceil(1.0/self.step)
		if clamp(self.frame*self.step,0,1) != 1:
			self.action_queue = {1:["depth_10"]}
		else:
			self.depth = 1
	
	elif event.is_action_pressed("reset_h_d"):
		self.call('fix_height_flip',true)
		self.height = 1
		self.depth = 0
	elif event.is_action_pressed("flip_h_d"):
		print("")
		print("flip h/d")
		if self.line_flipped:
			self.height = 0
			self.line_flipped = false
		else:
			self.height = 1
			self.line_flipped = true
		self.direction = self.UP
		self.call('fix_height_flip')
		self.action_queue = {1:["reset_frame"]}
	#force flip_h_d:
	#self.height = abs(self.height-1)
	#self.depth = abs(self.depth-1)
	
	elif event.is_action_pressed("reset_frame"):
		if self.height == 1:
			self.depth = 1
			self.height = 0
		else:
			self.depth = 0
			self.height = 1
		self.frame = 0
		self.direction = null
	
	elif event.is_action_pressed("transition_1"):
		self.transition = 0
	elif event.is_action_pressed("transition_2"):
		self.transition = 1
	elif event.is_action_pressed("transition_3"):
		self.transition = 2
	elif event.is_action_pressed("transition_4"):
		self.transition = 3
	elif event.is_action_pressed("transition_5"):
		self.transition = 4
	elif event.is_action_pressed("transition_6"):
		self.transition = 5
	elif event.is_action_pressed("transition_7"):
		self.transition = 6
	elif event.is_action_pressed("transition_8"):
		self.transition = 7
	elif event.is_action_pressed("transition_9"):
		self.transition = 8
	
	elif event.is_action_pressed("easing_1"):
		self.easing = 0
	elif event.is_action_pressed("easing_2"):
		self.easing = 1
	elif event.is_action_pressed("easing_3"):
		self.easing = 2
	elif event.is_action_pressed("easing_4"):
		self.easing = 3
	
	elif event.is_action_pressed("toggle_line"):
		print("")
		if not self.line_active:
			get_node("Line2D").clear_points()
			print("LINE ON")
		else:
			print("LINE OFF")
		print("")
		self.line_active = !self.line_active
	
	elif event.is_action_pressed("toggle_breath"):
		if not self.line_active:
			print("line not active")
			return
		#if get_node("Line2D").tweening_active:
			#print("HOLD BREATH ON COOLDOWN")
			#return
		if self.playback_active or self.preview_active:
			for i in 206:
					yield(get_tree(),"idle_frame")
			if self.playback_active:
				get_node("Line2D/Tween").playback_speed = 0.23
				get_node("Ball/Tween").playback_speed = 0.23
		else:
			get_node("Line2D/Tween").playback_speed = 1
		get_node("Line2D").toggle_line_color()
		print("LINE COLOR CHANGED")
	
	elif event.is_action_pressed("toggle_recording"):
		if not self.recording_active:
			self.starting_values = {
				bpm = self.bpm,
				transition = self.transition,
				easing = self.easing,
				limit = self.limit,
				height = self.height,
				depth = self.depth,
				line_active = self.line_active}
			self.recording_active = true
			get_node('Header/Recording').show()
			call('display_print',"RECORDING ACTIVE")
		else:
			self.recording_active = false
			get_node('Header/Recording').hide()
			call('display_print',"RECORDING STOPPED")
	
	elif event.is_action_pressed("playback"):
		if not self.playback_active:
			if self.recording_active:
				self.recording_active = false
				call('display_print',"RECORDING STOPPED")
			self.playback_active = true
			call('create_capture_dir')
			call('save_record')
			OS.set_window_position(Vector2(0,OS.window_position.y))
			OS.set_window_size(Vector2(1920,400))
			OS.set_borderless_window(true)
			get_node("Header").hide()
			get_node("Ball/Read").show()
			get_node("Ball/Write").position.x = 1997.5
			yield(get_tree(),"idle_frame")
			yield(get_tree(),"idle_frame")
			for property in self.starting_values:
				self.set(property,self.starting_values[property])
			self.starting_values.clear()
			self.playback_active = true
			self.index = 0
			call('display_print',"PLAYBACK CAPTURE ACTIVE")
	
	elif event.is_action_pressed("clear_record"):
		self.record.clear()
		self.starting_values.clear()
		call('display_print',"RECORD CLEARED")
	
	elif event.is_action_pressed("save_record"):
		call('save_record')
	
	elif event.is_action_pressed("load_record"):
		call('load_record')
	
	elif event.is_action_pressed("preview"):
		if not self.preview_active:
			if self.recording_active:
				self.recording_active = false
				call('display_print',"RECORDING STOPPED")
			yield(get_tree(),"idle_frame")
			yield(get_tree(),"idle_frame")
			for property in self.starting_values:
				self.set(property,self.starting_values[property])
			self.record_preview = self.record.duplicate()
			self.record_preview_orig_size = self.record_preview.size()
			OS.set_window_position(Vector2(0,OS.window_position.y))
			OS.set_window_size(Vector2(1920,400))
			get_node("Ball/Read").show()
			get_node("Ball/Write").position.x = 1997.5
			self.preview_active = true
			call('display_print',"PREVIEW ACTIVE")
	
	elif event.is_action_pressed("open_dir"):
		OS.shell_open(OS.get_user_data_dir())
