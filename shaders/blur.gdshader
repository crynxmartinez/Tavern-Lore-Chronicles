shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 5.0) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 pixel_size = SCREEN_PIXEL_SIZE;
	
	// Simple 9-sample box blur with fixed offsets
	vec4 color = texture(screen_texture, SCREEN_UV);
	
	if (blur_amount > 0.0) {
		vec2 offset = pixel_size * blur_amount;
		
		// Sample 8 surrounding pixels + center
		color = texture(screen_texture, SCREEN_UV) * 0.25;
		color += texture(screen_texture, SCREEN_UV + vec2(-offset.x, -offset.y)) * 0.0625;
		color += texture(screen_texture, SCREEN_UV + vec2(0.0, -offset.y)) * 0.125;
		color += texture(screen_texture, SCREEN_UV + vec2(offset.x, -offset.y)) * 0.0625;
		color += texture(screen_texture, SCREEN_UV + vec2(-offset.x, 0.0)) * 0.125;
		color += texture(screen_texture, SCREEN_UV + vec2(offset.x, 0.0)) * 0.125;
		color += texture(screen_texture, SCREEN_UV + vec2(-offset.x, offset.y)) * 0.0625;
		color += texture(screen_texture, SCREEN_UV + vec2(0.0, offset.y)) * 0.125;
		color += texture(screen_texture, SCREEN_UV + vec2(offset.x, offset.y)) * 0.0625;
	}
	
	COLOR = color;
}
