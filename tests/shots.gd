extends Node
## Captures README screenshots (needs a display, e.g. xvfb-run in CI).
## Output: $SHOTS/<prefix><name>.jpg
var main
var out := "user://"
var pre := ""

func _ready() -> void:
	out = OS.get_environment("SHOTS") if OS.get_environment("SHOTS") != "" else "user://"
	pre = OS.get_environment("PREFIX")
	get_tree().create_timer(170.0).timeout.connect(func(): get_tree().quit())
	_run.call_deferred()

func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var w := mini(900, img.get_width())
	img.resize(w, int(float(w) * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.save_jpg(out + "/" + pre + name + ".jpg", 0.72)
	print("[shot] ", pre, name)

func _play(song: int, d: int, mode: int, at: float) -> void:
	main._cmd("start:%d:%d:%d" % [song, d, mode])
	while main.state == "loading":
		await get_tree().process_frame
	main.auto = true
	main.t0_us -= int((at + main.lead_in) * 1000000.0)
	await _f(40)

func _run() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await _f(120)
	await _snap("title")
	main.goto("select")
	main.sel = 2
	await _f(30)
	await _snap("select")
	await _play(0, 1, 0, 34.0)
	await _snap("lanes")
	await _play(5, 2, 1, 30.0)
	await _snap("runner")
	await _play(7, 2, 0, 40.0)
	main.fever_until = main.t_now + 8.0
	await _f(20)
	await _snap("fever")
	await _play(1, 1, 1, 200.0)
	await _f(60)
	await _snap("results")
	main.goto("settings")
	await _f(20)
	await _snap("settings")
	get_tree().quit()
