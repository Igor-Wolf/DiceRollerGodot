extends RefCounted
## Geometria procedural dos dados (D4, D6, D8, D10, D12, D20).
## Gera vertices, faces, numeracao (faces opostas somam lo+hi), quadro 2D de cada face
## (para posicionar os numeros) e os arrays do mesh com UV apontando para o atlas.

const PHI := 1.618033988749895

# up: "vertex" = numero com a "cabeca" apontando para um vertice; "edge" = alinhado a uma aresta
# size: altura do numero relativa ao raio da circunferencia inscrita da face
const CONFIG := {
	"d4":  {"up": "vertex", "size": 0.0,  "lo": 0, "hi": 0,  "shuffle": false},
	"d6":  {"up": "edge",   "size": 1.0,  "lo": 1, "hi": 6,  "shuffle": false},
	"d8":  {"up": "vertex", "size": 1.0,  "lo": 1, "hi": 8,  "shuffle": false},
	"d10": {"up": "vertex", "size": 1.35, "lo": 0, "hi": 9,  "shuffle": false},
	"d12": {"up": "vertex", "size": 0.85, "lo": 1, "hi": 12, "shuffle": true},
	"d20": {"up": "vertex", "size": 1.0,  "lo": 1, "hi": 20, "shuffle": true},
}


# ---------------------------------------------------------------------------
# Vertices dos solidos
# ---------------------------------------------------------------------------
static func ico_verts() -> Array:
	var v: Array = []
	for s1 in [1.0, -1.0]:
		for s2 in [1.0, -1.0]:
			v.append(Vector3(0.0, s1, s2 * PHI))
			v.append(Vector3(s1, s2 * PHI, 0.0))
			v.append(Vector3(s2 * PHI, 0.0, s1))
	return v


static func dodeca_verts() -> Array:
	var v: Array = []
	for x in [1.0, -1.0]:
		for y in [1.0, -1.0]:
			for z in [1.0, -1.0]:
				v.append(Vector3(x, y, z))
	for s1 in [1.0, -1.0]:
		for s2 in [1.0, -1.0]:
			v.append(Vector3(0.0, s1 * PHI, s2 / PHI))
			v.append(Vector3(s1 / PHI, 0.0, s2 * PHI))
			v.append(Vector3(s1 * PHI, s2 / PHI, 0.0))
	return v


static func cube_verts() -> Array:
	var v: Array = []
	for x in [1.0, -1.0]:
		for y in [1.0, -1.0]:
			for z in [1.0, -1.0]:
				v.append(Vector3(x, y, z))
	return v


# ---------------------------------------------------------------------------
# Faces
# ---------------------------------------------------------------------------
static func _order_polygon(V: Array, idx: Array, n: Vector3) -> Array:
	## Ordena os indices de uma face em sentido anti-horario visto de fora.
	var c := Vector3.ZERO
	for i in idx:
		c += V[i]
	c /= float(idx.size())
	var a := n.cross(Vector3(1.0, 0.0, 0.0))
	if a.length() < 1e-6:
		a = n.cross(Vector3(0.0, 1.0, 0.0))
	a = a.normalized()
	var b := n.cross(a)
	var items: Array = []
	for i in idx:
		var d: Vector3 = V[i] - c
		items.append([atan2(d.dot(b), d.dot(a)), i])
	items.sort_custom(func(x, y): return x[0] < y[0])
	var out: Array = []
	for it in items:
		out.append(it[1])
	return out


static func faces_from_normals(V: Array, normals: Array) -> Array:
	## Cada normal define uma face: os vertices mais "altos" naquela direcao.
	var faces: Array = []
	for nv in normals:
		var n: Vector3 = nv.normalized()
		var dmax := -1.0e9
		for v in V:
			dmax = maxf(dmax, v.dot(n))
		var idx: Array = []
		for i in V.size():
			if V[i].dot(n) > dmax - 1.0e-4:
				idx.append(i)
		faces.append(_order_polygon(V, idx, n))
	return faces


static func _raw_normal(V: Array, f: Array) -> Vector3:
	return (V[f[1]] - V[f[0]]).cross(V[f[2]] - V[f[0]]).normalized()


static func face_normal(V: Array, f: Array) -> Vector3:
	var n := _raw_normal(V, f)
	var c := Vector3.ZERO
	for i in f:
		c += V[i]
	c /= float(f.size())
	if n.dot(c) < 0.0:
		return -n
	return n


