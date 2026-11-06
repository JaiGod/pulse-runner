class_name Synth
extends RefCounted
## Pulse Runner sound engine: every instrument is synthesized from math.
## One-shot voices (drums, synth notes) are rendered once and cached, then a
## song is mixed into a single 16-bit AudioStreamWAV in small chunks per frame
## so the game never freezes while a track is being built.

const SR := 22050
const TAU_F := TAU

static var _cache := {}
static var _noise := PackedFloat32Array()

# wave ids
const SQUARE := 0
const PULSE := 1
const SAW := 2
const TRI := 3
const SUPERSAW := 4
const SINE := 5

static func hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

static func _noise_buf() -> PackedFloat32Array:
	if _noise.is_empty():
		var r := RandomNumberGenerator.new()
		r.seed = 1337
		_noise.resize(SR * 2)
		for i in _noise.size():
			_noise[i] = r.randf() * 2.0 - 1.0
	return _noise

## Returns a cached one-shot buffer for a voice key.
static func voice(key: String) -> PackedFloat32Array:
	if _cache.has(key):
		return _cache[key]
	var parts := key.split(":")
	var b: PackedFloat32Array
	match parts[0]:
		"K": b = _kick()
		"S": b = _snare()
		"H": b = _hat(0.045)
		"O": b = _hat(0.2)
		"X": b = _crash()
		"C": b = _click(float(parts[1]))
		_:
			# tone: kind:wave:midi:len_sec
			b = _tone(parts[0], int(parts[1]), float(parts[2]), float(parts[3]))
	_cache[key] = b
	return b

static func _kick() -> PackedFloat32Array:
	var n := int(SR * 0.34)
	var b := PackedFloat32Array()
	b.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var f := 44.0 + 120.0 * exp(-t * 30.0)
		ph += f / SR
		var e := exp(-t * 8.5)
		var click := 0.0
		if i < 60:
			click = (1.0 - i / 60.0) * 0.35
		b[i] = sin(ph * TAU_F) * e * 0.95 + click
	return b

static func _snare() -> PackedFloat32Array:
	var nz := _noise_buf()
	var n := int(SR * 0.2)
	var b := PackedFloat32Array()
	b.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var x := nz[i + 700]
		lp += 0.55 * (x - lp)
		b[i] = lp * exp(-t * 17.0) * 0.75 + sin(TAU_F * 185.0 * t) * exp(-t * 30.0) * 0.55
	return b

static func _hat(dec: float) -> PackedFloat32Array:
	var nz := _noise_buf()
	var n := int(SR * dec * 2.2)
	var b := PackedFloat32Array()
	b.resize(n)
	var prev := 0.0
	var k := 1.0 / (dec * 0.45)
	for i in n:
		var t := float(i) / SR
		var x := nz[i + 9000]
		b[i] = (x - prev) * 0.45 * exp(-t * k)
		prev = x
	return b

static func _crash() -> PackedFloat32Array:
	var nz := _noise_buf()
	var n := int(SR * 1.4)
	var b := PackedFloat32Array()
	b.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / SR
		var x := nz[(i * 3 + 17) % nz.size()]
		b[i] = (x - prev * 0.6) * 0.3 * exp(-t * 2.6)
		prev = x
	return b

static func _click(f: float) -> PackedFloat32Array:
	var n := int(SR * 0.05)
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var t := float(i) / SR
		b[i] = sin(TAU_F * f * t) * exp(-t * 90.0) * 0.9
	return b

