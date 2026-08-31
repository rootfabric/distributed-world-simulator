extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

static func factor_square(matrix: Array, relative_tolerance: float) -> Dictionary:
	if not Utils.is_positive_number(relative_tolerance):
		return Utils.failure("INVALID_LINEAR_PIVOT_TOLERANCE")
	var n := matrix.size()
	if n == 0:
		return Utils.failure("EMPTY_LINEAR_MATRIX")
	var lu: Array = []
	for row_index in range(n):
		if typeof(matrix[row_index]) != TYPE_ARRAY or matrix[row_index].size() != n:
			return Utils.failure("INVALID_LINEAR_MATRIX")
		var row: Array = []
		for column_index in range(n):
			if not Utils.is_finite_number(matrix[row_index][column_index]):
				return Utils.failure("INVALID_LINEAR_MATRIX")
			row.append(float(matrix[row_index][column_index]))
		lu.append(row)
	var scale := max_abs_matrix(lu)
	if scale == 0.0:
		return {
			"success": false, "error_code": "RANK_DEFICIENCY",
			"details": {"rank": 0, "matrix_size": n, "threshold": 0.0},
		}
	var threshold := relative_tolerance * scale
	var permutation: Array = []
	for index in range(n):
		permutation.append(index)
	var minimum_abs_pivot := INF
	var maximum_abs_pivot := 0.0
	var work_units := 0
	for column in range(n):
		var pivot_row := column
		var pivot_abs := absf(float(lu[column][column]))
		for row_index in range(column + 1, n):
			var candidate := absf(float(lu[row_index][column]))
			if candidate > pivot_abs:
				pivot_abs = candidate
				pivot_row = row_index
		if pivot_abs <= threshold:
			return {
				"success": false, "error_code": "RANK_DEFICIENCY",
				"details": {
					"rank": column, "matrix_size": n, "threshold": threshold,
					"failed_column": column, "pivot_abs": pivot_abs,
				},
			}
		if pivot_row != column:
			var row_swap = lu[column]
			lu[column] = lu[pivot_row]
			lu[pivot_row] = row_swap
			var permutation_swap = permutation[column]
			permutation[column] = permutation[pivot_row]
			permutation[pivot_row] = permutation_swap
		minimum_abs_pivot = minf(minimum_abs_pivot, pivot_abs)
		maximum_abs_pivot = maxf(maximum_abs_pivot, pivot_abs)
		var pivot := float(lu[column][column])
		for row_index in range(column + 1, n):
			lu[row_index][column] = float(lu[row_index][column]) / pivot
			work_units += 1
			var multiplier := float(lu[row_index][column])
			for k in range(column + 1, n):
				lu[row_index][k] = float(lu[row_index][k]) - multiplier * float(lu[column][k])
				work_units += 2
	return {
		"success": true,
		"error_code": "",
		"details": {
			"lu": lu,
			"permutation": permutation,
			"rank": n,
			"matrix_size": n,
			"matrix_scale": scale,
			"threshold": threshold,
			"minimum_abs_pivot": minimum_abs_pivot,
			"maximum_abs_pivot": maximum_abs_pivot,
			"factor_work_units": work_units,
		},
	}

static func solve_factored(factor: Dictionary, rhs: Array) -> Dictionary:
	if not bool(factor.get("success", false)):
		return Utils.failure("INVALID_LINEAR_FACTOR")
	var details: Dictionary = factor.get("details", {})
	var lu: Array = details.get("lu", [])
	var permutation: Array = details.get("permutation", [])
	var n := lu.size()
	if rhs.size() != n or permutation.size() != n:
		return Utils.failure("INVALID_LINEAR_SOLVE_RHS")
	var y: Array = []
	for row in range(n):
		var source_index := int(permutation[row])
		if source_index < 0 or source_index >= rhs.size() or not Utils.is_finite_number(rhs[source_index]):
			return Utils.failure("INVALID_LINEAR_SOLVE_RHS")
		var value := float(rhs[source_index])
		for column in range(row):
			value -= float(lu[row][column]) * float(y[column])
		y.append(value)
	var x: Array = []
	x.resize(n)
	for reverse_index in range(n):
		var row := n - 1 - reverse_index
		var value := float(y[row])
		for column in range(row + 1, n):
			value -= float(lu[row][column]) * float(x[column])
		var pivot := float(lu[row][row])
		if pivot == 0.0:
			return Utils.failure("RANK_DEFICIENCY")
		x[row] = value / pivot
	return Utils.success({"solution": x, "solve_work_units": 2 * n * n})

