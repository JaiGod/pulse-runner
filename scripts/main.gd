extends Node2D
## Pulse Runner - state machine, input, menus and gameplay rules.
## All visuals are drawn in code (see view.gd); all audio is synthesized (synth.gd).

const W_PERFECT := 0.045
const W_GREAT := 0.09
const W_GOOD := 0.135
const JNAME := ["PERFECT", "GREAT", "GOOD", "MISS"]
const JCOL := [Color("#ffe45c"), Color("#2cf6ff"), Color("#7dff8a"), Color("#ff4d6d")]
const LANE_COL := [Color("#2cf6ff"), Color("#ff3cac"), Color("#ff9f2c")]
const SAVE_PATH := "user://pulse_runner.cfg"
const KEYS := [[KEY_A, KEY_LEFT], [KEY_S, KEY_DOWN], [KEY_D, KEY_RIGHT]]
const LANES := 3

var state := "title"
var settings := {"speed": 1.0, "offset": 0, "mode": 0, "sound": true, "hits": true}
var best := {}
var sel := 0
var diff := 1
var focus := 0
var btns: Array = []
var anim := 0.0       # free-running time for menu animation
var trans := 0.0      # screen transition ease
var auto := false

var music: AudioStreamPlayer
var sfx: AudioStreamPlayer
var tick_stream: AudioStreamWAV
var title_job
var title_stream: AudioStreamWAV
var streams := {}
var comps := {}
var job
var job_song := -1

# clock
var t0_us := 0
var lead_in := 0.0
var clock_on := false
var paused_e := 0.0
var resume_cd := 0.0
var song_len := 0.0
var bpm := 120.0

# play state
var notes: Array = []   # [t, lane, judgment(-1), hit_t]
var scan := 0
var t_now := -9.0
var score := 0
var combo := 0
var max_combo := 0
var counts := [0, 0, 0, 0]
var health := 1.0
var fever := 0.0
var fever_until := -1.0
var failed := false
var last_t := 0.0
var result := {}
var pressed := [false, false, false]
var flash := [0.0, 0.0, 0.0]
var pop := {"text": "", "col": Color.WHITE, "t": 9.0, "ms": 0}
var parts: Array = []
var shake := 0.0
var runner := {"x": 1.0, "lane": 1, "jump": 9.0, "slide": 9.0, "dash": 9.0, "trip": 9.0}

# calibration
var cal_taps: Array = []
var cal_stream: AudioStreamWAV
var cal_t0 := 0
const CAL_BPM := 100.0

var view = preload("res://scripts/view.gd")
var js_t := 0.0
var title_t0 := 0

func _ready() -> void:
	randomize()
	_load()
	music = AudioStreamPlayer.new()
	add_child(music)
	sfx = AudioStreamPlayer.new()
	sfx.max_polyphony = 6
	sfx.volume_db = -6.0
	add_child(sfx)
	tick_stream = _quick([[0.0, "T:3:96:0.03", 0.5], [0.0, "H", 0.5]], 0.12)
	sfx.stream = tick_stream
	AudioServer.set_bus_mute(0, not settings.sound)
	# title loop: 4 bars of the first song's chorus
	var s0: Dictionary = Music.SONGS[0]
	var comp := Music.compose(s0)
	var ch_start := 0
	for sc in comp.sections:
		if sc[1] == "chorus":
			ch_start = sc[0]; break
	var evs := []
	for e in Music.render_events(comp, 0.0):
		var st: float = e[0] / comp.step_sec
		if st >= ch_start and st < ch_start + 64:
			evs.append([e[0] - ch_start * comp.step_sec, e[1], e[2]])
	title_job = Synth.Job.new(evs, 64 * comp.step_sec)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("location.search", true)
		auto = str(q).find("auto") >= 0

func _quick(evs: Array, sec: float) -> AudioStreamWAV:
	return Synth.Job.new(evs, sec).finish()

# ------------------------------------------------------------------ save
func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cf.get_value("settings", k, settings[k])
	# v2 saves: the default chart speed was halved (2.0 -> 1.0); migrate old saves once
	if int(cf.get_value("settings", "v", 1)) < 2:
		settings.speed = 1.0
	best = cf.get_value("scores", "best", {})
	sel = clampi(int(cf.get_value("ui", "sel", 0)), 0, Music.SONGS.size() - 1)
	diff = clampi(int(cf.get_value("ui", "diff", 1)), 0, 2)

