extends Control
## Tela principal: area 3D (toque para rolar), botoes de dados, modificadores,
## menu de cores RGB e opcoes (incluindo chacoalhar o celular).

const FactoryScript = preload("res://scripts/dice_factory.gd")
const MesaScript = preload("res://scripts/mesa.gd")

const DIE_TYPES := ["d20", "d12", "d10", "d8", "d6", "d4"]
const MAX_DICE := 24
const SAVE_PATH := "user://dados_config.cfg"
const OP_SYMBOL := {"+": "+", "-": "−", "*": "×", "/": "÷"}
const OP_CODES := ["+", "-", "*", "/"]

# [corpo, numero]
const DEFAULT_COLORS := {
	"d20": [Color(0.05, 0.12, 0.30), Color(1.00, 0.84, 0.32)],
	"d12": [Color(0.88, 0.42, 0.06), Color(0.07, 0.04, 0.03)],
	"d10": [Color(0.38, 0.10, 0.58), Color(0.98, 0.92, 0.55)],
	"d8":  [Color(0.08, 0.28, 0.68), Color(0.96, 0.97, 1.00)],
	"d6":  [Color(0.62, 0.06, 0.08), Color(0.98, 0.82, 0.30)],
	"d4":  [Color(0.07, 0.42, 0.24), Color(1.00, 0.95, 0.80)],
}

var factory
var mesa

var _view: SubViewportContainer
var _vp: SubViewport
var _lbl_total: Label
var _lbl_detalhe: Label
var _lbl_mods: Label
var _carregando: Label
var _count_labels := {}
var _ov_cores: Dictionary
var _ov_mods: Dictionary
var _ov_opcoes: Dictionary

var _cores := {}                 # tipo -> {"corpo": Color, "numero": Color}
var _mods: Array = []            # [{"op": "+", "val": 2.0}, ...]
var _opts := {"d10_zero": true, "chacoalhar": true, "vibrar": true, "forca": 14.0, "arred": 0}

# menu de cores
var _cor_tipo := "d20"
var _rgb_corpo: Dictionary
var _rgb_num: Dictionary
var _prev_corpo: ColorRect
var _prev_num: Label

# menu de modificadores
var _mods_list: VBoxContainer
var _op_option: OptionButton
var _val_spin: SpinBox

# chacoalhar
var _grav := Vector3.ZERO
var _grav_ok := false
var _cool := 0.0


func _ready() -> void:
	_carregar()
	theme = _make_theme()
	_build_view()
	_build_ui()
	_build_overlays()

	_carregando = Label.new()
	_carregando.text = "Preparando dados..."
	_carregando.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_carregando.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_carregando)

	await factory.preparar()
	_carregando.queue_free()

	for t in DIE_TYPES:
		_aplicar_cor(t)
	mesa.d10_zero_vale_dez = _opts["d10_zero"]
	mesa.rolagem_iniciada.connect(_on_rolagem_iniciada)
	mesa.rolagem_concluida.connect(_on_rolagem_concluida)
	_vp.size_changed.connect(_on_vp_resized)
	_on_vp_resized()
	_atualizar_mods_ui()
	mesa.adicionar("d20")
	_update_counts()


# ===========================================================================
# Construcao da interface
# ===========================================================================
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 28
	t.set_stylebox("normal", "Button", _flat(Color(0.17, 0.21, 0.30), 16))
	t.set_stylebox("hover", "Button", _flat(Color(0.22, 0.27, 0.38), 16))
	t.set_stylebox("pressed", "Button", _flat(Color(0.30, 0.50, 0.85), 16))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", _flat(Color(0.08, 0.10, 0.15), 0))
	return t


