extends RefCounted
class_name InflationCalculator


static func calculate_compounded_month_over_month_inflation(monthly_inflation: Array[InflationData]) -> OperationResult:
	if monthly_inflation.is_empty():
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Monthly inflation series is empty.")

	var observations: Array[InflationData] = []
	for item in monthly_inflation:
		if item == null:
			return OperationResult.fail(ERR_INVALID_DATA, "Monthly inflation series contains null entry.")

		if item.period.strip_edges().to_lower() != InflationData.PERIOD_MONTHLY:
			return OperationResult.fail(ERR_INVALID_DATA, "Inflation entry is not monthly: %s" % item.id)

		if item.month_over_month_index <= 0.0:
			return OperationResult.fail(ERR_INVALID_DATA, "Monthly CPI index is invalid for: %s" % item.get_period_label())

		observations.append(item)

	_sort_by_period_ascending(observations)

	var continuity_result := _validate_monthly_continuity(observations)
	if not continuity_result.is_ok():
		return continuity_result

	var factor := 1.0
	for observation in observations:
		factor *= observation.month_over_month_index / 100.0

	var compounded_index := factor * 100.0
	var compounded_rate := (factor - 1.0) * 100.0

	return OperationResult.ok({
		"start_period": observations[0].get_period_label(),
		"end_period": observations[observations.size() - 1].get_period_label(),
		"months": observations.size(),
		"factor": factor,
		"compounded_index": compounded_index,
		"compounded_rate": compounded_rate
	}, "Monthly inflation calculated.")


static func _sort_by_period_ascending(observations: Array[InflationData]) -> void:
	for index in range(observations.size()):
		var min_index := index

		for compare_index in range(index + 1, observations.size()):
			if _period_key(observations[compare_index]) < _period_key(observations[min_index]):
				min_index = compare_index

		if min_index != index:
			var current := observations[index]
			observations[index] = observations[min_index]
			observations[min_index] = current


static func _validate_monthly_continuity(observations: Array[InflationData]) -> OperationResult:
	for index in range(1, observations.size()):
		var previous := observations[index - 1]
		var current := observations[index]

		if _period_key(current) != _period_key(previous) + 1:
			return OperationResult.fail(
				ERR_INVALID_DATA,
				"Monthly CPI series has a gap between %s and %s." % [
					previous.get_period_label(),
					current.get_period_label()
				]
			)

	return OperationResult.ok()


static func _period_key(inflation: InflationData) -> int:
	return inflation.year * 12 + inflation.month
