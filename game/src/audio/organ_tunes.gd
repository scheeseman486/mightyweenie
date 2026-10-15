class_name MwOrganTunes
extends RefCounted
## The organ pool's own tunes (plan 39, [MwOrganPool]), each about 6 s on
## the rink jingles' organ. Times are 60 Hz ticks; a part written with a key
## shift of +12 sounds at the written name's pitch (the organ sounds an
## octave below its key); at most four notes sound at once.
##
## Public-domain classics, arranged for the port (owner's picks, 2026-10-10):
## Bach (Toccata and Fugue in D minor, the Little Fugue in G minor, the
## Passacaglia in C minor), Grieg (In the Hall of the Mountain King, March of
## the Trolls), Chopin (the Funeral March), Gounod (Funeral March of a
## Marionette), Mussorgsky / Rimsky-Korsakov (Night on Bald Mountain),
## Beethoven (Symphony No. 5, the Moonlight Sonata), Mozart (the Requiem's
## Dies irae), Wagner (Ride of the Valkyries), Rachmaninoff (Prelude in C#
## minor), Holst (Mars), Tchaikovsky (Dance of the Sugar Plum Fairy), Berlioz
## (March to the Scaffold), Schubert (Erlkonig), Bizet (Carmen's fate motif).
## Written for the port: Stomp Manor (with floor hits) and Hearse Gallop.
## Their melodies were checked against public-domain scores and note
## transcriptions (docs/re/sound.md 13.12); the tempos are quickened to
## fit about 6 s.

const Tune := MwOrganPool.Tune
## How many tunes [method all] returns.
const COUNT := 20


## Every tune, in the pool's order (after the original's five).
static func all() -> Array[Tune]:
	return [toccata(), mountain_king(), stomp_manor(), hearse_gallop(),
			funeral_march(), marionette(), bald_mountain(), little_fugue(), fifth_symphony(),
			moonlight(), requiem(), valkyries(), bells_prelude(), mars(), sugar_plum(),
			passacaglia(), scaffold(), erlking(), trolls(), carmen_fate()]


## [param k] as a MIDI key ([method MwOrganPool.key]): an int, or a name such as "F#3".
static func key(k: Variant) -> int:
	return MwOrganPool.key(k)


## [param x] rounded to a tick, halves up ([method MwOrganPool.tick]).
static func tick(x: float) -> int:
	return MwOrganPool.tick(x)


## Bach, BWV 565: phrase 1 (A-G-A, held; G F E D C# D, held) and phrase 3
## two octaves down onto the pedal D, the diminished seventh built up over it
## (G passing, so four notes at most), the D major resolution. 6.1 s.
static func toccata() -> Tune:
	var tune := Tune.new("toccata")
	var hi := tune.part(1)        # the manual's line
	var lo := tune.part(2)        # doubled an octave below
	var ped := tune.part(3)       # the pedal D and the chords
	# a line and its octave below: [name, step, length] from [param t]
	var line := func(t: int, notes: Array, vel: int) -> void:
		for n: Array in notes:
			tune.note(hi, t, n[2], key(n[0]) + 12, vel)
			tune.note(lo, t, n[2], n[0], vel - 6)
			t += n[1]
	# phrase 1: A-G-A mordent, held; G F E D C# D, held
	line.call(0, [["A5", 6, 5], ["G5", 6, 5], ["A5", 50, 42]], 104)
	line.call(62, [["G5", 7, 6], ["F5", 7, 6], ["E5", 7, 6], ["D5", 7, 6], ["C#5", 12, 11], ["D5", 52, 42]], 104)
	# phrase 3, two octaves down, the last D onto the pedal
	line.call(154, [["A3", 5, 4], ["G3", 5, 4], ["A3", 36, 30]], 108)
	line.call(200, [["G3", 6, 5], ["F3", 6, 5], ["E3", 6, 5], ["D3", 6, 5], ["C#3", 10, 9]], 108)
	var d0 := 234
	tune.note(hi, d0, 14, "D4", 108)
	tune.note(ped, d0, 128, "D3", 112)
	# the diminished seventh over the pedal, built from below: E, G (passing), Bb, C#
	tune.note(lo, d0 + 10, 50, "E4", 108)
	tune.note(hi, d0 + 18, 15, "G4", 108)
	tune.note(lo, d0 + 26, 34, "Bb4", 108)
	tune.note(hi, d0 + 34, 26, "C#5", 108)
	# resolution: D major over the pedal
	tune.chord(ped, d0 + 64, 64, ["F#4", "A4", "D5"], 118)
	return tune


