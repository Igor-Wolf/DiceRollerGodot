extends Node
## Cria, uma unica vez, tudo que cada TIPO de dado precisa: mesh, forma de colisao,
## mascara de numeros (SubViewport) e material (shader com cores ajustaveis).

const DiceGeometry = preload("res://scripts/dice_geometry.gd")
const AtlasCanvas = preload("res://scripts/atlas_canvas.gd")
const DieShader = preload("res://shaders/dado.gdshader")

const TYPES := ["d20", "d12", "d10", "d8", "d6", "d4"]
# Raio circunscrito de cada dado, em unidades do mundo (ajuste para dados maiores/menores).
const RADIUS := {"d4": 0.78, "d6": 0.80, "d8": 0.74, "d10": 0.78, "d12": 0.72, "d20": 0.80}
const CELL := 160          # pixels por face no atlas de numeros
const FLIP_V := false      # coloque true se os numeros aparecerem de cabeca para baixo

var tipos: Dictionary = {}


func preparar() -> void:
	for nome in TYPES:
		_criar_tipo(nome)
	# espera os atlas de numeros serem desenhados
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _criar_tipo(nome: String) -> void:
	var data := DiceGeometry.build(nome, RADIUS[nome], CELL)

	# --- mesh
	var arr := DiceGeometry.mesh_arrays(data)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = arr["verts"]
	arrays[Mesh.ARRAY_NORMAL] = arr["norms"]
	arrays[Mesh.ARRAY_TEX_UV] = arr["uvs"]
	arrays[Mesh.ARRAY_INDEX] = arr["idx"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# --- colisao (casco convexo)
	var verts := PackedVector3Array(data["V"])
	var shape := ConvexPolygonShape3D.new()
	shape.points = verts

	# --- atlas de numeros
	var vp := SubViewport.new()
	vp.size = Vector2i(int(data["W"]), int(data["H"]))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := AtlasCanvas.new()
	canvas.labels = DiceGeometry.canvas_labels(data)
	canvas.size = Vector2(float(data["W"]), float(data["H"]))
	vp.add_child(canvas)
	add_child(vp)

	# --- material
	var mat := ShaderMaterial.new()
	mat.shader = DieShader
	mat.set_shader_parameter("mask", vp.get_texture())
	mat.set_shader_parameter("flip_v", FLIP_V)

	var fnormals := PackedVector3Array()
	for fr in data["frames"]:
		fnormals.append(fr["n"])

	tipos[nome] = {
		"nome": nome,
		"mesh": mesh,
		"shape": shape,
		"material": mat,
		"verts": verts,
		"face_normals": fnormals,
		"face_values": PackedInt32Array(data["values"]),
	}


func set_cores(nome: String, corpo: Color, numero: Color) -> void:
	if not tipos.has(nome):
		return
	var mat: ShaderMaterial = tipos[nome]["material"]
	var c := corpo.srgb_to_linear()
	var n := numero.srgb_to_linear()
	mat.set_shader_parameter("body_color", Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("num_color", Vector3(n.r, n.g, n.b))