## kind: "L" lead, "B" bass, "A" arp, "P" pad, "T" tick (hit sound)
static func _tone(kind: String, wave: int, midi: float, len: float) -> PackedFloat32Array:
	var f := hz(midi)
	var a := 0.004
	var d := 0.12
	var s := 0.6
	var r := 0.08
	var cut := 1.0
	var vib := 0.0
	match kind:
		"L":
			a = 0.006; d = 0.18; s = 0.55; r = 0.12; cut = 0.55; vib = 0.005
		"B":
			a = 0.003; d = 0.09; s = 0.7; r = 0.05; cut = 0.22
		"A":
			a = 0.002; d = 0.06; s = 0.25; r = 0.04; cut = 0.5
		"P":
			a = 0.25; d = 0.4; s = 0.75; r = 0.5; cut = 0.18
		"T":
			a = 0.001; d = 0.04; s = 0.0; r = 0.02; cut = 0.8
	var n := int((len + r) * SR)
	var b := PackedFloat32Array()
	b.resize(n)
	var inc := f / SR
	var ph := 0.0
	var ph2 := 0.37
	var y := 0.0
	var duty := 0.25 if wave == PULSE else 0.5
	for i in n:
		var t := float(i) / SR
		var env: float
		if t < a:
			env = t / a
		elif t < a + d:
			env = 1.0 - (1.0 - s) * ((t - a) / d)
		elif t < len:
			env = s
		else:
			env = s * maxf(0.0, 1.0 - (t - len) / r)
		var step := inc
		if vib > 0.0 and t > 0.12:
			step = inc * (1.0 + vib * sin(TAU_F * 5.5 * t))
		ph += step
		ph -= floorf(ph)
		var x: float
		if wave == SQUARE or wave == PULSE:
			x = 0.8 if ph < duty else -0.8
		elif wave == SAW:
			x = ph * 2.0 - 1.0
		elif wave == TRI:
			x = 4.0 * absf(ph - 0.5) - 1.0
		elif wave == SUPERSAW:
			ph2 += step * 1.007
			ph2 -= floorf(ph2)
			x = (ph * 2.0 - 1.0) * 0.55 + (ph2 * 2.0 - 1.0) * 0.55
		else:
			x = sin(ph * TAU_F)
		y += cut * (x - y)
		b[i] = y * env
	return b


## ------------------------------------------------------------------
## Chunked song renderer. Call step(budget_usec) every frame until done.
class Job:
	extends RefCounted
	var events: Array = []   # [start_sec, key, gain]
	var total := 0
	var mix := PackedFloat32Array()
	var bytes := PackedByteArray()
	var ei := 0
	var ci := 0
	var phase := 0
	var gain := 1.0
	var done := false
	var stream: AudioStreamWAV

	func _init(evs: Array, seconds: float) -> void:
		events = evs
		total = int(seconds * Synth.SR) + 8
		mix.resize(total)
		bytes.resize(total * 2)

	func progress() -> float:
		if done:
			return 1.0
		if phase == 0:
			return 0.85 * float(ei) / maxf(1.0, events.size())
		return 0.85 + 0.15 * float(ci) / total

	func step(budget_usec: int) -> bool:
		var t0 := Time.get_ticks_usec()
		while not done and Time.get_ticks_usec() - t0 < budget_usec:
			if phase == 0:
				var lim := mini(ei + 24, events.size())
				while ei < lim:
					var ev: Array = events[ei]
					var buf: PackedFloat32Array = Synth.voice(ev[1])
					var o := int(float(ev[0]) * Synth.SR)
					var g: float = ev[2]
					var m := mini(buf.size(), total - o)
					var j := 0
					while j < m:
						mix[o + j] += buf[j] * g
						j += 1
					ei += 1
				if ei >= events.size():
					phase = 1
					var pk := 0.01
					var i := 0
					while i < total:
						pk = maxf(pk, absf(mix[i]))
						i += 5
					gain = 0.92 / pk
			else:
				var lim2 := mini(ci + 20000, total)
				var g2 := gain * 32000.0
				while ci < lim2:
					bytes.encode_s16(ci * 2, int(clampf(mix[ci] * g2, -32700.0, 32700.0)))
					ci += 1
				if ci >= total:
					stream = AudioStreamWAV.new()
					stream.format = AudioStreamWAV.FORMAT_16_BITS
					stream.mix_rate = Synth.SR
					stream.stereo = false
					stream.data = bytes
					mix = PackedFloat32Array()
					done = true
		return done

	## Render synchronously (tests / tiny jingles).
	func finish() -> AudioStreamWAV:
		while not step(1000000):
			pass
		return stream
