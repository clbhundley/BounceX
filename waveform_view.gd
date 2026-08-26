extends Node2D

## WaveformView — Audio waveform visualizer for BounceX
##
## SETUP (add through the Godot editor):
##
##   STATIC mode — full-song view with moving playhead + click/drag to seek
##     • Add a Node2D child to BounceX, attach this script
##     • Set display_mode = STATIC, view_height to taste (~80px)
##     • Position just below TrackSliderLarge (or replace it)
##
##   SCROLLING mode — rolling waveform behind the path canvas
##     • Add a Node2D child to BounceX, place it BEFORE $Backdrop in the tree
##     • Set display_mode = SCROLLING, position = Vector2(0, 0)
##     • Tune scrolling_alpha (0.2–0.4 looks good)
##
##   Both modes share one decode pass via static variables.
##   STATIC uses a 2048-column lo-res array (good for full-song overview).
##   SCROLLING uses a per-frame hi-res array (sharp at any path_speed zoom).
##
##   INSTANT SEEKING: For CBR MP3, a frame index is parsed from the raw MP3
##   data on load, enabling O(1) byte-offset seeks via stream slicing.

enum DisplayMode { STATIC, SCROLLING }

# ── Per-instance exports ──────────────────────────────────────────────────────
@export var display_mode: DisplayMode = DisplayMode.STATIC
@export var view_height: float = 80.0
@export_range(0.0, 1.0) var scrolling_alpha: float = 0.35
@export var show_peak: bool = true
@export var show_rms:  bool = true

# ── Lo-res waveform (2048 cols) — used by STATIC view ────────────────────────
const NUM_COLS := 2048

static var _waveform:     PackedVector2Array
static var _waveform_rms: Array[float]

# ── Hi-res waveform (1 col per frame) — used by SCROLLING view ───────────────
const MAX_SCROLL_COLS := 300000

static var _scroll_cols:     int = 0
static var _waveform_hi:     PackedVector2Array
static var _waveform_rms_hi: Array[float]

# ── Shared accumulator arrays (capture decode path) ───────────────────────────
static var _rms_sum_sq_lo: Array[float]
static var _rms_count_lo:  Array[float]
static var _rms_sum_sq_hi: Array[float]
static var _rms_count_hi:  Array[float]

# ── Shared decode state ────────────────────────────────────────────────────────
static var _has_waveform  := false
static var _computing     := false
static var _decoded_col   := 0
static var _last_stream           = null
static var _stream_duration: float = 0.0

# ── Waveform decode bus (16× pitch — fast) ────────────────────────────────────
const DECODE_PITCH    := 16.0
const DECODE_BUS_NAME := "WaveformDecode_BX"

static var _decode_bus_idx: int               = -1
static var _capture_effect: AudioEffectCapture = null
static var _decode_player:  AudioStreamPlayer  = null


# ── CBR MP3 seek index ────────────────────────────────────────────────────────
## Parses MPEG Layer 3 frame headers to compute exact byte offsets for any time.
## Only populated for CBR files — falls back to Controls.scrub() for VBR.
static var _mp3_data:         PackedByteArray  # original bytes kept for slicing
static var _cbr_first_offset: int   = 0        # byte offset of first audio frame
static var _cbr_avg_bytes:    float = 0.0      # avg frame size (0 = not CBR/parsed)
static var _cbr_sample_rate:  int   = 0
static var _cbr_seek_offset:  float = 0.0     # seconds sliced off the front (0 for WAV/VBR)

# ── Primary-instance tracking ─────────────────────────────────────────────────
static var _primary = null

## Slicing the source bytes to seek an MP3 costs the whole remainder of the
## file, so coalesce the seeks a scrub produces and pay it once.
const SEEK_DEBOUNCE := 0.06
var _seek_timer: Timer
var _seek_pending: float = -1.0

# ── Input state (per-instance) ────────────────────────────────────────────────
var _dragging := false

