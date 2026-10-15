// The hallways between the pens (owner, 2026-10-11: extended and faded to
// black, then about twice as long and fading out more gently; docs/rink3d.md,
// The model): the rink model's pen walls, their glass and the bar between the
// benches run on under the stands and darken gently (smoothstep) along them:
// lit up to x arch.x (west) / arch.z (east), black at arch.y / arch.w (their
// end), within |y| <= arch_half_y of the centre line. MwRinkModel sets both
// from MwBench3D (HALL_WEST, HALL_EAST, ARCH_HALF_Y).
// Rink px from the model's own coordinates (the glb's: 1 px = 0.05 m, Godot
// X = x, Z = y), so a scaled world (the calibration camera) changes nothing.
// A shader including this has ARCH_VERTEX in its vertex() (a varying is set
// there only, never in a function).

uniform vec4 arch = vec4(-232.0, -344.0, 238.0, 344.0);
uniform float arch_half_y = 40.5;
varying vec2 arch_at;    // rink px (x, y) of the fragment

#define ARCH_VERTEX arch_at = VERTEX.xz / RINK_PX

// How lit the fragment is: 1, or less deep in a hallway (0 black).
float arch_shade() {
	if (abs(arch_at.y) > arch_half_y) {
		return 1.0;
	}
	if (arch_at.x < arch.x) {
		return smoothstep(arch.y, arch.x, arch_at.x);
	}
	if (arch_at.x > arch.z) {
		return 1.0 - smoothstep(arch.z, arch.w, arch_at.x);
	}
	return 1.0;
}
