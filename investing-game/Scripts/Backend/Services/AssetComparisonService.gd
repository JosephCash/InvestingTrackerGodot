extends RefCounted
class_name AssetComparisonService


func build_common_start_comparison(
	assets: Array[AssetData],
	start_date: String = "",
	end_date: String = ""
) -> OperationResult:
	if assets.is_empty():
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Asset comparison requires at least one asset.")

	var clean_start_date: String = start_date.strip_edges()
	var clean_end_date: String = end_date.strip_edges()
	if not clean_start_date.is_empty() and not DateUtils.is_valid_iso_date(clean_start_date):
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Comparison start date must use YYYY-MM-DD.")
	if not clean_end_date.is_empty() and not DateUtils.is_valid_iso_date(clean_end_date):
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Comparison end date must use YYYY-MM-DD.")
	if not clean_start_date.is_empty() and not clean_end_date.is_empty():
		if _compare_dates(clean_start_date, clean_end_date) > 0:
			return OperationResult.fail(ERR_INVALID_PARAMETER, "Comparison start date cannot be after end date.")

	var prepared_assets: Array[Dictionary] = []
	for asset in assets:
		if asset == null:
			return OperationResult.fail(ERR_INVALID_PARAMETER, "Asset comparison contains null asset.")

		var points_result: OperationResult = _prepare_history_points(asset, clean_start_date, clean_end_date)
		if not points_result.is_ok():
			return points_result

		if not (points_result.data is Dictionary):
			return OperationResult.fail(ERR_INVALID_DATA, "Prepared history result has invalid format.")

		prepared_assets.append(_copy_dictionary(points_result.data))

	var common_range_result: OperationResult = _find_common_range(prepared_assets)
	if not common_range_result.is_ok():
		return common_range_result

	if not (common_range_result.data is Dictionary):
		return OperationResult.fail(ERR_INVALID_DATA, "Common comparison range has invalid format.")

	var common_range: Dictionary = _copy_dictionary(common_range_result.data)
	var common_start: String = str(common_range.get("start_date", ""))
	var common_end: String = str(common_range.get("end_date", ""))
	var comparison_series: Array[Dictionary] = []
	var ranking: Array[Dictionary] = []

	for prepared in prepared_assets:
		var asset_raw: Variant = prepared.get("asset", null)
		var points_raw: Variant = prepared.get("points", [])
		if not (asset_raw is AssetData) or not (points_raw is Array):
			return OperationResult.fail(ERR_INVALID_DATA, "Prepared asset data has invalid format.")

		var asset: AssetData = asset_raw as AssetData
		if asset == null:
			return OperationResult.fail(ERR_INVALID_DATA, "Prepared asset reference is invalid.")

		var points: Array = []
		points.assign(points_raw)
		var normalized_result: OperationResult = _build_normalized_asset_series(asset, points, common_start, common_end)
		if not normalized_result.is_ok():
			return normalized_result

		if not (normalized_result.data is Dictionary):
			return OperationResult.fail(ERR_INVALID_DATA, "Normalized asset series has invalid format.")

		var series: Dictionary = _copy_dictionary(normalized_result.data)
		comparison_series.append(series)
		ranking.append({
			"asset_id": str(series.get("asset_id", "")),
			"symbol": str(series.get("symbol", "")),
			"return_percent": float(series.get("latest_return_percent", 0.0)),
			"latest_date": str(series.get("latest_date", ""))
		})

	_sort_ranking_descending(ranking)

	return OperationResult.ok({
		"common_start_date": common_start,
		"common_end_date": common_end,
		"asset_count": comparison_series.size(),
		"series": comparison_series,
		"ranking": ranking
	}, "Common-start asset comparison built.")


func _prepare_history_points(asset: AssetData, start_date: String, end_date: String) -> OperationResult:
	var points: Array[Dictionary] = asset.get_history_price_points()
	if points.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Asset has no historical price points: %s" % asset.symbol)

	var filtered_points: Array[Dictionary] = []
	for point in points:
		var date_value: String = str(point.get("date", "")).strip_edges()
		var close_value: float = float(point.get("close", -1.0))
		if not DateUtils.is_valid_iso_date(date_value) or close_value <= 0.0:
			continue
		if not start_date.is_empty() and _compare_dates(date_value, start_date) < 0:
			continue
		if not end_date.is_empty() and _compare_dates(date_value, end_date) > 0:
			continue

		filtered_points.append(point.duplicate(true))

	if filtered_points.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Asset has no valid historical price points in requested range: %s" % asset.symbol)

	_sort_points_by_date_ascending(filtered_points)
	return OperationResult.ok({
		"asset": asset,
		"points": filtered_points
	})


