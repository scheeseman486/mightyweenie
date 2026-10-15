// Standing sprite frames as billboards (plan 14, docs/rink3d.md), shared by
// the rink's standing sprite shaders. The quad lies in the screen's plane at
// its anchor, the frame raised above it by the point's height in pixels, as
// the original draws it: its pixels are square on screen at any resolution
// and from any camera, and frames at one anchor (a lamp on its stand) stay
// lined up. The anchor is the ice point under the frame's point or, for the
// frames in front of the far glass (the far lamp stand and its lamp, the
// winged skull), a pin on the glass: they stay on the post they cover in the
// original from any camera. Its depth, per pixel, is where the camera's ray
// meets the frame standing upright at its anchor (facing the camera or, when
// pinned, along the glass) or, for the rows below the ice (stick blades,
// skates, splashes), the ice towards the camera.

const float BB_PX = RINK_PX;   // one frame pixel in view units (rink3d_geom)

uniform float folded_lift = 0.002;   // the rows lying on the ice: above the ground layers (m)
// left, top, width, height: frame pixels from the frame's point (y down)
instance uniform vec4 px_rect = vec4(0.0, 0.0, 1.0, 1.0);
// x: the anchor's height above the ice point (px), 0 = on the ice, > 0 =
// pinned to the far glass at that height; y: depth bias towards the camera (m)
instance uniform vec2 pin = vec2(0.0, 0.0);

varying flat vec3 bb_anchor;   // view space: the ice point under the frame's point, or its pin
varying flat vec3 bb_up;       // view space: the rink's up, 1 m
varying flat vec3 bb_toward;   // view space: the depth plane's normal, 1 m: level towards
                               // the camera, or (pinned) the far glass's facing
varying flat float bb_pinned;  // 1: pinned to the far glass (nothing lies on the ice)

// Plan 16, the 3D order: the boards (the physics boundary, a rounded
// rectangle: rink3d_geom's rink_sd) and their height (the far glass's top).
// With boards_rule off (the calibration camera: the original's 2D order)
// the depth is the plain card's.
uniform bool boards_rule = true;
const float BOARDS_TOP = RINK_BOARDS_TOP;

vec3 to_rink(vec3 v, mat4 inv_view) {
	vec3 w = (inv_view * vec4(v, 1.0)).xyz;
	return vec3(w.x, w.z, w.y) / BB_PX;
}

vec3 from_rink(vec3 r, mat4 view) {
	return (view * vec4(vec3(r.x, r.z, r.y) * BB_PX, 1.0)).xyz;
}

// Plan 32 (owner: the benches' figures clipped at the barrier, but not where
// they hang over it): the walls round the benches and the boxes, as
// the rink model has them (rink px: x0, y0, x1, y1) and their tops (z, the
// pens' tall glass included to its panes' top; the hallways' walls run on
// under the stands - owner, 2026-10-11; MwBench3D.BARRIERS is the same list). A billboard
// standing outside the boards (a reserve, a penalised player, a player at
// the bench door) is a flat drawing wider than the body it shows: seen
// front-on, its sides reach through a wall seen edge-on, which cannot hide
// them. Its pixels that lie past a wall from his feet (on the upright plane
// at them, facing the camera) and below its top are not drawn; above it
// they hang over it and are, up to OVERHANG px past it (owner: the robots,
// the widest, hung over too far). The boxes' spear fence is not one (owner:
// cut at it, a figure showed gaps between its bars); the half-height
// panels beyond it count to their pad (their glass is see-through too).
const int BARRIERS = 16;
const vec4 BARRIER[16] = {
	vec4(-185.0, 160.0, -216.0, 160.0),   // west: the pens' end walls
	vec4(-185.0, -160.0, -216.0, -160.0),
	vec4(-216.0, 40.0, -216.0, 160.0),   // their back walls
	vec4(-216.0, -40.0, -216.0, -160.0),
	vec4(-216.0, 40.0, -344.0, 40.0),   // the hallway's walls
	vec4(-216.0, -40.0, -344.0, -40.0),
	vec4(-185.0, -160.0, -185.0, 160.0),   // the low boards in front of the benches
	vec4(-185.0, 0.0, -344.0, 0.0),   // the bar between the benches
	vec4(185.0, 160.0, 216.0, 160.0),   // east: the boxes' end walls
	vec4(185.0, -160.0, 216.0, -160.0),
	vec4(216.0, 40.0, 216.0, 160.0),   // their back walls
	vec4(216.0, -40.0, 216.0, -160.0),
	vec4(216.0, 40.0, 344.0, 40.0),   // the hallway's walls
	vec4(216.0, -40.0, 344.0, -40.0),
	vec4(185.0, 128.0, 185.0, 160.0),   // the boards beyond the fence (their pad)
	vec4(185.0, -160.0, 185.0, -128.0)
};
const float BARRIER_TOP[16] = {
	49.0, 49.0, 49.0, 49.0, 49.0, 49.0, 19.0, 16.0,
	49.0, 49.0, 49.0, 49.0, 49.0, 49.0, 19.0, 19.0
};
const float OVERHANG = 4.0;
uniform bool barriers = true;   // off: drawn whole (for comparisons)

varying flat vec3 bb_scale;    // the world's scale (the ortho camera's: y, z by sqrt 2)
varying flat vec2 bb_feet;     // rink px: the ice point under the frame's point

