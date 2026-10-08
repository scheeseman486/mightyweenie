class_name MwPlayoffs
extends RefCounted
## The playoff run (`$FFBD6A`, 21 bytes; docs/re/menus.md, Playoffs): what
## the original keeps between the playoff screens and games, and what its
## passwords carry. Node-free; the screens read and change it.
##
## [codeblock]
## +$0  .l  the playoffs' own random stream (seeded from [member seed])
## +$4  .l  dead players of the player's team (18 bits)
## +$8  .l  dead players of the opponent, or a check value of the rest
## +$C  .w  seed (12 bits, never 0): the bracket and CPU results follow
## +$E  .b  the two teams' places in their conference: A * 10 + B
## +$F  .b  conference (0: teams 0-9, 1: teams 10-19)
## +$10 .b  best of 3
## +$11 .b  (to be named)
## +$12 .b  series state: game 1 / 2 / 3 and who leads
## +$13 .b  round: 3 first round, 0 division finals, 1 conference
##          championship, 2 Monster Cup
## +$14 .b  flags: NEW, SHOW_PASSWORD, CHAMPION, ELIMINATED, RANDOM_DEAD
## [/codeblock]

const NEW := 0x01
const SHOW_PASSWORD := 0x02
const CHAMPION := 0x04
const ELIMINATED := 0x08
const RANDOM_DEAD := 0x10
const FIRST_ROUND := 3
const CUP_FINAL := 2
## `$11FA6`: steps of the playoff stream after seeding.
const SEED_STEPS := 0x45
const CHECK_STEPS := 0x27
const ALPHABET := 0x66CD3          ## the password's 28 symbols
const PASSWORD_LEN := 13
## `$1204A`: which matches of the player's side are played out (bit 6 the
## first match ... bit 0 the final); the other side plays all.
const OWN_SIDE_MATCHES := 0x3A
## Codes `$12854` returns after a playoff game.
enum Result { NEXT_GAME = 0, CHAMPION = 1, WON_SERIES = 2, LOST_GAME = 3, ELIMINATED = 4 }

## `$11FC0` / `$1204A` (`$FFC770`): each side's eight teams, then the
## winners of its seven matches (four, two, one); side 0 is the player's
## conference with team A first and team B second.
var sides: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]

var rng := MlhRng.new()
var dead := PackedInt32Array([0, 0])
var seed := 0
var pair := 0
var conference := 0
var best_of_3 := 0
var flag_11 := 0
var series := 0
var round := 0
var flags := 0


## `$11D8E` (main menu Start): a fresh state; in the playoff modes (1, 2) a
## new run of [param setup]'s two teams from the first round with a new seed
## drawn from [param main_rng].
func start(setup: MwMatchSetup, main_rng: MlhRng) -> void:
	dead = PackedInt32Array([0, 0])
	seed = 0
	pair = 0
	conference = 0
	best_of_3 = 0
	flag_11 = 0
	series = 0
	round = 0
	flags = 0
	var mode := setup.play_mode
	if mode < 1 or mode > 2:
		return
	flags |= NEW
	if mode == 2:
		best_of_3 = 1
	round = FIRST_ROUND
	var a := setup.team_a
	var b := setup.team_b
	if a >= 10:
		a -= 10
		b -= 10
		conference = 1
	pair = (a * 10 + b) & 0xFF
	new_seed(main_rng)


## `$11F98`: a new non-zero 12-bit seed from the main stream, then reseed.
func new_seed(main_rng: MlhRng) -> void:
	var s := 0
	while s == 0:
		s = main_rng.next_state() & 0xFFF
	seed = s
	reseed()


## `$11FA6`: the playoff stream from the seed.
func reseed() -> void:
	rng.state = seed
	for i in SEED_STEPS:
		rng.next_state()


## The two teams of the run, from [member pair] and [member conference].
func teams() -> Vector2i:
	@warning_ignore("integer_division")
	var a := pair / 10
	return Vector2i(a + 10 * conference, pair % 10 + 10 * conference)


