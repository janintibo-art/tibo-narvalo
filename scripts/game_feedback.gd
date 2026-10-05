extends Node

var xr_camera: XRCamera3D
var left_hand: XRController3D
var right_hand: XRController3D
var enemy_root: Node3D

var alert_label: Label3D
var score_label: Label3D
var impact_label: Label3D
var wave_label: Label3D

var score := 0
var ko_count := 0
var alert_serial := 0
var impact_serial := 0
var wave_serial := 0
var last_game_state := ""
var last_wave := 0
var bound_enemy_root_id := 0
var enemy_health: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_try_bind")


func _process(_delta: float) -> void:
	_try_bind()
	_track_enemy_health()

	var main := get_tree().current_scene
	if main == null:
		return

	var state_value = main.get("game_state")
	if state_value == null:
		return

	var state := String(state_value)

	if state == "playing" and last_game_state != "playing":
		score = 0
		ko_count = 0
		last_wave = 0
		enemy_health.clear()
		_update_score()

	var wave_value = main.get("wave")
	if state == "playing" and wave_value != null:
		var current_wave := int(wave_value)
		if current_wave > last_wave:
			last_wave = current_wave
			_show_wave(current_wave)

	if score_label:
		score_label.visible = state == "playing"

	if wave_label:
		wave_label.visible = state == "playing"

	if alert_label and state != "playing":
		alert_label.text = ""

	if impact_label and state != "playing":
		impact_label.text = ""

	last_game_state = state


func _on_node_added(_node: Node) -> void:
	call_deferred("_try_bind")


func _try_bind() -> void:
	if not is_instance_valid(xr_camera):
		xr_camera = get_tree().get_first_node_in_group("xr_camera") as XRCamera3D

	if xr_camera:
		if left_hand == null:
			left_hand = xr_camera.get_parent().get_node_or_null("LeftHand") as XRController3D
		if right_hand == null:
			right_hand = xr_camera.get_parent().get_node_or_null("RightHand") as XRController3D

		if alert_label == null:
			_create_feedback_hud()

	var main := get_tree().current_scene
	if main == null:
		return

	var root := main.get_node_or_null("EnemyRoot") as Node3D
	if root == null:
		return

	var root_id := root.get_instance_id()
	if root_id != bound_enemy_root_id:
		enemy_root = root
		bound_enemy_root_id = root_id

		if not enemy_root.child_entered_tree.is_connected(_on_enemy_added):
			enemy_root.child_entered_tree.connect(_on_enemy_added)

	for child in root.get_children():
		if child.is_in_group("tibo"):
			_register_enemy(child)


func _create_feedback_hud() -> void:
	alert_label = _make_hud_label("TiboDirectionAlert", Vector3(0, 0.24, -1.4), 44)
	impact_label = _make_hud_label("TiboImpact", Vector3(0, -0.24, -1.2), 38)
	wave_label = _make_hud_label("TiboWave", Vector3(0, 0.34, -1.5), 56)
	wave_label.visible = false
	score_label = _make_hud_label("TiboScore", Vector3(0.62, -0.40, -1.4), 30)
	score_label.visible = false

	_update_score()


func _make_hud_label(label_name: String, pos: Vector3, size: int) -> Label3D:
	var label := Label3D.new()
	label.name = label_name
	label.position = pos
	label.font_size = size
	label.pixel_size = 0.001
	label.outline_size = 8
	label.no_depth_test = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = ""
	xr_camera.add_child(label)
	return label


func _on_enemy_added(node: Node) -> void:
	if not node.is_in_group("tibo"):
		return

	call_deferred("_register_enemy", node)
	call_deferred("_announce_enemy", node)


func _register_enemy(node: Node) -> void:
	if not is_instance_valid(node):
		return

	if not node.is_in_group("tibo"):
		return

	var node_id := node.get_instance_id()

	var health_value = node.get("health")
	if health_value != null:
		enemy_health[node_id] = int(health_value)

	if node.has_signal("defeated"):
		var defeated_callable := Callable(self, "_on_tibo_defeated")
		if not node.is_connected("defeated", defeated_callable):
			node.connect("defeated", defeated_callable)

	if node.has_signal("player_hit"):
		var hit_callable := Callable(self, "_on_player_hit").bind(node)
		if not node.is_connected("player_hit", hit_callable):
			node.connect("player_hit", hit_callable)


func _track_enemy_health() -> void:
	if not is_instance_valid(enemy_root):
		return

	for child in enemy_root.get_children():
		if not child.is_in_group("tibo"):
			continue

		var health_value = child.get("health")
		if health_value == null:
			continue

		var node_id := child.get_instance_id()
		var current_health := int(health_value)

		if not enemy_health.has(node_id):
			enemy_health[node_id] = current_health
			continue

		var old_health := int(enemy_health[node_id])

		if current_health < old_health:
			_enemy_hit_feedback(child as Node3D, old_health - current_health)

		enemy_health[node_id] = current_health


