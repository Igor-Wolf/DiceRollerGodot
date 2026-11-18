extends Node3D
## A mesa de rolagem: camera de cima, piso, paredes e teto invisiveis (limitador),
## fisica dos dados e deteccao de quando tudo parou.

const DieScript = preload("res://scripts/die.gd")

signal rolagem_iniciada
signal rolagem_concluida(resultados: Array)

const FOV := 50              # campo de visao HORIZONTAL (camera KEEP_WIDTH)
const CAMPO_LARGURA := 5        # metade da largura visivel no piso (unidades do mundo) configura a altura da camera com os dados
const ALTURA_PAREDE := 8.0
const TETO := 8                 # altura maxima que os dados alcancam
const MAX_ESPERA := 9.0           # segundos; depois disso aceita o resultado
const MAX_TENTATIVAS := 3         # re-empurroes em dados "cocados" (inclinados)

var factory
var dados: Array = []
var campo := Vector2(2.5, 3.0)    # metade da area util (x, z)
var rolando := false
var d10_zero_vale_dez := true

var _t := 0.0
var _tentativas := 0
var _cam: Camera3D
var _cs_piso: CollisionShape3D
var _cs_teto: CollisionShape3D
var _cs_norte: CollisionShape3D
var _cs_sul: CollisionShape3D
var _cs_oeste: CollisionShape3D
var _cs_leste: CollisionShape3D


func _ready() -> void:
	_montar_ambiente()
	_montar_fisica()
	ajustar(Vector2(720.0, 880.0))


# ---------------------------------------------------------------------------
# Montagem
# ---------------------------------------------------------------------------
func _montar_ambiente() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.10, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62.0, -30.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 18.0
	add_child(sun)

	# piso visual (feltro)
	var piso := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60.0, 60.0)
	piso.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.07, 0.30, 0.19)
	fm.roughness = 0.95
	piso.material_override = fm
	add_child(piso)

	# camera olhando de cima; +Z fica para baixo na tela
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = FOV
	_cam.near = 0.1
	_cam.far = 60.0
	add_child(_cam)
	var h := CAMPO_LARGURA / tan(deg_to_rad(FOV * 0.5))
	_cam.position = Vector3(0.0, h, 0.0)
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_cam.current = true


func _criar_corpo(nome: String, quique: float) -> CollisionShape3D:
	var body := StaticBody3D.new()
	body.name = nome
	var pm := PhysicsMaterial.new()
	pm.bounce = quique
	pm.friction = 0.8
	body.physics_material_override = pm
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	body.add_child(cs)
	add_child(body)
	return cs


func _montar_fisica() -> void:
	_cs_piso = _criar_corpo("Piso", 0.15)
	_cs_teto = _criar_corpo("Teto", 0.3)
	_cs_norte = _criar_corpo("ParedeNorte", 0.4)
	_cs_sul = _criar_corpo("ParedeSul", 0.4)
	_cs_oeste = _criar_corpo("ParedeOeste", 0.4)
	_cs_leste = _criar_corpo("ParedeLeste", 0.4)


func _set_box(cs: CollisionShape3D, tamanho: Vector3, pos: Vector3) -> void:
	(cs.shape as BoxShape3D).size = tamanho
	(cs.get_parent() as Node3D).position = pos


