// The crowd's figures in the stands (plan 15, docs/rink3d.md, Crowd): one
// MultiMesh of billboards. Each instance stands on its tread facing the
// rink (its local +Z); it shows its front view when the camera is in front
// of it and its back view from behind. Since plan 32 (screen_billboards,
// MwStands3D.billboards) a figure is drawn as the rink's sprites are: a
// quad in the screen's plane at his feet, his pixels square on screen;
// before, a card standing upright on his tread turned to the camera. A view is a rect of the figure
// atlas (R8 indexed, line * 16 + colour; 0 see-through) in atlas px: front in
// INSTANCE_CUSTOM, back in COLOR, a negative width mirrors it. Opaque
// cut-out, depth tested like the boards (the rink's sprites test it too).
// The top rows fade to black; the game's cameras cut away what would hide
// the play (rink3d_stands_common). Each fan wears his team's colours
// (plan 16 amendment, MwCrowdMix): his rects' x carries it, x + 1024 *
// (team + 1), and line 1 (the crowd's) comes from that team's row of
// team_lines; 0 (Satan): the palette as it is.
// The crowd's life (plan 30, owner: a livelier crowd): all a fan can
// do is shake side to side, bounce up and down and turn left and right
// (his drawing mirrored). Each fan fidgets with a slow sway of his own;
// the livelier the crowd (the game's crowd level, MwCrowdLife) the
// more of them hop, in bursts of their own, higher; the leading team's
// fans livelier, the trailing team's calmer; now and then one turns the
// other way for a moment; and a wave can go round the stands (a band of
// fans hopping up as it passes). Movement only: the drawings are the ROM's.
// The crowd makes way (owner, 2026-10-09; MwCrowdDuck): a fan who hides the
// rink, between the camera and a thing on the ice (a player, the puck, the
// referee, a net, a standing hazard, the goal's skull in flight) whose
// drawing covers it on the screen, or comes near it side to side, sinks
// behind his seat until his head is just below its lowest pixel - all the
// way close to it, less further aside; wider and gentler during a goal.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform;
#include "res://src/rink3d/rink3d_common.gdshaderinc"
#include "res://src/rink3d/rink3d_stands_common.gdshaderinc"

const float PX = RINK_PX;   // rink3d_geom

uniform sampler2D atlas : filter_nearest, repeat_disable;
// Plan 32 (owner: the crowd and the referee billboards as the players): each
// figure a quad in the screen's plane at its foot point, its pixels square
// on screen as the rink's sprites are (rink3d_billboard), instead of
// standing upright in the world facing the camera.
uniform bool screen_billboards = true;
// Figures whose middle is nearer the camera than this (m) are not drawn
// (cameras among the crowd: no giant heads filling the screen; 0 = all drawn).
uniform float near_hide = 0.0;
// Line 1 of the palette by team: 16 x 23, row t with team t as team A
// (MwStands3D.lines_by_team).
uniform sampler2D team_lines : source_color, filter_nearest, repeat_disable;
const float TEAM_STRIDE = 1024.0;   // MwStands3D.TEAM_STRIDE

varying flat int team;   // the fan's team + 1; 0: the palette's own line 1
// Screen billboards' depth (as rink3d_billboard's): the figure's foot point
// and the plane it stands in, level and facing the camera (view space).
varying flat vec3 bb_anchor;
varying flat vec3 bb_toward;

// The crowd's life (MwCrowdLife's snapshot, MwStands3D.show_life): the
// match's seed (each fan's pace and moments), its clock (s), the whole
// crowd's liveliness (0 calm .. 1 roaring), the leading and trailing teams'
// codes (team + 1; 0 none) and how much livelier the leader's fans are, the
// wave (where it is: radians round the rink's centre, atan(x, z) in the
// world; 0 none .. 1 a full wave).
uniform float crowd_seed = 0.0;
uniform float crowd_time = 0.0;
uniform float liveliness = 0.0;
uniform int lead_team = 0;
uniform int trail_team = 0;
uniform float lead_lift = 0.0;
uniform float wave_angle = 0.0;
uniform float wave_amp = 0.0;
// The match's opening (plan 33, owner: about 80 % of the fans jump twice for
// the two booms, landing at each boom's peak in the sample, then the clap
// with a slight fast shake; MwChant, MwStands3D.chant):
// the chant's clock (s since its sample last started; < 0: no chant), its
// period (start to start), its beats (s into the sample: the two stomps'
// peaks, the clap's), and whether this is its first bar (no jump started
// before the sound).
uniform float chant_time = -1.0;
uniform float chant_period = 1.55;
uniform vec3 chant_beats = vec3(0.1, 0.51, 0.84);
uniform bool chant_first = false;
const float CHANT_SHARE = 0.8;    // of the fans chant
const float CHANT_AIR = 0.24;     // s from leaving the tread to landing on the beat
const float CHANT_HOP = 7.0;      // px high, and up to this much more
const float CHANT_HOP_MORE = 4.0;
const float CHANT_LAG = 0.03;     // s: each fan a little early or late, at most half of it
const float CLAP_SHAKE = 1.5;     // px each way
const float CLAP_HZ = 14.0;
const float CLAP_LEN = 0.22;      // s

