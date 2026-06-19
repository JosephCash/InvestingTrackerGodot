extends RefCounted
class_name MomentumSignalService

const REGIME_RISK_ON := "risk_on"
const REGIME_RISK_OFF := "risk_off"

func build_signal(
	comparison: Dictionary,
	minimum_positive_return_percent: float = 0.0,
	defensive_symbol: String = "CASH"
) -> OperationResult:
	var ranking_result: OperationResult = _ranking_from_comparison(comparison)
	if not ranking_result.is_ok():
		return ranking_result

	if not (ranking_result.data is Array):
		return OperationResult.fail(ERR_INVALID_DATA, "Momentum ranking has invalid format.")

	var ranking: Array = []
	ranking.assign(ranking_result.data)
	if ranking.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Momentum ranking is empty.")

	var leader: Dictionary = _copy_dictionary(ranking[0])
	var leader_symbol: String = str(leader.get("symbol", ""))
	var leader_return: float = float(leader.get("return_percent", 0.0))
	var clean_defensive_symbol: String = defensive_symbol.strip_edges().to_upper()
	if clean_defensive_symbol.is_empty():
		clean_defensive_symbol = "CASH"

	var regime: String = REGIME_RISK_OFF
	var selected_symbol: String = clean_defensive_symbol
	var selected_reason: String = "Best momentum is not positive enough."
	if leader_return > minimum_positive_return_percent:
		regime = REGIME_RISK_ON
		selected_symbol = leader_symbol
		selected_reason = "Best momentum is above threshold."

	var signal_data: Dictionary = {
		"schema_version": 1,
		"strategy_id": "momentum",
		"strategy_name": "Momentum",
		"regime": regime,
		"selected_symbol": selected_symbol,
		"leader_symbol": leader_symbol,
		"leader_return_percent": leader_return,
		"minimum_positive_return_percent": minimum_positive_return_percent,
		"defensive_symbol": clean_defensive_symbol,
		"reason": selected_reason,
		"common_start_date": str(comparison.get("common_start_date", "")),
		"common_end_date": str(comparison.get("common_end_date", "")),
		"ranking": _copy_array_of_dictionaries(ranking),
		"generated_at": Time.get_unix_time_from_system()
	}

	var validation_errors: PackedStringArray = _validate_signal(signal_data)
	if not validation_errors.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Momentum signal is invalid: %s" % str(validation_errors))

	return OperationResult.ok(signal_data, "Momentum signal built.")


func _ranking_from_comparison(comparison: Dictionary) -> OperationResult:
	var ranking_raw: Variant = comparison.get("ranking", [])
	if ranking_raw is Array:
		var existing_ranking: Array = []
		existing_ranking.assign(ranking_raw)
		if not existing_ranking.is_empty():
			_sort_ranking_descending(existing_ranking)
			return OperationResult.ok(existing_ranking)

	var series_raw: Variant = comparison.get("series", [])
	if not (series_raw is Array):
		return OperationResult.fail(ERR_INVALID_DATA, "Comparison does not contain ranking or series.")

	var series_items: Array = []
	series_items.assign(series_raw)
	var ranking: Array[Dictionary] = []
	for item in series_items:
		if not (item is Dictionary):
			continue

		var series: Dictionary = _copy_dictionary(item)
		ranking.append({
			"asset_id": str(series.get("asset_id", "")),
			"symbol": str(series.get("symbol", "")),
			"return_percent": float(series.get("latest_return_percent", 0.0)),
			"latest_date": str(series.get("latest_date", ""))
		})

	if ranking.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Comparison contains no rankable series.")

	_sort_ranking_descending(ranking)
	return OperationResult.ok(ranking)


func _sort_ranking_descending(ranking: Array) -> void:
	for index in range(ranking.size()):
		var max_index: int = index

		for compare_index in range(index + 1, ranking.size()):
			if not (ranking[compare_index] is Dictionary) or not (ranking[max_index] is Dictionary):
				continue

			var compare_item: Dictionary = _copy_dictionary(ranking[compare_index])
			var max_item: Dictionary = _copy_dictionary(ranking[max_index])
			var compare_return: float = float(compare_item.get("return_percent", 0.0))
			var max_return: float = float(max_item.get("return_percent", 0.0))
			if compare_return > max_return:
				max_index = compare_index

		if max_index != index:
			var current: Variant = ranking[index]
			ranking[index] = ranking[max_index]
			ranking[max_index] = current


func _copy_array_of_dictionaries(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for value in values:
		if value is Dictionary:
			result.append(_copy_dictionary(value))

	return result


func _validate_signal(signal_data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var strategy_id: String = str(signal_data.get("strategy_id", "")).strip_edges()
	var regime: String = str(signal_data.get("regime", "")).strip_edges().to_lower()
	var selected_symbol: String = str(signal_data.get("selected_symbol", "")).strip_edges()
	var defensive_symbol: String = str(signal_data.get("defensive_symbol", "")).strip_edges()

	if strategy_id.is_empty():
		errors.append("Strategy id is empty.")

	if regime != REGIME_RISK_ON and regime != REGIME_RISK_OFF:
		errors.append("Strategy regime is unsupported: %s." % regime)

	if selected_symbol.is_empty():
		errors.append("Selected symbol is empty.")

	if defensive_symbol.is_empty():
		errors.append("Defensive symbol is empty.")

	return errors


func _copy_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		for key in value:
			result[key] = value[key]

	return result
