class_name MwCustomCoach
extends RefCounted
## A custom team's coach (plan 38): what the original keeps in the coach
## record (its name) and in the coach table `$1CD26` (face, quote set), with
## the port's own colours, voice and speeches. [MwCustomOverlay] gives him a
## coach record, an entry in the table's layout, portrait data and quote
## sets of his own.

## Voices a coach can have (sound ids): the ROM's coach voices `$0B` (DPCM),
## `$0C`, `$0F` (pitched-sample sequences), `$32` (an effect), the players'
## `$31`, `$39` (PCM), and `$0D`, `$0E` (coach-voice sequences no portrait
## uses; kept after hearing them - owner, 2026-10-10). -1 in
## [member voice]: the face's own.
const VOICES := [0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x31, 0x32, 0x39]
const NAME_MAX := 18
## The colours of his face's palette line he may have of his own: shirt
## 2-3, pants 5-6, skin 7-8, shade 9 (docs/re/menus.md, Portraits).
const COLOUR_INDICES := [2, 3, 5, 6, 7, 8, 9]

var name := "COACH NEW"
## An index into [method MwCustomTeams.coach_faces] (0-6).
var face := 0
## Seven colour words for COLOUR_INDICES, or empty: his team's (the original).
var colours := PackedInt32Array()
## A sound id from VOICES, or -1: his face's.
var voice := -1
## His base lines: the quote set 0-7 (quote categories 0-7 and 9) - the
## original coach he was copied from; what he says where he has no
## [member speeches] of his own.
var style := 0
## His own speeches in the rink (owner, 2026-10-14: CREATE-A-TEAM's
## SPEECHES edits them): [method MwCoachSpeeches.key] -> PackedStringArray,
## the lines of a situation (tokens for the team names,
## [constant MwCoachSpeeches.TOKENS]). A situation without: [member style]'s.
var speeches := {}


## Everything into range: the name cut to [constant NAME_MAX] and the charset
## ("COACH" if empty), the face 0-6, seven colour words (masked to the
## Genesis' bits) or none, a voice of [constant VOICES] or -1, the quote set
## 0-7, his speeches ([method MwCoachSpeeches.validate]).
func validate() -> void:
	name = MwCustomTeam.clean_text(name, NAME_MAX)
	if name == "":
		name = "COACH"
	face = clampi(face, 0, 6)
	if colours.size() != COLOUR_INDICES.size():
		colours = PackedInt32Array()
	for i in colours.size():
		colours[i] &= 0x0EEE
	if voice != -1 and not voice in VOICES:
		voice = -1
	style = clampi(style, 0, 7)
	speeches = MwCoachSpeeches.validate(speeches)


## A copy of the original team [param team]'s coach.
static func from_team(rom: PackedByteArray, team: int) -> MwCustomCoach:
	var coach := MwCustomCoach.new()
	var rec := MwTeams.coach(rom, team)
	coach.name = MwGfx.rom_string(rom, MwGfx.u32(rom, rec)).get_string_from_ascii()
	var face_data := MwPortrait.coach_face(rom, rec)
	coach.face = maxi(0, MwCustomTeams.coach_faces(rom).find(face_data[0]))
	coach.style = face_data[1]
	coach.validate()
	return coach


## The coach in the custom teams' JSON: name, face, quote set, voice (hex; null:
## the face's), colours (null: his team's) and, when he has some, his own
## speeches ({"category.situation": [lines]}; a file without them is as before).
func to_dict() -> Dictionary:
	var d := {
		"name": name, "face": face, "style": style,
		"voice": null if voice < 0 else "%02X" % voice,
		"colours": null if colours.is_empty() else MwCustomTeam.words_out(colours),
	}
	if not speeches.is_empty():
		var out := {}
		for k: String in speeches:
			out[k] = Array(speeches[k])
		d["speeches"] = out
	return d


## A coach read from the custom teams' JSON [param d] ([method to_dict]'s form)
## through [MwPlain]'s readers, then validated.
static func from_dict(d: Dictionary) -> MwCustomCoach:
	var coach := MwCustomCoach.new()
	coach.name = MwPlain.text(d.get("name"), coach.name)
	coach.face = MwPlain.num(d.get("face"), 0)
	coach.style = MwPlain.num(d.get("style"), 0)
	var v: Variant = d.get("voice")
	coach.voice = MwPlain.hex(MwPlain.text(v)) if v is String or v is int or v is float else -1
	var cs: Variant = d.get("colours")
	if cs is Array:
		coach.colours = MwCustomTeam.words_in(cs)
	var sp := MwPlain.dict(d.get("speeches"))
	for k: Variant in sp:
		if coach.speeches.size() >= MwCoachSpeeches.SITUATIONS.size() * MwCoachSpeeches.LINES_MAX:
			break                                  # (a bound on what a file or the network can make us read)
		var lines := PackedStringArray()
		for l: Variant in MwPlain.array(sp[k]).slice(0, MwCoachSpeeches.LINES_READ):
			lines.append(MwPlain.text(l))
		coach.speeches[str(k)] = lines
	coach.validate()
	return coach
