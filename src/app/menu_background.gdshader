shader_type canvas_item;
// Fondo del menú: silueta del mapamundi a partir del mapa de IDs de provincia.
uniform int first_sea_id = 1000000;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	int id = int(c.r * 255.0 + 0.5) + int(c.g * 255.0 + 0.5) * 256;
	float dist = c.b * 255.0;
	vec3 sea = mix(vec3(0.16, 0.22, 0.27), vec3(0.07, 0.10, 0.14), clamp(dist / 60.0, 0.0, 1.0));
	vec3 land = mix(vec3(0.42, 0.36, 0.25), vec3(0.55, 0.48, 0.34), clamp(dist / 30.0, 0.0, 1.0));
	vec3 col = id >= first_sea_id ? sea : land;
	COLOR = vec4(col, 1.0);
}