# ── Colors / font ─────────────────────────────────────────────────────────────
var _peak_col := Color(0.25, 0.60, 1.00)
var _rms_col  := Color(0.55, 0.88, 1.00)
static var _time_font: Font = null


# ═══════════════════════════════════════════════════════════════════════════════
# Lifecycle
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	add_to_group("WaveformView")
	if not is_instance_valid(_primary):
		_primary = self
	_seek_timer = Timer.new()
	_seek_timer.wait_time = SEEK_DEBOUNCE
	_seek_timer.one_shot = true
	_seek_timer.timeout.connect(_on_seek_timeout)
	add_child(_seek_timer)


func _exit_tree() -> void:
	if _primary == self:
		_primary = null
		if _decode_bus_idx != -1:
			AudioServer.remove_bus(_decode_bus_idx)
			_decode_bus_idx = -1
			_capture_effect  = null


func _process(_delta: float) -> void:
	if not is_instance_valid(owner):
		return
	
	if _primary == self:
		var stream = %AudioStreamPlayer.stream
		if stream != _last_stream:
			_last_stream = stream
			if stream != null:
				_start_decode(stream)
			else:
				_clear_waveform()
	
		if _computing and _capture_effect != null:
			_drain_capture()
	
	if _has_waveform or _computing:
		queue_redraw()


# ═══════════════════════════════════════════════════════════════════════════════
# Waveform decode
# ═══════════════════════════════════════════════════════════════════════════════

func _clear_waveform() -> void:
	_waveform        = PackedVector2Array()
	_waveform_rms    = []
	_waveform_hi     = PackedVector2Array()
	_waveform_rms_hi = []
	_rms_sum_sq_lo   = []
	_rms_count_lo    = []
	_rms_sum_sq_hi   = []
	_rms_count_hi    = []
	_has_waveform    = false
	_computing       = false
	_decoded_col     = 0
	
	_mp3_data        = PackedByteArray()
	_cbr_avg_bytes   = 0.0
	_cbr_seek_offset = 0.0
	
	if is_instance_valid(_decode_player) and _decode_player.playing:
		_decode_player.stop()
	
	queue_redraw()


func _init_arrays() -> void:
	_scroll_cols = clampi(int(ceil(_stream_duration * 60.0)), 1, MAX_SCROLL_COLS)
	
	_waveform.resize(NUM_COLS)
	_waveform_rms.resize(NUM_COLS)
	_rms_sum_sq_lo.resize(NUM_COLS)
	_rms_count_lo.resize(NUM_COLS)
	
	_waveform_hi.resize(_scroll_cols)
	_waveform_rms_hi.resize(_scroll_cols)
	_rms_sum_sq_hi.resize(_scroll_cols)
	_rms_count_hi.resize(_scroll_cols)
	
	for i in NUM_COLS:
		_waveform[i]      = Vector2.ZERO
		_waveform_rms[i]  = 0.0
		_rms_sum_sq_lo[i] = 0.0
		_rms_count_lo[i]  = 0.0
	
	for i in _scroll_cols:
		_waveform_hi[i]     = Vector2.ZERO
		_waveform_rms_hi[i] = 0.0
		_rms_sum_sq_hi[i]   = 0.0
		_rms_count_hi[i]    = 0.0
	
	_decoded_col  = 0
	_has_waveform = false


func _start_decode(stream) -> void:
	_clear_waveform()
	_stream_duration = stream.get_length()
	if _stream_duration <= 0.0:
		return
	_init_arrays()
	
	if stream is AudioStreamWAV:
		_decode_wav(stream)
	else:
		# For MP3: parse CBR index for near-instant seeking right away
		if stream is AudioStreamMP3:
			_mp3_data = stream.data
			_parse_cbr_index(_mp3_data)
		# Fast waveform decode (16×)
		_computing = true
		_setup_decode_bus()
		_decode_player.stream      = stream
		_decode_player.pitch_scale = DECODE_PITCH
		_decode_player.play()


# ── WAV path ──────────────────────────────────────────────────────────────────