func _flat(c: Color, r: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	sb.set_content_margin_all(10)
	return sb


func _btn(txt: String, cb: Callable, min_size: Vector2 = Vector2(0, 72)) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = min_size
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _build_view() -> void:
	factory = FactoryScript.new()
	add_child(factory)

	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE   # o toque e tratado em _input

	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_view.add_child(_vp)

	mesa = MesaScript.new()
	mesa.factory = factory
	_vp.add_child(mesa)


func _build_ui() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 0)
	add_child(vb)
	vb.add_child(_view)

	# --- painel inferior
	var panel := PanelContainer.new()
	vb.add_child(panel)
	var mg := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(mg)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	mg.add_child(col)

	_lbl_mods = Label.new()
	_lbl_mods.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_mods.add_theme_font_size_override("font_size", 24)
	col.add_child(_lbl_mods)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for t in DIE_TYPES:
		var c := VBoxContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_theme_constant_override("separation", 6)
		c.add_child(_btn("+", _on_add.bind(t), Vector2(0, 76)))
		var lb := Label.new()
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.add_theme_font_size_override("font_size", 26)
		c.add_child(lb)
		_count_labels[t] = lb
		c.add_child(_btn("-", _on_remove.bind(t), Vector2(0, 76)))
		row.add_child(c)

	var acoes := HBoxContainer.new()
	acoes.add_theme_constant_override("separation", 8)
	col.add_child(acoes)
	acoes.add_child(_btn("Rolar", _on_rolar, Vector2(0, 84)))
	acoes.add_child(_btn("Limpar", _on_limpar, Vector2(0, 84)))
	acoes.add_child(_btn("Cores", _abrir.bind("cores"), Vector2(0, 84)))
	acoes.add_child(_btn("Mods", _abrir.bind("mods"), Vector2(0, 84)))
	acoes.add_child(_btn("Opções", _abrir.bind("opcoes"), Vector2(0, 84)))

	# --- resultado (sobre a area 3D, nao captura toques)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.offset_top = 16
	add_child(top)
	_lbl_total = Label.new()
	_lbl_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_total.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_estilo_resultado(_lbl_total, 96, 14)
	top.add_child(_lbl_total)
	_lbl_detalhe = Label.new()
	_lbl_detalhe.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_detalhe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_detalhe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_estilo_resultado(_lbl_detalhe, 28, 8)
	top.add_child(_lbl_detalhe)
	_lbl_total.text = "Adicione dados"


func _estilo_resultado(l: Label, tam: int, contorno: int) -> void:
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", contorno)


func _make_overlay(titulo: String) -> Dictionary:
	var root_c := PanelContainer.new()
	root_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_c.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.98)
	root_c.add_theme_stylebox_override("panel", sb)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	root_c.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	m.add_child(vb)
	var title := Label.new()
	title.text = titulo
	title.add_theme_font_size_override("font_size", 40)
	vb.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	vb.add_child(_btn("Fechar", _fechar.bind(root_c), Vector2(0, 84)))
	add_child(root_c)
	return {"root": root_c, "content": content}


func _abrir(nome: String) -> void:
	match nome:
		"cores":
			(_ov_cores["root"] as Control).visible = true
		"mods":
			(_ov_mods["root"] as Control).visible = true
		"opcoes":
			(_ov_opcoes["root"] as Control).visible = true


func _fechar(root_c: Control) -> void:
	root_c.visible = false


func _overlay_aberto() -> bool:
	for ov in [_ov_cores, _ov_mods, _ov_opcoes]:
		if ov and (ov["root"] as Control).visible:
			return true
	return false


func _build_overlays() -> void:
	_build_ov_cores()
	_build_ov_mods()
	_build_ov_opcoes()


# ---------------------------------------------------------------- menu de cores
func _build_ov_cores() -> void:
	_ov_cores = _make_overlay("Cores dos dados")
	var c: VBoxContainer = _ov_cores["content"]

	var tipos := HBoxContainer.new()
	tipos.add_theme_constant_override("separation", 6)
	c.add_child(tipos)
	var grp := ButtonGroup.new()
	for t in DIE_TYPES:
		var b := Button.new()
		b.text = t.to_upper()
		b.toggle_mode = true
		b.button_group = grp
		b.custom_minimum_size = Vector2(0, 68)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(_selecionar_tipo_cor.bind(t))
		tipos.add_child(b)
		if t == _cor_tipo:
			b.button_pressed = true

	_prev_corpo = ColorRect.new()
	_prev_corpo.custom_minimum_size = Vector2(0, 120)
	c.add_child(_prev_corpo)
	_prev_num = Label.new()
	_prev_num.text = "20"
	_prev_num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prev_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prev_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prev_num.add_theme_font_size_override("font_size", 80)
	_prev_corpo.add_child(_prev_num)

	_rgb_corpo = _rgb_group(c, "Cor do dado")
	_rgb_num = _rgb_group(c, "Cor dos números")

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 8)
	c.add_child(linha)
	linha.add_child(_btn("Aleatória", _cor_aleatoria, Vector2(0, 72)))
	linha.add_child(_btn("Padrão", _cor_padrao, Vector2(0, 72)))
	c.add_child(_btn("Aplicar esta cor a todos os dados", _cor_aplicar_todos, Vector2(0, 72)))
	_selecionar_tipo_cor(_cor_tipo)


