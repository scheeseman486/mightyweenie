// The 3D rink's glass (plan 14): true translucency where the ROM's pictures
// dither glass. In the glass rows ([member glass_rows], picture rows) the
// glass colours of line 0 become translucent: [member glass_alpha] holds the
// alpha of colours 0, 4, 5 and 6; colours 0 and 5 take colour 5's tint (the
// near glass is a checker of colour 5 and colour 0). Frames and posts stay
// solid, including the posts' glass-coloured middles ([member post_cols] marks
// the posts' columns, [member post_rows] the rows where that applies); colour 0
// elsewhere is see-through, and colour 3 in [member clear_rows] (the signs
// picture's backdrop above its glass, around the posts' tips).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_never;
#include "res://src/rink3d/rink3d_common.gdshaderinc"

uniform sampler2D picture : filter_nearest, repeat_disable;
uniform vec4 glass_rows = vec4(40.0, 70.0, 808.0, 833.0);  // [start, end) twice
uniform vec4 glass_alpha = vec4(0.12, 0.5, 0.22, 0.32);     // colours 0, 4, 5, 6
uniform vec2 clear_rows = vec2(0.0, 0.0);                   // [start, end)
uniform sampler2D post_cols : filter_nearest, repeat_disable;  // w x 1, red 1 = a post's column
uniform vec2 post_rows = vec2(0.0, 0.0);                    // [start, end)

void fragment() {
	int i = indexed_at(picture, UV);
	float row = floor(UV.y * float(textureSize(picture, 0).y));
	bool glass = (row >= glass_rows.x && row < glass_rows.y) || (row >= glass_rows.z && row < glass_rows.w);
	if (glass && row >= post_rows.x && row < post_rows.y) {
		int w = textureSize(picture, 0).x;
		int col = clamp(int(floor(UV.x * float(w))), 0, w - 1);
		glass = texelFetch(post_cols, ivec2(col, 0), 0).r < 0.5;
	}
	if (glass && (i == 0 || i == 4 || i == 5 || i == 6)) {
		ALBEDO = colour_of(i == 0 ? 5 : i);
		ALPHA = i == 0 ? glass_alpha.x : (i == 4 ? glass_alpha.y : (i == 5 ? glass_alpha.z : glass_alpha.w));
	} else if (i % 16 == 0 || (i == 3 && row >= clear_rows.x && row < clear_rows.y)) {
		discard;
	} else {
		ALBEDO = colour_of(i);
		ALPHA = 1.0;
	}
}
