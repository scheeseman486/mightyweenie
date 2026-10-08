// The 3D rink's floor: the ice (plan 14). Colour 0 is the ice (the VDP
// backdrop, palette colour 0). Only the ice inside the boards shows (plan 16,
// ice_mask from MwRinkModel): the rink picture's flat surroundings (the
// crowd, the boards and signs drawn flat, the pens) are black; the 3D
// model, the stands and the crowd stand there instead.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://src/rink3d/rink3d_common.gdshaderinc"

uniform sampler2D picture : filter_nearest, repeat_disable;
uniform sampler2D ice_mask : filter_nearest, repeat_disable;

void fragment() {
	int i = indexed_at(picture, UV);
	if (indexed_at(ice_mask, UV) > 0) {
		ALBEDO = colour_of(i % 16 == 0 ? 0 : i);
	} else {
		ALBEDO = vec3(0.0);
	}
}
