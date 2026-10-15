extends RefCounted
## Plan 45 (M1): a script the player-config tests name in crafted [code].cfg[/code] files
## ([code]Object(RefCounted, "script": Resource(...))[/code]): the engine's parser would load
## it and make one while reading the file; [member made] counts how many were made.

## How many have been made (the tests set it to 0 first).
static var made := 0


func _init() -> void:
	made += 1
