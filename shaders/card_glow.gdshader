shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform float glow_intensity : hint_range(0.0, 3.0) = 0.0;
uniform float glow_size : hint_range(0.0, 20.0) = 4.0;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.0;
uniform bool enable_pulse = true;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    // Calculate glow based on alpha edges
    float alpha = tex_color.a;
    
    // Sample surrounding pixels for edge detection
    vec2 pixel_size = 1.0 / vec2(textureSize(TEXTURE, 0));
    float outline = 0.0;
    
    for (float x = -glow_size; x <= glow_size; x += 1.0) {
        for (float y = -glow_size; y <= glow_size; y += 1.0) {
            vec2 offset = vec2(x, y) * pixel_size;
            float dist = length(vec2(x, y));
            if (dist <= glow_size) {
                float sample_alpha = texture(TEXTURE, UV + offset).a;
                outline = max(outline, sample_alpha * (1.0 - dist / glow_size));
            }
        }
    }
    
    // Pulse effect
    float pulse = 1.0;
    if (enable_pulse && glow_intensity > 0.0) {
        pulse = 0.7 + 0.3 * sin(TIME * pulse_speed);
    }
    
    // Apply glow
    float glow = outline * glow_intensity * pulse * (1.0 - alpha);
    vec4 final_color = tex_color;
    final_color.rgb = mix(tex_color.rgb, glow_color.rgb, glow * 0.5);
    final_color.a = max(tex_color.a, glow * glow_color.a);
    
    COLOR = final_color;
}