func _find_common_range(prepared_assets: Array[Dictionary]) -> OperationResult:
	var common_start: String = ""
	var common_end: String = ""

	for prepared in prepared_assets:
		var points_raw: Variant = prepared.get("points", [])
		if not (points_raw is Array):
			return OperationResult.fail(ERR_INVALID_DATA, "Prepared points have invalid format.")

		var points: Array = []
		points.assign(points_raw)
		if points.is_empty():
			return OperationResult.fail(ERR_INVALID_DATA, "Prepared points are empty.")

		var first_point: Dictionary = _copy_dictionary(points[0])
		var latest_point: Dictionary = _copy_dictionary(points[points.size() - 1])
		var first_date: String = str(first_point.get("date", ""))
		var latest_date: String = str(latest_point.get("date", ""))

		if common_start.is_empty() or _compare_dates(first_date, common_start) > 0:
			common_start = first_date
		if common_end.is_empty() or _compare_dates(latest_date, common_end) < 0:
			common_end = latest_date

	if common_start.is_empty() or common_end.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Cannot determine common comparison range.")

	if _compare_dates(common_start, common_end) > 0:
		return OperationResult.fail(ERR_INVALID_DATA, "Asset histories do not overlap.")

	return OperationResult.ok({
		"start_date": common_start,
		"end_date": common_end
	})


func _build_normalized_asset_series(
	asset: AssetData,
	points: Array,
	common_start: String,
	common_end: String
) -> OperationResult:
	var trimmed_points: Array[Dictionary] = []

	for item in points:
		if not (item is Dictionary):
			continue

		var point: Dictionary = _copy_dictionary(item)
		var date_value: String = str(point.get("date", ""))
		if _compare_dates(date_value, common_start) < 0:
			continue
		if _compare_dates(date_value, common_end) > 0:
			continue

		trimmed_points.append(point)

	if trimmed_points.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "No overlapping points for asset: %s" % asset.symbol)

	var base_point: Dictionary = trimmed_points[0]
	var base_close: float = float(base_point.get("close", 0.0))
	if base_close <= 0.0:
		return OperationResult.fail(ERR_INVALID_DATA, "Base price is invalid for asset: %s" % asset.symbol)

	var normalized_points: Array[Dictionary] = []
	for point in trimmed_points:
		var close_value: float = float(point.get("close", 0.0))
		if close_value <= 0.0:
			continue

		var relative_value: float = close_value / base_close
		var return_percent: float = (relative_value - 1.0) * 100.0
		normalized_points.append({
			"date": str(point.get("date", "")),
			"close": close_value,
			"currency": str(point.get("currency", asset.quote_currency)),
			"relative_value": relative_value,
			"return_percent": return_percent
		})

	if normalized_points.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "No valid normalized points for asset: %s" % asset.symbol)

	var latest_point: Dictionary = normalized_points[normalized_points.size() - 1]
	return OperationResult.ok({
		"asset_id": asset.id,
		"symbol": asset.symbol,
		"name": asset.name,
		"asset_type": asset.asset_type,
		"currency": asset.quote_currency,
		"base_date": str(base_point.get("date", "")),
		"base_close": base_close,
		"latest_date": str(latest_point.get("date", "")),
		"latest_close": float(latest_point.get("close", 0.0)),
		"latest_return_percent": float(latest_point.get("return_percent", 0.0)),
		"points": normalized_points
	})


func _sort_points_by_date_ascending(points: Array[Dictionary]) -> void:
	for index in range(points.size()):
		var min_index: int = index

		for compare_index in range(index + 1, points.size()):
			var compare_date: String = str(points[compare_index].get("date", ""))
			var min_date: String = str(points[min_index].get("date", ""))
			if _compare_dates(compare_date, min_date) < 0:
				min_index = compare_index

		if min_index != index:
			var current: Dictionary = points[index]
			points[index] = points[min_index]
			points[min_index] = current


func _sort_ranking_descending(ranking: Array[Dictionary]) -> void:
	for index in range(ranking.size()):
		var max_index: int = index

		for compare_index in range(index + 1, ranking.size()):
			var compare_return: float = float(ranking[compare_index].get("return_percent", 0.0))
			var max_return: float = float(ranking[max_index].get("return_percent", 0.0))
			if compare_return > max_return:
				max_index = compare_index

		if max_index != index:
			var current: Dictionary = ranking[index]
			ranking[index] = ranking[max_index]
			ranking[max_index] = current


func _compare_dates(left_date: String, right_date: String) -> int:
	if left_date == right_date:
		return 0
	if left_date < right_date:
		return -1

	return 1


func _copy_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		for key in value:
			result[key] = value[key]

	return result
