// A standing sprite frame's colours in the original's 2D order (plan 16: the
// calibration camera): no depth test, over the boards whatever their depth.
// See rink3d_sprite_body.gdshaderinc.
shader_type spatial;
#define ORDER_2D
#include "res://src/rink3d/rink3d_sprite_body.gdshaderinc"