## Grieg: the theme once, speeding up from a quiet two-octave start to three
## octaves with a bass on each bar's downbeat, then the B minor crash. 6.1 s.
static func mountain_king() -> Tune:
	var tune := Tune.new("mountain_king")
	var a := tune.part(1)
	var b := tune.part(2)
	var c := tune.part(3)
	var bass := tune.part(4)
	# the theme in eighths [name, eighths], B minor
	var theme := [["B2", 1], ["C#3", 1], ["D3", 1], ["E3", 1], ["F#3", 1], ["D3", 1], ["F#3", 2],
			["E#3", 1], ["C#3", 1], ["E#3", 2], ["E3", 1], ["C3", 1], ["E3", 2],
			["B2", 1], ["C#3", 1], ["D3", 1], ["E3", 1], ["F#3", 1], ["D3", 1], ["F#3", 1], ["B3", 1],
			["A3", 1], ["F#3", 1], ["D3", 1], ["F#3", 1], ["A3", 4]]
	var total := 0
	for n: Array in theme:
		total += int(n[1])
	var bar_bass := ["B2", "C#3", "B2", "F#3"]
	var pos := 0
	var tf := 0.0
	for n: Array in theme:
		var e: int = n[1]
		var step := 12.0 - 5.0 * pos / total            # an eighth: 12 -> 7 ticks
		var vel := int(84 + 36.0 * pos / total)
		var ts := floori(tf + 0.5)
		var ln := maxi(3, int(step * 0.5)) if e == 1 else int(e * step) - 4
		tune.note(a, ts, ln, key(n[0]) + 12, vel)
		tune.note(b, ts, ln, key(n[0]) + 24, vel - 4)
		if pos >= 16:                                     # the second half: a third octave and the bass
			tune.note(c, ts, ln, key(n[0]) + 36, vel - 14)
			if pos % 8 == 0:
				@warning_ignore("integer_division")
				tune.note(bass, ts, maxi(3, int(step * 0.6)), bar_bass[pos / 8], vel)
		pos += e
		tf += e * step
	# the crash: B minor, short then long
	var t := floori(tf + 0.5) + 2
	var chord_notes := ["B2", "F#4", "B4", "D5"]
	var chans := [bass, a, b, c]
	for i in 4:
		tune.note(chans[i], t, 6, chord_notes[i], 120)
		tune.note(chans[i], t + 12, 46, chord_notes[i], 124)
	return tune


## Written for the port: stomp, stomp, then the organ answers - an E minor
## figure (up a semitone and back, then down), sequenced down by steps; the
## last bar's stomp lands with the E minor chord, which wilts. 6.6 s.
static func stomp_manor() -> Tune:
	var tune := Tune.new("stomp_manor")
	var hi := tune.part(1)
	var lo := tune.part(2)
	var bass := tune.part(3)
	var end := tune.part(4)       # the last chord, bent on its own channel
	var beat := 28
	var bar := 112
	var t0 := 4
	# [the answer, its bass, the bass on beat 4 (or none)]
	var answers := [
		[["E5", "F5", "E5", "B4"], ["E3", "B3"], []],
		[["D5", "Eb5", "D5", "A4"], ["D3", "A3"], []],
		[["C5", "Db5", "C5", "B4"], ["C3", "G3"], ["B2", "F#3"]],
	]
	for i in answers.size():
		var mel: Array = answers[i][0]
		var b1: Array = answers[i][1]
		var b2: Array = answers[i][2]
		var bar_start := t0 + i * bar
		tune.hit(bar_start - 2)              # the stomp's thump peaks ~2 ticks into the hit
		tune.hit(bar_start + beat - 2)
		var note_at := bar_start + 2 * beat
		for j in mel.size():
			var ln := 11 if j < 3 else (24 if i < 2 else 12)   # the last one clears the final chord
			tune.note(hi, note_at, ln, mel[j], 104)
			tune.note(lo, note_at, ln, key(mel[j]) - 12, 98)
			note_at += 14
		if b2.is_empty():
			tune.chord(bass, bar_start + 2 * beat, 2 * beat - 4, b1, 110)
		else:
			tune.chord(bass, bar_start + 2 * beat, beat - 3, b1, 110)
			tune.chord(bass, bar_start + 3 * beat, beat - 2, b2, 112)
	var t := t0 + 3 * bar
	tune.hit(t - 2)
	tune.chord(end, t, 56, ["E3", "B3", "G4", "E5"], 122)
	tune.glide(end, t + 30, t + 56, 0, -12, 2)    # the chord wilts at the end
	return tune


