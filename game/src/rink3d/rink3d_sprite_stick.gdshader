// A standing sprite frame's stick shadow, kept on the billboard beside the
// stick (owner, 2026-10-09: MwFlatShadows.ON_STICK), in the shade colour but
// never lighter than what is behind it: see rink3d_sprite_body.gdshaderinc.
shader_type spatial;
#define STICK_PASS
#include "res://src/rink3d/rink3d_sprite_body.gdshaderinc"