// Whether the segments a-b and c-d cross (a-b's ends excluded).
bool bb_crosses(vec2 a, vec2 b, vec2 c, vec2 d) {
	vec2 r = b - a;
	vec2 s = d - c;
	float den = r.x * s.y - r.y * s.x;
	if (abs(den) < 1e-6) {
		return false;
	}
	vec2 q = c - a;
	float t = (q.x * s.y - q.y * s.x) / den;
	float u = (q.x * r.y - q.y * r.x) / den;
	return t > 0.0 && t < 1.0 && u >= 0.0 && u <= 1.0;
}

// Whether the billboard pixel at view position [param v] is past a barrier
// from the feet of a frame standing outside the boards, and below its top
// or more than OVERHANG past it.
bool past_barrier(vec3 v, bool ortho, mat4 inv_view) {
	if (!barriers || bb_pinned > 0.5 || rink_sd(bb_feet) <= 0.0) {
		return false;                 // on the ice: the boards' own rules
	}
	vec3 g = (inv_view * vec4(ray_plane(v, bb_toward, bb_anchor, ortho), 1.0)).xyz / bb_scale;
	vec3 p = vec3(g.x, g.z, g.y) / BB_PX;
	for (int k = 0; k < BARRIERS; k++) {
		vec2 c = BARRIER[k].xy;
		vec2 d = BARRIER[k].zw;
		if (bb_crosses(bb_feet, p.xy, c, d)) {
			vec2 along = normalize(d - c);
			float past = abs(along.x * (p.y - c.y) - along.y * (p.x - c.x));
			if (p.z < BARRIER_TOP[k] || past > OVERHANG) {
				return true;
			}
		}
	}
	return false;
}

// A card pixel [param p] (view space) that reaches past the boards behind
// the player is not cut by them: its depth moves along the line of sight
// towards the camera to where that line comes back inside the boards or
// rises above them (whichever comes first); if it does neither (the pixel is
// on the camera's side of the boards), it keeps its own.
vec3 boards_pull(vec3 p, bool ortho, mat4 inv_view, mat4 view) {
	vec3 pr = to_rink(p, inv_view);
	if (rink_sd(pr.xy) <= 0.0) {
		return p;
	}
	vec3 cw = ortho ? (inv_view * vec4(p, 1.0)).xyz + inv_view[2].xyz * 400.0 : inv_view[3].xyz;
	vec3 d = vec3(cw.x, cw.z, cw.y) / BB_PX - pr;
	float t_hit = 2.0;
	if (pr.z >= BOARDS_TOP) {
		t_hit = 0.0;
	} else if (d.z > 1e-4) {
		t_hit = (BOARDS_TOP - pr.z) / d.z;
	}
	// the distance to a convex outline along a line is convex: its minimum,
	// then (if it is inside) where the line enters
	float a = 0.0;
	float b = min(t_hit, 1.0);
	for (int k = 0; k < 18; k++) {
		float m1 = a + (b - a) / 3.0;
		float m2 = b - (b - a) / 3.0;
		if (rink_sd(pr.xy + d.xy * m1) < rink_sd(pr.xy + d.xy * m2)) {
			b = m2;
		} else {
			a = m1;
		}
	}
	float tm = 0.5 * (a + b);
	if (rink_sd(pr.xy + d.xy * tm) < 0.0) {
		float lo = 0.0;
		float hi = tm;
		for (int k = 0; k < 18; k++) {
			float m = 0.5 * (lo + hi);
			if (rink_sd(pr.xy + d.xy * m) < 0.0) {
				hi = m;
			} else {
				lo = m;
			}
		}
		t_hit = min(t_hit, hi);
	}
	if (t_hit > 1.0) {
		return p;
	}
	return from_rink(pr + d * t_hit, view);
}

// The view-space depth position of the billboard pixel at view position
// [param v] (see above): where its ray meets the frame standing upright at its
// anchor (a plane through it facing the camera or, pinned, along the far
// glass), or below the ice the ice (just above it). In the 3D order, parts
// past the boards behind the player come forward (boards_pull); rows below
// the ice that would lie past the boards stay at the player's feet (and
// for a figure outside them, rows that would lie inside).
vec3 billboard_depth_point(vec3 v, bool ortho, mat4 inv_view, mat4 view) {
	vec3 p = ray_plane(v, bb_toward, bb_anchor, ortho);
	bool folded = false;
	if (bb_pinned < 0.5 && dot(p - bb_anchor, bb_up) < 0.0) {
		p = ray_plane(v, bb_up, bb_anchor + bb_up * folded_lift, ortho);
		folded = true;
	}
	if (boards_rule && rink_sd(to_rink(bb_anchor, inv_view).xy) <= 0.0) {
		if (folded) {
			if (rink_sd(to_rink(p, inv_view).xy) > 0.0) {
				p = bb_anchor + bb_up * folded_lift;
			}
		} else {
			p = boards_pull(p, ortho, inv_view, view);
		}
	} else if (boards_rule && folded && rink_sd(to_rink(p, inv_view).xy) <= 0.0) {
		// standing outside the boards (the benches, plan 32): rows below the
		// ice that would lie on the rink's side of them stay at his feet,
		// behind the boards
		p = bb_anchor + bb_up * folded_lift;
	}
	p.z += pin.y;
	return p;
}
