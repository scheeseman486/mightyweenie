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
// With strip_shadow (MwSettings.flat_shadows, MwFlatShadows) the frame's
// shadow pixels (colour 11 of the team lines) are left out of every pass:
// MwSprites3D lays them on the ice beneath it (rink3d_sprite_shadow), or
// nowhere in the bench area. The stick's shadow stays on the billboard:
// rink3d_sprite_stick (STICK_PASS, after the colours, frames that have one)
// draws the shadow pixels its shadow_mask marks as the stick's
// (MwFlatShadows.ON_STICK) in the shade colour but never lighter than what
// the opaque pass drew behind them - black over black.
//
// Plan 37, the ice as a mirror (MwSettings.reflections, owner: the on-ice
// sprites from 25 % opaque at their base to none over 12 pixels, then both
// doubled: 50 % over 24): rink3d_sprite_reflect (REFLECT_PASS) draws a frame
// standing on the ice flipped about its point - its rows above the ice as
// many rows below it, in the screen's plane like the billboard (seen from the
// original's angle, exactly the mirror image of the frame standing upright)
// - row n above the ice at reflect_alpha * (1 - n / reflect_fade), on the
// ice only, at the depth of the ice under each pixel; not its clear, shadow
// or operator pixels. Drawn before the standing sprites (MwSprites3D), which
// cover it where they stand in front (rink3d_reflect.gdshaderinc).
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
#elif defined(STICK_PASS)
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform, blend_mix, depth_draw_never;
#elif defined(REFLECT_PASS)
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform, blend_mix, depth_draw_never;
#elif defined(ORDER_2D)
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform, blend_mix, depth_test_disabled, depth_draw_never;
#else
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform, blend_mix, depth_draw_never;
#endif
#include "res://src/rink3d/rink3d_common.gdshaderinc"
#include "res://src/rink3d/rink3d_billboard.gdshaderinc"
#ifdef REFLECT_PASS
#include "res://src/rink3d/rink3d_reflect.gdshaderinc"
#endif

uniform sampler2D frame : filter_nearest, repeat_disable;
// The part of the frame this quad shows (x, y, w, h in 0..1).
instance uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
// 1: a flat card (plan 16: the winged skulls' wings, the skull at rest)
// where the quad mesh instance stands, double-sided: the drawing reads the
// right way from behind too; its depth is its own.
instance uniform float flat_card = 0.0;
// How lit the frame is (plan 32, MwBench3D.shade_at): 1, or less in an
// arch's dark (0 black).
instance uniform float shade = 1.0;
// Plan 37: its colours this many of each channel's 8 levels darker (the oil
// in flight, owner: a shade darker; darker_by).
instance uniform float darker = 0.0;
// The frame's shadow pixels left out (see above).
uniform bool strip_shadow = false;
// One more index left out with them, and from the reflection (plan 37: a
// fire's scorch mark, MwFlatShadows.scorch_index; -1 none).
uniform int strip_also = -1;
#ifdef STICK_PASS
// MwFlatShadows.mask of the frame: 128 = a shadow pixel of the stick's
uniform sampler2D shadow_mask : filter_nearest, repeat_disable;
uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
#endif

void vertex() {
	bb_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 ground = MODEL_MATRIX[3].xyz / max(bb_scale, vec3(1e-6));
	bb_feet = vec2(ground.x, ground.z) / BB_PX;
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
			vec3 level = level_toward_camera(MODEL_MATRIX, INV_VIEW_MATRIX);
			bb_toward = (MODELVIEW_MATRIX * vec4(level, 0.0)).xyz;
		}
		vec2 px = px_rect.xy + vec2(VERTEX.x + 0.5, 0.5 - VERTEX.y) * px_rect.zw;
#ifdef REFLECT_PASS
		VERTEX = bb_anchor + vec3(px.x, px.y, 0.0) * BB_PX;    // flipped about the frame's point
#else
		VERTEX = bb_anchor + vec3(px.x, -px.y, 0.0) * BB_PX;
#endif
		NORMAL = vec3(0.0, 0.0, 1.0);
	}
}

// Where in the frame this fragment is (a flat card seen from behind: mirrored back).
vec2 frame_uv(vec2 uv, bool front) {
	if (flat_card > 0.5 && !front) {
		uv.x = 1.0 - uv.x;
	}
	return uv_rect.xy + uv * uv_rect.zw;
}

// The frame's pixel for this fragment.
int frame_index(vec2 uv, bool front) {
	return indexed_at(frame, frame_uv(uv, front));
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
#ifndef ORDER_2D
	// standing outside the boards: not past the benches' and boxes' walls
	// below their tops (plan 32, rink3d_billboard's past_barrier)
	if (boards_rule && past_barrier(VERTEX, PROJECTION_MATRIX[3][3] != 0.0, INV_VIEW_MATRIX)) {
		discard;
	}
#endif
#ifndef STICK_PASS
	if (strip_shadow && (i == 27 || i == 43 || i == strip_also)) {
		discard;     // colour 11 of lines 1 and 2: the shadow, drawn flat on the ice (a fire's scorch too)
	}
#endif
#ifdef REFLECT_PASS
	if (i % 16 == 0 || i >= 62 || i == 27 || i == 43 || i == strip_also) {
		discard;     // clear, the operators, the shadow and a scorch (they lie on the ice)
	}
	// rows above the ice of the frame's row this pixel shows (0: standing on it)
	float n = -(px_rect.y + floor(clamp(UV.y, 0.0, 0.99999) * px_rect.w) + 1.0);
	if (n <= -1.0) {
		discard;     // a row below the ice (lying on it)
	}
	float a = reflect_row_alpha(max(n, 0.0));
	if (a <= 0.0) {
		discard;
	}
	bool ortho = PROJECTION_MATRIX[3][3] != 0.0;
	vec3 p = ray_plane(VERTEX, bb_up, bb_anchor, ortho);
	if (!reflect_on_ice(p, INV_VIEW_MATRIX, bb_scale)) {
		discard;
	}
	ALBEDO = darker_by(colour_of(i), darker) * shade;
	ALPHA = a;
	DEPTH = reflect_depth(p, ortho, PROJECTION_MATRIX);
#elif defined(STICK_PASS)
	if (indexed_at(shadow_mask, frame_uv(UV, FRONT_FACING)) != 128) {
		discard;     // only the stick's shadow pixels (MwFlatShadows.ON_STICK)
	}
	vec3 below = textureLod(screen, SCREEN_UV, 0.0).rgb;
	ALBEDO = min(below, colour_of(27)) * shade;
	ALPHA = 1.0;
	DEPTH = frame_depth(VERTEX, FRAGCOORD, PROJECTION_MATRIX, INV_VIEW_MATRIX, VIEW_MATRIX);
#else
	bool op = i >= 62;   // line 3, colour 14 (highlight) or 15 (shadow)
#ifdef OPS_PASS
	if (!op) {
		discard;
	}
	ALBEDO = vec3(i == 62 ? 1.0 : 0.0);
	ALPHA = 0.5 * shade;
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
	ALBEDO = darker_by(colour_of(i), darker) * shade;
	ALPHA = 1.0;
#ifndef ORDER_2D
	DEPTH = frame_depth(VERTEX, FRAGCOORD, PROJECTION_MATRIX, INV_VIEW_MATRIX, VIEW_MATRIX);
#endif
#endif
#endif
#endif
}
