// The crowd's figures in the stands (plan 15, docs/rink3d.md, Crowd): one
// MultiMesh of upright billboards. Each instance stands on its tread facing
// the rink (its local +Z); it shows its front view when the camera is in
// front of it and its back view from behind. A view is a rect of the figure
// atlas (R8 indexed, line * 16 + colour; 0 see-through) in atlas px: front in
// INSTANCE_CUSTOM, back in COLOR, a negative width mirrors it. Opaque
// cut-out, depth tested like the boards (the rink's sprites test it too).
// The top rows fade to black; the game's cameras cut away what would hide
// the play (rink3d_stands_common). Each fan wears his team's colours
// (plan 16 amendment, MwCrowdMix): his rects' x carries it, x + 1024 *
// (team + 1), and line 1 (the crowd's) comes from that team's row of
// team_lines; 0 (the referee): the palette as it is.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform;
#include "res://src/rink3d/rink3d_common.gdshaderinc"
#include "res://src/rink3d/rink3d_stands_common.gdshaderinc"

const float PX = 0.05;   // MwRink3D.METRES_PER_PX

uniform sampler2D atlas : filter_nearest, repeat_disable;
// Figures whose middle is nearer the camera than this (m) are not drawn
// (cameras among the crowd: no giant heads filling the screen; 0 = all drawn).
uniform float near_hide = 0.0;
// Line 1 of the palette by team: 16 x 23, row t with team t as team A
// (MwStands3D.lines_by_team).
uniform sampler2D team_lines : source_color, filter_nearest, repeat_disable;
const float TEAM_STRIDE = 1024.0;   // MwStands3D.TEAM_STRIDE

varying flat int team;   // the fan's team + 1; 0: the palette's own line 1

void vertex() {
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	vec4 rect = cam.z >= 0.0 ? INSTANCE_CUSTOM : COLOR;
	float code = floor(rect.x / TEAM_STRIDE);
	rect.x -= code * TEAM_STRIDE;
	team = int(code);
	// Four views, Doom's rule (plan 16, owner): a fan's true front is his
	// row's facing (towards the rink). The ROM has no straight-on views: its
	// front drawings face front-right, its back drawings back-right (owner);
	// mirrored, front-left and back-left. Front or back by the camera's side
	// of him (above); left or right by which way his true front points across
	// his line of sight from the camera: mirrored when to the screen's left. The referee (instance 0) mirrors towards
	// the play instead (MwStands3D.watch). MwStands3D.shown_mirrored is the
	// same rule.
	vec3 gaze = (MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;      // world: x east, z south
	vec3 at = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 sight = PROJECTION_MATRIX[3][3] != 0.0 ? -INV_VIEW_MATRIX[2].xyz : at - INV_VIEW_MATRIX[3].xyz;
	float across = dot(gaze.xz, vec2(-sight.z, sight.x));          // > 0: towards the screen's right
	if (INSTANCE_ID != 0) {
		rect.z = across < 0.0 ? -abs(rect.z) : abs(rect.z);
	}
	vec3 anchor = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 up = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float scale = length(up);
	up /= scale;
	vec3 right;
	if (PROJECTION_MATRIX[3][3] != 0.0) {
		right = normalize(vec3(1.0, 0.0, 0.0) - up * up.x);
	} else {
		right = normalize(cross(up, -anchor));
	}
	float w = abs(rect.z);
	float h = rect.w;
	// too near the camera, or cut away (its top above the cut, see
	// rink3d_stands_common): all four corners at the anchor, nothing drawn
	float shown = near_hide > 0.0 && length(anchor + up * (0.5 * h * PX * scale)) < near_hide ? 0.0 : 1.0;
	vec3 top = (MODEL_MATRIX * vec4(0.0, h * PX, 0.0, 1.0)).xyz;
	if (stands_cut(top)) {
		shown = 0.0;
	}
	VERTEX = anchor + (right * (VERTEX.x * w * PX * scale) + up * (VERTEX.y * h * PX * scale)) * shown;
	NORMAL = vec3(0.0, 0.0, 1.0);
	float u = rect.z < 0.0 ? 1.0 - UV.x : UV.x;
	UV = (rect.xy + vec2(u * w, UV.y * h)) / vec2(textureSize(atlas, 0));
	COLOR = vec4(1.0);
}

void fragment() {
	int i = indexed_at(atlas, UV);
	if (i == 0) {
		discard;
	}
	vec3 c = team > 0 && i >= 16 && i < 32 ? texelFetch(team_lines, ivec2(i - 16, team - 1), 0).rgb : colour_of(i);
	ALBEDO = c * stands_fade((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y);
}
