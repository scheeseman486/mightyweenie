// The stands under the crowd (plan 15, docs/rink3d.md, Crowd): treads,
// risers and seat bars in the crowd's colours (palette line 1), dark as the
// picture's background between the figures. COLOR.r says which surface
// (x 4): 0 tread, 1 riser (black), 2 a seat bar's face, 3 its top. UV is in rink px along and down the surface: a
// seat face is the picture's seat drawing, 2 rows checker of dark grey and
// black, 3 rows dark grey, a 1 row grey rim; its top is the checker. The top
// rows fade to black; the game's cameras cut away what would hide the play
// (rink3d_stands_common).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://src/rink3d/rink3d_common.gdshaderinc"
#include "res://src/rink3d/rink3d_stands_common.gdshaderinc"

const int BLACK = 31;
const int DARK_GREY = 30;
const int GREY = 29;

void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (stands_cut(w)) {
		discard;
	}
	int kind = int(round(COLOR.r * 4.0));
	ivec2 p = ivec2(floor(UV));
	bool odd = ((p.x + p.y) & 1) == 1;
	int c = BLACK;
	if (kind == 2) {
		c = p.y < 2 ? (odd ? BLACK : DARK_GREY) : (p.y < 5 ? DARK_GREY : GREY);
	} else if (kind == 3) {
		c = odd ? BLACK : DARK_GREY;
	}
	ALBEDO = colour_of(c) * stands_fade(w.y);
}