func _rgb_group(parent: Control, titulo: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	var lbl := Label.new()
	lbl.text = titulo
	box.add_child(lbl)
	var sliders: Array = []
	var vals: Array = []
	var nomes := ["R", "G", "B"]
	for i in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var ch := Label.new()
		ch.text = nomes[i]
		ch.custom_minimum_size = Vector2(36, 0)
		row.add_child(ch)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 255
		s.step = 1
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.custom_minimum_size = Vector2(0, 56)
		row.add_child(s)
		var v := Label.new()
		v.custom_minimum_size = Vector2(70, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(v)
		s.value_changed.connect(_on_rgb_slider.bind(v))
		sliders.append(s)
		vals.append(v)
	return {"sliders": sliders, "vals": vals}


func _on_rgb_slider(val: float, lbl: Label) -> void:
	lbl.text = str(int(val))
	_on_cor_alterada()


func _rgb_set(g: Dictionary, c: Color) -> void:
	var comps := [c.r, c.g, c.b]
	for i in 3:
		var val := int(round(float(comps[i]) * 255.0))
		(g["sliders"][i] as HSlider).set_value_no_signal(val)
		(g["vals"][i] as Label).text = str(val)


func _rgb_get(g: Dictionary) -> Color:
	var s: Array = g["sliders"]
	return Color8(int((s[0] as HSlider).value), int((s[1] as HSlider).value), int((s[2] as HSlider).value))


func _selecionar_tipo_cor(t: String) -> void:
	_cor_tipo = t
	_rgb_set(_rgb_corpo, _cores[t]["corpo"])
	_rgb_set(_rgb_num, _cores[t]["numero"])
	_atualizar_preview()


func _atualizar_preview() -> void:
	_prev_corpo.color = _cores[_cor_tipo]["corpo"]
	_prev_num.add_theme_color_override("font_color", _cores[_cor_tipo]["numero"])
	_prev_num.text = _cor_tipo.substr(1)


func _on_cor_alterada() -> void:
	_cores[_cor_tipo] = {"corpo": _rgb_get(_rgb_corpo), "numero": _rgb_get(_rgb_num)}
	_aplicar_cor(_cor_tipo)
	_atualizar_preview()
	_salvar()


func _aplicar_cor(t: String) -> void:
	factory.set_cores(t, _cores[t]["corpo"], _cores[t]["numero"])
	if _count_labels.has(t):
		(_count_labels[t] as Label).add_theme_color_override("font_color", _cor_legivel(_cores[t]["corpo"]))


func _cor_legivel(c: Color) -> Color:
	## cor do texto do contador: o proprio corpo do dado, clareado se for muito escuro
	if c.get_luminance() < 0.25:
		return c.lightened(0.55)
	return c


func _cor_aleatoria() -> void:
	var corpo := Color.from_hsv(randf(), randf_range(0.55, 0.95), randf_range(0.45, 0.90))
	var numero := Color(0.06, 0.05, 0.05) if corpo.get_luminance() > 0.45 else Color(1.0, 0.95, 0.80)
	_cores[_cor_tipo] = {"corpo": corpo, "numero": numero}
	_rgb_set(_rgb_corpo, corpo)
	_rgb_set(_rgb_num, numero)
	_aplicar_cor(_cor_tipo)
	_atualizar_preview()
	_salvar()


func _cor_padrao() -> void:
	var d: Array = DEFAULT_COLORS[_cor_tipo]
	_cores[_cor_tipo] = {"corpo": d[0], "numero": d[1]}
	_selecionar_tipo_cor(_cor_tipo)
	_aplicar_cor(_cor_tipo)
	_salvar()


func _cor_aplicar_todos() -> void:
	var atual: Dictionary = _cores[_cor_tipo]
	for t in DIE_TYPES:
		_cores[t] = {"corpo": atual["corpo"], "numero": atual["numero"]}
		_aplicar_cor(t)
	_salvar()


# ------------------------------------------------------- menu de modificadores
func _build_ov_mods() -> void:
	_ov_mods = _make_overlay("Modificadores")
	var c: VBoxContainer = _ov_mods["content"]
	var info := Label.new()
	info.text = "Aplicados na ordem, sobre a soma dos dados. Ex.: 12  +2  ×2  =  28"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 24)
	c.add_child(info)

	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 8)
	c.add_child(linha)
	_op_option = OptionButton.new()
	_op_option.custom_minimum_size = Vector2(0, 76)
	_op_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_op_option.add_item("+  Somar")
	_op_option.add_item("−  Subtrair")
	_op_option.add_item("×  Multiplicar")
	_op_option.add_item("÷  Dividir")
	linha.add_child(_op_option)
	_val_spin = SpinBox.new()
	_val_spin.min_value = -999
	_val_spin.max_value = 999
	_val_spin.step = 0.5
	_val_spin.value = 1
	_val_spin.custom_minimum_size = Vector2(190, 76)
	linha.add_child(_val_spin)
	c.add_child(_btn("Adicionar modificador", _on_add_mod, Vector2(0, 76)))

	_mods_list = VBoxContainer.new()
	_mods_list.add_theme_constant_override("separation", 8)
	c.add_child(_mods_list)