// Hops (px): the lowest and how much higher at full liveliness; the wave's.
const float HOP = 2.0;
const float HOP_MORE = 5.0;
const float WAVE_HOP = 12.0;
// The wave's half width (radians).
const float WAVE_WIDTH = 0.16;

// The crowd makes way (MwCrowdDuck, MwStands3D.make_way): the things on the
// ice, each with its wake - their ice points (world) and weights (w, 0..1),
// their drawings (left, top, width, height px from the point, y down, as
// the sprites' px_rect); how far a goal's wider curve has come in (0..1);
// the world's scale (the ortho camera's). The rule's numbers are
// MwCrowdDuck's (CORE, REACH, GOAL_CORE, GOAL_REACH, CLEAR, TOP_SOFT, FRONT,
// RINK_SOFT; MAX_POINTS); the boards' outline MwStands' (BOARD, CORNER_FAR,
// CORNER_NEAR).
uniform int duck_count = 0;
uniform vec4 duck_at[128];
uniform vec4 duck_rect[128];
uniform float duck_goal = 0.0;
uniform vec3 duck_scale = vec3(1.0);
const float DUCK_CORE = 6.0;
const float DUCK_REACH = 36.0;
const float DUCK_GOAL_CORE = 16.0;
const float DUCK_GOAL_REACH = 128.0;
const float DUCK_CLEAR = 4.0;
const float DUCK_TOP_SOFT = 8.0;
const float DUCK_FRONT = 8.0;
const float DUCK_RINK_SOFT = 8.0;

// A fixed random number in [0, 1) for each (fan, salt) in the match's seed.
float fan_random(int fan, float salt) {
	return fract(sin(float(fan) * 12.9898 + salt * 78.233 + crowd_seed) * 43758.5453);
}

// How much the fan whose head is at world point hw hides the rink: the
// camera's line of sight over his head comes down on the ice inside the
// boards (MwCrowdDuck.occludes). The side stands seen from an end never do.
float rink_hidden(vec3 hw, mat4 inv_view, bool ortho) {
	vec3 from = ortho ? hw : inv_view[3].xyz;
	vec3 d = ortho ? -inv_view[2].xyz : hw - inv_view[3].xyz;
	if (d.y >= -1e-6) {
		return 0.0;
	}
	vec3 p = from + d * (-from.y / d.y);
	vec2 r = vec2(p.x / duck_scale.x, p.z / duck_scale.z) / PX;
	return 1.0 - smoothstep(-DUCK_RINK_SOFT, 0.0, rink_sd(r));
}