func _decode_wav(stream: AudioStreamWAV) -> void:
	var data: PackedByteArray = stream.data
	var fmt:  int             = stream.format
	var ch:   int             = 2 if stream.stereo else 1
	
	if fmt != AudioStreamWAV.FORMAT_8_BITS and fmt != AudioStreamWAV.FORMAT_16_BITS:
		_computing = true
		_setup_decode_bus()
		_decode_player.stream      = stream
		_decode_player.pitch_scale = DECODE_PITCH
		_decode_player.play()
		return
	
	var num_samples: int = data.size() / (ch * (2 if fmt == AudioStreamWAV.FORMAT_16_BITS else 1))
	
	for col in _scroll_cols:
		var f0:    int   = col * num_samples / _scroll_cols
		var f1:    int   = (col + 1) * num_samples / _scroll_cols
		var mn:    float = 0.0
		var mx:    float = 0.0
		var sqsum: float = 0.0
		var count: int   = 0
		var step:  int   = max(1, (f1 - f0) / 32)
	
		for f in range(f0, f1, step):
			var s: float
			if fmt == AudioStreamWAV.FORMAT_8_BITS:
				var b := data[f * ch]
				s = (b if b < 128 else b - 256) / 128.0
			else:
				var bi:  int = f * ch * 2
				var raw: int = data[bi] | (data[bi + 1] << 8)
				if raw >= 32768: raw -= 65536
				s = raw / 32767.0
			mn    = minf(mn, s)
			mx    = maxf(mx, s)
			sqsum += s * s
			count += 1
	
		_waveform_hi[col] = Vector2(mn, mx)
		if count > 0:
			_waveform_rms_hi[col] = sqrt(sqsum / count)
	
	for lo_col in NUM_COLS:
		var hi0: int   = lo_col * _scroll_cols / NUM_COLS
		var hi1: int   = (lo_col + 1) * _scroll_cols / NUM_COLS
		var mn:  float = 0.0
		var mx:  float = 0.0
		var rsum: float = 0.0
		var count: int  = 0
		for hi_col in range(hi0, mini(hi1 + 1, _scroll_cols)):
			mn    = minf(mn, _waveform_hi[hi_col].x)
			mx    = maxf(mx, _waveform_hi[hi_col].y)
			rsum += _waveform_rms_hi[hi_col]
			count += 1
		_waveform[lo_col] = Vector2(mn, mx)
		if count > 0:
			_waveform_rms[lo_col] = rsum / count
	
	_has_waveform = true


# ── Waveform capture drain (16× decode) ──────────────────────────────────────

func _drain_capture() -> void:
	var available := _capture_effect.get_frames_available()
	if available <= 0:
		if not _decode_player.playing:
			_computing    = false
			_has_waveform = true
		return
	
	var frames  := _capture_effect.get_buffer(available)
	var pos     := _decode_player.get_playback_position()
	var hi_end  := mini(int(pos / _stream_duration * _scroll_cols), _scroll_cols - 1)
	var lo_end  := mini(int(pos / _stream_duration * NUM_COLS),     NUM_COLS - 1)
	
	for i in frames.size():
		var t: float = float(i) / frames.size()
	
		var hi_col: int = _decoded_col + int(t * max(0, hi_end - _decoded_col)) \
						  if hi_end > _decoded_col else _decoded_col
		hi_col = clampi(hi_col, 0, _scroll_cols - 1)
		var lo_col: int = clampi(hi_col * NUM_COLS / _scroll_cols, 0, NUM_COLS - 1)
	
		var s: float = (frames[i].x + frames[i].y) * 0.5
	
		_waveform_hi[hi_col]   = Vector2(minf(_waveform_hi[hi_col].x, s), maxf(_waveform_hi[hi_col].y, s))
		_rms_sum_sq_hi[hi_col] = _rms_sum_sq_hi[hi_col] + s * s
		_rms_count_hi[hi_col]  = _rms_count_hi[hi_col]  + 1.0
		if _rms_count_hi[hi_col] > 0.0:
			_waveform_rms_hi[hi_col] = sqrt(_rms_sum_sq_hi[hi_col] / _rms_count_hi[hi_col])
	
		_waveform[lo_col]      = Vector2(minf(_waveform[lo_col].x, s), maxf(_waveform[lo_col].y, s))
		_rms_sum_sq_lo[lo_col] = _rms_sum_sq_lo[lo_col] + s * s
		_rms_count_lo[lo_col]  = _rms_count_lo[lo_col]  + 1.0
		if _rms_count_lo[lo_col] > 0.0:
			_waveform_rms[lo_col] = sqrt(_rms_sum_sq_lo[lo_col] / _rms_count_lo[lo_col])
	
	_decoded_col  = hi_end
	_has_waveform = true
	
	if not _decode_player.playing:
		_computing = false


