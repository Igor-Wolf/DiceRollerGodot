extends Control
## Desenha os numeros (em branco, fundo transparente) do atlas de textura de um dado.
## O resultado vira uma mascara: o shader usa o alfa para pintar numero x corpo.

var labels: Array = []   # {text, center: Vector2, h: float, rot: float}
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if _font == null:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 0.5
		_font = fv
	for l in labels:
		var h: float = l["h"]
		var fs := int(round(h / 0.72))   # altura dos digitos ~ 0.72 do tamanho da fonte
		var txt: String = l["text"]
		var w: float = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_set_transform(l["center"], float(l["rot"]), Vector2.ONE)
		var base_y := h * 0.5
		draw_string(_font, Vector2(-w * 0.5, base_y), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		if txt.contains("6") or txt.contains("9"):   # sublinhado: evita confundir 6 com 9
			draw_rect(Rect2(-w * 0.5, base_y + h * 0.14, w, maxf(2.0, h * 0.09)), Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
