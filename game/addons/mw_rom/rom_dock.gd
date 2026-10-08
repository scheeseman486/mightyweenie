@tool
extends VBoxContainer
## ROM browser: the asset catalogue (res://data/rom_catalogue.json) by kind,
## each entry decoded live from the ROM for the preview, with its parameters
## and a button that adds a ROM-backed node for it to the open scene.

var plugin: EditorPlugin

const KINDS := ["picture", "tilebank", "map", "palette", "anim", "font", "frames", "pieces"]

var _status := Label.new()
var _screen := SpinBox.new()
var _tree := Tree.new()
var _preview := TextureRect.new()
var _info := Label.new()
var _add := Button.new()
var _selected := {}


func _ready() -> void:
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "Screen"
	row.add_child(l)
	_screen.min_value = -1
	_screen.max_value = 19
	_screen.value = -1
	_screen.tooltip_text = "Only entries used on this screen (-1: all)"
	_screen.value_changed.connect(func(_v): _fill())
	row.add_child(_screen)
	var reload := Button.new()
	reload.text = "Reload"
	reload.pressed.connect(_reload)
	row.add_child(reload)
	add_child(row)
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 200)
	_tree.item_selected.connect(_on_selected)
	add_child(_tree)
	_preview.custom_minimum_size = Vector2(0, 220)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_preview)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	_add.text = "Add to scene"
	_add.disabled = true
	_add.pressed.connect(_add_to_scene)
	add_child(_add)
	_reload()


func _reload() -> void:
	MwRom.use(null)
	if not MwRom.available():
		_status.text = "No ROM: run tools/bin/setup-rom (game/rom/mlh.gen)."
	else:
		_status.text = "ROM %s, catalogue %d entries" % [MwRom.archive().sha1.left(8), MwRom.catalogue().get("entries", {}).size()]
	_fill()


func _fill() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var cat := MwRom.catalogue()
	var screen := int(_screen.value)
	for kind in KINDS:
		var parent := _tree.create_item(root)
		parent.set_text(0, kind)
		parent.set_selectable(0, false)
		var n := 0
		if kind == "frames":
			for group in cat.get("frames", {}):
				if screen < 0 or str(screen) in group.split(","):
					_leaf(parent, "screens %s (%d)" % [group, cat["frames"][group].size()], {"kind": "frames", "group": group})
					n += 1
		elif kind == "pieces":
			for caller in cat.get("pieces", {}):
				var g: Dictionary = cat["pieces"][caller]
				if screen < 0 or MwRom.has_screen(g, screen):
					_leaf(parent, "drawn by $%s (%d)" % [caller.to_upper(), g["pieces"].size()], {"kind": "pieces", "caller": caller})
					n += 1
		else:
			for key in MwRom.keys(kind, screen):
				_leaf(parent, key, {"kind": kind, "key": key})
				n += 1
		parent.set_text(0, "%s (%d)" % [kind, n])
		parent.collapsed = n > 12


func _leaf(parent: TreeItem, text: String, meta: Dictionary) -> void:
	var it := _tree.create_item(parent)
	it.set_text(0, text)
	it.set_metadata(0, meta)


func _first_screen(e: Dictionary) -> int:
	var s := int(_screen.value)
	if s >= 0:
		return s
	var screens: Array = e.get("screens", [0])
	return int(screens[0]) if not screens.is_empty() else 0


func _on_selected() -> void:
	var meta = _tree.get_selected().get_metadata(0)
	if meta == null or not MwRom.available():
		return
	_selected = meta
	var rom := MwRom.data()
	var cat := MwRom.catalogue()
	var img: Image
	var info := ""
	match meta["kind"]:
		"frames":
			var frames: Array = cat["frames"][meta["group"]]
			var screen := int(meta["group"].split(",")[0])
			img = _frames_image(rom, frames.map(func(f): return MwGfx.frame_pieces(rom, int(f))), MwScreenPalettes.palette(screen))
			info = "%d frames drawn outside animations on screens %s" % [frames.size(), meta["group"]]
		"pieces":
			var g: Dictionary = cat["pieces"][meta["caller"]]
			img = _frames_image(rom, g["pieces"].map(func(p): return [MwGfx.piece(rom, int(p))]), MwScreenPalettes.palette(int(g["screens"][0])))
			info = "%d single pieces drawn by $%s on screens %s" % [g["pieces"].size(), meta["caller"].to_upper(), g["screens"]]
		_:
			var e := MwRom.entry(meta["key"])
			var screen := _first_screen(e)
			var pal := MwScreenPalettes.palette(screen, meta["key"])
			info = _describe(e)
			match e["kind"]:
				"picture":
					var p := MwGfx.picture_image(rom, MwGfx.picture(rom, int(e["address"])))
					img = _rgba(p["w"], p["h"], p["px"], pal)
				"tilebank":
					img = _bank_image(rom, e, pal)
				"map":
					img = _map_image(rom, e, screen, pal)
				"palette":
					img = _swatches(MwGfx.words(rom, int(e["address"]), 16))
				"anim":
					var an := MwGfx.animation(rom, int(e["address"]))
					var frames := []
					for o in MwGfx.anim_offsets(rom, an, 0):
						frames.append(MwGfx.flip_pieces(MwGfx.frame_pieces(rom, an["frames"] + o), an["variants"][0][1]))
					img = _frames_image(rom, frames, pal)
					info += "\n%d variants, %.1f frames/s" % [an["variants"].size(), MwGfx.anim_fps(an)]
				"font":
					var glyphs := []
					for g in MwGfx.font_glyphs(rom, int(e["address"])):
						glyphs.append([MwGfx.piece(rom, g)])
					img = _frames_image(rom, glyphs, pal)
					info += "\nchars: " + "".join(MwGfx.font_char_map(rom, int(e["address"])).keys())
	_preview.texture = ImageTexture.create_from_image(img) if img else null
	_info.text = info
	_add.disabled = meta["kind"] in ["palette", "font", "pieces"]


