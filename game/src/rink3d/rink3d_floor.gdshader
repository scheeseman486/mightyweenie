// The 3D rink's floor: the ice (plan 14). Colour 0 is the ice (the VDP
// backdrop, palette colour 0). Only the ice inside the boards shows (plan 16,
// ice_mask from MwRinkModel): the rink picture's flat surroundings (the
// crowd, the boards and signs drawn flat, the pens) are black; the 3D
// model, the stands and the crowd stand there instead.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://src/rink3d/rink3d_common.gdshaderinc"
#include "res://src/rink3d/rink3d_paint.gdshaderinc"

uniform sampler2D picture : filter_nearest, repeat_disable;
uniform sampler2D ice_mask : filter_nearest, repeat_disable;
// Plan 37 (owner: the red opaque on the ice's main colour, about 75 % on
// any other pixel, the lines and the like): the paint's strength over the
// ice's markings (MwRinkModel.paint_marks_alpha).
uniform float paint_marks_alpha = 0.75;
// The ice's own detail (owner: dark and light splotches of ~10 % opacity,
// the skates' scratches; 15 % after the owner's review): towards black or
// white by this much.
uniform float ice_detail_alpha = 0.15;

void fragment() {
	int i = indexed_at(picture, UV);
	if (indexed_at(ice_mask, UV) > 0) {
		int v = paint_texel(UV2);       // plan 37: blood or oil, and the ice's detail
		int k = paint_blood ? v % 4 : 0;
		int d = ice_detail ? (v / 4) % 4 : 0;
		vec3 ice = colour_of(i % 16 == 0 ? 0 : i);
		if (d > 0) {
			ice = mix(ice, d == 1 ? vec3(0.0) : vec3(1.0), ice_detail_alpha);
		}
		if (k > 0) {
			// opaque on the plain ice (colour 0, or a colour equal to it), the
			// markings showing through elsewhere
			bool plain = i % 16 == 0 || colour_of(i) == colour_of(0);
			ice = plain ? paint_colour(k) : mix(ice, paint_colour(k), paint_marks_alpha);
		}
		ALBEDO = ice;
	} else {
		ALBEDO = vec3(0.0);
	}
}
