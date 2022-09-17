extends Node2D

func toggle_breath(active:bool):
	var scaling = [Vector2(1,1),Vector2(0,0)]
	var colors = [Color('#196680ff'),Color('#19ff3bbd')]
	if active:
		scaling.invert()
		colors.invert()
	for center in ['CenterBall','CenterHeart']:
		for ball in ['Read','Write']:
			get_node(ball+'/'+center)
			$Tween.interpolate_property(
				get_node(ball+'/'+center),
				'scale',
				scaling[0],
				scaling[1],
				1.8,
				Tween.TRANS_ELASTIC,
				Tween.EASE_IN_OUT)
		scaling.invert()
	for background in [$Read/Background,$Write/Background]:
		$Tween.interpolate_property(
			background,
			'self_modulate',
			colors[0],
			colors[1],
			1.0,
			Tween.TRANS_EXPO,
			Tween.EASE_IN)
	$Tween.start()

func _on_Tween_tween_all_completed():
	get_node("../Line2D").tweening_active = false

#func _ready():
#	get_tree().get_root().connect('size_changed', self, 'resize')
#
#func resize():
#	if not owner.playback_active and not owner.preview_active:
#		$Write.position.x = get_tree().get_root().get_size().x - 72.5
