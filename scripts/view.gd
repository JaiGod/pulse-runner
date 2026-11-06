extends RefCounted
## Pulse Runner renderer. Everything on screen is drawn here with the
## CanvasItem API: synthwave sky, lanes, the perspective runner track,
## the runner, HUD and all menus. `m` is the main node (state + draw target).

const BG_TOP := Color("#12052e")
const BG_BOT := Color("#3a0b4d")
const INK := Color("#f4eeff")
const DIM := Color("#a99cc8")
const PANEL := Color(0.05, 0.02, 0.12, 0.82)

static func font() -> Font:
	return ThemeDB.fallback_font

static func vsize(m) -> Vector2:
	return m.get_viewport_rect().size

static func text(m, p: Vector2, s: String, sz: int, c: Color, w := -1.0, align := HORIZONTAL_ALIGNMENT_CENTER, outline := 0) -> void:
	var f := font()
	if w < 0.0:
		w = vsize(m).x
		p.x = 0.0
	if outline > 0:
		m.draw_string_outline(f, p, s, align, w, sz, outline, Color(0, 0, 0, 0.6))
	m.draw_string(f, p, s, align, w, sz, c)

static func song_hue(m) -> float:
	return float(Music.SONGS[m.sel].hue)

# ------------------------------------------------------------------ layout helpers
static func lane_geom(m) -> Dictionary:
	var sz := vsize(m)
	var w := minf(460.0, sz.x * 0.92)
	var x0 := (sz.x - w) * 0.5
	return {"x0": x0, "w": w, "lw": w / 3.0, "hit": sz.y - 170.0, "top": 90.0}

static func lane_hit_pos(m, lane: int) -> Vector2:
	var g := lane_geom(m)
	if int(m.settings.mode) == 1:
		return _proj(m, lane, 0.0)
	return Vector2(g.x0 + g.lw * (lane + 0.5), g.hit)

static func pause_rect(m) -> Rect2:
	return Rect2(vsize(m).x - 66.0, 14.0, 52.0, 52.0)

static func approach(m) -> float:
	return 2.4 / float(m.settings.speed)

# ------------------------------------------------------------------ entry
static func draw_all(m) -> void:
	var sz := vsize(m)
	var sh := Vector2.ZERO
	if m.shake > 0.0:
		var a: float = m.shake * m.shake * 14.0
		sh = Vector2(randf_range(-a, a), randf_range(-a, a))
	m.draw_set_transform(sh)
	var play: bool = m.state in ["play", "pause", "results", "loading"]
	draw_bg(m, sz, play)
	if m.state in ["play", "pause"] or (m.state == "results" and m.failed):
		if int(m.settings.mode) == 1:
			draw_runner_track(m, sz)
		else:
			draw_lanes(m, sz)
		draw_parts(m)
		draw_hud(m, sz)
	m.draw_set_transform(Vector2.ZERO)
	match m.state:
		"title": draw_title(m, sz)
		"select": draw_select(m, sz)
		"howto": draw_howto(m, sz)
		"settings": draw_settings(m, sz)
		"calib": draw_calib(m, sz)
		"loading": draw_loading(m, sz)
		"pause": draw_pause(m, sz)
		"results": draw_results(m, sz)
	if m.state != "play":
		var r := Rect2(sz.x - 66.0, 14.0, 52.0, 52.0)
		if m.state in ["pause", "results", "loading", "calib"]:
			return
		m.btns.append({"r": r, "id": "snd"})
		m.draw_rect(r, Color(1, 1, 1, 0.08))
		_speaker(m, r.get_center(), m.settings.sound)

static func _speaker(m, c: Vector2, on: bool) -> void:
	var col := INK if on else Color("#ff4d6d")
	m.draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -6), c + Vector2(-6, -6), c + Vector2(4, -15), c + Vector2(4, 15), c + Vector2(-6, 6), c + Vector2(-14, 6)]), col)
	if on:
		m.draw_arc(c + Vector2(4, 0), 9.0, -0.9, 0.9, 10, col, 2.5)
		m.draw_arc(c + Vector2(4, 0), 15.0, -0.9, 0.9, 12, col, 2.5)
	else:
		m.draw_line(c + Vector2(8, -8), c + Vector2(18, 8), col, 3.0)
		m.draw_line(c + Vector2(18, -8), c + Vector2(8, 8), col, 3.0)

