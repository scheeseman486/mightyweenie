extends "res://test/rom/rom_test_base.gd"
## Whose fans the 3D crowd are (plan 16 amendment, MwCrowdMix): the home
## team's and the away teams' shares by their ability, in groups; the rest
## anyone else's; fixed per matchup; worn in 3D (MwStands3D).

const WEENIES := 5               # no skulls
const ACES := 22                 # six
const STEPS := ["screen_palette", "rom 1BD8A 3"]   # the rink's palette

var seats: Array = []
var skulls := PackedInt32Array()


func before_all() -> void:
	super.before_all()
	seats = MwStands.seats(MwCrowd.load_data())
	if not rom.is_empty():
		skulls = MwCrowdMix.skulls(rom)


func _share(teams: PackedInt32Array, t: int) -> float:
	return float(MwCrowdMix.counts(teams).get(t, 0)) / teams.size()


## Whether [param share] is within [param range] x the ability of
## [param skull_count] (one seat of rounding).
func _assert_share(share: float, range: Vector2, skull_count: int, what: String) -> void:
	var f := MwCrowdMix.ability(skull_count)
	var slack := 1.0 / seats.size()
	assert_between(share, range.x * f - slack, range.y * f + slack, what)


func test_ability_margin() -> void:
	assert_almost_eq(MwCrowdMix.ability(0), 0.8, 1e-6, "no skulls: 20% fewer fans")
	assert_almost_eq(MwCrowdMix.ability(3), 1.0, 1e-6)
	assert_almost_eq(MwCrowdMix.ability(6), 1.2, 1e-6, "six: 20% more")
	assert_almost_eq(MwCrowdMix.ability(9), 1.2, 1e-6, "clamped")


func test_skulls_from_the_rom() -> void:
	if not need_rom():
		return
	assert_eq(skulls.size(), 23)
	assert_eq(skulls[WEENIES], 0, "the Mighty Weenies")
	assert_eq(skulls[ACES], 6, "the Galaxy Aces")
	for s in skulls:
		assert_between(s, 0, 6)


func test_home_and_away_shares() -> void:
	if not need_rom():
		return
	for m: Array in [[0, 7, 0], [7, 0, 0], [12, 20, 20], [14, 16, 14], [WEENIES, ACES, ACES], [ACES, WEENIES, WEENIES]]:
		var teams := MwCrowdMix.assign(seats, m[0], m[1], m[2], skulls)
		var away: int = m[1] if m[0] == m[2] else m[0]
		_assert_share(_share(teams, m[2]), MwCrowdMix.HOME_SHARE, skulls[m[2]], "home %s" % [m])
		if skulls[away] > 0:
			_assert_share(_share(teams, away), MwCrowdMix.AWAY_SHARE, skulls[away], "away %s" % [m])


func test_the_weenies() -> void:
	if not need_rom():
		return
	var at_home := MwCrowdMix.assign(seats, WEENIES, 0, WEENIES, skulls)
	_assert_share(_share(at_home, WEENIES), MwCrowdMix.HOME_SHARE, 0, "at home: 20% fewer")
	assert_lt(_share(at_home, WEENIES), 0.32 + 1.0 / seats.size())
	assert_eq(_share(MwCrowdMix.assign(seats, 0, WEENIES, 0, skulls), WEENIES), 0.0, "away: none")
	assert_eq(_share(MwCrowdMix.assign(seats, WEENIES, 0, 7, skulls), WEENIES), 0.0, "at a third stadium: none")


func test_a_third_teams_stadium() -> void:
	if not need_rom():
		return
	var teams := MwCrowdMix.assign(seats, 1, 2, 7, skulls)
	_assert_share(_share(teams, 7), MwCrowdMix.HOME_SHARE, skulls[7], "the stadium's own fans")
	_assert_share(_share(teams, 1), MwCrowdMix.AWAY_SHARE, skulls[1], "team A away")
	_assert_share(_share(teams, 2), MwCrowdMix.AWAY_SHARE, skulls[2], "team B away")


## The share of [param team]'s fans' neighbours (seats within a seat along
## the row or a row up or down) who support them too.
func _together(teams: PackedInt32Array, team: int) -> float:
	var cells := {}
	for i in seats.size():
		var p: Vector3 = seats[i]["pos"]
		var c := Vector2i(floori(p.x / 32.0), floori(p.y / 32.0))
		if not cells.has(c):
			cells[c] = []
		cells[c].append(i)
	var same := 0
	var all := 0
	for i in seats.size():
		if teams[i] != team:
			continue
		var p: Vector3 = seats[i]["pos"]
		var c := Vector2i(floori(p.x / 32.0), floori(p.y / 32.0))
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for j: int in cells.get(c + Vector2i(dx, dy), []):
					if j != i and p.distance_to(seats[j]["pos"]) < 26.0:
						all += 1
						same += int(teams[j] == team)
	return float(same) / maxi(all, 1)


func test_in_groups_spread_over_the_stands() -> void:
	if not need_rom():
		return
	var teams := MwCrowdMix.assign(seats, 0, 7, 0, skulls)
	var home := _share(teams, 0)
	assert_gt(_together(teams, 0), 0.6, "home fans sit together (%.2f of the seats theirs)" % home)
	assert_gt(_together(teams, 7), 0.45, "so do the away fans")
	var where := {}
	for i in seats.size():
		if teams[i] == 0:
			where[[seats[i]["region"], seats[i]["pos"].x < 0.0]] = true
	assert_eq(where.size(), 8, "home groups in every part of the stands, both halves")


func test_the_rest_is_anyone_elses() -> void:
	if not need_rom():
		return
	var teams := MwCrowdMix.assign(seats, 3, 9, 3, skulls)
	var others := {}
	for t in teams:
		assert_between(t, 0, 22)
		if t != 3 and t != 9:
			others[t] = true
	assert_eq(others.size(), 21, "every other team has some fans")
	assert_lt(_together(teams, 15), 0.3, "scattered, not grouped")


func test_same_matchup_same_crowd() -> void:
	if not need_rom():
		return
	var a := MwCrowdMix.assign(seats, 4, 11, 4, skulls)
	assert_eq(MwCrowdMix.assign(seats, 4, 11, 4, skulls), a, "fixed per matchup")
	assert_ne(MwCrowdMix.assign(seats, 4, 11, 11, skulls), a, "another stadium, another crowd")


func test_the_stands_wear_their_teams() -> void:
	if not need_rom():
		return
	var stands := MwStands3D.new()
	add_child_autofree(stands)
	var p := RomPalette.make(4, PackedStringArray(STEPS), 0, 0)
	p.team_b = 7
	stands.palette = p
	assert_eq(stands.fan_teams.size(), stands.seats.size(), "a team per seat")
	assert_eq(stands.fan_teams, MwCrowdMix.assign(stands.seats, 0, 7, 0, skulls))
	for t in [0, WEENIES, ACES]:
		var line := RomPalette.make(4, PackedStringArray(STEPS), t, 0)
		for i in range(1, 16):
			assert_eq(stands.team_lines.get_pixel(i, t).to_rgba32(), line.rgba(16 + i).to_rgba32(),
					"team %d colour %d" % [t, i])
	p.stadium = 7
	stands.refresh()
	assert_eq(stands.fan_teams, MwCrowdMix.assign(stands.seats, 0, 7, 7, skulls), "follows the palette")
	stands.variety = false
	assert_true(stands.fan_teams.is_empty(), "off: everyone in team A's colours")
