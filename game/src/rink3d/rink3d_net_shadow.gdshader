// The ground shadow inside a 3D net (plan 17, MwNet3D): the ROM's own
// shadow, the ice the net's front drawing shows through its mouth (decal:
// R8 indices, line * 16 + colour, 0 = the ice shows), and the fill colour
// where that drawing hides the ground behind the posts and the side netting
// (the sides) or the back bar (behind it). In front of the drawing's ground
// (the goal line) the ice shows. UV = (x, 1 - d) in rink px, d behind the
// goal line. MwNet3D.shadow_index is the same rule.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
#include "res://src/rink3d/rink3d_common.gdshaderinc"

uniform sampler2D decal : filter_nearest, repeat_disable;
uniform ivec2 ground_x = ivec2(-19, 18);   // the decal's columns (x, inclusive)
uniform ivec2 ground_d = ivec2(2, 13);     // its rows (d, inclusive)
uniform int fill = 6;

void fragment() {
	ivec2 p = ivec2(floor(vec2(UV.x, 1.0 - UV.y)));
	int i = 0;
	if (p.x < ground_x.x || p.x > ground_x.y || p.y > ground_d.y) {
		i = fill;
	} else if (p.y >= ground_d.x) {
		i = int(round(texelFetch(decal, ivec2(p.x - ground_x.x, p.y - ground_d.x), 0).r * 255.0));
	}
	if (i == 0) {
		discard;
	}
	ALBEDO = colour_of(i);
}
