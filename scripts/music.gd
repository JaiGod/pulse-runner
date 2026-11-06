class_name Music
extends RefCounted
## Procedural composer + chart generator for Pulse Runner.
## Every song is an original piece written as data (tempo, key, chord
## progression, instruments, groove) and a seeded melody generator. The
## same note data drives both the audio and the Easy / Normal / Hard charts.

const SCALES := {
	"minor": [0, 2, 3, 5, 7, 8, 10],
	"major": [0, 2, 4, 5, 7, 9, 11],
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"harmonic": [0, 2, 3, 5, 7, 8, 11],
	"mixo": [0, 2, 4, 5, 7, 9, 10],
}

const SONGS := [
	{"id": "neon_heartbeat", "name": "Neon Heartbeat", "bpm": 118, "root": 45, "scale": "minor",
	 "prog": [0, 5, 2, 6], "lead": 2, "bass": "pulse", "drums": "four", "hue": 0.88, "seed": 11,
	 "lv": [2, 5, 8], "tag": "Synthwave"},
	{"id": "pixel_sunrise", "name": "Pixel Sunrise", "bpm": 132, "root": 48, "scale": "major",
	 "prog": [0, 4, 5, 3], "lead": 1, "bass": "oct", "drums": "chip", "hue": 0.12, "seed": 23,
	 "lv": [2, 5, 8], "tag": "Chiptune"},
	{"id": "midnight_arcade", "name": "Midnight Arcade", "bpm": 124, "root": 40, "scale": "minor",
	 "prog": [0, 3, 6, 4], "lead": 0, "bass": "off", "drums": "four", "hue": 0.72, "seed": 37,
	 "lv": [3, 6, 9], "tag": "Arcade house"},
	{"id": "static_bloom", "name": "Static Bloom", "bpm": 98, "root": 41, "scale": "major",
	 "prog": [0, 5, 3, 4], "lead": 3, "bass": "walk", "drums": "half", "hue": 0.42, "seed": 41,
	 "lv": [1, 4, 7], "tag": "Lo-fi glow"},
	{"id": "lunar_drift", "name": "Lunar Drift", "bpm": 110, "root": 43, "scale": "dorian",
	 "prog": [0, 3, 0, 6], "lead": 5, "bass": "walk", "drums": "break", "hue": 0.55, "seed": 53,
	 "lv": [2, 5, 8], "tag": "Space funk"},
	{"id": "chrome_comet", "name": "Chrome Comet", "bpm": 148, "root": 50, "scale": "minor",
	 "prog": [0, 6, 5, 4], "lead": 2, "bass": "pulse", "drums": "drive", "hue": 0.02, "seed": 67,
	 "lv": [3, 7, 10], "tag": "Outrun"},
	{"id": "overclock", "name": "Overclock", "bpm": 166, "root": 47, "scale": "harmonic",
	 "prog": [0, 5, 3, 4], "lead": 1, "bass": "oct", "drums": "break", "hue": 0.32, "seed": 79,
	 "lv": [4, 8, 11], "tag": "Breakbeat"},
	{"id": "hyperpulse", "name": "Hyperpulse", "bpm": 178, "root": 49, "scale": "minor",
	 "prog": [0, 5, 6, 4], "lead": 4, "bass": "pulse", "drums": "drive", "hue": 0.8, "seed": 97,
	 "lv": [5, 9, 12], "tag": "Finale"},
]

const DIFFS := ["Easy", "Normal", "Hard"]

static func scale_note(sc: Array, idx: int) -> int:
	var o := floori(float(idx) / 7.0)
	var k := idx - o * 7
	return o * 12 + int(sc[k])

## Song structure as [type, bars]
static func structure(song: Dictionary) -> Array:
	var target := int(round(70.0 * song.bpm / 240.0 / 4.0)) * 4
	var s := [["intro", 4], ["verse", 8], ["chorus", 8], ["break", 4], ["chorus", 8], ["outro", 4]]
	var total := 36
	if target >= 44:
		s.insert(3, ["verse", 8]); total += 8
	if target >= 52:
		s.insert(6, ["chorus", 8]); total += 8
	return s

