class_name Funscript

## Shorter than the briefest hold found in hand-authored paths, so every pause
## an author would write survives import while sampling artefacts do not.
const HOLD_MIN_FRAMES := 20


static func export(marker_data: Dictionary, path_meta: Dictionary, out_path: String, invert: bool, duration: int = 0) -> void:
	var actions := []
	var sorted_frames := marker_data.keys()
	sorted_frames.sort()
	for frame in sorted_frames:
		var marker: Array = marker_data[frame]
		var at := int(frame * (1000.0 / 60.0))
		var pos := clampi(int(round(marker[0] * 100.0)), 0, 100)
		actions.append({"at": at, "pos": pos})
	
	var funscript := {
		"version": "1.0",
		"inverted": invert,
		"range": 100,
		"actions": actions,
		"metadata": {
			"creator": path_meta.get("path_creator", ""),
			"title": path_meta.get("related_media", ""),
			"description": "",
			"duration": duration if duration > 0 else int(round(sorted_frames.back() / 60.0)),
			"license": "",
			"notes": "Exported from BounceX",
			"performers": [],
			"script_url": "",
			"tags": [],
			"type": "basic",
			"video_url": ""
		}
	}
	
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(funscript))
		file.close()


static func import(file_path: String, amp_threshold := 0.08, separation_min := 5, max_frame := 0) -> Dictionary:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not parsed.get("actions") is Array:
		return {}
	return {
		"markers": to_marker_data(parsed, amp_threshold, separation_min, max_frame),
		"source": source_meta(parsed)
	}


static func to_marker_data(
		funscript: Dictionary,
		amp_threshold := 0.08,
		separation_min := 5,
		max_frame := 0) -> Dictionary:
	var actions: Array = funscript["actions"].duplicate()
	actions.sort_custom(func(a, b): return int(a.get("at", 0)) < int(b.get("at", 0)))
	
	var inverted: bool = funscript.get("inverted", false)
	var value_range := float(funscript.get("range", 100))
	if value_range <= 0.0:
		value_range = 100.0
	
	var points: Array
	for action in actions:
		if not action is Dictionary or not action.has("at") or not action.has("pos"):
			continue
		var depth := clampf(float(action["pos"]) / value_range, 0.0, 1.0)
		if inverted:
			depth = 1.0 - depth
		var frame := roundi(float(action["at"]) * 60.0 / 1000.0)
		if frame < 0 or (max_frame > 0 and frame >= max_frame):
			continue
		if not points.is_empty() and points[-1][0] == frame:
			points[points.size() - 1] = [frame, depth]
		else:
			points.append([frame, depth])
	
	var marker_data: Dictionary
	for point in _simplify(points, amp_threshold, separation_min):
		marker_data[point[0]] = [point[1], Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0]
	return marker_data


static func _simplify(points: Array, amp_threshold: float, separation_min: int) -> Array:
	if points.size() < 3:
		return points
	# Funscripts trace curves out of many small linear steps, so collapse each
	# run down to the direction change it describes, ignoring reversals too
	# small to be intentional. A run of identical positions is a hold, which
	# has to be closed off with its own marker or the pause it describes turns
	# into a slow drift across the move that follows it.
	var extremes := [points[0]]
	var direction := 0
	var hold = null
	for i in range(1, points.size()):
		var delta: float = points[i][1] - extremes[-1][1]
		var step := int(signf(delta))
		if step == 0:
			hold = points[i]
			continue
		if step != direction and absf(delta) < amp_threshold:
			continue
		if hold != null and hold[0] - extremes[-1][0] >= HOLD_MIN_FRAMES:
			extremes.append(hold)
			direction = 0
		hold = null
		if step == direction:
			extremes[extremes.size() - 1] = points[i]
		else:
			extremes.append(points[i])
			direction = step
	# Whatever is still closer together than the editor permits collapses to
	# whichever marker of the pair sits further from centre.
	var separated := [extremes[0]]
	for i in range(1, extremes.size()):
		if extremes[i][0] - separated[-1][0] < separation_min:
			if absf(extremes[i][1] - 0.5) > absf(separated[-1][1] - 0.5):
				separated[separated.size() - 1] = extremes[i]
		else:
			separated.append(extremes[i])
	return separated


static func source_meta(funscript: Dictionary) -> Dictionary:
	var source: Dictionary
	for key in funscript:
		if key != "actions":
			source[key] = funscript[key]
	source["action_count"] = funscript["actions"].size()
	return source