func _save() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.set_value("settings", "v", 2)
	cf.set_value("scores", "best", best)
	cf.set_value("ui", "sel", sel)
	cf.set_value("ui", "diff", diff)
	cf.save(SAVE_PATH)

# ------------------------------------------------------------------ clock
func elapsed() -> float:
	if not clock_on:
		return paused_e
	return float(Time.get_ticks_usec() - t0_us) / 1000000.0

func song_time() -> float:
	var lat := clampf(AudioServer.get_output_latency(), 0.0, 0.25)
	return elapsed() - lead_in - lat - float(settings.offset) / 1000.0

func beat_phase() -> float:
	if state in ["play", "pause", "results", "loading"] and clock_on:
		return fposmod(song_time() * bpm / 60.0, 1.0)
	if state == "calib":
		return fposmod(float(Time.get_ticks_usec() - cal_t0) / 1000000.0 * CAL_BPM / 60.0, 1.0)
	if music.playing and music.stream == title_stream:
		return fposmod(float(Time.get_ticks_usec() - title_t0) / 1000000.0 * Music.SONGS[0].bpm / 60.0, 1.0)
	return fposmod(anim * 2.0, 1.0)

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	anim += delta
	trans = minf(1.0, trans + delta * 4.0)
	if title_job and not title_job.done:
		title_job.step(4000)
		if title_job.done:
			title_stream = title_job.stream
			title_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			title_stream.loop_end = title_stream.data.size() / 2
			if state in ["title", "select", "howto", "settings"]:
				_title_music()
	match state:
		"loading":
			_update_loading()
		"play":
			_update_play(delta)
		"calib":
			pass
	for i in LANES:
		flash[i] = maxf(0.0, flash[i] - delta * 5.0)
	pop.t += delta
	shake = maxf(0.0, shake - delta * 2.5)
	runner.jump += delta; runner.slide += delta; runner.dash += delta; runner.trip += delta
	runner.x = lerpf(runner.x, float(runner.lane), minf(1.0, delta * 16.0))
	var keep := []
	for p in parts:
		p.life -= delta
		if p.life > 0.0:
			p.pos += p.vel * delta
			p.vel *= 0.92
			p.vel.y += 300.0 * delta
			keep.append(p)
	parts = keep
	js_t += delta
	if js_t > 0.25 and OS.has_feature("web"):
		js_t = 0.0
		_js_sync()
	queue_redraw()

func _js_sync() -> void:
	var cmd = JavaScriptBridge.eval("(function(){var c=window.__prCmd||'';window.__prCmd='';return c;})()", true)
	if typeof(cmd) == TYPE_STRING and cmd != "":
		_cmd(cmd)
	var a = JavaScriptBridge.eval("window.__prAuto===undefined?-1:(window.__prAuto?1:0)", true)
	if a != null and int(a) >= 0:
		auto = int(a) == 1
	var pp := music.get_playback_position() if music.playing else -1.0
	var d := {"state": state, "t": snappedf(t_now, 0.001), "e": snappedf(elapsed(), 0.001),
		"pp": snappedf(pp, 0.001), "lat": AudioServer.get_output_latency(), "score": score,
		"combo": combo, "counts": counts, "health": snappedf(health, 0.01), "auto": auto,
		"notes": notes.size(), "load": job.progress() if job else 1.0, "result": result}
	JavaScriptBridge.eval("window.__pr=" + JSON.stringify(d) + ";", true)

## Test / automation commands (also used by the screenshot + smoke tests)
func _cmd(c: String) -> void:
	var p := c.split(":")
	match p[0]:
		"start":
			sel = int(p[1]); diff = int(p[2])
			if p.size() > 3:
				settings.mode = int(p[3])
			start_song()
		"auto":
			auto = p.size() < 2 or p[1] != "0"
		"state":
			goto(p[1])
		"key":
			hit(int(p[1]))

func goto(s: String) -> void:
	state = s
	focus = 0
	trans = 0.0
	if s in ["title", "select", "howto", "settings"]:
		_title_music()

func _title_music() -> void:
	if title_stream and (music.stream != title_stream or not music.playing):
		music.stream = title_stream
		music.play()
		title_t0 = Time.get_ticks_usec()