## Compose a song into note events: [step, kind, midi, len_steps, vel]
static func compose(song: Dictionary) -> Dictionary:
	var sc: Array = SCALES[song.scale]
	var root: int = song.root
	var prog: Array = song.prog
	var ev: Array = []
	var secs: Array = []
	var step := 0
	var motifs := {}
	var fast: bool = song.bpm >= 145
	for sec in structure(song):
		var typ: String = sec[0]
		var bars: int = sec[1]
		secs.append([step, typ, bars])
		if not motifs.has(typ):
			motifs[typ] = _motif(song, typ, fast)
		var mot: Array = motifs[typ]
		for b in bars:
			var bs := step + b * 16
			var deg: int = prog[b % prog.size()]
			var ch := [scale_note(sc, deg), scale_note(sc, deg + 2), scale_note(sc, deg + 4)]
			var last := b == bars - 1
			_drums(ev, song, typ, b, bars, bs)
			_bass(ev, song, typ, bs, root + ch[0], root + ch[2])
			if typ in ["intro", "chorus", "break", "outro"]:
				for c in ch:
					ev.append([bs, "P", root + 12 + c, 16, 0.16])
			if typ == "chorus" or (typ == "verse" and song.drums == "chip"):
				_arp(ev, typ, bs, root + 24, ch, fast)
			if typ in ["verse", "chorus", "break"]:
				# melody: 2-bar motif, bars 4/8 resolve to chord root
				for n in mot[b % 2]:
					var s0: int = n[0]
					if last and s0 >= 8:
						continue
					var idx: int = n[1]
					if b % 4 == 3 and s0 >= 8:
						continue
					ev.append([bs + s0, "L", root + 24 + scale_note(sc, idx + deg if typ == "break" else idx), n[2], 0.5])
				if b % 4 == 3 or last:
					ev.append([bs + 8, "L", root + 24 + scale_note(sc, deg + (7 if typ == "chorus" else 0)), 8, 0.5])
			if typ == "outro" and last:
				ev.append([bs, "L", root + 24, 16, 0.45])
		if typ == "chorus" or typ == "verse":
			ev.append([step, "X", 0, 16, 0.55])
		step += bars * 16
	ev.append([step, "X", 0, 16, 0.5])
	ev.sort_custom(func(a, b): return a[0] < b[0])
	return {"events": ev, "steps": step + 16, "sections": secs,
		"step_sec": 60.0 / song.bpm / 4.0, "song": song}

static func _motif(song: Dictionary, typ: String, fast: bool) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = int(song.seed) * 131 + typ.hash()
	var dens := 0.42
	var oct := 0
	match typ:
		"chorus":
			dens = 0.62; oct = 7
		"break":
			dens = 0.22
	var res := []
	var idx := 2 + oct
	for half in 2:
		var notes := []
		var onsets := []
		var grid := 2
		if typ == "chorus" and not fast:
			grid = 1 if r.randf() < 0.35 else 2
		var s := 0
		while s < 16:
			var p := dens
			if s % 4 == 0:
				p += 0.28
			if s == 0 or r.randf() < p:
				onsets.append(s)
			s += grid if s % 4 != 0 else 2
		for i in onsets.size():
			var o: int = onsets[i]
			var nxt: int = onsets[i + 1] if i + 1 < onsets.size() else 16
			if o % 4 == 0:
				# land near a chord tone (0,2,4 offsets)
				var tones := [oct, oct + 2, oct + 4, oct + 7]
				var best: int = tones[0]
				for t in tones:
					if absi(t - idx) < absi(best - idx):
						best = t
				idx = best
			else:
				idx += [-2, -1, -1, 1, 1, 2, 0, 3, -3][r.randi() % 9]
			idx = clampi(idx, oct - 2, oct + 9)
			notes.append([o, idx, maxi(1, mini(nxt - o, 6))])
		res.append(notes)
	return res

