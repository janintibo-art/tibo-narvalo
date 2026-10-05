extends Node

var enemy_root: Node3D
var bound_enemy_root_id := 0
var boss_wave_done := -1
var pending_boss_wave := -1


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
	var wave_value = main.get("wave")

	if state_value == null or wave_value == null:
		return

	var state := String(state_value)
	var current_wave := int(wave_value)

	if state != "playing":
		pending_boss_wave = -1
		return

	if current_wave > 0 and current_wave % 5 == 0 and current_wave != boss_wave_done:
		pending_boss_wave = current_wave


func _on_node_added(_node: Node) -> void:
	call_deferred("_try_bind")


func _try_bind() -> void:
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


func _on_enemy_added(node: Node) -> void:
	if pending_boss_wave <= 0:
		return

	if pending_boss_wave == boss_wave_done:
		return

	if not node.is_in_group("tibo"):
		return

	var wave_to_claim := pending_boss_wave
	boss_wave_done = wave_to_claim
	pending_boss_wave = -1

	call_deferred("_make_boss", node, wave_to_claim)


func _make_boss(node: Node, wave_number: int) -> void:
	if not is_instance_valid(node):
		return

	if not node is Node3D:
		return

	var enemy := node as Node3D

	var max_health_value = enemy.get("max_health")
	if max_health_value != null:
		var boss_health := maxi(250, int(max_health_value) * 2)
		enemy.set("max_health", boss_health)
		enemy.set("health", boss_health)

	var attack_value = enemy.get("attack_damage")
	if attack_value != null:
		enemy.set("attack_damage", maxi(18, int(attack_value) + 8))

	var speed_value = enemy.get("move_speed")
	if speed_value != null:
		enemy.set("move_speed", float(speed_value) * 0.88)

	enemy.scale = Vector3.ONE * 1.35
	enemy.set_meta("is_boss", true)
	enemy.set_meta("boss_wave", wave_number)

	var label := enemy.get_node_or_null("Name") as Label3D
	if label:
		var health_value = enemy.get("health")
		var shown_health := 250

		if health_value != null:
			shown_health = int(health_value)

		label.text = "MEGA TIBO  %d" % shown_health
		label.font_size = 56

	var feedback := get_node_or_null("/root/GameFeedback")
	if feedback:
		var alert = feedback.get("alert_label")

		if alert is Label3D:
			(alert as Label3D).text = "BOSS : MEGA TIBO !"

	GameAudio.play_sfx("boss")
	print("Tibo Narvalo : MEGA TIBO vague %d." % wave_number)
