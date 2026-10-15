// Shared by the 3D rink's shaders (plan 14, docs/rink3d.md).
// ROM graphics as indexed textures: R8 = palette line * 16 + colour index, as
// palette_swap.gdshader; colours from the 64x1 palette texture of a RomPalette
// (sRGB, hence source_color). Nearest pixels only.

uniform sampler2D palette : source_color, filter_nearest, repeat_disable;

// The colour index at UV of an indexed texture.
int indexed_at(sampler2D tex, vec2 uv) {
	ivec2 size = textureSize(tex, 0);
	ivec2 p = clamp(ivec2(floor(uv * vec2(size))), ivec2(0), size - 1);
	return int(round(texelFetch(tex, p, 0).r * 255.0));
}

vec3 colour_of(int i) {
	return texelFetch(palette, ivec2(i, 0), 0).rgb;
}

// The palette's colour c (linear) darker by n of each channel's 8 levels, as
// RomPalette.darker does it to a colour word (the Genesis's levels: x * 255 /
// 7 in sRGB; none below 0). Plan 37: the oil in flight (owner: a shade
// darker).
vec3 darker_by(vec3 c, float n) {
	if (n <= 0.0) {
		return c;
	}
	vec3 s = mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
	vec3 level = max(round(s * 7.0) - n, vec3(0.0));      // floor(x * 255 / 7) / 255 * 7: just under x
	vec3 o = floor(level * 255.0 / 7.0) / 255.0;
	return mix(o / 12.92, pow((o + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), o));
}

// The rink's geometry (plan 40): the boards, their signed distance.
#include "res://src/rink3d/rink3d_geom.gdshaderinc"
