class_name MwCaptainVote
extends RefCounted
## A team's captain vote (plan 34 section 7; owner: once everyone has picked
## a character, the team votes for its captain among the picked characters):
## each of the team's players casts a ballot for one of the candidates - on
## character selection (111) the players whose characters are picked, on the
## vote's own screen (112) the team's players. The most votes win; a tie
## votes again among the tied, once; a second tie is drawn from a port
## random stream seeded from the session ([method stream]: never the
## original's streams, so the match's random numbers are the same whoever is
## captain). Node-free.

## The team (0 A, 1 B), its voters (player numbers) and the candidates.
var team := 0
var voters: Array[int] = []
var candidates: Array[int] = []
## voter -> the candidate they voted for.
var ballots := {}
## 1, or 2 for the tied's second vote.
@warning_ignore("shadowed_global_identifier")   # a frozen name (docs/style.md N9): read by name elsewhere
var round := 1
## The captain (0 until decided) and whether a draw decided it.
var winner := 0
var drawn := false


func _init(team_: int, voters_: Array, candidates_: Array) -> void:
	team = team_
	voters.assign(voters_)
	candidates.assign(candidates_)
	candidates.sort()


## [param voter]'s ballot for [param candidate]; false when either isn't
## in this vote, or it is over.
func vote(voter: int, candidate: int) -> bool:
	if winner != 0 or not voter in voters or not candidate in candidates:
		return false
	ballots[voter] = candidate
	return true


## Takes [param voter]'s ballot back (before the count).
func unvote(voter: int) -> void:
	if winner == 0:
		ballots.erase(voter)


## True when every voter has cast a ballot.
func all_voted() -> bool:
	for v in voters:
		if not ballots.has(v):
			return false
	return true


## The votes for each candidate.
func tally() -> Dictionary:
	var out := {}
	for c in candidates:
		out[c] = 0
	for v in ballots:
		out[ballots[v]] = int(out[ballots[v]]) + 1
	return out


## Counts the ballots: the captain (the most votes), or 0 when the first
## round ties - the tied then vote again ([member candidates] narrowed,
## the ballots cleared); a second tie is drawn with [param rng].
func count(rng: MlhRng) -> int:
	var t := tally()
	var best := 0
	for c in candidates:
		best = maxi(best, int(t[c]))
	var tops: Array[int] = []
	for c in candidates:
		if int(t[c]) == best:
			tops.append(c)
	if tops.size() == 1:
		winner = tops[0]
	elif round == 1:
		round = 2
		candidates = tops
		ballots.clear()
	else:
		winner = tops[rng.range_value(0, tops.size() - 1)]
		drawn = true
	return winner


## The port's random stream for the votes' draws: the session's port stream
## [constant MwSession.STREAM_CAPTAINS] (plan 35: derived from the session
## seed, in the start record, so every machine draws the same captain) -
## never one of the original's streams.
static func stream(session: MwSession) -> MlhRng:
	return session.port_stream(MwSession.STREAM_CAPTAINS)