func _describe(e: Dictionary) -> String:
	var parts := []
	for k in e:
		if k in ["kind", "placements", "uses", "strings"]:
			continue
		var v = e[k]
		if v is float and k in ["address", "tiles", "map", "frame_data"]:
			parts.append("%s $%X" % [k, int(v)])
		elif v is float:
			parts.append("%s %d" % [k, int(v)])
		else:
			parts.append("%s %s" % [k, str(v)])
	for k in ["placements", "uses", "strings"]:
		if e.has(k):
			parts.append("%d %s" % [e[k].size(), k])
	return ", ".join(parts)


func _rgba(w: int, h: int, px: PackedByteArray, pal: RomPalette) -> Image:
	var img := Image.create_empty(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	img.fill(pal.backdrop())
	for y in h:
		for x in w:
			var v := px[y * w + x]
			if v % 16:
				img.set_pixel(x, y, pal.rgba(v))
	return img


func _bank_image(rom: PackedByteArray, e: Dictionary, pal: RomPalette) -> Image:
	var count := int(e["count"])
	var cols := 32
	var rows := ceili(count / float(cols))
	var px := PackedByteArray()
	px.resize(cols * 8 * rows * 8)
	for i in count:
		MwGfx.blit_tile(px, cols * 8, (i % cols) * 8, (i / cols) * 8, MwGfx.tile_indices(rom, int(e["tiles"]) + 32 * i), 0, false, false)
	return _rgba(cols * 8, rows * 8, px, pal)


func _map_image(rom: PackedByteArray, e: Dictionary, screen: int, pal: RomPalette) -> Image:
	var ts := RomTileSet.new()
	ts.banks = MwScreenPalettes.banks(screen)
	var vram := ts.vram_tiles()
	var cols := int(e["cols"])
	var rows := int(e["rows"])
	var px := PackedByteArray()
	px.resize(cols * 8 * rows * 8)
	for y in rows:
		for x in cols:
			var w := MwGfx.u16(rom, int(e["address"]) + y * int(e["src_stride"]) + 2 * x)
			if vram.has(w & 0x7FF):
				MwGfx.blit_tile(px, cols * 8, x * 8, y * 8, MwGfx.tile_indices(rom, vram[w & 0x7FF]), (w >> 13) & 3, (w & 0x800) != 0, (w & 0x1000) != 0)
	return _rgba(cols * 8, rows * 8, px, pal)


func _swatches(colours: PackedInt32Array) -> Image:
	var img := Image.create_empty(16 * 8, 8, false, Image.FORMAT_RGBA8)
	for i in colours.size():
		img.fill_rect(Rect2i(i * 8, 0, 8, 8), MwGfx.color(colours[i]))
	return img


## Frames side by side on one strip (up to 24).
func _frames_image(rom: PackedByteArray, frames: Array, pal: RomPalette) -> Image:
	var shown := frames.slice(0, 24)
	var images := []
	var w := 0
	var h := 0
	for f in shown:
		var fi := MwGfx.frame_image(rom, f)
		images.append(fi)
		w += fi["w"] + 4
		h = maxi(h, fi["h"])
	var strip := Image.create_empty(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.15, 0.15, 0.2))
	var x := 0
	for fi in images:
		if fi["w"] > 0:
			strip.blend_rect(_rgba_clear(fi, pal), Rect2i(0, 0, fi["w"], fi["h"]), Vector2i(x, h - fi["h"]))
		x += fi["w"] + 4
	return strip


func _rgba_clear(fi: Dictionary, pal: RomPalette) -> Image:
	var img := Image.create_empty(fi["w"], fi["h"], false, Image.FORMAT_RGBA8)
	for y in fi["h"]:
		for x in fi["w"]:
			var v: int = fi["px"][y * fi["w"] + x]
			if v % 16:
				img.set_pixel(x, y, pal.rgba(v))
	return img


func _add_to_scene() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or _selected.is_empty():
		return
	var node: Node
	var meta := _selected
	match meta["kind"]:
		"picture", "tilebank", "map":
			var e := MwRom.entry(meta["key"])
			var screen := _first_screen(e)
			var layer := RomTileMapLayer.new()
			var ts := RomTileSet.new()
			ts.banks = MwScreenPalettes.banks(screen, meta["key"] if e["kind"] != "map" else "")
			layer.tiles = ts
			layer.palette = MwScreenPalettes.palette(screen, meta["key"])
			layer.map = meta["key"] if e["kind"] != "tilebank" else ""
			node = layer
		"anim":
			var e := MwRom.entry(meta["key"])
			var sprite := RomSprite.new()
			sprite.palette = MwScreenPalettes.palette(_first_screen(e))
			sprite.anim = meta["key"]
			node = sprite
		"frames":
			var sprite := RomSprite.new()
			var addrs: Array = MwRom.catalogue()["frames"][meta["group"]]
			sprite.palette = MwScreenPalettes.palette(int(meta["group"].split(",")[0]))
			sprite.frame_addresses = PackedInt32Array(addrs.map(func(a): return int(a)))
			node = sprite
	if node == null:
		return
	node.name = (meta.get("key", meta["kind"])).to_pascal_case()
	var ur := plugin.get_undo_redo()
	ur.create_action("Add ROM node")
	ur.add_do_method(root, "add_child", node, true)
	ur.add_do_method(node, "set_owner", root)
	ur.add_do_reference(node)
	ur.add_undo_method(root, "remove_child", node)
	ur.commit_action()
