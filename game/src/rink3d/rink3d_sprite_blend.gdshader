// Sprite frames lying on the ice (plan 14): shadows, markers, plates and
// in-ice hazards, translucent, drawn before everything else translucent in
// the original's depth order (the materials' render priority). The VDP's
// shadow / highlight operator pixels (colours 14 and 15 of line 3) are true
// translucency, like palette_swap.gdshader's shadow_highlight: half-
// transparent black and white.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_never;
#include "res://src/rink3d/rink3d_common.gdshaderinc"

uniform sampler2D frame : filter_nearest, repeat_disable;
// The part of the frame this quad shows (x, y, w, h in 0..1).
instance uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	int i = indexed_at(frame, uv_rect.xy + UV * uv_rect.zw);
	if (i % 16 == 0) {
		discard;
	}
	if (i == 63) {
		ALBEDO = vec3(0.0);
		ALPHA = 0.5;
	} else if (i == 62) {
		ALBEDO = vec3(1.0);
		ALPHA = 0.5;
	} else {
		ALBEDO = colour_of(i);
		ALPHA = 1.0;
	}
}