# ------------------------------------------------------------------ song flow
func start_song() -> void:
	var s: Dictionary = Music.SONGS[sel]
	_save()
	music.stop()
	bpm = s.bpm
	lead_in = Music.lead_in_for(s)
	if not comps.has(sel):
		comps[sel] = Music.compose(s)
	var comp: Dictionary = comps[sel]
	song_len = Music.length_sec(comp, lead_in)
	notes = []
	for n in Music.chart(comp, diff):
		notes.append([n[0], n[1], -1, 0.0])
	last_t = notes[-1][0] if notes.size() > 0 else 10.0
	job_song = sel
	if streams.has(sel):
		job = null
	else:
		job = Synth.Job.new(Music.render_events(comp, lead_in), song_len)
	clock_on = false
	paused_e = 0.0
	goto("loading")

func _update_loading() -> void:
	if job and not job.done:
		job.step(11000)
		return
	if job and job.done:
		streams[job_song] = job.stream
		job = null
	_begin()

func _begin() -> void:
	scan = 0; score = 0; combo = 0; max_combo = 0; counts = [0, 0, 0, 0]
	health = 1.0; fever = 0.0; fever_until = -1.0; failed = false; result = {}
	parts = []; pop.t = 9.0
	runner = {"x": 1.0, "lane": 1, "jump": 9.0, "slide": 9.0, "dash": 9.0, "trip": 9.0}
	for n in notes:
		n[2] = -1
	music.stream = streams[sel]
	music.play()
	t0_us = Time.get_ticks_usec()
	clock_on = true
	resume_cd = 0.0
	state = "play"
	trans = 1.0

func pause_game() -> void:
	if state != "play":
		return
	paused_e = elapsed()
	clock_on = false
	music.stop()
	goto("pause")

func resume_game() -> void:
	state = "play"
	resume_cd = 1.0

func _update_play(delta: float) -> void:
	if resume_cd > 0.0:
		resume_cd -= delta
		if resume_cd <= 0.0:
			music.play(paused_e)
			t0_us = Time.get_ticks_usec() - int(paused_e * 1000000.0)
			clock_on = true
		return
	t_now = song_time()
	if auto:
		var i := scan
		while i < notes.size() and notes[i][0] <= t_now:
			if notes[i][2] == -1:
				_judge(i, 0.0)
				flash[notes[i][1]] = 1.0
			i += 1
	while scan < notes.size() and (notes[scan][2] != -1 or notes[scan][0] < t_now - W_GOOD):
		if notes[scan][2] == -1:
			_judge(scan, W_GOOD + 1.0)
		scan += 1
	if fever_until > 0.0 and t_now > fever_until:
		fever_until = -1.0
		fever = 0.0
	if failed:
		return
	if t_now > last_t + 2.0 or elapsed() > song_len:
		_finish(false)

func hit(lane: int) -> void:
	flash[lane] = 1.0
	if settings.hits:
		sfx.play()
	if state != "play" or resume_cd > 0.0:
		return
	var t := song_time()
	var bi := -1
	var bd := 99.0
	var i := scan
	while i < notes.size() and notes[i][0] <= t + W_GOOD:
		if notes[i][2] == -1 and notes[i][1] == lane:
			var d := absf(notes[i][0] - t)
			if d < bd:
				bd = d; bi = i
		i += 1
	if bi >= 0 and bd <= W_GOOD:
		_judge(bi, t - notes[bi][0])

func in_fever() -> bool:
	return fever_until > 0.0

