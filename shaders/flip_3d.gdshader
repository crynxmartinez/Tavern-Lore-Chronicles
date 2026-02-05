shader_type canvas_item;

uniform float flip_progress : hint_range(0.0, 1.0) = 0.0;
uniform bool flip_vertical = true;
uniform float perspective : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec2 uv = UV;
	
	// Calculate rotation angle (0 to PI)
	float angle = flip_progress * PI;
	
	// Center the UV
	vec2 centered_uv = uv - 0.5;
	
	if (flip_vertical) {
		// Vertical flip (top to bottom rotation)
		float cos_angle = cos(angle);
		float sin_angle = sin(angle);
		
		// Apply perspective based on Y position
		float perspective_factor = 1.0 + centered_uv.y * sin_angle * perspective;
		
		// Scale X based on rotation (creates the 3D illusion)
		centered_uv.x *= abs(cos_angle) + (1.0 - abs(cos_angle)) * 0.3;
		centered_uv.x /= perspective_factor;
		
		// Compress Y as it rotates
		centered_uv.y *= mix(1.0, 0.1, sin_angle * 0.5);
	} else {
		// Horizontal flip (left to right rotation)
		float cos_angle = cos(angle);
		float sin_angle = sin(angle);
		
		float perspective_factor = 1.0 + centered_uv.x * sin_angle * perspective;
		
		centered_uv.y *= abs(cos_angle) + (1.0 - abs(cos_angle)) * 0.3;
		centered_uv.y /= perspective_factor;
		
		centered_uv.x *= mix(1.0, 0.1, sin_angle * 0.5);
	}
	
	// Restore UV
	uv = centered_uv + 0.5;
	
	// Hide when flipped past 90 degrees (back of card)
	float visibility = step(0.0, cos(angle));
	
	// Clamp UV to avoid sampling outside texture
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		COLOR = texture(TEXTURE, uv);
		COLOR.a *= visibility;
	}
}
