shader_type spatial;

// Cor do corpo e dos numeros (ja em espaco linear; o script converte do sRGB).
uniform vec3 body_color = vec3(0.1, 0.2, 0.5);
uniform vec3 num_color = vec3(1.0, 0.85, 0.3);
// Mascara dos numeros (canal alfa) gerada em tempo de execucao.
uniform sampler2D mask : filter_linear;
// Se os numeros aparecerem de cabeca para baixo, mude para true (ou FLIP_V em dice_factory.gd).
uniform bool flip_v = false;
uniform float body_roughness = 0.50;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec2 uv = UV;
	if (flip_v) {
		uv.y = 1.0 - uv.y;
	}
	float m = texture(mask, uv).a;
	// leve efeito "marmorizado" de resina
	float marble = 0.5 + 0.5 * sin(lpos.x * 9.0 + 2.5 * sin(lpos.y * 6.0 + lpos.z * 4.0));
	vec3 body = body_color * (0.86 + 0.14 * marble);
	ALBEDO = mix(body, num_color, m);
	ROUGHNESS = mix(body_roughness, 0.5, m);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	RIM = 0.15;
	RIM_TINT = 0.5;
}