# ------------------------------------------------------------------ background
static func draw_bg(m, sz: Vector2, play: bool) -> void:
	var hue := song_hue(m) if play else 0.86
	var fv: bool = play and m.in_fever()
	if fv:
		hue = fposmod(m.anim * 0.25, 1.0)
	var top := Color.from_hsv(fposmod(hue - 0.12, 1.0), 0.85, 0.16)
	var bot := Color.from_hsv(hue, 0.8, 0.34)
	var hz := sz.y * 0.42
	m.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x, hz), Vector2(0, hz)]),
		PackedColorArray([top, top, bot, bot]))
	m.draw_rect(Rect2(0, hz, sz.x, sz.y - hz), Color.from_hsv(fposmod(hue - 0.1, 1.0), 0.8, 0.07))
	# stars
	for i in 46:
		var sx := fposmod(i * 137.31 + 11.0, sz.x)
		var sy := fposmod(i * 71.17 + 5.0, hz * 0.85)
		var tw := 0.4 + 0.6 * absf(sin(m.anim * 1.3 + i))
		m.draw_rect(Rect2(sx, sy, 2, 2), Color(1, 1, 1, 0.5 * tw))
	# sun with stripes, pulses on the beat
	var bp: float = m.beat_phase()
	var pulse := 1.0 + 0.035 * pow(1.0 - bp, 3.0)
	var sr := minf(sz.x * 0.32, 190.0) * pulse
	var sc := Vector2(sz.x * 0.5, hz - sr * 0.25)
	var sun_a := Color("#ffd23f")
	var sun_b := Color("#ff3cac")
	var n := 30
	for k in n:
		var y0 := sc.y - sr + (2.0 * sr) * k / n
		var y1 := y0 + 2.0 * sr / n
		if y0 > hz:
			break
		var gap := 0.0
		if k > n * 0.45:
			gap = (k - n * 0.45) * 0.55
		var yc := (y0 + y1) * 0.5
		var dy := absf(yc - sc.y)
		if dy >= sr:
			continue
		var hw := sqrt(sr * sr - dy * dy)
		m.draw_rect(Rect2(sc.x - hw, y0 + gap, hw * 2.0, maxf(0.0, (y1 - y0) - gap)), sun_a.lerp(sun_b, float(k) / n))
	m.draw_circle(sc, sr * 1.25, Color(1.0, 0.3, 0.6, 0.06))
	# mountains silhouette
	var pts := PackedVector2Array()
	pts.append(Vector2(0, hz))
	var steps := 18
	for i in steps + 1:
		var x := sz.x * i / steps
		var h := 30.0 + 40.0 * absf(sin(i * 1.7)) + 22.0 * absf(sin(i * 0.63 + 1.0))
		pts.append(Vector2(x, hz - h))
	pts.append(Vector2(sz.x, hz))
	m.draw_colored_polygon(pts, Color.from_hsv(fposmod(hue - 0.15, 1.0), 0.7, 0.12))
	m.draw_line(Vector2(0, hz), Vector2(sz.x, hz), Color(1.0, 0.35, 0.8, 0.9), 2.0)
	# perspective grid floor
	var gc := Color.from_hsv(hue, 0.7, 1.0, 0.35)
	var speed := 1.2 if not play else 2.0
	var off := fposmod(m.anim * speed, 1.0)
	for i in 12:
		var u := (i + off) / 12.0
		var y := hz + (sz.y - hz) * u * u
		m.draw_line(Vector2(0, y), Vector2(sz.x, y), Color(gc, gc.a * u), 1.5)
	for i in range(-10, 11):
		var xb := sz.x * 0.5 + i * sz.x * 0.16
		m.draw_line(Vector2(sz.x * 0.5 + i * 18.0, hz), Vector2(xb, sz.y), Color(gc, 0.25), 1.0)

# ------------------------------------------------------------------ classic lanes
static func draw_lanes(m, sz: Vector2) -> void:
	var g := lane_geom(m)
	var fv: bool = m.in_fever()
	m.draw_rect(Rect2(g.x0, 0, g.w, sz.y), Color(0.02, 0.0, 0.06, 0.62))
	for l in 3:
		var x: float = g.x0 + g.lw * l
		var col: Color = m.LANE_COL[l]
		if fv:
			col = Color.from_hsv(fposmod(m.anim * 0.5 + l * 0.33, 1.0), 0.7, 1.0)
		var fl: float = m.flash[l]
		if m.pressed[l]:
			fl = maxf(fl, 0.6)
		if fl > 0.0:
			m.draw_polygon(PackedVector2Array([Vector2(x, g.hit), Vector2(x + g.lw, g.hit), Vector2(x + g.lw, g.hit - 260), Vector2(x, g.hit - 260)]),
				PackedColorArray([Color(col, 0.35 * fl), Color(col, 0.35 * fl), Color(col, 0), Color(col, 0)]))
		m.draw_line(Vector2(x, 0), Vector2(x, sz.y), Color(1, 1, 1, 0.08), 1.0)
		# receptor
		var rc := Vector2(x + g.lw * 0.5, g.hit)
		m.draw_rect(Rect2(rc.x - g.lw * 0.4, rc.y - 14, g.lw * 0.8, 28), Color(col, 0.25 + 0.5 * fl), false, 3.0)
		text(m, Vector2(x, g.hit + 62), ["A", "S", "D"][l], 26, Color(col, 0.75), g.lw)
	m.draw_line(Vector2(g.x0 + g.w, 0), Vector2(g.x0 + g.w, sz.y), Color(1, 1, 1, 0.08), 1.0)
	m.draw_line(Vector2(g.x0, g.hit), Vector2(g.x0 + g.w, g.hit), Color(1, 1, 1, 0.55), 2.0)
	var ap := approach(m)
	var t: float = m.t_now
	var dist: float = g.hit - g.top
	var i: int = m.scan
	# draw from a little before scan (fading misses)
	var j0 := maxi(0, i - 24)
	for k in range(j0, m.notes.size()):
		var n: Array = m.notes[k]
		var dt: float = n[0] - t
		if dt > ap:
			break
		var y: float = g.hit - dt / ap * dist
		if y > sz.y + 30:
			continue
		var l: int = n[1]
		var col: Color = m.LANE_COL[l]
		if fv:
			col = Color.from_hsv(fposmod(m.anim * 0.5 + l * 0.33, 1.0), 0.7, 1.0)
		var a := 1.0
		if n[2] >= 0 and n[2] < 3:
			continue
		if n[2] == 3:
			a = 0.3
			col = Color("#ff4d6d")
		var cx: float = g.x0 + g.lw * (l + 0.5)
		var r := Rect2(cx - g.lw * 0.42, y - 12, g.lw * 0.84, 24)
		m.draw_rect(r.grow(6), Color(col, 0.18 * a))
		m.draw_rect(r, Color(col, a))
		m.draw_rect(Rect2(r.position + Vector2(4, 4), Vector2(r.size.x - 8, 6)), Color(1, 1, 1, 0.55 * a))