// How far (px, his own) the fan standing at view point a (his feet), w x h
// px, sinks to make way: only if he hides the rink (rink_hidden), then the
// most any thing asks (MwCrowdDuck.sink is the rule for one). For each thing
// he stands in front of, seen at its distance: if his head is higher on the
// screen than its lowest pixel, down to DUCK_CLEAR px below it - all of that
// within DUCK_CORE px of its drawing side to side, none from DUCK_REACH
// (during a goal the GOAL_ ones), none once his feet are above its top
// (eased over DUCK_TOP_SOFT px) - but never more than his height and the
// clearance (by then he is behind his seat). The boxes come eased and cut
// at the ice (MwCrowdDuck), so nothing here jumps.
float duck_px(vec3 a, float w, float h, mat4 view, mat4 inv_view, bool ortho) {
	if (!ortho && a.z >= -1e-3) {
		return 0.0;
	}
	float hidden = rink_hidden((inv_view * vec4(a + vec3(0.0, h * PX, 0.0), 1.0)).xyz, inv_view, ortho);
	if (hidden <= 0.0) {
		return 0.0;
	}
	float core = mix(DUCK_CORE, DUCK_GOAL_CORE, duck_goal);
	float reach = mix(DUCK_REACH, DUCK_GOAL_REACH, duck_goal);
	float most = 0.0;
	for (int j = 0; j < duck_count; j++) {
		vec4 p = duck_at[j];
		vec3 o = (view * vec4(p.xyz, 1.0)).xyz;
		float nearer = (a.z - o.z) / PX;
		if (nearer <= 0.0) {
			continue;
		}
		float k = ortho ? 1.0 : o.z / a.z;
		vec4 r = duck_rect[j];
		float hx = (a.x * k - o.x) / PX;
		float feet = (a.y * k - o.y) / PX;
		float head = feet + h * k;
		float need = head + r.y + r.w + DUCK_CLEAR;   // above its lowest pixel, -(top + height)
		float covers = smoothstep(0.0, DUCK_TOP_SOFT, -r.y - feet);   // his feet below its top
		if (need <= 0.0 || covers <= 0.0) {
			continue;
		}
		float half_w = 0.5 * w * k;
		float gap = max(0.0, max(r.x - (hx + half_w), (hx - half_w) - (r.x + r.z)));
		float f = (1.0 - smoothstep(core, reach, gap)) * smoothstep(0.0, DUCK_FRONT, nearer) * covers * p.w;
		most = max(most, f * min(need / k, h + DUCK_CLEAR));
	}
	return most * hidden;
}