func _enemy_hit_feedback(enemy: Node3D, damage: int) -> void:
	impact_serial += 1
	var this_impact := impact_serial

	if impact_label:
		if damage >= 90:
			impact_label.text = "PELLE !  %d" % damage
		elif damage >= 65:
			impact_label.text = "BAM !  %d" % damage
		else:
			impact_label.text = "PAF !  %d" % damage

	await get_tree().create_timer(0.32).timeout

	if this_impact == impact_serial and impact_label:
		impact_label.text = ""


func _nearest_controller(enemy: Node3D) -> XRController3D:
	if enemy == null:
		return null

	if left_hand == null:
		return right_hand

	if right_hand == null:
		return left_hand

	var left_distance := left_hand.global_position.distance_squared_to(enemy.global_position)
	var right_distance := right_hand.global_position.distance_squared_to(enemy.global_position)

	if left_distance <= right_distance:
		return left_hand

	return right_hand


func _on_player_hit(damage: int, _source: Node) -> void:
	var shown := damage
	var blocked := false
	var main := get_tree().current_scene

	if main != null and main.has_method("is_guarding") and main.call("is_guarding"):
		blocked = true
		shown = int(main.call("reduced_damage", damage))

	var strength := 0.75 if blocked else 0.30

	if left_hand:
		left_hand.trigger_haptic_pulse("haptic", 0.0, strength, 0.10, 0.0)

	if right_hand:
		right_hand.trigger_haptic_pulse("haptic", 0.0, strength, 0.10, 0.0)

	impact_serial += 1
	var this_impact := impact_serial

	if impact_label:
		if blocked:
			impact_label.text = "PARADE !  -%d PV" % shown
		else:
			impact_label.text = "AIE !  -%d PV" % shown

	await get_tree().create_timer(0.45).timeout

	if this_impact == impact_serial and impact_label:
		impact_label.text = ""


func _announce_enemy(node: Node) -> void:
	if not is_instance_valid(node):
		return

	if not node is Node3D:
		return

	if xr_camera == null or alert_label == null:
		return

	var enemy := node as Node3D
	var to_enemy := enemy.global_position - xr_camera.global_position
	to_enemy.y = 0.0

	if to_enemy.length_squared() < 0.01:
		return

	to_enemy = to_enemy.normalized()

	var forward := -xr_camera.global_transform.basis.z
	forward.y = 0.0

	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	var right := xr_camera.global_transform.basis.x
	right.y = 0.0

	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var forward_dot := to_enemy.dot(forward)
	var right_dot := to_enemy.dot(right)
	var direction_text := "DEVANT"

	if absf(forward_dot) >= absf(right_dot):
		if forward_dot < 0.0:
			direction_text = "DERRIERE"
	else:
		if right_dot >= 0.0:
			direction_text = "A DROITE"
		else:
			direction_text = "A GAUCHE"

	alert_serial += 1
	var this_alert := alert_serial

	alert_label.text = "TIBO %s !" % direction_text

	await get_tree().create_timer(1.15).timeout

	if this_alert == alert_serial and alert_label:
		alert_label.text = ""


func show_message(text: String, seconds: float = 1.2) -> void:
	if alert_label == null:
		return

	alert_serial += 1
	var this_alert := alert_serial

	alert_label.text = text

	await get_tree().create_timer(seconds).timeout

	if this_alert == alert_serial and alert_label:
		alert_label.text = ""


func player_damaged(damage: int) -> void:
	_on_player_hit(damage, null)


func show_combo(count: int) -> void:
	if alert_label == null or count < 2:
		return

	alert_serial += 1
	var this_alert := alert_serial

	alert_label.text = "COMBO x%d" % count

	await get_tree().create_timer(0.9).timeout

	if this_alert == alert_serial and alert_label:
		alert_label.text = ""


func _show_wave(wave_number: int) -> void:
	if wave_label == null:
		return

	wave_serial += 1
	var this_wave := wave_serial

	wave_label.text = "VAGUE %d" % wave_number
	GameAudio.play_sfx("wave")

	await get_tree().create_timer(1.10).timeout

	if this_wave == wave_serial and wave_label:
		wave_label.text = ""


func _on_tibo_defeated(tibo: Node) -> void:
	if is_instance_valid(tibo):
		enemy_health.erase(tibo.get_instance_id())

	ko_count += 1

	var points := 100
	var main := get_tree().current_scene

	if main:
		var difficulty_value = main.get("selected_difficulty")

		if difficulty_value != null:
			var difficulty := String(difficulty_value)

			if difficulty == "normal":
				points = 150
			elif difficulty == "difficile":
				points = 225

	if is_instance_valid(tibo):
		var kind_value = tibo.get("kind")

		if kind_value != null:
			var kind := String(kind_value)

			if kind == "costaud":
				points *= 2
			elif kind == "lanceur" or kind == "rapide":
				points = int(points * 1.5)

	score += points
	_update_score()


func _update_score() -> void:
	if score_label == null:
		return

	score_label.text = "SCORE %06d\nKO %d" % [score, ko_count]