# ------------------------------------------------------------------ runner track
static func _proj(m, lane: float, u: float) -> Vector2:
	# u: 0 at the hit line, 1 at the horizon
	var sz := vsize(m)
	var hz := sz.y * 0.42
	var hit := sz.y - 200.0
	var s := 1.0 / (1.0 + maxf(-0.12, u) * 6.0)
	var w := minf(500.0, sz.x * 0.96)
	var x := sz.x * 0.5 + (lane - 1.0) * (w / 3.0) * s
	var y := hz + (hit - hz) * s
	return Vector2(x, y)

static func _pscale(u: float) -> float:
	return 1.0 / (1.0 + maxf(-0.12, u) * 6.0)

static func draw_runner_track(m, sz: Vector2) -> void:
	var fv: bool = m.in_fever()
	var ap := approach(m)
	# road
	var a := _proj(m, -0.5, 1.0)
	var b := _proj(m, 2.5, 1.0)
	var c := _proj(m, 2.5, -0.12)
	var d := _proj(m, -0.5, -0.12)
	m.draw_colored_polygon(PackedVector2Array([a, b, c, d]), Color(0.03, 0.0, 0.08, 0.85))
	for l in 4:
		var p0 := _proj(m, l - 0.5, 1.0)
		var p1 := _proj(m, l - 0.5, -0.12)
		var col := Color(1, 1, 1, 0.16) if l in [1, 2] else Color("#ff3cac")
		m.draw_line(p0, p1, col, 2.0)
	# moving stripes (beat synced)
	var bt: float = 60.0 / m.bpm
	for k in 10:
		var tt: float = (floorf(m.t_now / bt) + k) * bt - m.t_now
		var u := tt / ap
		if u < -0.1 or u > 1.0:
			continue
		var p0 := _proj(m, -0.5, u)
		var p1 := _proj(m, 2.5, u)
		m.draw_line(p0, p1, Color(1, 1, 1, 0.08 + 0.1 * (1.0 - u)), 1.5)
	# hit line
	var h0 := _proj(m, -0.5, 0.0)
	var h1 := _proj(m, 2.5, 0.0)
	m.draw_line(h0, h1, Color(1, 1, 1, 0.6), 3.0)
	for l in 3:
		var hp := _proj(m, l, 0.0)
		var col: Color = m.LANE_COL[l]
		var fl: float = m.flash[l]
		m.draw_circle(hp, 10.0 + 8.0 * fl, Color(col, 0.3 + 0.5 * fl))
		text(m, Vector2(hp.x - 50, hp.y + 74), ["A jump", "S slide", "D dash"][l], 20, Color(col, 0.8), 100.0)
	# obstacles far -> near
	var vis := []
	for k in range(maxi(0, m.scan - 16), m.notes.size()):
		var n: Array = m.notes[k]
		var dt: float = n[0] - m.t_now
		if dt > ap:
			break
		if n[2] >= 0 and n[2] < 3:
			continue
		if dt / ap < -0.11:
			continue
		vis.append(n)
	vis.reverse()
	for n in vis:
		var u: float = (n[0] - m.t_now) / ap
		var l: int = n[1]
		var s := _pscale(u)
		var p := _proj(m, l, u)
		var col: Color = m.LANE_COL[l]
		if fv:
			col = Color.from_hsv(fposmod(m.anim * 0.5 + l * 0.33, 1.0), 0.7, 1.0)
		if n[2] == 3:
			col = Color(1.0, 0.3, 0.4, 0.4)
		var hw := 52.0 * s
		if l == 2:
			# energy barrier -> dash through
			var bh := 80.0 * s
			m.draw_rect(Rect2(p + Vector2(-hw, -bh), Vector2(hw * 2, bh)), Color(col, 0.22))
			m.draw_rect(Rect2(p + Vector2(-hw, -bh), Vector2(hw * 2, bh)), col, false, 3.0 * s + 1.0)
			for q in 2:
				var cx := -10.0 * s + q * 18.0 * s
				m.draw_polyline(PackedVector2Array([p + Vector2(cx - 8 * s, -bh * 0.7), p + Vector2(cx + 6 * s, -bh * 0.5), p + Vector2(cx - 8 * s, -bh * 0.3)]), col, 3.0 * s + 1.0)
		elif l == 0:
			# hurdle: two posts + bar -> jump
			var hh := 46.0 * s
			m.draw_line(p + Vector2(-hw, 0), p + Vector2(-hw, -hh), col, 4.0 * s + 1.0)
			m.draw_line(p + Vector2(hw, 0), p + Vector2(hw, -hh), col, 4.0 * s + 1.0)
			m.draw_rect(Rect2(p + Vector2(-hw - 4 * s, -hh - 10 * s), Vector2(hw * 2 + 8 * s, 12 * s)), col)
			m.draw_rect(Rect2(p + Vector2(-hw - 10 * s, -hh - 16 * s), Vector2(hw * 2 + 20 * s, 24 * s)), Color(col, 0.18))
		else:
			# low gate -> slide under
			var gh := 92.0 * s
			m.draw_rect(Rect2(p + Vector2(-hw, -gh - 26 * s), Vector2(hw * 2, 26 * s)), col)
			m.draw_rect(Rect2(p + Vector2(-hw - 6 * s, -gh - 32 * s), Vector2(hw * 2 + 12 * s, 38 * s)), Color(col, 0.18))
			m.draw_line(p + Vector2(-hw, 0), p + Vector2(-hw, -gh), Color(col, 0.5), 2.0 * s + 1.0)
			m.draw_line(p + Vector2(hw, 0), p + Vector2(hw, -gh), Color(col, 0.5), 2.0 * s + 1.0)
	draw_runner(m)