static func _drums(ev: Array, song: Dictionary, typ: String, b: int, bars: int, bs: int) -> void:
	var st: String = song.drums
	if typ == "break" and b < bars - 1:
		ev.append([bs, "K", 0, 4, 0.5])
		for s in [4, 12]:
			ev.append([bs + s, "H", 0, 1, 0.3])
		return
	if typ == "intro" and b < 2:
		for s in range(0, 16, 4):
			ev.append([bs + s + 2, "H", 0, 1, 0.35])
		return
	var k := []
	var sn := [4, 12]
	var hh := [2, 6, 10, 14]
	match st:
		"four":
			k = [0, 4, 8, 12]
		"chip":
			k = [0, 8, 10]; hh = [0, 2, 4, 6, 8, 10, 12, 14]
		"half":
			k = [0, 10]; sn = [8]; hh = [0, 2, 4, 6, 8, 10, 12, 14]
		"break":
			k = [0, 6, 10]; sn = [4, 12, 15]; hh = [0, 2, 4, 6, 8, 10, 12, 14]
		"drive":
			k = [0, 4, 8, 12]; hh = range(16)
	if typ == "chorus" and st == "four":
		hh = range(0, 16)
	for s in k:
		ev.append([bs + s, "K", 0, 4, 0.9])
	for s in sn:
		ev.append([bs + s, "S", 0, 4, 0.35 if s == 15 else 0.7])
	for s in hh:
		ev.append([bs + s, "O" if s % 4 == 2 and st == "four" else "H", 0, 1, 0.42 if s % 2 == 0 else 0.26])
	if b == bars - 1 and typ != "outro":
		for s in [12, 13, 14, 15]:
			ev.append([bs + s, "S", 0, 1, 0.3 + 0.1 * (s - 12)])

static func _bass(ev: Array, song: Dictionary, typ: String, bs: int, r: int, fifth: int) -> void:
	if typ == "intro":
		ev.append([bs, "B", r, 16, 0.4])
		return
	if typ == "break":
		ev.append([bs, "B", r, 14, 0.45])
		return
	match song.bass:
		"pulse":
			for s in 16:
				ev.append([bs + s, "B", r + (12 if s % 8 == 7 else 0), 1, 0.5 if s % 4 == 0 else 0.34])
		"oct":
			for s in range(0, 16, 2):
				ev.append([bs + s, "B", r + (12 if s % 4 == 2 else 0), 2, 0.5])
		"off":
			for s in range(0, 16, 2):
				ev.append([bs + s, "B", r, 2, 0.55 if s % 4 == 2 else 0.25])
		_:
			var seq := [r, fifth, r + 12, fifth]
			for i in 4:
				ev.append([bs + i * 4, "B", seq[i], 3, 0.55])

static func _arp(ev: Array, typ: String, bs: int, base: int, ch: Array, fast: bool) -> void:
	var pat := [0, 1, 2, 3, 2, 1]
	var g := 2 if fast else 1
	var i := 0
	for s in range(0, 16, g):
		var k: int = pat[i % pat.size()]
		var m: int = base + (ch[k] if k < 3 else ch[0] + 12)
		ev.append([bs + s, "A", m, g, 0.18 if typ == "chorus" else 0.12])
		i += 1

## Convert note events into synth render events [sec, voice_key, gain]
static func render_events(comp: Dictionary, lead_in: float) -> Array:
	var song: Dictionary = comp.song
	var ss: float = comp.step_sec
	var out := []
	for e in comp.events:
		var t: float = lead_in + e[0] * ss
		var k: String = e[1]
		var key := k
		match k:
			"L":
				key = "L:%d:%d:%.3f" % [song.lead, e[2], e[3] * ss * 0.92]
				out.append([t + ss * 3.0, key, e[4] * 0.3])  # echo
			"B":
				key = "B:%d:%d:%.3f" % [2 if song.bass == "pulse" else 0 if song.bass == "oct" else 3, e[2], e[3] * ss * 0.9]
			"A":
				key = "A:1:%d:%.3f" % [e[2], e[3] * ss * 0.7]
			"P":
				key = "P:4:%d:%.3f" % [e[2], e[3] * ss]
		out.append([t, key, e[4]])
	# count-in clicks
	var beat := ss * 4.0
	var n := int(round(lead_in / beat))
	for i in n:
		out.append([lead_in - (n - i) * beat, "C:%d" % (1760 if i == 0 else 1320), 0.35])
	return out

static func lead_in_for(song: Dictionary) -> float:
	var beat: float = 60.0 / song.bpm
	return beat * (4 if song.bpm < 130 else 8)