func _on_add_mod() -> void:
	var op: String = OP_CODES[_op_option.selected]
	var v: float = _val_spin.value
	if op == "/" and v == 0.0:
		return
	_mods.append({"op": op, "val": v})
	_atualizar_mods_ui()
	_salvar()
	_reexibir_resultado()


func _on_remove_mod(i: int) -> void:
	if i >= 0 and i < _mods.size():
		_mods.remove_at(i)
	_atualizar_mods_ui()
	_salvar()
	_reexibir_resultado()


func _mod_texto(m: Dictionary) -> String:
	return OP_SYMBOL[m["op"]] + _fmt(float(m["val"]))


func _atualizar_mods_ui() -> void:
	for ch in _mods_list.get_children():
		ch.queue_free()
	for i in _mods.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := Label.new()
		l.text = "%d.  %s" % [i + 1, _mod_texto(_mods[i])]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := _btn("Remover", _on_remove_mod.bind(i), Vector2(190, 64))
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(b)
		_mods_list.add_child(row)
	if _mods.is_empty():
		_lbl_mods.text = "Sem modificadores"
	else:
		var partes: Array = []
		for m in _mods:
			partes.append(_mod_texto(m))
		_lbl_mods.text = "Modificadores:  " + "   ".join(partes)


# ------------------------------------------------------------------- opcoes
func _build_ov_opcoes() -> void:
	_ov_opcoes = _make_overlay("Opções")
	var c: VBoxContainer = _ov_opcoes["content"]

	c.add_child(_check("Chacoalhar o celular para rolar", _opts["chacoalhar"], _set_opt.bind("chacoalhar")))
	var lf := Label.new()
	lf.text = "Força necessária para chacoalhar: %d" % int(_opts["forca"])
	c.add_child(lf)
	var sf := HSlider.new()
	sf.min_value = 6
	sf.max_value = 30
	sf.step = 1
	sf.value = _opts["forca"]
	sf.custom_minimum_size = Vector2(0, 56)
	sf.value_changed.connect(_on_forca.bind(lf))
	c.add_child(sf)

	c.add_child(_check("Vibrar ao terminar a rolagem", _opts["vibrar"], _set_opt.bind("vibrar")))
	c.add_child(_check("D10: o número 0 vale 10", _opts["d10_zero"], _on_d10_zero))

	var la := Label.new()
	la.text = "Arredondamento das divisões"
	c.add_child(la)
	var oa := OptionButton.new()
	oa.custom_minimum_size = Vector2(0, 76)
	oa.add_item("Para baixo")
	oa.add_item("Para cima")
	oa.add_item("Mais próximo")
	oa.selected = int(_opts["arred"])
	oa.item_selected.connect(_on_arred)
	c.add_child(oa)


func _set_opt(valor, chave: String) -> void:
	_opts[chave] = valor
	_salvar()


func _on_forca(v: float, lbl: Label) -> void:
	_opts["forca"] = v
	lbl.text = "Força necessária para chacoalhar: %d" % int(v)
	_salvar()


func _on_d10_zero(on: bool) -> void:
	_opts["d10_zero"] = on
	mesa.d10_zero_vale_dez = on
	_salvar()
	_reexibir_resultado()


func _on_arred(i: int) -> void:
	_opts["arred"] = i
	_salvar()
	_reexibir_resultado()


func _check(txt: String, on: bool, cb: Callable) -> CheckButton:
	var cbn := CheckButton.new()
	cbn.text = txt
	cbn.custom_minimum_size = Vector2(0, 76)
	cbn.set_pressed_no_signal(on)
	cbn.toggled.connect(cb)
	return cbn


# ===========================================================================
# Acoes
# ===========================================================================
func _on_add(t: String) -> void:
	if mesa.dados.size() >= MAX_DICE:
		return
	mesa.adicionar(t)
	_update_counts()


func _on_remove(t: String) -> void:
	if mesa.contar(t) == 0:
		return
	mesa.remover(t)
	_update_counts()
	if not mesa.rolando:
		_reexibir_resultado()