static func draw_runner(m) -> void:
	var r: Dictionary = m.runner
	var base := _proj(m, r.x, 0.0) + Vector2(0, -6)
	var bt: float = 60.0 / m.bpm
	var ph: float = fposmod(m.t_now / bt, 1.0) * TAU
	var col := Color("#f4eeff")
	if m.in_fever():
		col = Color.from_hsv(fposmod(m.anim, 1.0), 0.5, 1.0)
	if r.trip < 0.3:
		col = Color("#ff4d6d")
		base.x += sin(r.trip * 60.0) * 6.0
	var jump: float = r.jump
	var slide: float = r.slide
	var jd := 0.42
	var y := 0.0
	var sliding := slide < 0.42
	var dash: float = r.get("dash", 9.0)
	if jump < jd:
		var q := jump / jd
		y = -4.0 * q * (1.0 - q) * 90.0
	var c := base + Vector2(0, y)
	var glow := Color(1.0, 0.25, 0.7, 0.25)
	m.draw_circle(base + Vector2(0, 2), 26.0, Color(0, 0, 0, 0.35))
	if dash < 0.3:
		# forward dash: lean + afterimages + speed lines
		for k in 3:
			var gc := Color(col, 0.18 - k * 0.05)
			var o := Vector2(-18.0 * (k + 1), 0)
			m.draw_line(c + o + Vector2(0, -34), c + o + Vector2(16, -62), gc, 9.0)
		var hp2 := c + Vector2(0, -34)
		var nk := c + Vector2(16, -62)
		m.draw_line(hp2, nk, col, 9.0)
		m.draw_circle(nk + Vector2(6, -12), 11.0, col)
		m.draw_rect(Rect2(nk + Vector2(2, -16), Vector2(16, 5)), Color("#ff9f2c"))
		m.draw_line(hp2, c + Vector2(18, -4), col, 7.0)
		m.draw_line(hp2, c + Vector2(-20, -2), col, 7.0)
		m.draw_line(nk + Vector2(0, 6), nk + Vector2(26, 2), col, 6.0)
		for k in 4:
			m.draw_line(c + Vector2(-50 - k * 12, -60 + k * 14), c + Vector2(-80 - k * 12, -60 + k * 14), Color("#ff9f2c", 0.6), 3.0)
		return
	if sliding:
		# low dash pose
		var hip := c + Vector2(-6, -16)
		var sh := c + Vector2(20, -26)
		m.draw_line(hip, sh, col, 9.0)
		m.draw_circle(sh + Vector2(10, -6), 10.0, col)
		m.draw_line(hip, c + Vector2(-34, -6), col, 7.0)
		m.draw_line(hip, c + Vector2(-26, 2), col, 7.0)
		m.draw_line(sh, c + Vector2(36, -12), col, 6.0)
		for k in 4:
			m.draw_line(c + Vector2(-44 - k * 14, -18 + k * 4), c + Vector2(-60 - k * 14, -18 + k * 4), Color(glow, 0.5), 3.0)
		return
	var hip := c + Vector2(0, -34)
	var neck := c + Vector2(4, -64)
	m.draw_circle(neck + Vector2(2, -14), 11.0, col)
	m.draw_rect(Rect2(neck + Vector2(-8, -18), Vector2(20, 5)), Color("#2cf6ff"))  # visor
	m.draw_line(hip, neck, col, 9.0)
	var sw := sin(ph * 2.0)
	if jump < jd:
		sw = 0.6
	m.draw_line(hip, hip + Vector2(14 * sw, 18), col, 7.0)
	m.draw_line(hip + Vector2(14 * sw, 18), hip + Vector2(10 * sw - 4, 34), col, 7.0)
	m.draw_line(hip, hip + Vector2(-14 * sw, 18), col, 7.0)
	m.draw_line(hip + Vector2(-14 * sw, 18), hip + Vector2(-10 * sw - 6, 34), col, 7.0)
	m.draw_line(neck + Vector2(0, 6), neck + Vector2(-16 * sw, 24), col, 6.0)
	m.draw_line(neck + Vector2(0, 6), neck + Vector2(16 * sw, 22), col, 6.0)
	m.draw_circle(hip + Vector2(0, -12), 22.0, glow)

static func draw_parts(m) -> void:
	for p in m.parts:
		var a: float = clampf(p.life * 2.0, 0.0, 1.0)
		m.draw_rect(Rect2(p.pos - Vector2(3, 3), Vector2(6, 6)), Color(p.col, a))