static func length_sec(comp: Dictionary, lead_in: float) -> float:
	return lead_in + comp.steps * comp.step_sec + 1.5

## ------------------------------------------------------------------
## Charts: Array of [time_sec, lane], time relative to song start.
static func chart(comp: Dictionary, diff: int) -> Array:
	var ss: float = comp.step_sec
	var min_gap: float = [0.42, 0.2, 0.105][diff]
	var g := 1
	while g * ss < min_gap:
		g *= 2
	# relaxed grids: Easy = quarter notes (half notes on fast songs),
	# Normal = quarters with the odd 8th-note pair (quarters only on fast songs)
	if diff == 0:
		g = 4 if ss * 4.0 >= 0.42 else 8
	elif diff == 1:
		g = 2 if ss * 2.0 >= 0.19 else 4
	var cand := {}   # quant step -> [prio, kind, midi]
	for e in comp.events:
		var k: String = e[1]
		var pr := 0.0
		match k:
			"L": pr = 3.0
			"S": pr = 2.2 if e[4] > 0.5 else 0.0
			"K": pr = 2.0 if e[4] > 0.6 else 0.0
			"A": pr = 1.0 if diff == 2 else 0.0
			"H": pr = 0.6 if diff == 2 else 0.0
		if pr <= 0.0:
			continue
		if diff == 0 and pr < 2.0 and k != "L":
			continue
		var q: int = int(e[0]) / g * g
		if int(e[0]) % g != 0 and k != "L":
			continue
		if not cand.has(q) or cand[q][0] < pr:
			cand[q] = [pr, k, e[2]]
	var steps := cand.keys()
	steps.sort()
	var sec_of := func(st: int) -> String:
		var typ := "intro"
		for s in comp.sections:
			if st >= s[0]:
				typ = s[1]
		return typ
	var notes := []
	var prev_lane := -1
	var prev2 := -1
	var prev_step := -100
	var lo := 999
	var hi := 0
	for e in comp.events:
		if e[1] == "L":
			lo = mini(lo, e[2]); hi = maxi(hi, e[2])
	var dcount := 0
	var prev_midi := -1
	var kc := 0
	for st in steps:
		var c: Array = cand[st]
		var typ: String = sec_of.call(st)
		# keep easy/normal lighter outside of melody sections
		if diff == 0 and typ in ["intro", "outro", "break"] and st % 8 != 0:
			continue
		if diff == 1 and c[0] < 1.0:
			continue
		# Normal: an off-beat 8th only after a gap of at least a beat (no streams)
		if diff == 1 and st % 4 != 0 and st - prev_step < 4:
			continue
		# Easy: never closer than one beat
		if diff == 0 and st - prev_step < 4:
			continue
		var lane: int
		match c[1]:
			"L":
				var dm: int = int(c[2]) - prev_midi
				var base := prev_lane if prev_lane >= 0 else clampi(int(float(c[2] - lo) * 3.0 / float(hi - lo + 1)), 0, 2)
				if prev_midi < 0:
					lane = base
				elif dm == 0:
					lane = 2 - base if base != 1 else (prev2 if prev2 >= 0 and prev2 != 1 else 0)
				else:
					var stp := (1 if absi(dm) <= 4 else 2) * signi(dm)
					lane = base + stp
					if lane > 2: lane = maxi(0, base - absi(stp))
					if lane < 0: lane = mini(2, base + absi(stp))
				prev_midi = int(c[2])
			"S":
				lane = 1; kc += 1
			"K":
				lane = 0 if kc % 2 == 0 else 2; kc += 1
			_:
				lane = (st / g) % 3
		var gap: int = st - prev_step
		if lane == prev_lane and gap * ss < [0.9, 0.42, 0.22][diff]:
			lane = (lane + (1 if prev2 <= lane else 2)) % 3
		notes.append([st * ss, lane])
		# doubles
		if diff > 0 and typ == "chorus" and st % (16 if diff == 1 else 8) == 0:
			var l2 := 2 - lane
			if l2 == lane:
				l2 = 0
			notes.append([st * ss, l2])
			dcount += 1
		prev2 = prev_lane
		prev_lane = lane
		prev_step = st
	return notes

static func song_count() -> int:
	return SONGS.size()