static func _geom_d10() -> Dictionary:
	## Trapezoedro pentagonal: 10 faces em forma de pipa (todas planas).
	var h := 1.1
	var c := cos(deg_to_rad(36.0))
	var z0 := h * (1.0 - c) / (1.0 + c)
	var V: Array = [Vector3(0.0, 0.0, h), Vector3(0.0, 0.0, -h)]
	for k in 5:
		var a := deg_to_rad(72.0 * k)
		V.append(Vector3(cos(a), sin(a), z0))
	for k in 5:
		var a2 := deg_to_rad(72.0 * k + 36.0)
		V.append(Vector3(cos(a2), sin(a2), -z0))
	var F: Array = []
	for k in 5:
		F.append([0, 2 + k, 7 + k, 2 + (k + 1) % 5])
	for k in 5:
		F.append([1, 7 + k, 2 + (k + 1) % 5, 7 + (k + 1) % 5])
	# garante orientacao para fora, mantendo o vertice 0 como primeiro
	for i in F.size():
		var f: Array = F[i]
		var n := _raw_normal(V, f)
		var ctr := Vector3.ZERO
		for idx in f:
			ctr += V[idx]
		ctr /= float(f.size())
		if n.dot(ctr) < 0.0:
			var rest: Array = f.slice(1)
			rest.reverse()
			F[i] = [f[0]] + rest
	return {"V": V, "F": F}


static func geometry(nome: String) -> Dictionary:
	var V: Array = []
	var normals: Array = []
	match nome:
		"d4":
			V = [Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)]
			for v in V:
				normals.append(-v)
		"d6":
			V = cube_verts()
			normals = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
					Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
		"d8":
			V = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
					Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
			normals = cube_verts()
		"d10":
			return _geom_d10()
		"d12":
			V = dodeca_verts()
			normals = ico_verts()
		"d20":
			V = ico_verts()
			normals = dodeca_verts()
	return {"V": V, "F": faces_from_normals(V, normals)}


