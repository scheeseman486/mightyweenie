// A standing sprite frame's shadow as a flat on the ice beneath it (owner,
// 2026-10-09: MwFlatShadows, MwSprites3D). The quad's origin is the ice
// point under the frame's point; px_rect is the frame's rectangle there
// (frame pixels, y down), laid on the ice with its bottom edge towards the
// camera, as the billboard above it faces it: the rows below the point lie
// in front of the feet, those above it behind them. The mask is the flat
// (R8: 255 where the shadow is: the frame's dither, MwFlatShadows.mask),
// drawn in the shade colour (colour 11 of the
// team lines: the ice's colour 5) but never lighter than what the opaque
// pass drew below it, channel by channel - the shade on the ice, black over
// the black floor beyond it. Drawn before every other translucent thing
// (MwSprites3D gives it the lowest render priority), depth tested.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_never;
#include "res://src/rink3d/rink3d_common.gdshaderinc"

const float PX = RINK_PX;   // one frame pixel in model units (rink3d_geom)

uniform sampler2D mask : filter_nearest, repeat_disable;
// The flat's colour: colour 11 of the team lines, or a fire's scorch's own
// (plan 37, MwFlatShadows.scorch_index), never lighter than below.
uniform int shade_index = 27;
uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
// left, top, width, height: frame pixels from the frame's point (y down)
instance uniform vec4 px_rect = vec4(0.0, 0.0, 1.0, 1.0);

void vertex() {
	// level towards the camera, in the model's space (as the billboards)
	vec3 toward = level_toward_camera(MODEL_MATRIX, INV_VIEW_MATRIX);
	vec3 right = vec3(toward.z, 0.0, -toward.x);
	vec2 px = px_rect.xy + vec2(VERTEX.x + 0.5, 0.5 - VERTEX.y) * px_rect.zw;
	VERTEX = (right * px.x + toward * px.y) * PX;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	if (indexed_at(mask, UV) != 255) {
		discard;     // only the flat's pixels (MwFlatShadows.FLAT; 128: the stick's, on the billboard)
	}
	vec3 below = textureLod(screen, SCREEN_UV, 0.0).rgb;
	ALBEDO = min(below, colour_of(shade_index));
	ALPHA = 1.0;
}
