// Paint on the 3D arena (plan 37, docs/rink3d.md, Splatter): blood and oil
// kept all match in an R8 atlas (MwSplatterAtlas: bits 0-1 the paint, 0
// clear, 1 blood, 2 oil; bits 2-3 the ice's detail, 1 dark, 2 light), read
// at UV2 - the model's UV0 shifted by whole texels into the atlas
// (tools/blender/rink_build.py paint_layout), so a paint texel has exactly
// the edges of the picture's texel under it. Faces that take no paint point
// at a texel that stays clear. Include after rink3d_common.

uniform sampler2D paint : filter_nearest, repeat_disable, hint_default_black;
uniform bool paint_on = false;
// The blood and oil shown (ABACABB MODE, MwSettings.blood; off: only the
// ice's detail).
uniform bool paint_blood = true;
// The ice's own detail shown (DETAILED ICE, MwSettings.ice_detail; off: the
// plain ice). The floor's only.
uniform bool ice_detail = true;
// The paint's colours: line 1's colour 10 (the original's blood, `$042E`, the
// regional pair) and colour 14 (`$444`, the robots' oil in fights).
const int PAINT_BLOOD = 26;
const int PAINT_OIL = 30;

// The atlas texel at [uv2] (both fields; 0 when the paint is off).
int paint_texel(vec2 uv2) {
	if (!paint_on) {
		return 0;
	}
	ivec2 size = textureSize(paint, 0);
	ivec2 p = clamp(ivec2(floor(uv2 * vec2(size))), ivec2(0), size - 1);
	return int(round(texelFetch(paint, p, 0).r * 255.0));
}

// The paint at [uv2]: 0 none, 1 blood, 2 oil.
int paint_at(vec2 uv2) {
	return paint_blood ? paint_texel(uv2) % 4 : 0;
}

vec3 paint_colour(int k) {
	return colour_of(k == 2 ? PAINT_OIL : PAINT_BLOOD);
}