func _judge(i: int, dt: float) -> void:
	var a := absf(dt)
	var j := 3
	if a <= W_PERFECT: j = 0
	elif a <= W_GREAT: j = 1
	elif a <= W_GOOD: j = 2
	notes[i][2] = j
	notes[i][3] = t_now
	counts[j] += 1
	var lane: int = notes[i][1]
	var fv := in_fever()
	if j < 3:
		combo += 1
		max_combo = maxi(max_combo, combo)
		score += [300, 200, 100][j] * mult() * (2 if fv else 1)
		health = minf(1.0, health + [0.02, 0.015, 0.006][j])
		if not fv:
			fever = minf(1.0, fever + [0.034, 0.02, 0.006][j])
			if fever >= 1.0:
				fever_until = t_now + 16.0 * 60.0 / bpm
				shake = 0.6
				_burst(Vector2(get_viewport_rect().size.x / 2, get_viewport_rect().size.y * 0.4), Color("#ffe45c"), 40)
		runner.lane = lane
		# A = jump the hurdle, S = slide under the gate, D = dash through the barrier
		runner.jump = 0.0 if lane == 0 else 9.0
		runner.slide = 0.0 if lane == 1 else 9.0
		runner.dash = 0.0 if lane == 2 else 9.0
		var p: Vector2 = view.lane_hit_pos(self, lane)
		_burst(p, LANE_COL[lane] if j > 0 else Color("#ffe45c"), 14 if j == 0 else 8)
	else:
		combo = 0
		health -= [0.04, 0.055, 0.07][diff]
		if not fv:
			fever = maxf(0.0, fever - 0.12)
		shake = maxf(shake, 0.35)
		runner.trip = 0.0
		if health <= 0.0 and not failed:
			health = 0.0
			_finish(true)
	pop = {"text": JNAME[j], "col": JCOL[j], "t": 0.0, "ms": int(round(dt * 1000.0)) if j < 3 else 0}

func mult() -> int:
	return mini(4, 1 + combo / 10)

func accuracy() -> float:
	var n: int = counts[0] + counts[1] + counts[2] + counts[3]
	if n == 0:
		return 1.0
	return (counts[0] + counts[1] * 0.7 + counts[2] * 0.4) / float(n)

static func grade_for(acc: float) -> String:
	if acc >= 0.95: return "S"
	if acc >= 0.88: return "A"
	if acc >= 0.78: return "B"
	if acc >= 0.65: return "C"
	return "D"

func _finish(fail: bool) -> void:
	failed = fail
	var acc := accuracy()
	var g := "F" if fail else grade_for(acc)
	var key := "%s:%d" % [Music.SONGS[sel].id, diff]
	var prev: Dictionary = best.get(key, {})
	var fc: bool = not fail and counts[3] == 0
	var nb: bool = not fail and score > int(prev.get("score", 0))
	if nb:
		best[key] = {"score": score, "grade": g, "acc": acc, "fc": fc or bool(prev.get("fc", false))}
		_save()
	result = {"score": score, "grade": g, "acc": acc, "fc": fc, "new": nb, "fail": fail, "max": max_combo}
	if fail:
		music.stop()
		clock_on = false
		shake = 1.0
	goto("results")
	trans = 0.0

func _burst(p: Vector2, c: Color, n: int) -> void:
	for k in n:
		if parts.size() > 260:
			parts.pop_front()
		var a := randf() * TAU
		var sp := randf_range(120.0, 420.0)
		parts.append({"pos": p, "vel": Vector2(cos(a), sin(a) * 0.8 - 0.5) * sp, "life": randf_range(0.3, 0.7), "col": c})

# ------------------------------------------------------------------ calibration
func start_calib() -> void:
	if cal_stream == null:
		var beat := 60.0 / CAL_BPM
		var evs := []
		for i in 64:
			evs.append([i * beat, "C:%d" % (1760 if i % 4 == 0 else 1100), 0.8])
			evs.append([i * beat, "K", 0.5])
		cal_stream = _quick(evs, 64 * beat + 0.5)
	music.stream = cal_stream
	music.play()
	cal_t0 = Time.get_ticks_usec() + int(clampf(AudioServer.get_output_latency(), 0.0, 0.25) * 1000000.0)
	cal_taps = []
	goto("calib")

func calib_tap() -> void:
	var beat := 60.0 / CAL_BPM
	var t := float(Time.get_ticks_usec() - cal_t0) / 1000000.0
	if t < beat * 3.5:
		return
	var d: float = t - round(t / beat) * beat
	cal_taps.append(d)
	if cal_taps.size() > 16:
		cal_taps.pop_front()

func calib_value() -> int:
	if cal_taps.size() < 4:
		return int(settings.offset)
	var s := cal_taps.duplicate()
	s.sort()
	return int(round(s[s.size() / 2] * 1000.0))