## Written for the port: a 6/8 gallop in D minor - the bass galloping alone
## for a bar, then the organ's melody in octaves over Dm Dm Bb A A7, ending
## da... DUM. 6.6 s.
static func hearse_gallop() -> Tune:
	var tune := Tune.new("hearse_gallop")
	var hi := tune.part(1)
	var lo := tune.part(2)
	var bass := tune.part(3)
	var bass2 := tune.part(4)
	var e8 := 9
	var bar := 54
	# the bass per half bar: the root (a quarter) and the fifth (an eighth)
	var roots := [["D3", "A3"], ["D3", "A3"], ["D3", "A3"], ["Bb2", "F3"], ["A2", "E3"], ["A2", "E3"]]
	for i in roots.size():
		var bar_start := i * bar
		var v := 100 if i == 0 else 110
		for half: int in [0, 27]:
			tune.note(bass, bar_start + half, 15, roots[i][0], v)
			tune.note(bass2, bar_start + half, 15, key(roots[i][0]) + 12, v - 10)
			tune.note(bass, bar_start + half + 18, 6, roots[i][1], v - 8)
	var mel := [[["A4", 2], ["D5", 1], ["F5", 1], ["E5", 1], ["D5", 1]],
			[["C#5", 2], ["D5", 1], ["A4", 3]],
			[["Bb4", 2], ["D5", 1], ["F5", 1], ["G5", 1], ["F5", 1]],
			[["E5", 3], ["C#5", 2], ["A4", 1]],
			[["C#5", 1], ["E5", 1], ["G5", 1], ["Bb5", 2], ["A5", 1]]]
	var t := bar
	for b: Array in mel:
		for n: Array in b:
			var ln: int = int(n[1]) * e8 - 3
			tune.note(hi, t, ln, key(n[0]) + 12, 104)
			tune.note(lo, t, ln, n[0], 100)
			t += int(n[1]) * e8
	# da... DUM: D minor
	var final := ["D3", "A3", "F5", "D6"]
	var chans := [bass, bass2, lo, hi]
	for i in 4:
		tune.note(chans[i], t, 6, final[i], 118)
		tune.note(chans[i], t + 2 * e8, 52, final[i], 124)
	return tune


## Chopin, Piano Sonata No. 2, the march: bars 1, 3 and 4 over the Bb / Gb
## bell of the left hand. 5.8 s.
static func funeral_march() -> Tune:
	var tune := Tune.new("funeral_march")
	var hi := tune.part(1)
	var lo := tune.part(2)
	var lh := tune.part(3)
	var q := 28
	var mel := [["Bb4", 1], ["Bb4", .75], ["Bb4", .25], ["Bb4", 2],
			["Bb4", 1], ["Bb4", .75], ["Bb4", .25], ["Bb4", 1], ["Db5", .75], ["C5", .25],
			["C5", .75], ["Bb4", .25], ["Bb4", .75], ["A4", .25], ["Bb4", 2.5]]
	tune.line(0, mel, q, [[hi, 12, 0], [lo, 0, -6]], 104, 0.85)
	for beat in 10:
		var even := beat % 2 == 0
		tune.chord(lh, beat * q, q - 6, ["Bb2", "F3"] if even else ["Gb3", "Bb3"], 96 if even else 86)
	tune.chord(lh, 10 * q, tick(2.5 * q), ["Bb2", "F3"], 100)
	return tune


## Gounod, Funeral March of a Marionette: bars 1-4 in thirds over an
## oom-pah bass, a D minor close. 5.6 s.
static func marionette() -> Tune:
	var tune := Tune.new("marionette")
	var th := tune.part(1)
	var bass := tune.part(2)
	var e := 12
	var b1 := [[["D4"], 2], [["F4", "D4"], 1], [["F4", "D4"], 1], [["E4", "C#4"], 1], [["D4", "B3"], 1]]
	var b2 := [[["E4", "C#4"], 2], [["F4", "D4"], 1], [["G4", "E4"], 3]]
	tune.line(0, b1 + b2 + b1 + b2, e, [[th, 12, 0]], 104, 0.75)
	var basses := [["D3", "A2"], ["A2", "C#3"], ["D3", "A2"], ["A2", "C#3"]]
	for bar in 4:
		tune.note(bass, bar * 6 * e, 2 * e - 4, basses[bar][0], 100)
		tune.note(bass, bar * 6 * e + 3 * e, 2 * e - 4, basses[bar][1], 90)
	var t := 24 * e
	tune.chord(th, t, 50, ["D5", "F5", "A4"], 112)
	tune.note(bass, t, 50, "D3", 112)
	return tune


