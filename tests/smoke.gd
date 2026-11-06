extends Node
## Headless smoke test: composes all 8 songs, checks the 24 charts, renders
## one track, autoplays a whole chart (expects S + full combo), plays a run
## with no input (expects a fail) and walks every menu screen.
var main
var fails := 0

func check(c: bool, msg: String) -> void:
	print(("  ok   " if c else "  FAIL ") + msg)
	if not c:
		fails += 1

func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	get_tree().create_timer(280.0).timeout.connect(func(): print("SMOKE TIMEOUT"); get_tree().quit(2))
	await get_tree().process_frame
	_run()

func _sim_song(auto: bool, max_sec: float) -> void:
	# fast-forward the song clock by shifting t0 back each frame
	main.auto = auto
	var t := 0.0
	while main.state == "play" and t < max_sec:
		main.t0_us -= 12000
		t += 0.012
		await get_tree().process_frame

func _run() -> void:
	for i in Music.SONGS.size():
		var s: Dictionary = Music.SONGS[i]
		var comp := Music.compose(s)
		var c := []
		for d in 3:
			var ch := Music.chart(comp, d)
			c.append(ch.size())
			var ok := true
			for k in range(1, ch.size()):
				if ch[k][0] < ch[k - 1][0] - 0.0001 or ch[k][1] < 0 or ch[k][1] > 2:
					ok = false
			check(ok and ch.size() > 40, "%s %s chart sorted, %d notes" % [s.name, Music.DIFFS[d], ch.size()])
		check(c[0] < c[1] and c[1] < c[2], "%s difficulty ramps %s" % [s.name, str(c)])
	# menus
	for st in ["title", "select", "howto", "settings"]:
		main.goto(st)
		for f in 3: await get_tree().process_frame
		check(main.btns.size() > 0, "menu %s has buttons (%d)" % [st, main.btns.size()])
	main.start_calib()
	for f in 3: await get_tree().process_frame
	check(main.state == "calib", "calibration opens")
	main._act("back")
	# autoplay full song 0 normal, lanes
	main._cmd("start:0:1:0")
	var guard := 0
	while main.state == "loading" and guard < 2000:
		guard += 1
		await get_tree().process_frame
	check(main.state == "play", "track synthesized and playing (frames %d)" % guard)
	await _sim_song(true, 200.0)
	check(main.state == "results", "song finished -> results")
	check(main.result.get("grade", "") == "S" and main.result.get("fc", false), "autoplay gets S + full combo: %s" % str(main.result))
	check(main.counts[0] == main.notes.size(), "all perfect %d/%d" % [main.counts[0], main.notes.size()])
	check(main.best.has("neon_heartbeat:1"), "high score saved")
	# runner mode, no input -> fail
	main._cmd("start:5:2:1")
	guard = 0
	while main.state == "loading" and guard < 2000:
		guard += 1
		await get_tree().process_frame
	await _sim_song(false, 200.0)
	check(main.state == "results" and main.result.get("fail", false), "no input in runner mode -> SIGNAL LOST")
	# pause / resume
	main._cmd("start:5:0:1")
	for f in 5: await get_tree().process_frame
	main.pause_game()
	check(main.state == "pause", "pause")
	main.resume_game()
	await get_tree().create_timer(1.4).timeout
	check(main.state == "play" and main.clock_on, "resume")
	# manual hits during play
	main.auto = false
	main.t0_us = Time.get_ticks_usec() - int((main.notes[0][0] + main.lead_in + AudioServer.get_output_latency() + main.settings.offset / 1000.0) * 1000000.0)
	await get_tree().process_frame
	main.hit(main.notes[0][1])
	check(main.notes[0][2] >= 0 and main.notes[0][2] < 3, "manual key hit judged %d" % main.notes[0][2])
	check(Main_grade(), "grades")
	print("SMOKE OK" if fails == 0 else "SMOKE FAILED %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func Main_grade() -> bool:
	var g = main.get_script()
	return main.grade_for(0.96) == "S" and main.grade_for(0.9) == "A" and main.grade_for(0.5) == "D"