# ── Bus setup ─────────────────────────────────────────────────────────────────

func _setup_decode_bus() -> void:
	var existing := AudioServer.get_bus_index(DECODE_BUS_NAME)
	if existing != -1:
		_decode_bus_idx = existing
		for i in AudioServer.get_bus_effect_count(existing):
			var fx = AudioServer.get_bus_effect(existing, i)
			if fx is AudioEffectCapture:
				_capture_effect = fx
				break
		if _capture_effect == null:
			_capture_effect = AudioEffectCapture.new()
			_capture_effect.buffer_length = 0.1
			AudioServer.add_bus_effect(existing, _capture_effect)
	else:
		_decode_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_decode_bus_idx, DECODE_BUS_NAME)
		AudioServer.set_bus_mute(_decode_bus_idx, true)
		AudioServer.set_bus_send(_decode_bus_idx, "Master")
		_capture_effect               = AudioEffectCapture.new()
		_capture_effect.buffer_length = 0.1
		AudioServer.add_bus_effect(_decode_bus_idx, _capture_effect)
	
	if not is_instance_valid(_decode_player):
		_decode_player     = AudioStreamPlayer.new()
		_decode_player.bus = DECODE_BUS_NAME
		owner.add_child(_decode_player)


# ═══════════════════════════════════════════════════════════════════════════════
# CBR MP3 seek index
# ═══════════════════════════════════════════════════════════════════════════════

static func _parse_cbr_index(data: PackedByteArray) -> void:
	_cbr_avg_bytes = 0.0
	# Skip ID3v2 tag if present
	var i := 0
	if data.size() > 10 and data[0] == 0x49 and data[1] == 0x44 and data[2] == 0x33:
		i = 10 + (((data[6] & 0x7F) << 21) | ((data[7] & 0x7F) << 14) | \
				  ((data[8] & 0x7F) << 7) | (data[9] & 0x7F))
	# Find first valid MPEG Layer 3 frame
	var first := -1
	while i < data.size() - 4:
		if data[i] == 0xFF and (data[i+1] & 0xE6) == 0xE2 and (data[i+1] & 0x18) != 0x08:
			var b2 := data[i + 2]
			if (b2 >> 4) in range(1, 15) and ((b2 >> 2) & 3) < 3:
				first = i
				break
		i += 1
	if first < 0:
		return
	var h0 := _parse_mp3_header(data, first)
	if h0.is_empty():
		return
	# Skip XING (VBR) or INFO (CBR marker) frame if present
	for xoff in [first + 36, first + 21, first + 13]:
		if xoff + 4 <= data.size():
			var tag := (data[xoff] << 24) | (data[xoff+1] << 16) | (data[xoff+2] << 8) | data[xoff+3]
			if tag == 0x58696E67 or tag == 0x56425249:  # "Xing" or "VBRI"
				return  # VBR — cannot use CBR index
			if tag == 0x496E666F:  # "Info"
				first += h0["frame_size"]  # skip the info frame
				h0 = _parse_mp3_header(data, first)
				if h0.is_empty(): return
				break
	# Verify 5 consecutive frames have consistent sizes (CBR check)
	var off := first
	var ref_size: int = h0["frame_size"]
	for _k in 5:
		var h := _parse_mp3_header(data, off)
		if h.is_empty() or abs(h["frame_size"] - ref_size) > 1:
			return  # size inconsistency → VBR
		off += h["frame_size"]
	_cbr_first_offset = first
	_cbr_avg_bytes    = h0["avg_bytes"]
	_cbr_sample_rate  = h0["sample_rate"]


