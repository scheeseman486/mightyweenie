// The standing sprite shaders' body (plan 14, docs/rink3d.md): one composed
// ROM frame (R8 indexed, palette lines from its pieces and the draw's attr)
// as a billboard (rink3d_billboard.gdshaderinc) or a flat card, drawn in up
// to three passes:
//
// * rink3d_sprite_depth (DEPTH_PASS): writes the depth of the frame's solid
//   pixels where they are in front of what is already drawn, draws no colour;
// * rink3d_sprite: draws the solid pixels' colours, depth tested (plan 16,
//   the 3D order): the rink, the stands, the crowd and other sprites in front
//   of a frame hide it; parts of it past the boards behind the player come
//   forward (rink3d_billboard's boards_pull), so a frame wider than the
//   player never loses an arm into the boards beside it;
//   rink3d_sprite_2d (ORDER_2D, the calibration camera): the original's
//   order, no depth test, over the boards whatever their depth;
// * rink3d_sprite_ops (OPS_PASS, frames that have any): the shadow /
//   highlight operator pixels (colours 14 and 15 of line 3) as
//   half-transparent black and white, after the glass (MwSprites3D gives it
//   a later render priority), depth tested.
//
// The near end's outer wall and the glass are drawn after the colours and
// before the operators, tested against the depth: in front of a frame they
// cover or tint it, behind it they don't show through. The operator pixels
// write no depth, so the glass behind them is drawn first and they darken or
// lighten it, as on the original's screen (not the crowd behind the glass).
#ifdef DEPTH_PASS
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform, blend_mix, depth_draw_always;
#elif defined(OPS_PASS)
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform, blend_mix, depth_draw_never;
#elif defined(ORDER_2D)
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform, blend_mix, depth_test_disabled, depth_draw_never;
#else
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform, blend_mix, depth_draw_never;
#endif
#include "res://src/rink3d/rink3d_common.gdshaderinc"
#include "res://src/rink3d/rink3d_billboard.gdshaderinc"

uniform sampler2D frame : filter_nearest, repeat_disable;
// The part of the frame this quad shows (x, y, w, h in 0..1).
instance uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
// 1: a flat card (plan 16: the winged skulls' wings, the skull at rest)
// where the quad mesh instance stands, double-sided: the drawing reads the
// right way from behind too; its depth is its own.
instance uniform float flat_card = 0.0;

void vertex() {
	if (flat_card > 0.5) {
		bb_pinned = 1.0;
		bb_anchor = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		bb_up = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		bb_toward = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
		VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		NORMAL = normalize(bb_toward);
	} else {
		// the quad's origin is the ice point under the frame's point; a pinned
		// frame's anchor is pin.x pixels above it
		bb_pinned = pin.x > 0.0 ? 1.0 : 0.0;
		bb_anchor = (MODELVIEW_MATRIX * vec4(0.0, pin.x * BB_PX, 0.0, 1.0)).xyz;
		bb_up = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		if (bb_pinned > 0.5) {
			bb_toward = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;   // the far glass faces south (+z)
		} else {
			vec3 back = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[2].xyz, 0.0)).xyz;
			vec3 level = normalize(vec3(back.x, 0.0, back.z) + vec3(0.0, 0.0, 1e-6));
			bb_toward = (MODELVIEW_MATRIX * vec4(level, 0.0)).xyz;
		}
		vec2 px = px_rect.xy + vec2(VERTEX.x + 0.5, 0.5 - VERTEX.y) * px_rect.zw;
		VERTEX = bb_anchor + vec3(px.x, -px.y, 0.0) * BB_PX;
		NORMAL = vec3(0.0, 0.0, 1.0);
	}
}

// The frame's pixel for this fragment (a flat card seen from behind: mirrored back).
int frame_index(vec2 uv, bool front) {
	if (flat_card > 0.5 && !front) {
		uv.x = 1.0 - uv.x;
	}
	return indexed_at(frame, uv_rect.xy + uv * uv_rect.zw);
}

// The depth this fragment writes: the billboard's (see above) or a flat card's own.
float frame_depth(vec3 v, vec4 fragcoord, mat4 projection, mat4 inv_view, mat4 view) {
	if (flat_card > 0.5) {
		return fragcoord.z;
	}
	vec4 clip = projection * vec4(billboard_depth_point(v, projection[3][3] != 0.0, inv_view, view), 1.0);
	return clip.z / clip.w;
}

void fragment() {
	int i = frame_index(UV, FRONT_FACING);
	bool op = i >= 62;   // line 3, colour 14 (highlight) or 15 (shadow)
#ifdef OPS_PASS
	if (!op) {
		discard;
	}
	ALBEDO = vec3(i == 62 ? 1.0 : 0.0);
	ALPHA = 0.5;
	DEPTH = frame_depth(VERTEX, FRAGCOORD, PROJECTION_MATRIX, INV_VIEW_MATRIX, VIEW_MATRIX);
#else
	if (i % 16 == 0 || op) {
		discard;
	}
#ifdef DEPTH_PASS
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
	DEPTH = frame_depth(VERTEX, FRAGCOORD, PROJECTION_MATRIX, INV_VIEW_MATRIX, VIEW_MATRIX);
#else
	ALBEDO = colour_of(i);
	ALPHA = 1.0;
#ifndef ORDER_2D
	DEPTH = frame_depth(VERTEX, FRAGCOORD, PROJECTION_MATRIX, INV_VIEW_MATRIX, VIEW_MATRIX);
#endif
#endif
#endif
}
