// The 3D rink's glass (plan 14): true translucency where the ROM's pictures
// dither glass - see rink3d_glass_body.gdshaderinc (shared with its
// reflection in the ice, plan 37). The pens' glass darkens into the
// hallways (rink3d_arch).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_never;
#include "res://src/rink3d/rink3d_common.gdshaderinc"
#include "res://src/rink3d/rink3d_paint.gdshaderinc"
#include "res://src/rink3d/rink3d_arch.gdshaderinc"

uniform sampler2D picture : filter_nearest, repeat_disable;
#include "res://src/rink3d/rink3d_glass_body.gdshaderinc"

void vertex() {
	ARCH_VERTEX;
}

void fragment() {
	vec4 c = glass_colour(UV, UV2);
	if (c.a < 0.0) {
		discard;
	}
	ALBEDO = c.rgb * arch_shade();
	ALPHA = c.a;
}