static func _parse_mp3_header(data: PackedByteArray, off: int) -> Dictionary:
	if off + 4 > data.size() or data[off] != 0xFF: return {}
	var b1 := data[off + 1]
	if (b1 & 0xE6) != 0xE2 or (b1 & 0x18) == 0x08: return {}
	var b2 := data[off + 2]
	var bri := (b2 >> 4) & 0xF
	var sri := (b2 >> 2) & 0x3
	var pad := (b2 >> 1) & 0x1
	var mpeg := (b1 >> 3) & 0x3
	const BR1 = [0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0]
	const BR2 = [0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0]
	const SR1 = [44100,48000,32000,0]
	const SR2 = [22050,24000,16000,0]
	const SR25 = [11025,12000,8000,0]
	var br_kbps: int = (BR1 if mpeg == 3 else BR2)[bri]
	var sr: int      = (SR1 if mpeg == 3 else (SR2 if mpeg == 2 else SR25))[sri]
	if br_kbps <= 0 or sr <= 0: return {}
	var avg := 144.0 * br_kbps * 1000.0 / float(sr)
	return {"frame_size": int(avg) + pad, "avg_bytes": avg, "sample_rate": sr, "bitrate": br_kbps * 1000}


## Returns the true full track duration, unaffected by CBR stream slicing.
func get_track_duration() -> float:
	return _stream_duration


## Returns seconds sliced off the front by the last CBR seek (0 for WAV/VBR).
## Add to get_playback_position() to get the actual track position.
func get_seek_offset() -> float:
	return _cbr_seek_offset


## Call before define_path() when loading a new track, so define_path()
## falls back to stream.get_length() instead of the previous track's duration.
func invalidate_duration() -> void:
	_stream_duration = 0.0
	_mp3_data        = PackedByteArray()
	_cbr_avg_bytes   = 0.0
	_cbr_seek_offset = 0.0
	_last_stream     = null


func _fast_mp3_seek(t: float) -> void:
	seek_audio(t)
	_fast_mp3_seek_sync(t)


# ═══════════════════════════════════════════════════════════════════════════════
# Drawing
# ═══════════════════════════════════════════════════════════════════════════════

func _draw() -> void:
	if _waveform.size() < NUM_COLS:
		return
	match display_mode:
		DisplayMode.STATIC:
			_draw_static()
		DisplayMode.SCROLLING:
			_draw_scrolling()


func _draw_static() -> void:
	var vp_w:   float = get_viewport_rect().size.x
	var h:      float = view_height
	var cy:     float = h * 0.5
	var half_h: float = h * 0.5
	var bar_w:  float = vp_w / NUM_COLS
	var n_ready: int  = clampi(int(float(_decoded_col) / float(maxi(_scroll_cols, 1)) * NUM_COLS), \
							   0, NUM_COLS) if _computing else NUM_COLS
	
	for i in n_ready:
		var x: float = i * bar_w
		if show_peak:
			var lo:    float = _waveform[i].x
			var hi:    float = _waveform[i].y
			draw_rect(Rect2(x, cy - hi * half_h, maxf(1.0, bar_w), maxf(1.0, (hi - lo) * half_h)), _peak_col)
		if show_rms:
			var rms:   float = _waveform_rms[i]
			draw_rect(Rect2(x, cy - rms * half_h, maxf(1.0, bar_w), maxf(1.0, rms * h)), _rms_col)
	
	var total: float = float(owner.path.size())
	if total > 0.0:
		var t:  float = owner.frame / total
		var px: float = t * vp_w
		draw_rect(Rect2(0.0, 0.0, px, h), Color(0.0, 0.0, 0.0, 0.25))
		draw_line(Vector2(px, 0.0), Vector2(px, h), Color.YELLOW, 2.0)
		if not _time_font:
			_time_font = load("res://font/rubik_light.ttf")
		var playback_pos := t * _stream_duration
		var time_text := str(int(playback_pos) / 60).lpad(2, "0") + ":" + \
						 str(int(playback_pos) % 60).lpad(2, "0")
		draw_string(_time_font, Vector2(vp_w * 0.5 - 27, -9), time_text,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 20)