# --- bracket --------------------------------------------------------------------------------------
## `$11FC0` then `$1204A`: the bracket and its CPU results from the
## playoff stream (call [method reseed] first). [param rom] for the teams'
## strength (record +$B).
func build_bracket(rom: PackedByteArray, team_a: int, team_b: int) -> void:
	var lo := 0 if team_a <= 9 else 10
	var other := 10 if team_a <= 9 else -10
	var used := 1 << team_a
	var first := PackedInt32Array([team_a])
	var t := team_b
	while used >> t & 1:
		t = rng.range_value(lo, lo + 9)
	used |= 1 << t
	first.append(t)
	sides = [_draw(first, used, lo), _draw(PackedInt32Array(), 0, lo + other)]
	for side in 2:
		var lst := sides[side]
		var mask := OWN_SIDE_MATCHES if side == 0 else 0xFF
		for i in 7:
			var d3 := 6 - i
			var pick := 0
			if mask >> d3 & 1:
				pick = _match(rom, lst[2 * i], lst[2 * i + 1])
			if d3 == 6 and side == 0 and flag_11 != 0:
				pick = 1
			lst.append(lst[2 * i + pick])
		sides[side] = lst


## [param lst] filled to eight distinct teams of lo..lo+9 drawn from the stream.
func _draw(lst: PackedInt32Array, used: int, lo: int) -> PackedInt32Array:
	while lst.size() < 8:
		var t := rng.range_value(lo, lo + 9)
		if not used >> t & 1:
			used |= 1 << t
			lst.append(t)
	return lst


## `$120A2`: 0 when [param t1] wins, 1 when [param t2] does - t2 with odds
## 8(s2 + 1) in 8(s1 + 1) + 8(s2 + 1), s = the team's skulls.
func _match(rom: PackedByteArray, t1: int, t2: int) -> int:
	var w1 := (MwGfx.s8(rom, MwTeams.record(t1) + 0x0B) + 1) * 8
	var w2 := (MwGfx.s8(rom, MwTeams.record(t2) + 0x0B) + 1) * 8
	var r := rng.range_value(1, (w1 + w2) & 0xFFFF)
	return 1 if r <= (w2 & 0xFFFF) else 0


## `$11B4E` (`$1F1C0`): the teams of the current round's game - the first
## round's A and B, then the winners on A's path; the cup: A's side's
## champion against the other side's.
func game_teams() -> Vector2i:
	var own := sides[0]
	match round:
		FIRST_ROUND:
			return Vector2i(own[0], own[1])
		0:
			return Vector2i(own[8], own[9])
		1:
			return Vector2i(own[12], own[13])
	return Vector2i(own[14], sides[1][14])


# --- after a game -----------------------------------------------------------------------------------
## `$12854` (end of a playoff game): [param won] the player's team A won,
## [param forfeit] the game ended by forfeit (rink phase $D). Advances the
## series and the round; returns a [enum Result].
func game_over(won: bool, forfeit := false) -> Result:
	flags |= SHOW_PASSWORD
	if forfeit and not won:
		return _eliminated()
	if not forfeit and not won:
		if best_of_3 != 0:
			var lost_before := series & 1
			series |= 1
			if lost_before == 0:
				return Result.LOST_GAME
		return _eliminated()
	var code := Result.NEXT_GAME
	if not forfeit and best_of_3 != 0:
		var won_before := series & 2
		series |= 2
		if won_before == 0:
			return Result.NEXT_GAME
		if series & 1 == 0:
			code = Result.WON_SERIES
	series = 0
	round = (round + 1) & 3
	if round == FIRST_ROUND:
		flags &= ~SHOW_PASSWORD
		flags |= CHAMPION
		return Result.CHAMPION
	return code


func _eliminated() -> Result:
	flags &= ~SHOW_PASSWORD
	flags |= ELIMINATED
	return Result.ELIMINATED


## `$12A4E` (a playoff game starts; other play modes: none): the dead
## players of team A ([param team_a_side]) or team B. With RANDOM_DEAD
## team B's are drawn again on every call with [param main_rng]: n = 0-5,
## then n + 1 of its first 12 players (the 68000 loop runs once more than
## the count; repeats possible), none when n = 0.
func dead_for(team_a_side: bool, main_rng: MlhRng) -> int:
	var b := dead[1]
	if flags & RANDOM_DEAD:
		b = 0
		var n := main_rng.range_value(0, 5)
		if n > 0:
			for i in n + 1:
				b |= 1 << main_rng.range_value(0, 11)
	return dead[0] if team_a_side else b