# ------------------------------------------------------------------ input
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev.keycode)
	elif ev is InputEventKey and not ev.pressed:
		for l in LANES:
			if ev.keycode in KEYS[l]:
				pressed[l] = false
	elif ev is InputEventScreenTouch:
		var pos: Vector2 = get_canvas_transform().affine_inverse() * ev.position
		if ev.pressed:
			_touch(pos, ev.index)
		elif state == "play":
			for l in LANES:
				pressed[l] = false

func _key(k: int) -> void:
	if state == "play":
		for l in LANES:
			if k in KEYS[l]:
				pressed[l] = true
				hit(l)
				return
		if k in [KEY_ESCAPE, KEY_P, KEY_SPACE]:
			pause_game()
		return
	if state == "calib":
		if k == KEY_ESCAPE:
			music.stop(); goto("settings")
		elif k == KEY_ENTER:
			settings.offset = calib_value(); _save(); music.stop(); goto("settings")
		else:
			calib_tap()
		return
	if state == "loading":
		return
	if k == KEY_M:
		_act("snd"); return
	if state == "select":
		match k:
			KEY_UP, KEY_W: sel = (sel + 7) % 8
			KEY_DOWN, KEY_S: sel = (sel + 1) % 8
			KEY_LEFT, KEY_A: diff = (diff + 2) % 3
			KEY_RIGHT, KEY_D: diff = (diff + 1) % 3
			KEY_TAB, KEY_R: _act("mode")
			KEY_ENTER, KEY_SPACE: _act("start")
			KEY_ESCAPE, KEY_BACKSPACE: _act("back")
		return
	match k:
		KEY_UP, KEY_W, KEY_LEFT:
			focus = (focus + btns.size() - 1) % maxi(1, btns.size())
		KEY_DOWN, KEY_S, KEY_RIGHT, KEY_TAB:
			focus = (focus + 1) % maxi(1, btns.size())
		KEY_ENTER, KEY_SPACE:
			if focus < btns.size():
				_act(btns[focus].id)
		KEY_ESCAPE, KEY_BACKSPACE:
			if state == "pause": _act("resume")
			elif state != "title": _act("back")

func _touch(pos: Vector2, _idx: int) -> void:
	if state == "play":
		var r: Rect2 = view.pause_rect(self)
		if r.grow(10).has_point(pos):
			pause_game(); return
		var w := get_viewport_rect().size.x
		var l := clampi(int(pos.x / w * 3.0), 0, 2)
		pressed[l] = true
		hit(l)
		return
	if state == "calib":
		for b in btns:
			if b.r.has_point(pos):
				_act(b.id); return
		calib_tap(); return
	for b in btns:
		if b.r.has_point(pos):
			_act(b.id)
			return

func _act(id: String) -> void:
	if settings.hits and id != "snd":
		pass
	if id.begins_with("song:"):
		var n := int(id.substr(5))
		if n == sel and state == "select":
			start_song()
		else:
			sel = n
		return
	if id.begins_with("diff:"):
		diff = int(id.substr(5)); return
	match id:
		"play": goto("select")
		"howto": goto("howto")
		"settings": goto("settings")
		"back":
			if state == "results": goto("select")
			elif state in ["select", "howto"]: goto("title")
			elif state == "settings": _save(); goto("title")
			elif state == "calib": music.stop(); goto("settings")
		"start": start_song()
		"mode": settings.mode = 1 - int(settings.mode); _save()
		"snd":
			settings.sound = not settings.sound
			AudioServer.set_bus_mute(0, not settings.sound)
			_save()
		"hits": settings.hits = not settings.hits
		"spd-": settings.speed = maxf(0.5, settings.speed - 0.25)
		"spd+": settings.speed = minf(5.0, settings.speed + 0.25)
		"off-": settings.offset = int(settings.offset) - 5
		"off+": settings.offset = int(settings.offset) + 5
		"off0": settings.offset = 0
		"calib": start_calib()
		"calsave": settings.offset = calib_value(); _save(); music.stop(); goto("settings")
		"resume": resume_game()
		"retry", "restart": start_song()
		"songs": music.stop(); goto("select")

# ------------------------------------------------------------------ draw
func _draw() -> void:
	btns = []
	view.draw_all(self)

func button(r: Rect2, label: String, id: String, accent := Color("#2cf6ff"), sz := 26) -> void:
	var f := btns.size() == focus and state != "select"
	btns.append({"r": r, "id": id})
	view.draw_button(self, r, label, accent, f, sz)