## Mussorgsky / Rimsky-Korsakov, Night on Bald Mountain: the whirling
## strings, the bass's A-G#-Bb, the two lunges to the tritone, a D minor
## crash. 6.1 s.
static func bald_mountain() -> Tune:
	var tune := Tune.new("bald_mountain")
	var w1 := tune.part(1)
	var w2 := tune.part(2)
	var l1 := tune.part(3)
	var l2 := tune.part(4)
	var note_ticks := 6
	var whirl_bar := ["A4", "G#4", "A4", "Bb4", "A4", "G#4", "A4", "G#4", "A4", "Bb4", "A4", "G#4"]
	var whirl := func(at: int, n: int) -> void:
		for i in n:
			tune.line(at + i * note_ticks, [[whirl_bar[i % 12], 1]], note_ticks, [[w1, 12, 0], [w2, 24, -10]], 92, 0.9)
	whirl.call(0, 6)                                 # half a bar alone
	var t := 36
	for bar in 2:                                    # the bass under the whirl
		whirl.call(t, 12)
		tune.line(t, [["A2", 1], ["G#2", 1], ["Bb2", 1], ["G#2", 1]], 18, [[l1, 12, 0], [l2, 24, -6]], 112, 0.85)
		t += 72
	for lunge: Array in [["A3", "Bb3", "C4", "D4", "Eb4", "D4", "C4", "Bb3"],
			["A3", "B3", "C4", "D4", "E4", "D4", "C4", "B3"]]:
		whirl.call(t, 12)
		var seq := [[lunge[0], 29], [lunge[1], 2], [lunge[2], 2], [lunge[3], 3],
				[lunge[4], 29], [lunge[5], 2], [lunge[6], 2], [lunge[7], 3]]
		tune.line(t, seq, 1, [[l1, 12, 0], [l2, 0, -4]], 118, 0.92, 1)
		t += 72
	tune.chord(l1, t, 40, ["D3", "A3"], 122)
	tune.chord(w1, t, 40, ["D4", "F4"], 118)
	return tune


## Bach, Fugue in G minor BWV 578: the subject's first three bars (the
## mordent on the Bb), then a G minor chord. 6.3 s.
static func little_fugue() -> Tune:
	var tune := Tune.new("little_fugue")
	var hi := tune.part(1)
	var lo := tune.part(2)
	var c1 := tune.part(3)
	var c2 := tune.part(4)
	var subj := [["G4", 1], ["D5", 1], ["Bb4", .12], ["A4", .12], ["Bb4", 1.26], ["A4", .5],
			["G4", .5], ["Bb4", .5], ["A4", .5], ["G4", .5], ["F#4", .5], ["A4", .5], ["D4", 1],
			["G4", .5], ["D4", .5], ["A4", .5], ["D4", .5], ["Bb4", .5], ["A4", .25], ["G4", .25], ["A4", .5],
			["D4", .5]]
	var t := tick(tune.line(0, subj, 28, [[hi, 12, 0], [lo, 0, -6]], 106, 0.85, 2))
	tune.chord(c1, t, 44, ["G3", "D4"], 112)
	tune.chord(c2, t, 44, ["G4", "Bb4"], 112)
	return tune


## Beethoven, Symphony No. 5: the motto twice with its holds, then the climb
## of bars 14-15 and 18-21 to the Ab chord and G. 6.4 s.
static func fifth_symphony() -> Tune:
	var tune := Tune.new("fifth_symphony")
	var hi := tune.part(1)
	var lo := tune.part(2)
	var bs := tune.part(3)
	var ch := tune.part(4)
	var e := 9
	var parts := [[hi, 12, 0], [lo, 0, -4], [bs, -12, -2]]
	tune.line(e, [["G4", 1], ["G4", 1], ["G4", 1], ["Eb4", 5.3]], e, parts, 118, 0.8)
	tune.line(93, [["F4", 1], ["F4", 1], ["F4", 1], ["D4", 7.3]], e, parts, 118, 0.8)
	var t := tick(tune.line(196, [["D5", 1], ["G5", 1], ["G5", 1], ["F5", 1], ["Eb5", 4],
			["D5", 1], ["G5", 1], ["G5", 1], ["F5", 1]], e, [[hi, 12, 0], [lo, 0, -4]], 112, 0.8))
	# the closing chords: Eb over C minor, the Ab chord with C and F#, G
	for c: Array in [[16, "Eb6", "Eb5", "G4", "C3", 120, 116, 112, 118],
			[16, "C6", "F#5", "C5", "Ab3", 120, 116, 112, 118],
			[42, "G6", "G5", "D5", "G3", 124, 120, 114, 120]]:
		tune.chord(hi, t, c[0], [c[1]], c[5])
		tune.chord(lo, t, c[0], [c[2]], c[6])
		tune.chord(ch, t, c[0], [c[3]], c[7])
		tune.chord(bs, t, c[0], [c[4]], c[8])
		t += 18
	return tune


