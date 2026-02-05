shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.9, 0.3, 1.0);
uniform float pulse_speed : hint_range(0.5, 5.0) = 2.5;
uniform float glow_intensity : hint_range(0.1, 1.0) = 0.6;
uniform float ring_radius : hint_range(0.3, 0.5) = 0.42;
uniform float ring_width : hint_range(0.05, 0.3) = 0.15;

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center);
	
	// Pulsing effect
	float pulse = sin(TIME * pulse_speed) * 0.2 + 0.8;
	
	// Create ring glow (not filled circle)
	float ring_dist = abs(dist - ring_radius);
	float ring_alpha = exp(-ring_dist * (1.0 / ring_width) * 3.0);
	
	// Outer edge fade
	float outer_fade = 1.0 - smoothstep(ring_radius + ring_width, 0.5, dist);
	
	// Inner transparency (keep center clear to see hero)
	float inner_clear = smoothstep(ring_radius - ring_width * 1.5, ring_radius - ring_width * 0.5, dist);
	
	// Combine effects
	float final_alpha = ring_alpha * outer_fade * inner_clear * glow_intensity * pulse;
	
	// Apply color with calculated alpha
	COLOR = vec4(glow_color.rgb, final_alpha * glow_color.a);
}
