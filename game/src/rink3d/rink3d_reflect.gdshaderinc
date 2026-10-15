// The ice as a mirror (plan 37, owner: a planar reflection, the on-ice
// sprites' from 25 % opaque at their base to none over 12 px, the rink's
// geometry the same; then the opacity and the fade's length doubled: 50 %
// over 24 rows; docs/rink3d.md, Reflections). Shared by the reflections'
// shaders:
//
// * rink3d_reflect_mesh(_2s): the rink's boards, signs, fence and glass
//   (MwRinkModel) and the nets (MwNet3D) as mirrored copies of their meshes
//   under the ice (their instances scaled -1 up: Godot turns their culling
//   round, and FRONT_FACING with it);
// * rink3d_sprite_reflect: the standing sprites, each frame flipped about
//   its point (MwSprites3D): a billboard's rows above the ice drawn as many
//   rows below it, on the screen's pixel grid like the billboard.
//
// Each pixel row n above the ice (0: the row standing on it) is drawn
// reflect_alpha * (1 - n / reflect_fade) opaque, whole rows (the pixel grid:
// the boards' texels are a pixel tall, as are the sprites' rows), none from
// reflect_fade up (MwRink3D.REFLECT_ALPHA, REFLECT_FADE, reflect_alpha).
// A reflected pixel shows where the camera sees the ice: it is drawn at the
// depth of the ice point under it (a hair towards the camera, so the floor
// lets it through and whatever stands in front hides it) and only on the ice
// (reflect_ice: MwRinkModel.ice_mask, not the black floor beyond the
// boards). Drawn after the ice's under-ice frames and before its hazards,
// shadows and markers, the standing sprites after them all
// (MwRinkModel.REFLECT_PRIORITY). Not from the calibration camera.

const float REFLECT_PX = RINK_PX;      // rink3d_geom
const float REFLECT_BIAS = 0.0005;    // m towards the camera from the ice point
uniform float reflect_alpha = 0.5;    // MwRink3D.REFLECT_ALPHA
uniform float reflect_fade = 24.0;    // MwRink3D.REFLECT_FADE (rows)
// The ice (MwRinkModel.ice_mask: 255 inside the boards) over the rink
// picture: texel = rink px + reflect_origin (MwRink3D.MAP_ORIGIN).
uniform sampler2D reflect_ice : filter_nearest, repeat_disable;
uniform vec2 reflect_origin = vec2(256.0, 461.0);

// How opaque row n above the ice is (n whole rows; 0 below or past the fade).
float reflect_row_alpha(float n) {
	if (n < 0.0 || n >= reflect_fade) {
		return 0.0;
	}
	return reflect_alpha * (1.0 - n / reflect_fade);
}

// Whether view position p (on the ice plane) is on the ice: the world's
// scale ([param scale]: the ortho cameras' sqrt 2) taken off, rink px.
bool reflect_on_ice(vec3 p, mat4 inv_view, vec3 scale) {
	vec3 w = (inv_view * vec4(p, 1.0)).xyz / scale;
	ivec2 t = ivec2(floor(vec2(w.x, w.z) / REFLECT_PX + reflect_origin));
	ivec2 size = textureSize(reflect_ice, 0);
	if (t.x < 0 || t.y < 0 || t.x >= size.x || t.y >= size.y) {
		return false;
	}
	return texelFetch(reflect_ice, t, 0).r > 0.5;
}

// The depth a reflected pixel at ice point p (view space) is drawn at.
float reflect_depth(vec3 p, bool ortho, mat4 projection) {
	vec3 b = ortho ? p + vec3(0.0, 0.0, REFLECT_BIAS) : p * (1.0 - REFLECT_BIAS / max(length(p), 1e-6));
	vec4 clip = projection * vec4(b, 1.0);
	return clip.z / clip.w;
}