## Beethoven, Moonlight Sonata: bar 1's triplets, bars 5-6 with the dotted
## G#, half of bar 7 - at about twice the usual pace. 6.3 s.
static func moonlight() -> Tune:
	var tune := Tune.new("moonlight")
	var tri := tune.part(1)
	var b1 := tune.part(2)
	var b2 := tune.part(3)
	var mel := tune.part(4)
	var triplet_ticks := 9
	var cs := ["G#3", "C#4", "E4"]
	var groups := [[cs, cs, cs, cs], [["E3", "G#3", "C#4"], cs, cs, cs],
			[["G#3", "D#4", "F#4"], ["G#3", "D#4", "F#4"], ["G#3", "D#4", "F#4"], ["G#3", "D#4", "F#4"]],
			[cs, cs]]
	var basses := [["C#3", "C#4"], ["C#3", "C#4"], ["B#2", "B#3"], ["C#3", "C#4"]]
	var t := 0
	for k in 4:
		var n := 0
		for grp: Array in groups[k]:
			for nt: String in grp:
				tune.note(tri, t + n * triplet_ticks, triplet_ticks - 1, key(nt) + 12, 82)
				n += 1
		tune.note(b1, t, n * triplet_ticks - 2, basses[k][0], 90)
		tune.note(b2, t, n * triplet_ticks - 2, basses[k][1], 84)
		t += n * triplet_ticks
	tune.line(108 + 81, [["G#4", .75], ["G#4", .25], ["G#4", 3], ["G#4", .75], ["G#4", .25], ["G#4", 2]],
			27, [[mel, 12, 0]], 100, 0.9)
	return tune


## Mozart, Requiem, Dies irae: bars 1-4, the choir (soprano, alto where it
## is not the soprano's note, tenor) over the rolling orchestral bass, a D
## minor close. 6.0 s.
static func requiem() -> Tune:
	var tune := Tune.new("requiem")
	var soprano := tune.part(1)
	var a := tune.part(2)
	var tn := tune.part(3)
	var b := tune.part(4)
	var e := 10
	var sop := [["D5", 4], ["A4", 4], ["E5", 2], ["A4", 2], [null, 4], ["E5", 4], ["A4", 4],
			["F5", 2], ["D5", 2], [null, 2], ["D5", 1], ["D5", 1]]
	var alto := [["A4", 4], [null, 4], ["A4", 2], [null, 6], ["A4", 4], [null, 4],
			["A4", 2], ["A4", 2], [null, 2], ["A4", 1], ["A4", 1]]
	var ten := [["F4", 4], ["F4", 4], ["G4", 2], ["G4", 2], [null, 4], ["G4", 4], ["G4", 4],
			["F4", 2], ["F4", 2], [null, 2], ["F4", 1], ["F4", 1]]
	var bass := [["D3", 1], ["F3", 1], ["A3", 1], ["D4", 1], ["D3", 1], ["F3", 1], ["A3", 1], ["D4", 1],
			["D3", 1], ["D4", 2], ["D4", 2], ["D4", 2], ["D4", 1],
			["C#3", 1], ["E3", 1], ["A3", 1], ["C#4", 1], ["C#3", 1], ["E3", 1], ["A3", 1], ["C#4", 1],
			["D3", 1], ["D4", 2], ["D4", 2], ["D4", 2], ["D3", 1]]
	tune.line(0, sop, e, [[soprano, 0, 0]], 120, 0.85)
	tune.line(0, alto, e, [[a, 0, 0]], 112, 0.85)
	tune.line(0, ten, e, [[tn, 0, 0]], 112, 0.85)
	tune.line(0, bass, e, [[b, 0, 0]], 116, 0.8)
	var parts := [soprano, a, tn, b]
	var close := ["D5", "A4", "F4", "D3"]
	for k in 4:
		tune.note(parts[k], 32 * e, 42, close[k], 124)
	return tune