func _on_limpar() -> void:
	mesa.limpar()
	_update_counts()
	_reexibir_resultado()


func _on_rolar() -> void:
	mesa.rolar()


func _update_counts() -> void:
	for t in DIE_TYPES:
		(_count_labels[t] as Label).text = "%s\n×%d" % [t.to_upper(), mesa.contar(t)]


func _on_vp_resized() -> void:
	mesa.ajustar(Vector2(_vp.size))


func _on_rolagem_iniciada() -> void:
	_lbl_total.text = "..."
	_lbl_detalhe.text = ""


func _on_rolagem_concluida(res: Array) -> void:
	_mostrar_resultado(res)
	if _opts["vibrar"] and OS.has_feature("mobile"):
		Input.vibrate_handheld(60)


func _reexibir_resultado() -> void:
	if mesa.rolando:
		return
	_mostrar_resultado(mesa.resultados())


# ===========================================================================
# Resultado e modificadores
# ===========================================================================
func _arredondar(x: float) -> float:
	match int(_opts["arred"]):
		1:
			return ceilf(x)
		2:
			return roundf(x)
	return floorf(x)


func _fmt(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	return "%.1f" % x


func _mostrar_resultado(res: Array) -> void:
	if res.is_empty():
		_lbl_total.text = "Adicione dados"
		_lbl_detalhe.text = ""
		return
	var por_tipo := {}
	var soma := 0
	for r in res:
		if not por_tipo.has(r["tipo"]):
			por_tipo[r["tipo"]] = []
		por_tipo[r["tipo"]].append(int(r["valor"]))
		soma += int(r["valor"])

	var linhas: Array = []
	for t in DIE_TYPES:
		if por_tipo.has(t):
			var vs: Array = []
			for v in por_tipo[t]:
				vs.append(str(v))
			linhas.append("%s: %s" % [t.to_upper(), " + ".join(vs)])

	var total := float(soma)
	var passos := "Soma %d" % soma
	for m in _mods:
		var v: float = m["val"]
		match m["op"]:
			"+":
				total += v
			"-":
				total -= v
			"*":
				total *= v
			"/":
				if v != 0.0:
					total = _arredondar(total / v)
		passos += "  " + _mod_texto(m) + " = " + _fmt(total)
	_lbl_total.text = _fmt(total)
	var detalhe := "   ".join(linhas)
	if not _mods.is_empty():
		detalhe += "\n" + passos
	_lbl_detalhe.text = detalhe


# ===========================================================================
# Entrada: toque, tecla, chacoalhar
# ===========================================================================
func _input(event: InputEvent) -> void:
	if mesa == null or _overlay_aberto():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# so a area 3D (toque emulado a partir do touch no celular)
		if _view.get_global_rect().has_point(event.position):
			mesa.rolar()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		mesa.rolar()


func _process(delta: float) -> void:
	_cool -= delta
	if mesa == null or not _opts["chacoalhar"] or _cool > 0.0 or _overlay_aberto():
		return
	var a := Input.get_accelerometer()
	if a == Vector3.ZERO:
		return
	if not _grav_ok:
		_grav = a
		_grav_ok = true
	_grav = _grav.lerp(a, 0.08)          # filtro passa-baixa = gravidade
	var linear := a - _grav               # o que sobra e o movimento da mao
	if linear.length() > float(_opts["forca"]):
		_cool = 0.9
		mesa.rolar()


# ===========================================================================
# Persistencia
# ===========================================================================
func _carregar() -> void:
	for t in DIE_TYPES:
		var d: Array = DEFAULT_COLORS[t]
		_cores[t] = {"corpo": d[0], "numero": d[1]}
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for t in DIE_TYPES:
		_cores[t] = {
			"corpo": cf.get_value("cores", t + "_corpo", _cores[t]["corpo"]),
			"numero": cf.get_value("cores", t + "_numero", _cores[t]["numero"]),
		}
	for k in _opts.keys():
		_opts[k] = cf.get_value("opcoes", k, _opts[k])
	var ms = cf.get_value("mods", "lista", [])
	if ms is Array:
		_mods = ms


func _salvar() -> void:
	var cf := ConfigFile.new()
	for t in DIE_TYPES:
		cf.set_value("cores", t + "_corpo", _cores[t]["corpo"])
		cf.set_value("cores", t + "_numero", _cores[t]["numero"])
	for k in _opts.keys():
		cf.set_value("opcoes", k, _opts[k])
	cf.set_value("mods", "lista", _mods)
	cf.save(SAVE_PATH)
