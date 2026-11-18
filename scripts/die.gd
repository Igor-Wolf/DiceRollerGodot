extends RigidBody3D
## Um dado fisico. Sabe ler qual face (ou vertice, no D4) esta para cima.

var tipo: String = ""
var info: Dictionary = {}
var roller_power: float = 2


func configurar(i: Dictionary) -> void:
	info = i
	tipo = i["nome"]
	var mi := MeshInstance3D.new()
	mi.mesh = i["mesh"]
	mi.material_override = i["material"]
	add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = i["shape"]
	add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.2
	pm.friction = 0.6
	physics_material_override = pm
	mass = 1.0
	continuous_cd = true
	linear_damp = 0.15
	angular_damp = 0.5
	can_sleep = true


func pular(forca: float = 1.0) -> void:
	## "Pulo": impulso para cima + giro aleatorio + leve tendencia ao centro da mesa.
	sleeping = false
	var lateral := Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	var para_centro := Vector3(-position.x, 0.0, -position.z) * 0.6
	var cima := Vector3(0.0, randf_range(8.0, 11.0), 0.0) 
	apply_central_impulse((cima + lateral + para_centro) * forca * mass * roller_power)
	var eixo := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	apply_torque_impulse(eixo * randf_range(1.5, 3.5) * forca)


func ler() -> Dictionary:
	## {"valor": int, "alinhamento": float}  (alinhamento 1.0 = apoiado certinho)
	var b := global_transform.basis
	if tipo == "d4":
		var verts: PackedVector3Array = info["verts"]
		var best := -2.0
		var bi := 0
		for k in verts.size():
			var wy := (b * verts[k]).normalized().y
			if wy > best:
				best = wy
				bi = k
		return {"valor": bi + 1, "alinhamento": best}
	var normals: PackedVector3Array = info["face_normals"]
	var vals: PackedInt32Array = info["face_values"]
	var best_dot := -2.0
	var best_i := 0
	for k in normals.size():
		var d := (b * normals[k]).normalized().y
		if d > best_dot:
			best_dot = d
			best_i = k
	return {"valor": vals[best_i], "alinhamento": best_dot}