# ---------------------------------------------------------------------------
# Numeracao e quadros 2D das faces
# ---------------------------------------------------------------------------
static func _pair_values(V: Array, F: Array, lo: int, hi: int, shuffle: bool) -> Array:
	var normals: Array = []
	for f in F:
		normals.append(face_normal(V, f))
	var used := {}
	var pairs: Array = []
	for i in F.size():
		if used.has(i):
			continue
		var best := -1
		var bd := 2.0
		for j in F.size():
			var d: float = normals[i].dot(normals[j])
			if d < bd:
				bd = d
				best = j
		used[i] = true
		used[best] = true
		pairs.append([i, best])
	if shuffle:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in range(pairs.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = pairs[i]
			pairs[i] = pairs[j]
			pairs[j] = tmp
	var values: Array = []
	values.resize(F.size())
	for p in pairs.size():
		values[pairs[p][0]] = lo + p
		values[pairs[p][1]] = hi - p
	return values


static func _frames(V: Array, F: Array, up_mode: String) -> Array:
	var frames: Array = []
	for f in F:
		var P: Array = []
		for i in f:
			P.append(V[i])
		var c := Vector3.ZERO
		for p in P:
			c += p
		c /= float(P.size())
		var n := face_normal(V, f)
		var ref: Vector3
		if up_mode == "vertex":
			ref = P[0] - c
		else:
			ref = (P[0] + P[1]) * 0.5 - c
		var u := (ref - n * ref.dot(n)).normalized()
		var r := u.cross(n)
		var xy: Array = []
		for p in P:
			var d: Vector3 = p - c
			xy.append(Vector2(d.dot(r), d.dot(u)))
		# centroide de area (importante para as pipas do D10)
		var m := xy.size()
		var A := 0.0
		var cx := 0.0
		var cy := 0.0
		for k in m:
			var p0: Vector2 = xy[k]
			var p1: Vector2 = xy[(k + 1) % m]
			var cr := p0.x * p1.y - p1.x * p0.y
			A += cr
			cx += (p0.x + p1.x) * cr
			cy += (p0.y + p1.y) * cr
		A *= 0.5
		cx /= (6.0 * A)
		cy /= (6.0 * A)
		var c3 := c + r * cx + u * cy
		for k in m:
			xy[k] = xy[k] - Vector2(cx, cy)
		var R := 0.0
		var rin := 1.0e9
		for k in m:
			var a: Vector2 = xy[k]
			var b: Vector2 = xy[(k + 1) % m]
			R = maxf(R, a.length())
			rin = minf(rin, absf(a.x * b.y - a.y * b.x) / (b - a).length())
		frames.append({"c3": c3, "r": r, "u": u, "n": n, "xy": xy, "R": R, "rin": rin})
	return frames


static func build(nome: String, radius: float, cell: int) -> Dictionary:
	var cfg: Dictionary = CONFIG[nome]
	var g := geometry(nome)
	var V: Array = g["V"]
	var F: Array = g["F"]
	var maxlen := 0.0
	for v in V:
		maxlen = maxf(maxlen, v.length())
	for i in V.size():
		V[i] = V[i] / maxlen * radius

	var values: Array = []
	if nome != "d4":
		values = _pair_values(V, F, cfg["lo"], cfg["hi"], cfg["shuffle"])
	var frames := _frames(V, F, cfg["up"])

	for i in F.size():
		var fr: Dictionary = frames[i]
		var labels: Array = []
		if nome == "d4":
			# D4: o numero de cada vertice aparece nos 3 cantos da face, de cabeca para o vertice
			var xy: Array = fr["xy"]
			for k in xy.size():
				var p: Vector2 = xy[k]
				var o := p.normalized()
				labels.append({"text": str(int(F[i][k]) + 1), "pos": p * 0.58,
						"ang": atan2(o.x, o.y), "h": 0.32 * float(fr["R"])})
		else:
			labels.append({"text": str(values[i]), "pos": Vector2.ZERO, "ang": 0.0,
					"h": float(cfg["size"]) * float(fr["rin"])})
		fr["labels"] = labels

	var n_faces := F.size()
	var cols := ceili(sqrt(float(n_faces)))
	var rows := ceili(float(n_faces) / float(cols))
	return {"nome": nome, "V": V, "F": F, "frames": frames, "values": values,
			"cols": cols, "rows": rows, "cell": cell,
			"W": cols * cell, "H": rows * cell, "radius": radius}


# ---------------------------------------------------------------------------
# Mesh e atlas
# ---------------------------------------------------------------------------
static func scale_for(fr: Dictionary, cell: int) -> float:
	## unidades do modelo -> pixels do atlas
	return 0.47 * float(cell) / float(fr["R"])


static func mesh_arrays(data: Dictionary) -> Dictionary:
	var V: Array = data["V"]
	var F: Array = data["F"]
	var frames: Array = data["frames"]
	var cols: int = data["cols"]
	var cell: int = data["cell"]
	var W := float(data["W"])
	var H := float(data["H"])
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in F.size():
		var f: Array = F[i]
		var fr: Dictionary = frames[i]
		var n: Vector3 = fr["n"]
		var c3: Vector3 = fr["c3"]
		var r: Vector3 = fr["r"]
		var u: Vector3 = fr["u"]
		var s := scale_for(fr, cell)
		var ox := (float(i % cols) + 0.5) * float(cell)
		var oy := (floorf(float(i) / float(cols)) + 0.5) * float(cell)
		var base := verts.size()
		for vi in f:
			var p: Vector3 = V[vi]
			var d := p - c3
			verts.append(p)
			norms.append(n)
			# imagem com origem no topo-esquerdo (y para baixo)
			uvs.append(Vector2((ox + s * d.dot(r)) / W, (oy - s * d.dot(u)) / H))
		for k in range(1, f.size() - 1):
			var a: Vector3 = verts[base]
			var b: Vector3 = verts[base + k]
			var c: Vector3 = verts[base + k + 1]
			# Godot: frente = sentido horario visto de fora
			if (b - a).cross(c - a).dot(n) > 0.0:
				idx.append(base)
				idx.append(base + k + 1)
				idx.append(base + k)
			else:
				idx.append(base)
				idx.append(base + k)
				idx.append(base + k + 1)
	return {"verts": verts, "norms": norms, "uvs": uvs, "idx": idx}


static func canvas_labels(data: Dictionary) -> Array:
	## Lista de rotulos (texto, centro em pixels, altura, rotacao) para desenhar no atlas.
	var out: Array = []
	var cols: int = data["cols"]
	var cell: int = data["cell"]
	var frames: Array = data["frames"]
	for i in frames.size():
		var fr: Dictionary = frames[i]
		var s := scale_for(fr, cell)
		var ox := (float(i % cols) + 0.5) * float(cell)
		var oy := (floorf(float(i) / float(cols)) + 0.5) * float(cell)
		for lb in fr["labels"]:
			var pos: Vector2 = lb["pos"]
			out.append({"text": lb["text"],
					"center": Vector2(ox + s * pos.x, oy - s * pos.y),
					"h": s * float(lb["h"]),
					"rot": float(lb["ang"])})
	return out
