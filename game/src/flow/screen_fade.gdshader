shader_type canvas_item;
// MwScreenFader's cover: the screen behind it faded the original's way
// (`fade_vblank` $149F6, docs/re/title.md, Fade engine). Each colour channel
// is a 3-bit level (0-7); a fade from level a to level b at progress P
// (0-65535, the original's 16-bit fraction) shows
//     a + sign(b - a) * floor((2 |b - a| P + $10000) / $20000),
// and b once the fade is done (P >= 65536). Dim colours therefore reach
// black early, as on the original, instead of fading smoothly.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
// The cover's colour as levels (black: 0).
uniform vec3 cover = vec3(0.0);
// The fade's start and end: 0 the screen, 1 the cover, 2 (start only) an
// earlier fade stopped part way (mid_from -> the other end, at mid_p).
uniform int from_kind = 1;
uniform int to_kind = 1;
uniform int mid_from = 0;
uniform float mid_p = 0.0;
// Progress of this fade; 65536 or more: done.
uniform float p = 65536.0;
// An enhancement (MwScreenFader.smooth_fades, off: the original's): the
// colours interpolated smoothly instead of in 3-bit steps.
uniform bool smooth_fade = false;

vec3 faded(vec3 a, vec3 b, float pr) {
	if (pr >= 65536.0) {
		return b;
	}
	if (smooth_fade) {
		return mix(a, b, pr / 65536.0);
	}
	vec3 n = abs(b - a);
	return a + sign(b - a) * floor((2.0 * n * pr + 65536.0) / 131072.0);
}

void fragment() {
	vec3 v = texture(screen_tex, SCREEN_UV).rgb * 7.0;
	vec3 scr = smooth_fade ? v : round(v);    // the screen's levels
	vec3 a = from_kind == 0 ? scr : cover;
	if (from_kind == 2) {
		a = mid_from == 0 ? faded(scr, cover, mid_p) : faded(cover, scr, mid_p);
	}
	vec3 b = to_kind == 0 ? scr : cover;
	vec3 l = faded(a, b, p);
	// colours between levels (translucency, the 3D view) keep their offset
	// while their level is lit
	vec3 lit = step(0.5, l);
	COLOR = vec4(clamp((l + (v - scr) * lit) / 7.0, 0.0, 1.0), 1.0);
}
