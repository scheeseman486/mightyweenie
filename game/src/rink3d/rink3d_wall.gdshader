// The 3D rink's solid boards (plan 14): padding and the sign band facing the
// rink, the dark grey wall facing out. One-sided: each face is its own quad.
// Colour 0 is see-through. Paint (plan 37) over the colours where there is any.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
#include "res://src/rink3d/rink3d_common.gdshaderinc"
#include "res://src/rink3d/rink3d_paint.gdshaderinc"

uniform sampler2D picture : filter_nearest, repeat_disable;

void fragment() {
	int i = indexed_at(picture, UV);
	if (i % 16 == 0) {
		discard;
	}
	int k = paint_at(UV2);              // plan 37: blood or oil (the rink side only)
	ALBEDO = k > 0 ? paint_colour(k) : colour_of(i);
}
