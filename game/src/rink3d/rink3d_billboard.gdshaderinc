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

const float BB_PX = 0.05;   // MwRink3D.METRES_PER_PX: one frame pixel in view units

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

// Where the camera's ray through view position [param v] meets the plane
// through [param q] with normal [param n] (view space; [param ortho]: parallel
// rays along -z).
vec3 bb_ray_plane(vec3 v, vec3 n, vec3 q, bool ortho) {
	if (ortho) {
		float nz = abs(n.z) < 1e-6 ? 1e-6 : n.z;
		return v - vec3(0.0, 0.0, dot(n, v - q) / nz);
	}
	float nv = dot(n, v);
	return v * (dot(n, q) / (abs(nv) < 1e-9 ? 1e-9 : nv));
}

// Plan 16, the 3D order: the boards (the physics boundary, a rounded
// rectangle: half sizes 185 x 372 px, corners 74 far / 48 near) and their
// height (the far glass's top). With boards_rule off (the calibration
// camera: the original's 2D order) the depth is the plain card's.
uniform bool boards_rule = true;
const float BOARDS_TOP = 48.0;

// Signed distance (rink px) from the boards' inside line: < 0 on the ice.
float rink_sd(vec2 p) {
	float r = p.y < 0.0 ? 74.0 : 48.0;
	vec2 q = abs(p) - (vec2(185.0, 372.0) - r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 to_rink(vec3 v, mat4 inv_view) {
	vec3 w = (inv_view * vec4(v, 1.0)).xyz;
	return vec3(w.x, w.z, w.y) / BB_PX;
}

vec3 from_rink(vec3 r, mat4 view) {
	return (view * vec4(vec3(r.x, r.z, r.y) * BB_PX, 1.0)).xyz;
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
// the ice that would lie past the boards stay at the player's feet.
vec3 billboard_depth_point(vec3 v, bool ortho, mat4 inv_view, mat4 view) {
	vec3 p = bb_ray_plane(v, bb_toward, bb_anchor, ortho);
	bool folded = false;
	if (bb_pinned < 0.5 && dot(p - bb_anchor, bb_up) < 0.0) {
		p = bb_ray_plane(v, bb_up, bb_anchor + bb_up * folded_lift, ortho);
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
	}
	p.z += pin.y;
	return p;
}
