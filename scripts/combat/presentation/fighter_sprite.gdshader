// Fighter sprite: fixed-Y billboard, nearest filtering and alpha-cut discard (like a Sprite3D with
// billboard FIXED_Y, texture_filter NEAREST and alpha_cut DISCARD), plus the white flash, wind-up
// glow and greyed-out (downed) looks the combat presentation needs.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.45, 0.2, 1.0);
uniform float glow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float grey_amount : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
			MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 texel = texture(sprite_texture, UV);
	if (texel.a < alpha_cut) {
		discard;
	}
	vec3 color = texel.rgb * tint.rgb;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(luma * 0.6), grey_amount);
	color += glow_color.rgb * glow_amount * 0.6;
	color = mix(color, flash_color.rgb, flash_amount);
	ALBEDO = color;
}
