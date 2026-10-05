extends Node

# Bruitages fabriques par le code au demarrage : aucun fichier audio a importer.

const RATE := 22050
const POOL_2D := 6
const POOL_3D := 10

const SOUND_NAMES := [
	"click", "start", "back", "punch", "punch_strong", "shovel", "whoosh",
	"hurt", "windup", "ko", "wave", "boss", "gameover", "combo",
	"block", "guard", "grab", "drink", "glass", "heal",
	"spawn", "alert", "record"
]

var sounds: Dictionary = {}
var players_2d: Array[AudioStreamPlayer] = []
var players_3d: Array[AudioStreamPlayer3D] = []
var next_2d := 0
var next_3d := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = 20261005

	for i in POOL_2D:
		var player := AudioStreamPlayer.new()
		add_child(player)
		players_2d.append(player)

	for i in POOL_3D:
		var player3d := AudioStreamPlayer3D.new()
		player3d.unit_size = 4.0
		player3d.max_distance = 25.0
		add_child(player3d)
		players_3d.append(player3d)

	_generate_all()


func _generate_all() -> void:
	for sound_name in SOUND_NAMES:
		sounds[sound_name] = call("_make_" + String(sound_name))
		await get_tree().process_frame


func play_sfx(sfx_name: String, pos: Variant = null, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream = sounds.get(sfx_name)

	if stream == null:
		return

	var pitch_value := pitch * rng.randf_range(0.94, 1.06)

	if pos is Vector3:
		var player3d := players_3d[next_3d]
		next_3d = (next_3d + 1) % players_3d.size()
		player3d.stream = stream
		player3d.volume_db = volume_db
		player3d.pitch_scale = pitch_value
		player3d.global_position = pos
		player3d.play()
	else:
		var player := players_2d[next_2d]
		next_2d = (next_2d + 1) % players_2d.size()
		player.stream = stream
		player.volume_db = volume_db
		player.pitch_scale = pitch_value
		player.play()


func _build(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)

	for i in samples.size():
		var value := clampi(int(samples[i] * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, value)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


func _buffer(duration: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(duration * RATE))
	return buf


func _melody(freqs: Array, step: float, total: float, decay: float, harsh: float) -> AudioStreamWAV:
	var out := _buffer(total)

	for i in out.size():
		var t := float(i) / RATE
		var s := 0.0

		for k in freqs.size():
			var tl := t - k * step

			if tl < 0.0:
				continue

			var f: float = freqs[k]
			var env := exp(-tl * decay) * minf(1.0, tl * 200.0)
			s += (
				sin(TAU * f * tl)
				+ harsh * sin(TAU * f * 2.0 * tl)
				+ harsh * 0.5 * sin(TAU * f * 3.0 * tl)
			) * env

		out[i] = tanh(s * 0.5) * 0.7

	return _build(out)


func _make_click() -> AudioStreamWAV:
	var out := _buffer(0.07)

	for i in out.size():
		var t := float(i) / RATE
		out[i] = (
			sin(TAU * 900.0 * t) * exp(-t * 55.0) * 0.6
			+ sin(TAU * 1800.0 * t) * exp(-t * 70.0) * 0.2
		)

	return _build(out)


func _make_start() -> AudioStreamWAV:
	return _melody([440.0, 554.4, 659.3, 880.0], 0.09, 0.55, 8.0, 0.4)


func _make_back() -> AudioStreamWAV:
	return _melody([660.0, 440.0], 0.05, 0.18, 20.0, 0.1)


func _make_wave() -> AudioStreamWAV:
	return _melody([330.0, 330.0, 494.0], 0.16, 0.8, 5.0, 0.3)


func _make_combo() -> AudioStreamWAV:
	return _melody([880.0, 1320.0], 0.06, 0.25, 14.0, 0.1)


func _make_gameover() -> AudioStreamWAV:
	return _melody([392.0, 330.0, 262.0, 196.0], 0.25, 1.3, 4.0, 0.7)


func _make_punch() -> AudioStreamWAV:
	var out := _buffer(0.20)
	var phase := 0.0
	var lp := 0.0

	for i in out.size():
		var t := float(i) / RATE
		var freq := 50.0 + 130.0 * exp(-t * 38.0)
		phase += TAU * freq / RATE
		var thump := sin(phase) * exp(-t * 20.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.30
		var crack := lp * exp(-t * 55.0)
		out[i] = tanh((thump * 1.1 + crack * 1.2) * 1.4) * 0.85

	return _build(out)


func _make_punch_strong() -> AudioStreamWAV:
	var out := _buffer(0.32)
	var phase := 0.0
	var lp := 0.0

	for i in out.size():
		var t := float(i) / RATE
		var freq := 40.0 + 170.0 * exp(-t * 30.0)
		phase += TAU * freq / RATE
		var thump := sin(phase) * exp(-t * 13.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.50
		var crack := lp * exp(-t * 35.0)
		var sub := sin(TAU * 38.0 * t) * exp(-t * 9.0) * 0.6
		out[i] = tanh((thump * 1.2 + crack * 1.4 + sub) * 2.0) * 0.9

	return _build(out)


func _make_shovel() -> AudioStreamWAV:
	var out := _buffer(0.55)
	var partials := [
		[430.0, 1.0, 9.0],
		[612.0, 0.8, 11.0],
		[947.0, 0.6, 14.0],
		[1331.0, 0.5, 18.0],
		[1710.0, 0.3, 24.0]
	]

	for i in out.size():
		var t := float(i) / RATE
		var s := 0.0

		for partial in partials:
			var f: float = partial[0]
			var amp: float = partial[1]
			var decay: float = partial[2]
			s += sin(TAU * f * t) * amp * exp(-t * decay)

		var thump := sin(TAU * 70.0 * t) * exp(-t * 25.0)
		var tick := rng.randf_range(-1.0, 1.0) * exp(-t * 120.0)
		out[i] = tanh(s * 0.55 + thump * 0.9 + tick * 0.6) * 0.8

	return _build(out)


func _make_whoosh() -> AudioStreamWAV:
	var duration := 0.30
	var out := _buffer(duration)
	var lp := 0.0

	for i in out.size():
		var t := float(i) / RATE
		var env := pow(sin(PI * t / duration), 2.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.08 + 0.5 * env)
		out[i] = tanh(lp * env * 2.4) * 0.7

	return _build(out)


func _make_hurt() -> AudioStreamWAV:
	var out := _buffer(0.40)
	var phase := 0.0
	var phase2 := 0.0

	for i in out.size():
		var t := float(i) / RATE
		phase += TAU * (35.0 + 65.0 * exp(-t * 10.0)) / RATE
		phase2 += (70.0 + 110.0 * exp(-t * 8.0)) / RATE
		var thump := sin(phase) * exp(-t * 9.0)
		var saw := (fposmod(phase2, 1.0) * 2.0 - 1.0) * exp(-t * 7.0) * 0.5
		var burst := rng.randf_range(-1.0, 1.0) * exp(-t * 30.0) * 0.6
		out[i] = tanh((thump * 1.2 + saw + burst) * 1.6) * 0.85

	return _build(out)


func _make_windup() -> AudioStreamWAV:
	var duration := 0.55
	var out := _buffer(duration)
	var phase := 0.0
	var lp := 0.0

	for i in out.size():
		var t := float(i) / RATE
		var k := t / duration
		phase += (80.0 + 150.0 * pow(k, 1.5)) / RATE
		var saw := fposmod(phase, 1.0) * 2.0 - 1.0
		lp += (saw - lp) * 0.25
		var tremolo := 1.0 + 0.4 * sin(TAU * 18.0 * t)
		var fade := minf(1.0, (1.0 - k) * 12.0)
		out[i] = lp * k * tremolo * fade * 0.9

	return _build(out)


func _make_ko() -> AudioStreamWAV:
	var out := _buffer(0.60)
	var phase := 0.0

	for i in out.size():
		var t := float(i) / RATE
		phase += (60.0 + 380.0 * exp(-t * 3.2)) / RATE
		var tone := (sin(phase * TAU) * 0.6 + (fposmod(phase, 1.0) * 2.0 - 1.0) * 0.3) * exp(-t * 4.5)
		var burst := rng.randf_range(-1.0, 1.0) * exp(-t * 25.0) * 0.5
		out[i] = tanh((tone + burst) * 1.5) * 0.85

	return _build(out)


func _make_boss() -> AudioStreamWAV:
	var duration := 1.0
	var out := _buffer(duration)
	var phase_a := 0.0
	var phase_b := 0.0
	var lp := 0.0

	for i in out.size():
		var t := float(i) / RATE
		phase_a += 55.0 / RATE
		phase_b += 58.0 / RATE
		var saw := (fposmod(phase_a, 1.0) + fposmod(phase_b, 1.0)) - 1.0
		lp += (saw - lp) * 0.12
		var growl := 1.0 + 0.5 * sin(TAU * 7.0 * t)
		var env := sqrt(sin(PI * t / duration))
		var sub := sin(TAU * 110.0 * t) * 0.4
		out[i] = tanh((lp * 2.2 * growl + sub) * env * 1.4) * 0.9

	return _build(out)


func _make_block() -> AudioStreamWAV:
	var out := _buffer(0.28)
	var lp := 0.0

	for i in out.size():
		var t := float(i) / RATE
		var thump := sin(TAU * 90.0 * t) * exp(-t * 24.0)
		var ping := sin(TAU * 1400.0 * t) * exp(-t * 30.0) * 0.5 + sin(TAU * 2100.0 * t) * exp(-t * 42.0) * 0.3
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.4
		var tick := lp * exp(-t * 90.0) * 0.6
		out[i] = tanh((thump * 1.1 + ping + tick) * 1.5) * 0.85

	return _build(out)


func _make_guard() -> AudioStreamWAV:
	return _melody([520.0, 780.0], 0.04, 0.16, 22.0, 0.1)


func _make_grab() -> AudioStreamWAV:
	return _melody([500.0, 750.0], 0.03, 0.14, 30.0, 0.2)


func _make_heal() -> AudioStreamWAV:
	return _melody([523.0, 659.0, 784.0], 0.07, 0.5, 8.0, 0.2)


func _make_drink() -> AudioStreamWAV:
	var out := _buffer(0.75)
	var phase := 0.0

	for i in out.size():
		var t := float(i) / RATE
		var s_val := 0.0

		for gulp in 3:
			var u := (t - gulp * 0.22) / 0.16

			if u < 0.0 or u > 1.0:
				continue

			var env := sin(PI * u)
			var freq := 230.0 - 110.0 * u
			phase += TAU * freq / RATE
			s_val += (sin(phase) + 0.4 * sin(phase * 2.0)) * env * 0.5

		out[i] = tanh(s_val * 1.3) * 0.7

	return _build(out)


func _make_glass() -> AudioStreamWAV:
	var out := _buffer(0.55)
	var lp := 0.0
	var tinkles: Array = []

	for k in 7:
		tinkles.append([rng.randf_range(0.0, 0.25), rng.randf_range(2500.0, 6500.0), rng.randf_range(22.0, 45.0)])

	for i in out.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.15
		var crash := (noise - lp) * exp(-t * 16.0)
		var ring := 0.0

		for tinkle in tinkles:
			var tl: float = t - float(tinkle[0])

			if tl < 0.0:
				continue

			ring += sin(TAU * float(tinkle[1]) * tl) * exp(-tl * float(tinkle[2])) * 0.25

		out[i] = tanh(crash * 1.2 + ring) * 0.75

	return _build(out)


func _make_alert() -> AudioStreamWAV:
	return _melody([1100.0, 1100.0], 0.09, 0.26, 18.0, 0.5)


func _make_record() -> AudioStreamWAV:
	return _melody([523.0, 659.0, 784.0, 1047.0], 0.12, 1.0, 4.0, 0.3)


func _make_spawn() -> AudioStreamWAV:
	var duration := 0.5
	var pop_time := 0.42
	var out := _buffer(duration)
	var phase := 0.0
	var lp := 0.0

	for i in out.size():
		var t := float(i) / RATE
		var k := t / duration
		phase += TAU * (50.0 + 140.0 * k) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.05 + 0.3 * k)

		var env := pow(t / pop_time, 2.0) if t < pop_time else exp(-(t - pop_time) * 40.0)
		var body := (sin(phase) * 0.8 + lp * 1.5) * env
		var pop := 0.0

		if t >= pop_time:
			pop = sin(TAU * 160.0 * (t - pop_time)) * exp(-(t - pop_time) * 30.0) * 0.6

		out[i] = tanh((body + pop) * 1.4) * 0.7

	return _build(out)
