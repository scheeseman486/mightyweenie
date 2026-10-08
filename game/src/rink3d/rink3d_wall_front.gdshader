// The near end's outer wall (plan 14): as rink3d_wall, but drawn after the
// standing sprites (which go over the other boards in order, as the
// original's do), tested against their depth: it hides the players behind
// it. Its material has a high render priority (MwRinkModel).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, blend_mix, depth_draw_always;
#include "res://src/rink3d/rink3d_common.gdshaderinc"

uniform sampler2D picture : filter_nearest, repeat_disable;

void fragment() {
	int i = indexed_at(picture, UV);
	if (i % 16 == 0) {
		discard;
	}
	ALBEDO = colour_of(i);
	ALPHA = 1.0;
}
