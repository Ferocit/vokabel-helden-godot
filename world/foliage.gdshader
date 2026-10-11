// Urwald-Sprites (Bäume, Büsche): Pixel-Art mit harter Alphakante. Was zwischen Kamera und Held steht
// und auf dem Bildschirm nahe am Helden liegt, wird per geordnetem Dithering durchsichtig –
// so bleibt der Held sichtbar, ohne den Pixel-Look durch weiche Transparenz zu verwischen.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_nearest;
// Weltposition des Helden (Brusthöhe); weit weg = Effekt aus (Titel, Kampf).
global uniform vec3 player_world;
// Radius des Sichtfensters in Bildschirmhöhen.
uniform float reveal_radius = 0.16;
// Anteil der Pixel, die in der Mitte des Fensters entfallen.
uniform float reveal_strength = 0.8;

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * COLOR.rgb;
	ROUGHNESS = 0.92;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	vec4 pv = VIEW_MATRIX * vec4(player_world, 1.0);
	// Nur was näher an der Kamera ist als der Held (Blickrichtung ist -Z im View-Space).
	if (pv.z < 0.0 && VERTEX.z > pv.z + 0.35) {
		vec4 pc = PROJECTION_MATRIX * pv;
		vec4 fc = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
		vec2 d = fc.xy / fc.w - pc.xy / pc.w;
		d.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
		// NDC-Höhe ist 2, daher Radius verdoppeln.
		float dist = length(d) / 2.0;
		float fade = (1.0 - smoothstep(reveal_radius * 0.55, reveal_radius, dist)) * reveal_strength;
		if (fade > bayer4(FRAGCOORD.xy)) {
			discard;
		}
	}
}
