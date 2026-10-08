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
