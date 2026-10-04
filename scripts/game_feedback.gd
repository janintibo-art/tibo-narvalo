extends Node

var xr_camera: XRCamera3D
var enemy_root: Node3D

var alert_label: Label3D
var score_label: Label3D

var score := 0
var ko_count := 0
var alert_serial := 0
var last_game_state := ""
var bound_enemy_root_id := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_try_bind")


func _process(_delta: float) -> void:
	_try_bind()

	var main := get_tree().current_scene
	if main == null:
		return

	var state_value = main.get("game_state")
	if state_value == null:
		return

	var state := String(state_value)

	if state == "playing" and last_game_state == "menu":
		score = 0
		ko_count = 0
		_update_score()

	if score_label:
		score_label.visible = state == "playing"

	if alert_label and state != "playing":
		alert_label.text = ""

	last_game_state = state


func _on_node_added(_node: Node) -> void:
	call_deferred("_try_bind")


func _try_bind() -> void:
	if not is_instance_valid(xr_camera):
		xr_camera = get_tree().get_first_node_in_group("xr_camera") as XRCamera3D

	if xr_camera and alert_label == null:
		_create_feedback_hud()

	var main := get_tree().current_scene
	if main == null:
		return

	var root := main.get_node_or_null("EnemyRoot") as Node3D
	if root == null:
		return

	var root_id := root.get_instance_id()
	if root_id == bound_enemy_root_id:
		return

	enemy_root = root
	bound_enemy_root_id = root_id

	if not enemy_root.child_entered_tree.is_connected(_on_enemy_added):
		enemy_root.child_entered_tree.connect(_on_enemy_added)


func _create_feedback_hud() -> void:
	alert_label = Label3D.new()
	alert_label.name = "TiboDirectionAlert"
	alert_label.position = Vector3(0, 0.30, -1.35)
	alert_label.font_size = 58
	alert_label.outline_size = 12
	alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alert_label.text = ""
	xr_camera.add_child(alert_label)

	score_label = Label3D.new()
	score_label.name = "TiboScore"
	score_label.position = Vector3(0.68, 0.50, -1.55)
	score_label.font_size = 34
	score_label.outline_size = 8
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.visible = false
	xr_camera.add_child(score_label)

	_update_score()


func _on_enemy_added(node: Node) -> void:
	if not node.is_in_group("tibo"):
		return

	if node.has_signal("defeated"):
		var defeated_callable := Callable(self, "_on_tibo_defeated")
		if not node.is_connected("defeated", defeated_callable):
			node.connect("defeated", defeated_callable)

	call_deferred("_announce_enemy", node)


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


func _on_tibo_defeated(_tibo: Node) -> void:
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

	score += points
	_update_score()


func _update_score() -> void:
	if score_label == null:
		return

	score_label.text = "SCORE %06d\nKO %d" % [score, ko_count]