## Wagner, Ride of the Valkyries: the motif climbing B-D-F#-A over a pedal
## and the strings' trill. 6.0 s.
static func valkyries() -> Tune:
	var tune := Tune.new("valkyries")
	var hi := tune.part(1)
	var lo := tune.part(2)
	var ped := tune.part(3)
	var trill := tune.part(4)
	var mel := [["F#3", 1], ["B3", 1.5], ["F#3", .5], ["B3", 1], ["D4", 5], ["B3", 1],
			["D4", 1.5], ["B3", .5], ["D4", 1], ["F#4", 5], ["D4", 1],
			["F#4", 1.5], ["D4", .5], ["F#4", 1], ["A4", 11]]
	tune.line(0, mel, 11, [[hi, 12, 0], [lo, 0, -4]], 118, 0.85)
	tune.note(ped, 11, 196, "B2", 104)
	tune.note(ped, 209, 150, "D3", 108)
	var t := 11
	while t < 352:
		var pair := ["B5", "C#6"] if t < 209 else ["D6", "E6"]
		@warning_ignore("integer_division")
		tune.note(trill, t, 3, pair[(t / 4) % 2], 82)
		t += 4
	return tune


## Rachmaninoff, Prelude in C# minor: the fff motto A-G#-C# in three
## octaves, then the hushed chords over C#-A-G#, a C# minor close. 6.0 s.
static func bells_prelude() -> Tune:
	var tune := Tune.new("bells_prelude")
	var v1 := tune.part(1)
	var v2 := tune.part(2)
	var v3 := tune.part(3)
	var v4 := tune.part(4)
	for vs: Array in [[v1, 0], [v2, 12], [v3, 24]]:
		tune.note(vs[0], 0, 28, key("A2") + int(vs[1]), 124)
		tune.note(vs[0], 30, 28, key("G#2") + int(vs[1]), 124)
	tune.note(v1, 60, 178, "C#3", 124)                 # the bell's C#, held on as the bass
	tune.note(v2, 60, 130, "C#4", 120)
	tune.note(v3, 60, 130, "C#5", 118)
	var chords := [[15, ["E5", "G#5", "C#6"]], [30, ["G#5", "B5", "E6"]], [45, ["G5", "A#5", "D#6"]],
			[75, ["F#5", "A5", "D6"]], [105, ["D#5", "F#5", "C6"]]]
	var upper := [v2, v3, v4]
	for c: Array in chords:
		for k in 3:
			tune.note(upper[k], 180 + int(c[0]), 12, c[1][k], 82)
	tune.note(v1, 240, 28, "A2", 96)
	tune.note(v1, 270, 28, "G#2", 96)
	tune.note(v1, 300, 60, "C#3", 92)
	var last := ["E5", "G#5", "C#6"]
	for k in 3:
		tune.note(upper[k], 300, 60, last[k], 84)
	return tune


## Holst, Mars: the 5/4 col legno hammering on G under the horns' G, D, Db.
## 6.0 s.
static func mars() -> Tune:
	var tune := Tune.new("mars")
	var o1 := tune.part(1)
	var o2 := tune.part(2)
	var l1 := tune.part(3)
	var l2 := tune.part(4)
	var rhythm := [[0, 6], [8, 6], [16, 6], [24, 16], [48, 16], [72, 9], [84, 9], [96, 16]]
	for bar in 3:
		var v := 90 + bar * 10
		for r: Array in rhythm:
			tune.note(o1, bar * 120 + int(r[0]), r[1], "G2", v)
			tune.note(o2, bar * 120 + int(r[0]), r[1], "G3", v - 6)
	for l: Array in [["G4", 0, 190, 104], ["D5", 192, 238, 112], ["Db5", 240, 358, 118]]:
		tune.note(l1, l[1], int(l[2]) - int(l[1]), l[0], l[3])
		tune.note(l2, l[1], int(l[2]) - int(l[1]), key(l[0]) + 12, int(l[3]) - 8)
	return tune


