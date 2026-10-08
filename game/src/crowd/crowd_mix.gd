class_name MwCrowdMix
extends RefCounted
## Whose fans the 3D crowd are (plan 16 amendment, owner; docs/rink3d.md,
## Crowd colours). The crowd draws with line 1 of the rink's palette, whose
## colours 2-3 and 5-9 are team A's (`$215E`): in the original every fan
## wears team A's colours. In 3D each seat supports a team and wears line 1
## as the game builds it with that team as team A (MwStands3D):
##
## * the home team (the stadium's: stadium s is team s's) fills 30-40% of
##   the seats, each away team (the playing teams not at home: one in a home
##   game, both at a third team's stadium) 10-15%, in groups of neighbouring
##   seats spread over the stands;
## * those shares are scaled by the team's ability, its skulls (team record
##   +$B, 0-6): x0.8 with none to x1.2 with six; a team with no skulls (the
##   Mighty Weenies) has no away fans;
## * every other seat supports a random team, neither playing nor at home.
##
## Fixed per matchup: drawn from its own random numbers, seeded by the
## teams and the stadium (never the game's). Presentation only.

const TEAMS := 23                       # the team records (MwTeams.COUNT)
const HOME_SHARE := Vector2(0.30, 0.40) # of the seats (owner)
const AWAY_SHARE := Vector2(0.10, 0.15) # each away team's
const ABILITY_MARGIN := 0.20            # the shares x (1 -/+ this) by skulls (owner)
const MAX_SKULLS := 6
const GROUP_SIZE := Vector2i(6, 18)     # fans per group
const GROUP_REACH := 64.0               # px: a group's seats are looked for this near its first seat ...
const GROUP_ROUGH := 12.0               # ... with this much noise on the distances (ragged edges)


## Every team's skulls (team record +$B; the playoffs' and the AI's
## strength, 0-6).
static func skulls(rom: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	for t in TEAMS:
		out.append(rom[MwTeams.record(t) + 0x0B])
	return out


## A team's share factor by its [param skull_count]: 0.8 (none) .. 1.2 (six).
static func ability(skull_count: int) -> float:
	var s := clampf(skull_count, 0, MAX_SKULLS) / MAX_SKULLS
	return 1.0 - ABILITY_MARGIN + 2.0 * ABILITY_MARGIN * s


## The random numbers of a matchup: the same teams at the same stadium,
## the same crowd.
static func rng_for(team_a: int, team_b: int, stadium: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x4D4C48 + ((team_a * TEAMS + team_b) * TEAMS + stadium) * 2654435761
	return rng


## The home and away teams' shares of the seats, {team: share}, the home
## team first. [param skull_counts]: every team's ([method skulls]).
static func shares(team_a: int, team_b: int, stadium: int, skull_counts: PackedInt32Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	out[stadium] = rng.randf_range(HOME_SHARE.x, HOME_SHARE.y) * ability(skull_counts[stadium])
	for t: int in [team_a, team_b]:
		if out.has(t):
			continue
		var share := rng.randf_range(AWAY_SHARE.x, AWAY_SHARE.y) * ability(skull_counts[t])
		out[t] = share if skull_counts[t] > 0 else 0.0
	return out


## The team each of [param seats] (MwStands.seats, in that order) supports.
static func assign(seats: Array, team_a: int, team_b: int, stadium: int,
		skull_counts: PackedInt32Array) -> PackedInt32Array:
	var rng := rng_for(team_a, team_b, stadium)
	var n := seats.size()
	var teams := PackedInt32Array()
	teams.resize(n)
	teams.fill(-1)
	if n == 0:
		return teams
	var share := shares(team_a, team_b, stadium, skull_counts, rng)
	# the home and away fans' groups, in a random order
	var groups: Array = []
	for t: int in share:
		var left := roundi(share[t] * n)
		while left > 0:
			var size := mini(rng.randi_range(GROUP_SIZE.x, GROUP_SIZE.y), left)
			groups.append([t, size])
			left -= size
	_shuffle(groups, rng)
	var pos := PackedVector3Array()
	for s: Dictionary in seats:
		pos.append(s["pos"])
	var free := n
	for g: Array in groups:
		if free == 0:
			break
		var near := _group(pos, teams, _random_free(teams, rng), mini(g[1], free), rng)
		for i in near:
			teams[i] = g[0]
		free -= near.size()
	# the rest: anyone else's
	var others := PackedInt32Array()
	for t in TEAMS:
		if not share.has(t):
			others.append(t)
	for i in n:
		if teams[i] < 0:
			teams[i] = others[rng.randi_range(0, others.size() - 1)]
	return teams


## The fans of each team in [param teams] ([method assign]): {team: count}.
static func counts(teams: PackedInt32Array) -> Dictionary:
	var out := {}
	for t in teams:
		out[t] = out.get(t, 0) + 1
	return out


## A free seat at random (the next free one after a taken one).
static func _random_free(teams: PackedInt32Array, rng: RandomNumberGenerator) -> int:
	var i := rng.randi_range(0, teams.size() - 1)
	while teams[i] >= 0:
		i = (i + 1) % teams.size()
	return i


## The [param want] free seats nearest seat [param first] (with rough
## edges): one group.
static func _group(pos: PackedVector3Array, teams: PackedInt32Array, first: int, want: int,
		rng: RandomNumberGenerator) -> PackedInt32Array:
	var reach := GROUP_REACH
	var near: Array = []
	while true:
		near.clear()
		for i in pos.size():
			if teams[i] < 0:
				var d := pos[i].distance_to(pos[first])
				if d <= reach:
					near.append(Vector2(d + rng.randf() * GROUP_ROUGH, i))
		if near.size() >= want or reach > 8192.0:
			break
		reach *= 2.0
	near.sort()
	var out := PackedInt32Array()
	for k in mini(want, near.size()):
		out.append(int(near[k].y))
	return out


## Shuffles [param a] with [param rng] (Array.shuffle uses the global one).
static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t