void vertex() {
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	vec4 rect = cam.z >= 0.0 ? INSTANCE_CUSTOM : COLOR;
	float code = floor(rect.x / TEAM_STRIDE);
	rect.x -= code * TEAM_STRIDE;
	team = int(code);
	// Four views, Doom's rule (plan 16, owner): a fan's true front is his row's
	// facing (towards the rink). The ROM has no straight-on views: its front
	// drawings face front-right, its back drawings back-right (owner); mirrored,
	// front-left and back-left. Front or back by the camera's side of him (above);
	// left or right by which way his true front points across his line of sight
	// from the camera: mirrored when to the screen's left. Satan (instance 0)
	// mirrors towards the play instead (MwStands3D.watch).
	// MwStands3D.shown_mirrored is the same rule.
	vec3 gaze = (MODEL_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;      // world: x east, z south
	vec3 at = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 sight = PROJECTION_MATRIX[3][3] != 0.0 ? -INV_VIEW_MATRIX[2].xyz : at - INV_VIEW_MATRIX[3].xyz;
	float across = dot(gaze.xz, vec2(-sight.z, sight.x));          // > 0: towards the screen's right
	float bounce = 0.0;   // px up
	float sway = 0.0;     // px to the screen's right
	if (INSTANCE_ID != 0) {
		rect.z = across < 0.0 ? -abs(rect.z) : abs(rect.z);
		float r1 = fan_random(INSTANCE_ID, 1.0);
		float r2 = fan_random(INSTANCE_ID, 2.0);
		float r3 = fan_random(INSTANCE_ID, 3.0);
		float r4 = fan_random(INSTANCE_ID, 4.0);
		float life = liveliness;
		if (team > 0 && team == lead_team) {
			life += lead_lift;
		} else if (team > 0 && team == trail_team) {
			life *= 0.5;
		}
		life = clamp(life, 0.0, 1.0);
		sway = sin(crowd_time * (0.6 + 0.8 * r1) + TAU * r2) * (0.4 + 1.4 * life);
		// his own urge comes and goes; the livelier, the more often it is over his threshold
		float urge = 0.5 + 0.5 * sin(crowd_time * (0.2 + 0.35 * r3) + TAU * r4);
		float hopping = smoothstep(1.02 - life, 1.12 - life, urge);
		bounce = abs(sin(crowd_time * 3.14159 * (1.5 + 0.9 * r1) + TAU * r3)) * hopping * (HOP + HOP_MORE * life);
		// a moment's turn every 9-23 s
		if (fract(crowd_time / (9.0 + 14.0 * r2) + r4) < 0.05) {
			rect.z = -rect.z;
		}
		if (wave_amp > 0.0) {
			vec3 at_w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
			float d = mod(atan(at_w.x, at_w.z) - wave_angle + TAU * 0.5, TAU) - TAU * 0.5;
			bounce += wave_amp * WAVE_HOP * exp(-(d * d) / (WAVE_WIDTH * WAVE_WIDTH));
		}
		if (chant_time >= 0.0 && fan_random(INSTANCE_ID, 7.0) < CHANT_SHARE) {
			float lag = (fan_random(INSTANCE_ID, 9.0) - 0.5) * CHANT_LAG;
			float up = 0.0;
			for (int k = 0; k < 4; k++) {
				// this bar's two stomps and the next bar's (its first jump leaves before it starts)
				float beat = (k % 2 == 0 ? chant_beats.x : chant_beats.y) + (k < 2 ? 0.0 : chant_period) + lag;
				if (k < 2 && chant_first && beat - CHANT_AIR < 0.0) {
					continue;
				}
				float u = (chant_time - (beat - CHANT_AIR)) / CHANT_AIR;
				if (u > 0.0 && u < 1.0) {
					up = max(up, 4.0 * u * (1.0 - u));
				}
			}
			bounce = max(bounce, up * (CHANT_HOP + CHANT_HOP_MORE * fan_random(INSTANCE_ID, 8.0)));
			float c = chant_time - chant_beats.z - lag;
			if (c > -0.03 && c < CLAP_LEN) {
				sway += sin(c * TAU * CLAP_HZ) * CLAP_SHAKE * (1.0 - max(c, 0.0) / CLAP_LEN);
			}
		}
	}
	vec3 anchor = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 up = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float scale = length(up);
	up /= scale;
	vec3 right;
	bb_anchor = anchor;
	bb_toward = vec3(0.0, 0.0, 1.0);
	if (screen_billboards) {
		vec3 level = level_toward_camera(MODEL_MATRIX, INV_VIEW_MATRIX);
		bb_toward = (MODELVIEW_MATRIX * vec4(level, 0.0)).xyz;
		right = vec3(1.0, 0.0, 0.0);
		up = vec3(0.0, 1.0, 0.0);
		scale = 1.0;
	} else if (PROJECTION_MATRIX[3][3] != 0.0) {
		right = normalize(vec3(1.0, 0.0, 0.0) - up * up.x);
	} else {
		right = normalize(cross(up, -anchor));
	}
	float w = abs(rect.z);
	float h = rect.w;
	// making way (MwCrowdDuck): down behind his seat, no hops while he is
	if (INSTANCE_ID != 0 && duck_count > 0) {
		float duck = duck_px(anchor, w, h, VIEW_MATRIX, INV_VIEW_MATRIX, PROJECTION_MATRIX[3][3] != 0.0);
		bounce = bounce * (1.0 - clamp(duck * 0.25, 0.0, 1.0)) - duck;
	}
	// too near the camera, or cut away (its top above the cut, see
	// rink3d_stands_common): all four corners at the anchor, nothing drawn
	float shown = near_hide > 0.0 && length(anchor + up * (0.5 * h * PX * scale)) < near_hide ? 0.0 : 1.0;
	vec3 top = (MODEL_MATRIX * vec4(0.0, h * PX, 0.0, 1.0)).xyz;
	if (stands_cut(top)) {
		shown = 0.0;
	}
	VERTEX = anchor + (right * ((VERTEX.x * w + sway) * PX * scale) + up * ((VERTEX.y * h + bounce) * PX * scale)) * shown;
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
	// a screen billboard's depth: as if it stood upright at its foot point,
	// facing the camera (the rows behind and above it don't hide it)
	if (screen_billboards) {
		vec4 clip = PROJECTION_MATRIX * vec4(ray_plane(VERTEX, bb_toward, bb_anchor, PROJECTION_MATRIX[3][3] != 0.0), 1.0);
		DEPTH = clip.z / clip.w;
	} else {
		DEPTH = FRAGCOORD.z;
	}
	vec3 c = team > 0 && i >= 16 && i < 32 ? texelFetch(team_lines, ivec2(i - 16, team - 1), 0).rgb : colour_of(i);
	ALBEDO = c * stands_fade((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y);
}
