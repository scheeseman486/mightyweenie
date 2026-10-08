// The referee side's spear fence and gate rail (plan 14): seen from both
// sides alike. Colour 0 (between the bars) is see-through.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://src/rink3d/rink3d_common.gdshaderinc"

uniform sampler2D picture : filter_nearest, repeat_disable;

void fragment() {
	int i = indexed_at(picture, UV);
	if (i % 16 == 0) {
		discard;
	}
	ALBEDO = colour_of(i);
}