func _draw_scrolling() -> void:
	if _waveform_hi.size() < _scroll_cols or _scroll_cols == 0:
		return
	var vp_w:   float = get_viewport_rect().size.x
	var top_y:  float = owner.TOP
	var bot_y:  float = owner.BOTTOM
	var h:      float = bot_y - top_y
	if h <= 0.0:
		return
	var cy:     float = top_y + h * 0.5
	var half_h: float = h * 0.5
	var cx:     float = owner.playhead_position()
	var pspeed: float = owner.path_speed
	var total:  float = float(owner.path.size())
	if total <= 0.0 or pspeed <= 0.0:
		return
	
	var peak_c := Color(_peak_col.r, _peak_col.g, _peak_col.b, scrolling_alpha)
	var rms_c  := Color(_rms_col.r,  _rms_col.g,  _rms_col.b,  scrolling_alpha)
	
	var first_col: int = clampi(int((owner.frame - cx / pspeed) / total * _scroll_cols), 0, _scroll_cols - 1)
	var last_col:  int = clampi(int((owner.frame + (vp_w - cx) / pspeed) / total * _scroll_cols), 0, _scroll_cols - 1)
	if _computing:
		last_col = mini(last_col, _decoded_col)
	
	for col in range(first_col, last_col + 1):
		var f0: float = float(col)     / _scroll_cols * total
		var f1: float = float(col + 1) / _scroll_cols * total
		var x0: float = cx + (f0 - owner.frame) * pspeed
		var w:  float = maxf(1.0, (f1 - f0) * pspeed)
		if show_peak:
			var lo: float = _waveform_hi[col].x
			var hi: float = _waveform_hi[col].y
			draw_rect(Rect2(x0, cy - hi * half_h, w, maxf(1.0, (hi - lo) * half_h)), peak_c)
		if show_rms:
			var rms: float = _waveform_rms_hi[col]
			draw_rect(Rect2(x0, cy - rms * half_h, w, maxf(1.0, rms * h)), rms_c)


# ═══════════════════════════════════════════════════════════════════════════════
# Input — click / drag to seek (STATIC mode only)
# ═══════════════════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if display_mode != DisplayMode.STATIC:
		return
	if not _has_waveform or not is_instance_valid(owner):
		return
	if owner.input_disabled:
		return
	var rect := Rect2(global_position, Vector2(get_viewport_rect().size.x, view_height))
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and rect.has_point(event.global_position) \
			and not owner.get_node("Menu").is_ancestor_of(get_viewport().gui_get_hovered_control()):
			_dragging = true
			_seek_to(event.global_position.x)
			get_viewport().set_input_as_handled()
		elif not event.pressed:
			_dragging = false
	
	elif event is InputEventMouseMotion and _dragging:
		_seek_to(event.global_position.x)
		get_viewport().set_input_as_handled()


## Audio-only seek to normalized position t ∈ [0, 1].
## Frame / marker / ball sync is the caller's responsibility.
func seek_audio(t: float) -> void:
	if _cbr_avg_bytes > 0.0 and _mp3_data.size() > 0 and \
	   %AudioStreamPlayer.stream is AudioStreamMP3:
		# Defer the slice: a scrub asks for many positions and only the last
		# one is ever heard.
		_seek_pending = t
		_seek_timer.start()
		return
	_seek_audio_now(t)


func _on_seek_timeout() -> void:
	if _seek_pending < 0.0:
		return
	var t := _seek_pending
	_seek_pending = -1.0
	_seek_audio_now(t)