func ajustar(tamanho: Vector2) -> void:
	## Chamado quando a area 3D muda de tamanho: refaz o limitador para casar com a tela.
	if tamanho.x < 8.0 or tamanho.y < 8.0:
		return   # area ainda sem tamanho (layout nao terminou)
	var aspecto := tamanho.x / tamanho.y
	campo = Vector2(CAMPO_LARGURA * 0.95, CAMPO_LARGURA / aspecto * 0.95)
	var hw := campo.x
	var hd := campo.y
	var gx := hw * 2.0 + 6.0
	var gz := hd * 2.0 + 6.0
	_set_box(_cs_piso, Vector3(gx, 1.0, gz), Vector3(0.0, -0.5, 0.0))
	_set_box(_cs_teto, Vector3(gx, 1.0, gz), Vector3(0.0, TETO + 0.5, 0.0))
	_set_box(_cs_norte, Vector3(gx, ALTURA_PAREDE, 1.0), Vector3(0.0, ALTURA_PAREDE * 0.5, -hd - 0.5))
	_set_box(_cs_sul, Vector3(gx, ALTURA_PAREDE, 1.0), Vector3(0.0, ALTURA_PAREDE * 0.5, hd + 0.5))
	_set_box(_cs_oeste, Vector3(1.0, ALTURA_PAREDE, gz), Vector3(-hw - 0.5, ALTURA_PAREDE * 0.5, 0.0))
	_set_box(_cs_leste, Vector3(1.0, ALTURA_PAREDE, gz), Vector3(hw + 0.5, ALTURA_PAREDE * 0.5, 0.0))
	# se a area diminuiu (ex.: girou a tela), traz dados que ficaram de fora
	for d in dados:
		var p: Vector3 = d.position
		var q := Vector3(clampf(p.x, -hw + 0.8, hw - 0.8), maxf(p.y, 0.8), clampf(p.z, -hd + 0.8, hd - 0.8))
		if q != p:
			d.position = q
			d.sleeping = false


# ---------------------------------------------------------------------------
# Dados
# ---------------------------------------------------------------------------
func contar(tipo: String) -> int:
	var n := 0
	for d in dados:
		if d.tipo == tipo:
			n += 1
	return n


func adicionar(tipo: String) -> void:
	var d = DieScript.new()
	d.configurar(factory.tipos[tipo])
	d.position = Vector3(randf_range(-campo.x + 1.0, campo.x - 1.0), randf_range(2.4, 3.4),
			randf_range(-campo.y + 1.0, campo.y - 1.0))
	d.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	add_child(d)
	d.linear_velocity = Vector3(0.0, -2.0, 0.0)
	d.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	dados.append(d)
	_iniciar_estado()


func remover(tipo: String) -> void:
	for i in range(dados.size() - 1, -1, -1):
		if dados[i].tipo == tipo:
			var d = dados[i]
			dados.remove_at(i)
			d.queue_free()
			return


func limpar() -> void:
	for d in dados:
		d.queue_free()
	dados.clear()
	rolando = false


func rolar() -> void:
	## "Pulo/rolagem": os dados que ja estao na mesa sao lancados de novo.
	if dados.is_empty():
		return
	for d in dados:
		d.pular(1.0)
	_iniciar_estado()


func _iniciar_estado() -> void:
	rolando = true
	_t = 0.0
	_tentativas = 0
	rolagem_iniciada.emit()


# ---------------------------------------------------------------------------
# Resultado
# ---------------------------------------------------------------------------
func resultados() -> Array:
	var out: Array = []
	for d in dados:
		var r: Dictionary = d.ler()
		var v: int = r["valor"]
		if d.tipo == "d10" and v == 0 and d10_zero_vale_dez:
			v = 10
		out.append({"tipo": d.tipo, "valor": v})
	return out


func _physics_process(delta: float) -> void:
	if not rolando:
		return
	_t += delta
	if _t < 0.4:
		return
	var parados := true
	for d in dados:
		if not d.sleeping:
			parados = false
			break
	if not parados and _t < MAX_ESPERA:
		return
	# dados "cocados" (apoiados em outro dado/parede) ganham um novo empurrao
	if _t < MAX_ESPERA and _tentativas < MAX_TENTATIVAS:
		var inclinados: Array = []
		for d in dados:
			var r: Dictionary = d.ler()
			if float(r["alinhamento"]) < 0.97:
				inclinados.append(d)
		if inclinados.size() > 0:
			_tentativas += 1
			for d in inclinados:
				d.pular(0.45)
			_t = 0.0
			return
	rolando = false
	rolagem_concluida.emit(resultados())