## Tchaikovsky, Dance of the Sugar Plum Fairy: a bar of pizzicato, then the
## celesta's four bars over the E pedal and off-beat dyads. 6.3 s.
static func sugar_plum() -> Tune:
	var tune := Tune.new("sugar_plum")
	var mel := tune.part(1)
	var bass := tune.part(2)
	var d1 := tune.part(3)
	var d2 := tune.part(4)
	var e := 18
	for bar in 5:
		for pos: int in [0, 2]:
			if not (bar == 4 and pos == 2):
				tune.note(bass, bar * 72 + pos * e, 14, "E3", 96)
	tune.chord(d1, e, 14, [key("G3") + 12, key("E4") + 12], 88)
	tune.note(d2, e, 14, key("B3") + 12, 88)
	tune.chord(d1, 3 * e, 14, [key("A3") + 12, key("D#4") + 12], 88)
	tune.note(d2, 3 * e, 14, key("C4") + 12, 88)
	for d: Array in [[1, 1, "G3", "B3"], [1, 3, "A3", "C4"], [2, 1, "A#3", "C#4"], [2, 3, "B3", "D4"],
			[3, 1, "C#4", "E4"], [3, 3, "A3", "C4"], [4, 1, "A3", "C4"]]:
		var at: int = int(d[0]) * 72 + int(d[1]) * e
		tune.note(d1, at, 14, key(d[2]) + 12, 96)
		tune.note(d2, at, 14, key(d[3]) + 12, 96)
	var m := [[null, 1], ["G6", .5], ["E6", .5], ["G6", 1], ["F#6", 1],
			["D#6", 1], ["E6", 1], ["D6", .5], ["D6", .5], ["D6", 1],
			["C#6", .5], ["C#6", .5], ["C#6", 1], ["C6", .5], ["C6", .5], ["C6", 1],
			["B5", .5], ["E6", .5], ["C6", .5], ["E6", .5], ["B5", 1]]
	tune.line(72, m, e, [[mel, 0, 0]], 118, 0.7)
	tune.note(bass, 288 + 3 * e, 8, "C4", 96)
	tune.note(bass, 288 + 3 * e + 9, 8, "B3", 96)
	tune.note(bass, 360, 20, "E3", 100)
	tune.note(mel, 360, 20, "E6", 104)
	return tune


## Bach, Passacaglia in C minor BWV 582: the pedal theme alone, as the piece
## begins, closing on a C minor chord. 6.2 s.
static func passacaglia() -> Tune:
	var tune := Tune.new("passacaglia")
	var lo := tune.part(1)
	var hi := tune.part(2)
	var c1 := tune.part(3)
	var c2 := tune.part(4)
	var q := 15
	var th := [["C3", 1], ["G3", 2], ["Eb3", 1], ["F3", 2], ["G3", 1], ["Ab3", 2], ["F3", 1],
			["G3", 2], ["D3", 1], ["Eb3", 2], ["B2", 1], ["C3", 2], ["F2", 1], ["G2", 3], ["C2", 3]]
	tune.line(0, th, q, [[lo, 12, 0], [hi, 24, -8]], 110, 0.9)
	tune.note(c1, 22 * q, 3 * q - 2, "G4", 104)
	tune.note(c2, 22 * q, 3 * q - 2, "Eb5", 104)
	return tune


## Berlioz, Symphonie fantastique, March to the Scaffold: the low strings'
## falling G minor scale (bars 17-20), then G minor. 6.5 s.
static func scaffold() -> Tune:
	var tune := Tune.new("scaffold")
	var hi := tune.part(1)
	var lo := tune.part(2)
	var c1 := tune.part(3)
	var c2 := tune.part(4)
	var th := [["G3", 1], [null, 1], ["G4", 2], ["F4", 2], ["Eb4", 1], ["D4", .5], ["C4", .5],
			["Bb3", 1], [null, 1], ["A3", 1], [null, 1], ["G3", 2], ["F3", 1], ["Eb3", .5], ["D3", .5]]
	var t := tick(tune.line(0, th, 22, [[hi, 12, 0], [lo, 0, -4]], 118, 0.85))
	tune.chord(hi, t, 40, ["G4"], 124)
	tune.chord(lo, t, 40, ["G3"], 120)
	tune.chord(c1, t, 40, ["D4"], 116)
	tune.chord(c2, t, 40, ["Bb4"], 116)
	return tune


## Schubert, Erlkonig: the galloping octave triplets and the bass's rising
## run crashing back (bars 1-5). 6.0 s.
static func erlking() -> Tune:
	var tune := Tune.new("erlking")
	var r1 := tune.part(1)
	var r2 := tune.part(2)
	var l1 := tune.part(3)
	var l2 := tune.part(4)
	var triplet_ticks := 8
	for i in 45:
		tune.note(r1, i * triplet_ticks, 6, "G4", 96)
		tune.note(r2, i * triplet_ticks, 6, "G5", 88)
	var run := [["G2", 1], ["A2", 1], ["Bb2", 1], ["C3", 1], ["D3", 1], ["Eb3", 1], ["D3", 3], ["Bb2", 3]]
	for start: int in [48, 240]:
		tune.line(start, run, triplet_ticks, [[l1, 12, 0], [l2, 0, -6]], 116, 0.85)
	for start: int in [144, 336]:
		tune.line(start, [["G2", 3]], triplet_ticks, [[l1, 12, 0], [l2, 0, -6]], 118, 0.9)
	return tune