# --- passwords --------------------------------------------------------------------------------------
## `$12580`: the password of the run after a game, [param dead_a] /
## [param dead_b] the teams' dead players (18 bits each). Mid-series of a
## best of 3 both are kept; otherwise the opponent's will be random and a
## check value takes their place. [param pads] is the setup's pad mode.
func make_password(rom: PackedByteArray, dead_a: int, dead_b: int, pads: int) -> PackedByteArray:
	if pads != 0 and pads != 2 and round == 0 and series == 0 and flag_11 != 0:
		var t := dead_a
		dead_a = dead_b
		dead_b = t
	dead[0] = dead_a
	if best_of_3 != 0 and series != 0:
		dead[1] = dead_b
		flags &= ~RANDOM_DEAD
	else:
		dead[1] = 0
		flags |= RANDOM_DEAD
	var d0 := ((((dead[1] << 2) | round) << 10) | (dead[0] >> 8)) & 0xFFFFFFFF
	var d1 := dead[0] & 0xFF
	for f in [[series, 2], [flag_11, 1], [best_of_3, 1], [conference, 1], [pair, 7], [seed, 12]]:
		d1 = ((d1 << int(f[1])) | int(f[0])) & 0xFFFFFFFF
	if flags & RANDOM_DEAD:
		dead[1] = check(d0, d1)
		d0 |= dead[1] << 12
	return _symbols(rom, d0, d1)


## `$1266C`: takes a password typed on the Continue Playoffs screen: the
## fields are taken from it (also when refused, like the original); false
## when the original refuses it. The stream is left as the check left it
## ([method reseed] follows).
func enter_password(rom: PackedByteArray, pw: PackedByteArray) -> bool:
	var n := _number(rom, pw)
	var d0 := (n >> 32) & 0xFFFFFFFF
	var d1 := n & 0xFFFFFFFF
	var c := check(d0, d1)
	var s := d1 & 0xFFF
	var p := (d1 >> 12) & 0x7F
	var conf := (d1 >> 19) & 1
	var bo3 := (d1 >> 20) & 1
	var f11 := (d1 >> 21) & 1
	var ser := (d1 >> 22) & 3
	var da := ((d0 & 0x3FF) << 8) | ((d1 >> 24) & 0xFF)
	var rnd := (d0 >> 10) & 3
	var db := (d0 >> 12) & 0x3FFFF
	var ok := (d0 >> 30) & 3 == 0 and s != 0
	if ok and bo3 == 0:
		ok = rnd != FIRST_ROUND and ser == 0 and db == c
	elif ok and ser == 0:
		ok = db == c
	@warning_ignore("integer_division")
	var a := p / 10
	ok = ok and p < 100 and a != p % 10
	seed = s
	pair = p
	conference = conf
	best_of_3 = bo3
	flag_11 = f11
	series = ser
	dead = PackedInt32Array([da, db])
	round = rnd
	return ok


## `$12776`: the check value of a password's other bits: the playoff
## stream seeded with (d0 & $FFF) ^ d1, 39 steps, the low 18 bits. (A zero
## seed would make the original seed from the hardware's counters.)
func check(d0: int, d1: int) -> int:
	var s := ((d0 & 0xFFF) ^ d1) & 0xFFFFFFFF
	if s == 0:
		s = (randi() & 0xFFFFFFFF) | 1
		rng.state = s
		rng.warm_up()
	else:
		rng.state = s
	for i in CHECK_STEPS:
		rng.next_state()
	return rng.state & 0x3FFFF


## `$12804`: 13 base-28 digits of d0:d1, least significant first.
static func _symbols(rom: PackedByteArray, d0: int, d1: int) -> PackedByteArray:
	var n := (d0 << 32) | d1
	var out := PackedByteArray()
	for i in PASSWORD_LEN:
		out.append(rom[ALPHABET + n % 28])
		@warning_ignore("integer_division")
		n = n / 28
	return out


## `$12820`: the number a password spells (a symbol not in the alphabet
## counts $FFFF), modulo 2^64.
static func _number(rom: PackedByteArray, pw: PackedByteArray) -> int:
	var n := 0
	for k in range(PASSWORD_LEN - 1, -1, -1):
		var i := 0xFFFF
		var c := pw[k] if k < pw.size() else 0
		for j in 28:
			if rom[ALPHABET + j] == c:
				i = j
				break
		n = n * 28 + i
	return n
