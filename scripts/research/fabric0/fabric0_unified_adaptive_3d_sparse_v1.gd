class_name Fabric0UnifiedAdaptive3DSparseV1
extends RefCounted

const EPS := 1.0e-13
static func _assemble_a(rows: Array, minv: Array) -> Array:
	var a:Array=[]; for _i in range(rows.size()): a.append({})
	for i in range(rows.size()):
		for j in range(i,rows.size()):
			var v:=0.0
			for c in range(minv.size()): v += float(rows[i]["j"][c])*float(minv[c])*float(rows[j]["j"][c])
			if absf(v)>EPS: a[i][j]=v; a[j][i]=v
	return a

static func _prepare_pattern(cache: Dictionary, island: String, matrix: Array, mutate: bool) -> Dictionary:
	var rows: Array = []
	for i in range(matrix.size()):
		var cols: Array = matrix[i].keys()
		cols.sort()
		rows.append(cols)
	var key := island + "|" + JSON.stringify(rows, "", false)
	if mutate and cache["entries"].has(key):
		cache["hits"] = int(cache["hits"]) + 1
		return {"ok":true,"inverse_diagonal":cache["entries"][key].duplicate(true),"hit":true,"key":key}
	var inverse_diagonal: Array = []
	for i in range(matrix.size()):
		var diagonal := float(matrix[i].get(i, 0.0))
		if diagonal <= EPS:
			return {"ok":false,"code":"PATTERN_NONPOSITIVE_DIAGONAL"}
		inverse_diagonal.append(1.0 / diagonal)
	if mutate:
		cache["entries"][key] = inverse_diagonal.duplicate(true)
		cache["misses"] = int(cache["misses"]) + 1
	return {"ok":true,"inverse_diagonal":inverse_diagonal,"hit":false,"key":key}

static func _inverse_diagonal(matrix: Array) -> Array:
	var result: Array = []
	for i in range(matrix.size()):
		result.append(1.0 / float(matrix[i][i]))
	return result

static func _pcg(matrix: Array, rhs: Array, initial: Array, invdiag: Array, tol: float, maxit: int) -> Dictionary:
	var n := rhs.size()
	var x := initial.duplicate(true)
	var r := _zero(n)
	var ax := _matvec(matrix, x)
	for i in range(n):
		r[i] = float(rhs[i]) - float(ax[i])
	var z := _zero(n)
	for i in range(n):
		z[i] = float(r[i]) * float(invdiag[i])
	var p: Array = z.duplicate(true)
	var rz := _dot(r, z)
	var target := tol * maxf(1.0, sqrt(_dot(rhs, rhs)))
	var rn := sqrt(_dot(r, r))
	if rn <= target:
		return {"ok":true,"x":x,"iterations":0,"residual":rn}
	for it in range(maxit):
		var ap := _matvec(matrix, p)
		var denom := _dot(p, ap)
		if denom <= 0.0:
			return {"ok":false,"code":"PCG_NONPOSITIVE_CURVATURE"}
		var alpha := rz / denom
		for i in range(n):
			x[i] = float(x[i]) + alpha * float(p[i])
			r[i] = float(r[i]) - alpha * float(ap[i])
		rn = sqrt(_dot(r, r))
		if rn <= target:
			return {"ok":true,"x":x,"iterations":it+1,"residual":rn}
		for i in range(n):
			z[i] = float(r[i]) * float(invdiag[i])
		var rz2 := _dot(r, z)
		if absf(rz) <= 1.0e-30:
			return {"ok":false,"code":"PCG_BREAKDOWN"}
		var beta := rz2 / rz
		for i in range(n):
			p[i] = float(z[i]) + beta * float(p[i])
		rz = rz2
	return {"ok":false,"code":"PCG_NO_CONVERGENCE"}

static func _relation_row_count(rows: Array, rel: String) -> int:
	var count := 0
	for row in rows:
		if String(row["relation"]) == rel:
			count += 1
	return count

static func _add_scaled(a: Array, b: Array, scale: float) -> Array:
	var result := a.duplicate(true)
	for i in range(result.size()):
		result[i] = float(result[i]) + scale * float(b[i])
	return result

static func _zero(n: int) -> Array:
	var result: Array = []
	result.resize(n)
	result.fill(0.0)
	return result

static func _dot(a: Array, b: Array) -> float:
	var sum := 0.0
	for i in range(a.size()):
		sum += float(a[i]) * float(b[i])
	return sum

static func _matvec(a: Array, x: Array) -> Array:
	var result := _zero(a.size())
	for i in range(a.size()):
		for j in a[i].keys():
			result[i] += float(a[i][j]) * float(x[int(j)])
	return result

static func _results_hash(results: Array) -> String:
	var payload: Array = []
	for result in results:
		payload.append({"id":String(result["id"]),"x":result["x"]})
	payload.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	return _sha(JSON.stringify(payload,"",false))

static func _sha(text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()