## Grieg, March of the Trolls: the run-up, the chromatic creep in staccato
## pairs over the D-A bass (bars 2-10), a D minor stab. 6.1 s.
static func trolls() -> Tune:
	var tune := Tune.new("trolls")
	var top := tune.part(1)
	var m1 := tune.part(2)
	var m2 := tune.part(3)
	var lh := tune.part(4)
	var e := 11
	for i in 33:
		tune.note(lh, i * e, 8, "D3" if i % 2 == 0 else "A3", 96)
	var up := func(n: String) -> int: return key(n) + 12
	var run := ["D4", "E4", "F4", "G4"]
	for i in 4:
		tune.note(top, i * 3, 2, up.call(run[i]), 100)
	var pairs := func(t: int, tops: Array, under: Array) -> void:
		for j in tops.size():
			tune.note(top, t + j * e, 7, up.call(tops[j]), 104 if j % 2 == 0 else 96)
			tune.note(m1, t + j * e, 7, up.call(under[0]), 92)
			tune.note(m2, t + j * e, 7, up.call(under[1]), 92)
	var three := [top, m1, m2]
	tune.note(top, 11, 7, up.call("A4"), 106)
	pairs.call(22, ["D5", "D5", "C#5"], ["D4", "F4"])
	pairs.call(55, ["C#5", "C5", "C5", "B4"], ["D4", "F4"])
	pairs.call(99, ["B4", "Bb4", "Bb4", "A4"], ["D4", "F4"])
	for j in 2:
		var e6 := ["G#4", "B3", "E4"]
		for k in 3:
			tune.note(three[k], 143 + j * e, 7 if j == 0 else 18, up.call(e6[k]), 104)
	var run2 := ["G4", "A4", "Bb4", "C5"]
	for i in 4:
		tune.note(top, 143 + 3 * e + i * 3, 2, up.call(run2[i]), 104)
	tune.note(top, 187, 7, up.call("D5"), 110)
	pairs.call(198, ["G5", "G5", "F#5"], ["G4", "Bb4"])
	pairs.call(231, ["F#5", "F5", "F5", "E5"], ["G4", "Bb4"])
	pairs.call(275, ["E5", "Eb5", "Eb5", "D5"], ["G4", "Bb4"])
	var a7 := ["C#5", "E4", "A4"]
	for at: int in [319, 330]:
		for k in 3:
			tune.note(three[k], at, 9, up.call(a7[k]), 112)
	var dm := ["D5", "F4", "A4"]
	for k in 3:
		tune.note(three[k], 341, 22, up.call(dm[k]), 118)
	return tune


## Bizet, Carmen: the fate motif (the augmented second's sigh) over the
## strings' tremolo and the low D pulses. 6.0 s.
static func carmen_fate() -> Tune:
	var tune := Tune.new("carmen_fate")
	var mel := tune.part(1)
	var t1 := tune.part(2)
	var t2 := tune.part(3)
	var bass := tune.part(4)
	var trem := func(start: int, end: int, low: Array, high: String) -> void:
		var t := start
		var k := 0
		while t < end:
			if k % 2 == 0:
				tune.note(t1, t, 2, key(low[0]) + 12, 80)
				tune.note(t2, t, 2, key(low[1]) + 12, 80)
			else:
				tune.note(t1, t, 2, key(high) + 12, 80)
			t += 3
			k += 1
	trem.call(0, 216, ["D4", "F4"], "A4")
	trem.call(216, 288, ["D4", "F4"], "B4")
	trem.call(288, 360, ["D4", "G4"], "Bb4")
	var m := [["D4", 1.5], ["C#4", .5], ["Bb3", .5], ["C#4", .5], ["A3", .5], [null, 2.5],
			["A3", 1.5], ["G#3", .5], ["F3", .5], ["G#3", .5], ["E3", 1], [null, 2]]
	tune.line(72, m, 24, [[mel, 12, 0]], 122, 0.9)
	for bar: int in [1, 3]:
		for b: int in [1, 2]:
			tune.note(bass, 72 + bar * 72 + b * 24, 10, "D3", 112)
	return tune