func _seek_audio_now(t: float) -> void:
	if _cbr_avg_bytes > 0.0 and _mp3_data.size() > 0 and \
	   %AudioStreamPlayer.stream is AudioStreamMP3:
		# Fast path: slice from CBR byte offset (no frame sync — caller handles it)
		# Clamp to 0.5s before end to avoid invalid slices near EOF
		if _stream_duration > 0.5:
			t = minf(t, 1.0 - 0.5 / _stream_duration)
		var total_mp3_frames := int(_stream_duration * _cbr_sample_rate / 1152.0)
		var byte_off := _cbr_first_offset + int(t * total_mp3_frames * _cbr_avg_bytes)
		byte_off = clampi(byte_off, 0, _mp3_data.size() - 4)
		var scan_end := mini(byte_off + 8, _mp3_data.size() - 4)
		while byte_off < scan_end:
			if _mp3_data[byte_off] == 0xFF and (_mp3_data[byte_off + 1] & 0xE6) == 0xE2:
				break
			byte_off += 1
		# Not enough data remaining for a valid frame — too close to end of file
		if byte_off >= _mp3_data.size() - int(_cbr_avg_bytes):
			if %AudioStreamPlayer.playing and not %AudioStreamPlayer.stream_paused:
				%AudioStreamPlayer.stream_paused = true
			return
		_cbr_seek_offset = t * _stream_duration
		var sliced := AudioStreamMP3.new()
		sliced.data = _mp3_data.slice(byte_off)
		var was_paused: bool = %AudioStreamPlayer.stream_paused or not %AudioStreamPlayer.playing
		_last_stream = sliced
		%AudioStreamPlayer.stream = sliced
		%AudioStreamPlayer.play(0.0)
		if was_paused:
			%AudioStreamPlayer.stream_paused = true
	else:
		# Fallback: instant for WAV, O(position) for VBR MP3
		# NOTE: do NOT call Controls.scrub() here — callers own their UI sync,
		# and scrub() itself now calls seek_audio(), so that would recurse.
		if not is_instance_valid(owner) or _stream_duration <= 0.0:
			return
		_cbr_seek_offset = 0.0
		var pos := t * _stream_duration
		if not %AudioStreamPlayer.playing:
			%AudioStreamPlayer.play(pos)
			%AudioStreamPlayer.stream_paused = true
		elif %AudioStreamPlayer.stream_paused:
			%AudioStreamPlayer.stream_paused = false
			%AudioStreamPlayer.seek(pos)
			%AudioStreamPlayer.stream_paused = true
		else:
			%AudioStreamPlayer.seek(pos)


func _seek_to(screen_x: float) -> void:
	var t := clampf((screen_x - global_position.x) / get_viewport_rect().size.x, 0.0, 1.0)
	seek_audio(t)
	# Sync frame / markers / ball for waveform click+drag seeks
	_fast_mp3_seek_sync(t)


## Sync BounceX frame, markers, ball, and UI to normalized position t.
## Extracted so seek_audio() can stay audio-only.
func _fast_mp3_seek_sync(t: float) -> void:
	var total: int = owner.path.size()
	if total < 10:
		return
	owner.frame = clampi(int(t * total), 0, total - 10)
	%Markers.position.x = \
		owner.playhead_position() - float(owner.frame) * owner.path_speed
	if total > owner.frame + 1 and owner.path[owner.frame + 1] > -1:
		owner.place_ball(owner.path[owner.frame + 1])
	# Sync sliders, time display, and marker UI
	# (WAV gets this from scrub() in seek_audio fallback; MP3 fast path skips scrub)
	var t_sync := float(owner.frame) / float(total - 1)
	var playback_pos := t_sync * _stream_duration
	var seconds := str(int(playback_pos) % 60).lpad(2, "0")
	var minutes := str(int(playback_pos) / 60).lpad(2, "0")
	for bar in [%Controls/TrackSlider, %TrackSliderLarge]:
		bar.set_value(t_sync)
	%TrackSliderLarge/TrackTime.text = minutes + ":" + seconds
	%Controls.update_marker_menu()
	%Markers.position_markers()