# ------------------------------------------------------------------ HUD
static func draw_hud(m, sz: Vector2) -> void:
	var s: Dictionary = Music.SONGS[m.sel]
	text(m, Vector2(16, 40), "%08d" % m.score, 30, INK, 300.0, HORIZONTAL_ALIGNMENT_LEFT, 6)
	text(m, Vector2(16, 66), "%s · %s" % [s.name, Music.DIFFS[m.diff]], 17, DIM, 360.0, HORIZONTAL_ALIGNMENT_LEFT)
	var acc: float = m.accuracy()
	text(m, Vector2(sz.x - 290, 40), "%.2f%%" % (acc * 100.0), 24, INK, 200.0, HORIZONTAL_ALIGNMENT_RIGHT, 5)
	# pause button
	var pr := pause_rect(m)
	m.draw_rect(pr, Color(1, 1, 1, 0.1))
	m.draw_rect(Rect2(pr.position + Vector2(16, 14), Vector2(7, 24)), INK)
	m.draw_rect(Rect2(pr.position + Vector2(29, 14), Vector2(7, 24)), INK)
	# progress
	var prog := clampf(m.t_now / maxf(1.0, m.last_t), 0.0, 1.0)
	m.draw_rect(Rect2(0, 0, sz.x, 5), Color(1, 1, 1, 0.1))
	m.draw_rect(Rect2(0, 0, sz.x * prog, 5), Color("#2cf6ff"))
	# health + fever bars
	var bw := minf(420.0, sz.x - 40.0)
	var bx := (sz.x - bw) * 0.5
	var by := sz.y - 62.0
	m.draw_rect(Rect2(bx, by, bw, 12), Color(1, 1, 1, 0.12))
	var hc: Color = Color("#7dff8a") if m.health > 0.3 else Color("#ff4d6d")
	m.draw_rect(Rect2(bx, by, bw * m.health, 12), hc)
	text(m, Vector2(bx, by - 6), "PULSE", 14, DIM, bw, HORIZONTAL_ALIGNMENT_LEFT)
	var fy := by + 22.0
	m.draw_rect(Rect2(bx, fy, bw, 10), Color(1, 1, 1, 0.12))
	var fv: bool = m.in_fever()
	var fill: float = m.fever
	if fv:
		fill = clampf((m.fever_until - m.t_now) / (16.0 * 60.0 / m.bpm), 0.0, 1.0)
	var fc := Color.from_hsv(fposmod(m.anim, 1.0), 0.7, 1.0) if fv else Color("#ffd23f")
	m.draw_rect(Rect2(bx, fy, bw * fill, 10), fc)
	text(m, Vector2(bx, fy + 30), "FEVER x2!" if fv else "FEVER", 14, fc if fv else DIM, bw, HORIZONTAL_ALIGNMENT_RIGHT)
	# combo + multiplier
	var cy := sz.y * 0.30 if int(m.settings.mode) == 0 else sz.y * 0.20
	if m.combo >= 4:
		text(m, Vector2(0, cy), str(m.combo), 56, Color(INK, 0.9), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 8)
		text(m, Vector2(0, cy + 26), "COMBO  x%d" % m.mult(), 18, Color("#ffd23f"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 4)
	# judgment pop
	if m.pop.t < 0.6:
		var e: float = m.pop.t / 0.6
		var sc := 1.0 + 0.4 * pow(1.0 - minf(1.0, m.pop.t / 0.12), 2.0)
		var a := 1.0 - e * e
		var jy := cy + 80.0 - e * 14.0
		text(m, Vector2(0, jy), m.pop.text, int(34 * sc), Color(m.pop.col, a), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 6)
		if m.pop.text != "MISS" and m.pop.text != "PERFECT":
			text(m, Vector2(0, jy + 24), ("+%d ms" if m.pop.ms > 0 else "%d ms") % m.pop.ms, 15, Color(DIM, a))
	if fv:
		var ft: float = fposmod(m.anim * 3.0, 1.0)
		m.draw_rect(Rect2(0, 0, 6, sz.y), Color.from_hsv(ft, 0.8, 1.0, 0.6))
		m.draw_rect(Rect2(sz.x - 6, 0, 6, sz.y), Color.from_hsv(fposmod(ft + 0.5, 1.0), 0.8, 1.0, 0.6))
	# count-in / resume
	if m.state == "play" and m.t_now < 0.0 and m.resume_cd <= 0.0:
		var beats: float = -m.t_now * m.bpm / 60.0
		text(m, Vector2(0, sz.y * 0.45), str(int(ceil(beats))) if beats < 4.0 else "GET READY", 64 if beats < 4.0 else 44, Color("#ffd23f"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 8)
		text(m, Vector2(0, sz.y * 0.45 + 40), "A S D  or tap the lanes", 18, DIM)
	if m.resume_cd > 0.0:
		text(m, Vector2(0, sz.y * 0.45), "READY...", 52, Color("#2cf6ff"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 8)
	if m.auto:
		text(m, Vector2(16, 92), "AUTOPLAY", 14, Color("#ffd23f"), 200.0, HORIZONTAL_ALIGNMENT_LEFT)

# ------------------------------------------------------------------ menus
static func draw_button(m, r: Rect2, label: String, accent: Color, focused: bool, sz: int) -> void:
	var bp: float = m.beat_phase()
	m.draw_rect(r, Color(0.06, 0.02, 0.14, 0.88))
	m.draw_rect(r, Color(accent, 0.9 if focused else 0.45), false, 3.0 if focused else 2.0)
	if focused:
		m.draw_rect(r.grow(5.0 + 3.0 * (1.0 - bp)), Color(accent, 0.18), false, 2.0)
	var f := font()
	var ty := r.position.y + r.size.y * 0.5 + sz * 0.36
	m.draw_string(f, Vector2(r.position.x, ty), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, sz, INK if focused else Color(INK, 0.85))

static func _panel(m, r: Rect2) -> void:
	m.draw_rect(r, PANEL)
	m.draw_rect(r, Color(1, 0.3, 0.8, 0.5), false, 2.0)

static func _logo(m, sz: Vector2, y: float, scale := 1.0) -> void:
	var bp: float = m.beat_phase()
	var k := 1.0 + 0.06 * pow(1.0 - bp, 3.0)
	var fs := int(minf(sz.x / 6.2, 92.0) * scale * k)
	text(m, Vector2(0, y + 4), "PULSE", fs, Color("#ff3cac"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 0)
	text(m, Vector2(0, y), "PULSE", fs, Color("#2cf6ff"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 0)
	text(m, Vector2(0, y + fs * 0.95 + 3), "RUNNER", fs, Color("#ff9f2c"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 0)
	text(m, Vector2(0, y + fs * 0.95), "RUNNER", fs, Color("#ffd23f"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 0)
	# heartbeat line
	var w := minf(sz.x * 0.8, 520.0)
	var x0 := (sz.x - w) * 0.5
	var ly := y + fs * 1.35
	var pts := PackedVector2Array()
	for i in 41:
		var u := i / 40.0
		var v := 0.0
		var d := absf(u - 0.5)
		if d < 0.12:
			v = sin((u - 0.38) / 0.24 * TAU * 1.5) * (1.0 - d / 0.12) * 28.0 * k
		pts.append(Vector2(x0 + u * w, ly - v))
	m.draw_polyline(pts, Color("#ff3cac"), 4.0)

static func draw_title(m, sz: Vector2) -> void:
	var e: float = ease(m.trans, -2.0)
	_logo(m, sz, sz.y * 0.2 - (1.0 - e) * 40.0)
	text(m, Vector2(0, sz.y * 0.2 + 250), "A neon rhythm run · 8 original synth tracks", 19, DIM)
	var bw := minf(340.0, sz.x - 60.0)
	var x := (sz.x - bw) * 0.5
	var y := sz.y * 0.5 + 10.0
	m.button(Rect2(x, y, bw, 70), "PLAY", "play", Color("#2cf6ff"), 32)
	m.button(Rect2(x, y + 88, bw, 60), "HOW TO PLAY", "howto", Color("#ff3cac"))
	m.button(Rect2(x, y + 166, bw, 60), "SETTINGS", "settings", Color("#ffd23f"))
	text(m, Vector2(0, sz.y - 40), "Made by Jaineil Rana (JaKing) · JaiGod", 15, DIM)
	text(m, Vector2(0, sz.y - 64), "Enter / tap to choose · M toggles sound", 15, Color(DIM, 0.7))

static func draw_select(m, sz: Vector2) -> void:
	text(m, Vector2(0, 52), "SELECT A TRACK", 30, INK, -1.0, HORIZONTAL_ALIGNMENT_CENTER, 6)
	var w := minf(500.0, sz.x - 24.0)
	var x := (sz.x - w) * 0.5
	var foot := 230.0
	var avail := sz.y - 86.0 - foot
	var ch := clampf(avail / 8.0 - 6.0, 52.0, 84.0)
	var y := 78.0
	for i in Music.SONGS.size():
		var s: Dictionary = Music.SONGS[i]
		var r := Rect2(x, y + i * (ch + 6.0), w, ch)
		var on: bool = i == m.sel
		var hc: Color = Color.from_hsv(float(s.hue), 0.75, 1.0)
		m.btns.append({"r": r, "id": "song:%d" % i})
		m.draw_rect(r, Color(hc.r * 0.25, hc.g * 0.1, hc.b * 0.3, 0.9) if on else Color(0.05, 0.02, 0.12, 0.85))
		m.draw_rect(Rect2(r.position, Vector2(8, ch)), hc)
		if on:
			m.draw_rect(r, hc, false, 3.0)
		var f := font()
		m.draw_string(f, Vector2(x + 22, r.position.y + ch * 0.45), s.name, HORIZONTAL_ALIGNMENT_LEFT, w * 0.6, 22, INK)
		m.draw_string(f, Vector2(x + 22, r.position.y + ch * 0.8), "%s · %d BPM" % [s.tag, s.bpm], HORIZONTAL_ALIGNMENT_LEFT, w * 0.6, 15, DIM)
		var key: String = "%s:%d" % [s.id, m.diff]
		var b: Dictionary = m.best.get(key, {})
		if b.size() > 0:
			m.draw_string(f, Vector2(x + w - 150, r.position.y + ch * 0.55), String(b.grade), HORIZONTAL_ALIGNMENT_LEFT, 40, 30, _gcol(b.grade))
			m.draw_string(f, Vector2(x + w - 110, r.position.y + ch * 0.45), "%07d" % int(b.score), HORIZONTAL_ALIGNMENT_RIGHT, 96, 16, INK)
			if b.get("fc", false):
				m.draw_string(f, Vector2(x + w - 110, r.position.y + ch * 0.8), "FULL COMBO", HORIZONTAL_ALIGNMENT_RIGHT, 96, 12, Color("#ffd23f"))
		else:
			m.draw_string(f, Vector2(x + w - 110, r.position.y + ch * 0.6), "Lv %d" % int(s.lv[m.diff]), HORIZONTAL_ALIGNMENT_RIGHT, 96, 18, DIM)
	# footer: difficulty, mode, start
	var fy := sz.y - foot + 14.0
	var dw := (w - 16.0) / 3.0
	for d in 3:
		var r := Rect2(x + d * (dw + 8.0), fy, dw, 52)
		var col: Color = [Color("#7dff8a"), Color("#2cf6ff"), Color("#ff4d6d")][d]
		m.btns.append({"r": r, "id": "diff:%d" % d})
		m.draw_rect(r, Color(col, 0.3) if d == m.diff else Color(0.05, 0.02, 0.12, 0.85))
		m.draw_rect(r, col if d == m.diff else Color(col, 0.4), false, 2.0)
		text(m, Vector2(r.position.x, r.position.y + 25), Music.DIFFS[d], 20, INK, dw)
		text(m, Vector2(r.position.x, r.position.y + 44), "Lv %d" % int(Music.SONGS[m.sel].lv[d]), 14, DIM, dw)
	var mr := Rect2(x, fy + 64, w * 0.5 - 4, 56)
	m.btns.append({"r": mr, "id": "mode"})
	m.draw_rect(mr, Color(0.05, 0.02, 0.12, 0.85))
	m.draw_rect(mr, Color("#b36bff"), false, 2.0)
	text(m, Vector2(mr.position.x, mr.position.y + 25), "MODE: " + ("RUNNER" if int(m.settings.mode) == 1 else "LANES"), 18, INK, mr.size.x)
	text(m, Vector2(mr.position.x, mr.position.y + 45), "Tab / tap to switch", 13, DIM, mr.size.x)
	var sr := Rect2(x + w * 0.5 + 4, fy + 64, w * 0.5 - 4, 56)
	m.btns.append({"r": sr, "id": "start"})
	var bp: float = m.beat_phase()
	m.draw_rect(sr, Color(0.17, 0.9, 1.0, 0.25 + 0.15 * (1.0 - bp)))
	m.draw_rect(sr, Color("#2cf6ff"), false, 3.0)
	text(m, Vector2(sr.position.x, sr.position.y + 37), "START >", 26, INK, sr.size.x)
	var br := Rect2(x, fy + 132, 110, 44)
	m.btns.append({"r": br, "id": "back"})
	m.draw_rect(br, Color(0.05, 0.02, 0.12, 0.85))
	m.draw_rect(br, Color(1, 1, 1, 0.3), false, 2.0)
	text(m, Vector2(br.position.x, br.position.y + 29), "< BACK", 18, INK, br.size.x)
	text(m, Vector2(x + 120, fy + 160), "Up/Down track · Left/Right difficulty", 14, DIM, w - 120, HORIZONTAL_ALIGNMENT_RIGHT)

static func _gcol(g: String) -> Color:
	match g:
		"S": return Color("#ffd23f")
		"A": return Color("#2cf6ff")
		"B": return Color("#7dff8a")
		"C": return Color("#b36bff")
	return Color("#ff4d6d")

static func draw_howto(m, sz: Vector2) -> void:
	var w := minf(500.0, sz.x - 24.0)
	var x := (sz.x - w) * 0.5
	_panel(m, Rect2(x, 40, w, sz.y - 150))
	text(m, Vector2(0, 92), "HOW TO PLAY", 32, Color("#2cf6ff"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 6)
	var lines := [
		["Hit the notes as they cross the line.", INK],
		["Keys: A  S  D", Color("#ffd23f")],
		["Phone: tap the 3 screen columns.", Color("#ffd23f")],
		["", INK],
		["PERFECT ±45ms · GREAT ±90 · GOOD ±135", INK],
		["Combo raises the multiplier up to x4.", INK],
		["Fill the FEVER bar for double points!", Color("#ff3cac")],
		["Misses drain your PULSE - empty = fail.", Color("#ff4d6d")],
		["", INK],
		["RUNNER mode: same notes, new view.", Color("#b36bff")],
		["A jump hurdles · S slide · D dash.", INK],
		["", INK],
		["Grades S A B C D by accuracy.", INK],
		["Audio feels late? Settings > Calibrate.", INK],
		["Esc / P / Space pauses.", DIM],
	]
	var y := 150.0
	for l in lines:
		text(m, Vector2(x + 12, y), l[0], 19, l[1], w - 24)
		y += 32.0
	var bw := minf(300.0, w - 40.0)
	m.button(Rect2((sz.x - bw) * 0.5, sz.y - 96, bw, 60), "< BACK", "back", Color("#ff3cac"))

static func draw_settings(m, sz: Vector2) -> void:
	var w := minf(500.0, sz.x - 24.0)
	var x := (sz.x - w) * 0.5
	_panel(m, Rect2(x, 40, w, sz.y - 80))
	text(m, Vector2(0, 92), "SETTINGS", 32, Color("#ffd23f"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 6)
	var y := 130.0
	var st: Dictionary = m.settings
	var row := func(label: String, val: String, idm: String, idp: String) -> void:
		text(m, Vector2(x + 20, y + 22), label, 18, DIM, w - 40, HORIZONTAL_ALIGNMENT_LEFT)
		m.button(Rect2(x + 20, y + 34, 70, 56), "-", idm, Color("#2cf6ff"), 32)
		text(m, Vector2(x + 90, y + 72), val, 26, INK, w - 220)
		m.button(Rect2(x + w - 90, y + 34, 70, 56), "+", idp, Color("#2cf6ff"), 32)
	row.call("CHART SPEED", "x%.2f" % float(st.speed), "spd-", "spd+")
	y += 110.0
	row.call("AUDIO OFFSET (+ = audio late)", "%+d ms" % int(st.offset), "off-", "off+")
	y += 110.0
	var bw := w - 40.0
	m.button(Rect2(x + 20, y, bw * 0.62, 56), "CALIBRATE", "calib", Color("#ff3cac"))
	m.button(Rect2(x + 28 + bw * 0.62, y, bw * 0.38 - 8, 56), "RESET 0", "off0", Color("#a99cc8"), 20)
	y += 74.0
	m.button(Rect2(x + 20, y, bw, 56), "VIEW: " + ("RUNNER" if int(st.mode) == 1 else "LANES"), "mode", Color("#b36bff"))
	y += 74.0
	m.button(Rect2(x + 20, y, bw, 56), "HIT SOUNDS: " + ("ON" if st.hits else "OFF"), "hits", Color("#7dff8a"))
	y += 74.0
	m.button(Rect2(x + 20, y, bw, 56), "MUSIC & SFX: " + ("ON" if st.sound else "OFF"), "snd", Color("#ffd23f"))
	y += 74.0
	m.button(Rect2(x + 20, minf(y, sz.y - 120), bw, 56), "< SAVE & BACK", "back", Color("#ff3cac"))

static func draw_calib(m, sz: Vector2) -> void:
	var w := minf(500.0, sz.x - 24.0)
	var x := (sz.x - w) * 0.5
	_panel(m, Rect2(x, 40, w, sz.y - 80))
	text(m, Vector2(0, 92), "CALIBRATION", 32, Color("#ff3cac"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 6)
	text(m, Vector2(x + 16, 140), "Press any key or tap on every click.", 19, INK, w - 32)
	text(m, Vector2(x + 16, 168), "The first 4 clicks are a count-in.", 16, DIM, w - 32)
	var bp: float = m.beat_phase()
	var c := Vector2(sz.x * 0.5, sz.y * 0.4)
	var r := 70.0 + 30.0 * pow(1.0 - bp, 4.0)
	m.draw_circle(c, r, Color(1.0, 0.24, 0.67, 0.25 + 0.5 * pow(1.0 - bp, 3.0)))
	m.draw_arc(c, 100.0, 0, TAU, 48, Color(1, 1, 1, 0.3), 2.0)
	# tap history
	for i in m.cal_taps.size():
		var d: float = m.cal_taps[i]
		var px := c.x + clampf(d * 1000.0, -150.0, 150.0)
		m.draw_rect(Rect2(px - 2, c.y + 130, 4, 26), Color("#ffd23f", 0.3 + 0.7 * i / maxf(1.0, m.cal_taps.size())))
	m.draw_line(Vector2(c.x - 150, c.y + 143), Vector2(c.x + 150, c.y + 143), Color(1, 1, 1, 0.3), 1.0)
	m.draw_line(Vector2(c.x, c.y + 122), Vector2(c.x, c.y + 164), INK, 2.0)
	text(m, Vector2(c.x - 200, c.y + 186), "early", 14, DIM, 120.0, HORIZONTAL_ALIGNMENT_LEFT)
	text(m, Vector2(c.x + 80, c.y + 186), "late", 14, DIM, 120.0, HORIZONTAL_ALIGNMENT_RIGHT)
	var v: int = m.calib_value()
	text(m, Vector2(0, c.y + 236), "Measured offset: %+d ms  (%d taps)" % [v, m.cal_taps.size()], 22, INK)
	var bw := (w - 52.0) * 0.5
	var y := sz.y - 130.0
	m.button(Rect2(x + 20, y, bw, 60), "SAVE", "calsave", Color("#7dff8a"))
	m.button(Rect2(x + 32 + bw, y, bw, 60), "CANCEL", "back", Color("#ff4d6d"))

static func draw_loading(m, sz: Vector2) -> void:
	var s: Dictionary = Music.SONGS[m.sel]
	var p: float = m.job.progress() if m.job else 1.0
	var w := minf(420.0, sz.x - 60.0)
	var x := (sz.x - w) * 0.5
	text(m, Vector2(0, sz.y * 0.4), s.name, 40, INK, -1.0, HORIZONTAL_ALIGNMENT_CENTER, 6)
	text(m, Vector2(0, sz.y * 0.4 + 36), "Synthesizing track...  %d%%" % int(p * 100.0), 18, DIM)
	m.draw_rect(Rect2(x, sz.y * 0.4 + 60, w, 10), Color(1, 1, 1, 0.12))
	m.draw_rect(Rect2(x, sz.y * 0.4 + 60, w * p, 10), Color("#2cf6ff"))

static func draw_pause(m, sz: Vector2) -> void:
	m.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.55))
	text(m, Vector2(0, sz.y * 0.3), "PAUSED", 56, INK, -1.0, HORIZONTAL_ALIGNMENT_CENTER, 8)
	var bw := minf(320.0, sz.x - 60.0)
	var x := (sz.x - bw) * 0.5
	var y := sz.y * 0.38
	m.button(Rect2(x, y, bw, 64), "RESUME", "resume", Color("#2cf6ff"), 28)
	m.button(Rect2(x, y + 82, bw, 60), "RESTART", "restart", Color("#ffd23f"))
	m.button(Rect2(x, y + 160, bw, 60), "SONG LIST", "songs", Color("#ff3cac"))

static func draw_results(m, sz: Vector2) -> void:
	var r: Dictionary = m.result
	if r.is_empty():
		return
	m.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.45))
	var w := minf(480.0, sz.x - 24.0)
	var x := (sz.x - w) * 0.5
	_panel(m, Rect2(x, 50, w, minf(sz.y - 100, 640.0)))
	var s: Dictionary = Music.SONGS[m.sel]
	var e: float = ease(m.trans, -2.5)
	if r.fail:
		text(m, Vector2(0, 120), "SIGNAL LOST", 44, Color("#ff4d6d"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 8)
	else:
		text(m, Vector2(0, 120), "TRACK CLEAR!", 40, Color("#7dff8a"), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 8)
	text(m, Vector2(0, 152), "%s · %s" % [s.name, Music.DIFFS[m.diff]], 18, DIM)
	var gs := int(150 * (0.6 + 0.4 * e))
	text(m, Vector2(0, 175 + gs * 0.85), r.grade, gs, _gcol(r.grade), -1.0, HORIZONTAL_ALIGNMENT_CENTER, 10)
	var y := 175.0 + 150.0 + 20.0
	text(m, Vector2(0, y), "%08d" % int(float(r.score) * e), 40, INK, -1.0, HORIZONTAL_ALIGNMENT_CENTER, 6)
	if r.new:
		text(m, Vector2(0, y + 30), "NEW BEST!", 20, Color("#ffd23f"))
	if r.fc:
		text(m, Vector2(0, y + 54), "FULL COMBO", 20, Color("#2cf6ff"))
	y += 90.0
	for j in 4:
		text(m, Vector2(x + 40, y + j * 30), m.JNAME[j], 20, m.JCOL[j], 200.0, HORIZONTAL_ALIGNMENT_LEFT)
		text(m, Vector2(x + w - 240, y + j * 30), str(m.counts[j]), 20, INK, 200.0, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 128.0
	text(m, Vector2(x + 40, y), "Accuracy %.2f%%  ·  Max combo %d" % [r.acc * 100.0, r.max], 18, DIM, w - 80)
	var bw := (w - 52.0) * 0.5
	var by := minf(y + 30.0, sz.y - 130.0)
	m.button(Rect2(x + 20, by, bw, 60), "RETRY", "retry", Color("#ffd23f"))
	m.button(Rect2(x + 32 + bw, by, bw, 60), "SONGS", "songs", Color("#2cf6ff"))
