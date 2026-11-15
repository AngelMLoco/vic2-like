shader_type canvas_item;
// Mapamundi del modo Victoria.
// id_map (= textura del sprite) = mapa de IDs: id = R + G*256 ; B = distancia a la costa (px).
// color_lut  : color de cada provincia para el mapmode activo (alpha 0 en mar = sombreado por defecto).
// info_lut   : RG = índice de propietario, BA = id de estado (para distinguir fronteras).
// overlay_lut: color del controlador si la provincia está ocupada (alpha 1) → rayado.

uniform sampler2D id_map : filter_nearest;
uniform sampler2D color_lut : filter_nearest;
uniform sampler2D info_lut : filter_nearest;
uniform sampler2D overlay_lut : filter_nearest;
uniform vec2 map_size = vec2(5632.0, 2624.0);
uniform int first_sea_id = 100000;
uniform int selected_id = -1;
uniform int hover_id = -1;
uniform int selected_owner = -1;
uniform float province_border_alpha = 0.25;
uniform float state_border_alpha = 0.55;
uniform float time_s = 0.0;

const vec2 DIRS[4] = vec2[](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));

int decode16(float a, float b) {
	return int(a * 255.0 + 0.5) + int(b * 255.0 + 0.5) * 256;
}

int pid(vec2 p) {
	int w = int(map_size.x);
	int x = int(floor(p.x));
	x = ((x % w) + w) % w;
	int y = clamp(int(floor(p.y)), 0, int(map_size.y) - 1);
	vec4 c = texelFetch(id_map, ivec2(x, y), 0);
	return decode16(c.r, c.g);
}

vec4 lut(sampler2D t, int id) {
	return texelFetch(t, ivec2(id % 256, id / 256), 0);
}

int owner_of(int id) {
	vec4 i = lut(info_lut, id);
	return decode16(i.r, i.g);
}

int state_of(int id) {
	vec4 i = lut(info_lut, id);
	return decode16(i.b, i.a);
}

void fragment() {
	vec2 p = UV * map_size;
	vec4 raw = texelFetch(id_map, ivec2(clamp(floor(p), vec2(0.0), map_size - 1.0)), 0);
	int id = decode16(raw.r, raw.g);
	float dist = raw.b * 255.0;
	vec2 fw = fwidth(p);
	float spp = max(max(fw.x, fw.y), 0.0001); // texels por píxel de pantalla
	bool water = id >= first_sea_id;
	vec4 base = lut(color_lut, id);
	vec3 col;
	if (water) {
		vec3 deep = vec3(0.090, 0.150, 0.215);
		vec3 shallow = vec3(0.215, 0.335, 0.405);
		col = mix(shallow, deep, smoothstep(0.0, 45.0, dist));
		float wave = sin(p.x * 0.045 + p.y * 0.03 + dist * 0.45);
		col += 0.012 * wave * (1.0 - smoothstep(0.0, 30.0, dist));
		if (base.a > 0.5) {
			col = mix(col, base.rgb, 0.55);
		}
	} else {
		col = base.rgb;
		float n = fract(sin(dot(floor(p * 0.5), vec2(12.9898, 78.233))) * 43758.5453);
		col *= 0.965 + 0.05 * n;
		col = mix(col * 0.82, col, smoothstep(0.0, 4.0, dist));
		vec4 ov = lut(overlay_lut, id);
		if (ov.a > 0.5) {
			float period = max(spp * 9.0, 0.8);
			if (mod((p.x + p.y) / period, 2.0) < 1.0) {
				col = mix(col, ov.rgb, 0.8);
			}
		}
	}

	int own = water ? -1 : owner_of(id);
	int st = water ? -1 : state_of(id);
	float b_country = 0.0;
	float b_state = 0.0;
	float b_prov = 0.0;
	float b_coast = 0.0;
	float b_sel = 0.0;
	for (int i = 0; i < 4; i++) {
		int n1 = pid(p + DIRS[i] * spp * 1.0);
		int n2 = pid(p + DIRS[i] * spp * 2.0);
		if (n1 != id) {
			bool nwater = n1 >= first_sea_id;
			if (water != nwater) {
				b_coast = 1.0;
			} else if (!water) {
				int on = owner_of(n1);
				if (on != own) {
					b_country = 1.0;
				} else if (state_of(n1) != st) {
					b_state = 1.0;
				} else {
					b_prov = 1.0;
				}
			} else {
				b_prov = max(b_prov, 0.45);
			}
			if (id == selected_id || n1 == selected_id) {
				b_sel = 1.0;
			}
		}
		if (n2 != id && !water && n2 < first_sea_id && owner_of(n2) != own) {
			b_country = max(b_country, 0.75);
		}
		if (n2 != id && (id == selected_id || n2 == selected_id)) {
			b_sel = max(b_sel, 0.8);
		}
	}

	if (id == hover_id && !water) {
		col = mix(col, vec3(1.0), 0.12);
	}
	if (id == selected_id) {
		col = mix(col, vec3(1.0, 0.95, 0.75), 0.18 + 0.06 * sin(time_s * 4.0));
	} else if (selected_owner >= 0 && own == selected_owner) {
		col = mix(col, vec3(1.0, 0.97, 0.85), 0.07);
	}

	col = mix(col, col * 0.45, b_prov * province_border_alpha);
	col = mix(col, vec3(0.10, 0.08, 0.06), b_state * state_border_alpha);
	col = mix(col, vec3(0.06, 0.08, 0.10), b_coast * 0.85);
	col = mix(col, vec3(0.05, 0.04, 0.03), b_country * 0.92);
	col = mix(col, vec3(1.0, 0.86, 0.35), b_sel);
	COLOR = vec4(col, 1.0);
}
