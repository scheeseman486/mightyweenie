// The 3D rink's solid boards (plan 14): padding and the sign band facing the
// rink, the dark grey wall facing out. One-sided: each face is its own quad.
// Colour 0 is see-through.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
#include "res://src/rink3d/rink3d_common.gdshaderinc"

uniform sampler2D picture : filter_nearest, repeat_disable;

void fragment() {
	int i = indexed_at(picture, UV);
	if (i % 16 == 0) {
		discard;
	}
	ALBEDO = colour_of(i);
}