static func matrix_rank(matrix: Array, relative_tolerance: float) -> int:
	var rows := matrix.size()
	if rows == 0 or not Utils.is_positive_number(relative_tolerance):
		return 0
	if typeof(matrix[0]) != TYPE_ARRAY:
		return 0
	var columns: int = int(matrix[0].size())
	var a: Array = []
	for row_index in range(rows):
		if typeof(matrix[row_index]) != TYPE_ARRAY or matrix[row_index].size() != columns:
			return 0
		var row: Array = []
		for column_index in range(columns):
			if not Utils.is_finite_number(matrix[row_index][column_index]):
				return 0
			row.append(float(matrix[row_index][column_index]))
		a.append(row)
	var scale := max_abs_matrix(a)
	if scale == 0.0:
		return 0
	var threshold := relative_tolerance * scale
	var rank := 0
	var limit := mini(rows, columns)
	for pivot_index in range(limit):
		var best_row := -1
		var best_column := -1
		var best_abs := 0.0
		for row_index in range(pivot_index, rows):
			for column_index in range(pivot_index, columns):
				var candidate := absf(float(a[row_index][column_index]))
				if candidate > best_abs:
					best_abs = candidate
					best_row = row_index
					best_column = column_index
		if best_abs <= threshold or best_row < 0:
			break
		if best_row != pivot_index:
			var row_swap = a[pivot_index]
			a[pivot_index] = a[best_row]
			a[best_row] = row_swap
		if best_column != pivot_index:
			for row_index in range(rows):
				var column_swap = a[row_index][pivot_index]
				a[row_index][pivot_index] = a[row_index][best_column]
				a[row_index][best_column] = column_swap
		var pivot := float(a[pivot_index][pivot_index])
		for row_index in range(pivot_index + 1, rows):
			var multiplier := float(a[row_index][pivot_index]) / pivot
			for column_index in range(pivot_index + 1, columns):
				a[row_index][column_index] = float(a[row_index][column_index]) - multiplier * float(a[pivot_index][column_index])
		rank += 1
	return rank

static func matvec(matrix: Array, vector: Array) -> Array:
	var output: Array = []
	for row in matrix:
		var value := 0.0
		for column in range(vector.size()):
			value += float(row[column]) * float(vector[column])
		output.append(value)
	return output

static func dot(a: Array, b: Array) -> float:
	var value := 0.0
	for index in range(a.size()):
		value += float(a[index]) * float(b[index])
	return value

static func max_abs_matrix(matrix: Array) -> float:
	var result := 0.0
	for row in matrix:
		if typeof(row) != TYPE_ARRAY:
			continue
		for value in row:
			if Utils.is_finite_number(value):
				result = maxf(result, absf(float(value)))
	return result

static func max_abs_vector(vector: Array) -> float:
	var result := 0.0
	for value in vector:
		if Utils.is_finite_number(value):
			result = maxf(result, absf(float(value)))
	return result

static func max_abs_delta(a: Array, b: Array) -> float:
	if a.size() != b.size():
		return INF
	var result := 0.0
	for index in range(a.size()):
		result = maxf(result, absf(float(a[index]) - float(b[index])))
	return result

static func symmetry_error(matrix: Array) -> float:
	var n := matrix.size()
	var result := 0.0
	for row in range(n):
		for column in range(row + 1, n):
			result = maxf(result, absf(float(matrix[row][column]) - float(matrix[column][row])))
	return result

static func row_sum_residual(matrix: Array) -> float:
	var result := 0.0
	for row in matrix:
		var total := 0.0
		for value in row:
			total += float(value)
		result = maxf(result, absf(total))
	return result

static func laplacian_certificate(matrix: Array, tolerance: float) -> Dictionary:
	if matrix.is_empty() or not Utils.is_non_negative_number(tolerance):
		return Utils.failure("INVALID_LAPLACIAN_CERTIFICATE_INPUT")
	var scale := maxf(1.0, max_abs_matrix(matrix))
	var allowed := tolerance * scale
	var symmetry := symmetry_error(matrix)
	var row_sum := row_sum_residual(matrix)
	var minimum_diagonal := INF
	var maximum_off_diagonal := -INF
	for row in range(matrix.size()):
		minimum_diagonal = minf(minimum_diagonal, float(matrix[row][row]))
		for column in range(matrix.size()):
			if row != column:
				maximum_off_diagonal = maxf(maximum_off_diagonal, float(matrix[row][column]))
	var certified := symmetry <= allowed and row_sum <= allowed and minimum_diagonal >= -allowed and maximum_off_diagonal <= allowed
	return Utils.success({
		"certified": certified,
		"symmetry_error": symmetry,
		"row_sum_residual": row_sum,
		"minimum_diagonal": minimum_diagonal,
		"maximum_off_diagonal": maximum_off_diagonal,
		"allowed": allowed,
	})
