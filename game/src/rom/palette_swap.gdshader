// Palette swap for ROM graphics (docs/architecture.md, Rendering).
// The texture's red channel holds line * 16 + colour index as a byte (R8);
// the colour comes from a 64x1 palette texture built from ROM palette words
// (MwPalettes.texture). Colour 0 of each line has alpha 0 there, so it is
// transparent. Modulate still applies (fades, translucency).
//
// shadow_highlight: the rink's sprite operators (the VDP's shadow/highlight
// mode, docs/re/rink.md) as true translucency - colour 15 of line 3 is a
// half-transparent black (the VDP halves what is below), colour 14 a
// half-transparent white (half the brightness plus half the maximum).
//
// screen_tint: the modulate tints as a screen blend instead of multiplying -
// black takes the tint's colour, white stays white (dark text coloured on a
// light bar: the port menu's red ABACABB MODE label while it is selected).
shader_type canvas_item;

uniform sampler2D palette : filter_nearest, repeat_disable;
uniform bool shadow_highlight = false;
uniform bool screen_tint = false;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	int i = int(round(texture(TEXTURE, UV).r * 255.0));
	if (shadow_highlight && i == 63) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.5) * tint;
	} else if (shadow_highlight && i == 62) {
		COLOR = vec4(1.0, 1.0, 1.0, 0.5) * tint;
	} else if (screen_tint) {
		vec4 c = texelFetch(palette, ivec2(i, 0), 0);
		COLOR = vec4(1.0 - (1.0 - c.rgb) * (1.0 - tint.rgb), c.a * tint.a);
	} else {
		COLOR = texelFetch(palette, ivec2(i, 0), 0) * tint;
	}
}
