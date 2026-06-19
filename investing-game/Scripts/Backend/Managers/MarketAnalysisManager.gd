extends Node

signal analysis_requested(request_id: int, assets: Array)
signal analysis_ready(request_id: int, comparison: Dictionary, momentum_signal: Dictionary)
signal analysis_failed(request_id: int, error_message: String)
signal analysis_asset_failed(request_id: int, input_symbol: String, resolved_symbol: String, error_message: String)

const PROVIDER_COINGECKO: String = TickerResolver.PROVIDER_COINGECKO
const PROVIDER_YAHOO: String = TickerResolver.PROVIDER_YAHOO
const DEFAULT_HISTORY_RANGE: String = "1y"
const DEFAULT_HISTORY_INTERVAL: String = "1d"

var _next_request_id: int = 1
var _pending_requests: Dictionary = {}


func _ready() -> void:
	PortfolioManager.asset_history_updated.connect(_on_asset_history_updated)
	PortfolioManager.asset_history_fetch_failed.connect(_on_asset_history_fetch_failed)


func request_asset_comparison(
	input_assets: Array,
	start_date: String = "",
	end_date: String = "",
	range_value: String = DEFAULT_HISTORY_RANGE,
	interval: String = DEFAULT_HISTORY_INTERVAL,
	minimum_positive_return_percent: float = 0.0,
	defensive_symbol: String = "CASH"
) -> OperationResult:
	var clean_start_date: String = start_date.strip_edges()
	var clean_end_date: String = end_date.strip_edges()
	var clean_range: String = _clean_history_range(range_value)
	var clean_interval: String = _clean_history_interval(interval)

	var date_validation_result: OperationResult = _validate_requested_dates(clean_start_date, clean_end_date)
	if not date_validation_result.is_ok():
		return date_validation_result

	if input_assets.size() < 1:
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Market analysis requires at least one asset.")

	var specs: Array[Dictionary] = []
	var cache_keys: Dictionary = {}
	for input_value in input_assets:
		var spec_result: OperationResult = _resolve_asset_spec(input_value, clean_range, clean_interval)
		if not spec_result.is_ok():
			return spec_result

		if not (spec_result.data is Dictionary):
			return OperationResult.fail(ERR_INVALID_DATA, "Resolved market analysis asset has invalid format.")

		var spec: Dictionary = _copy_dictionary(spec_result.data)
		var cache_key: String = str(spec.get("cache_key", ""))
		if cache_key.is_empty():
			return OperationResult.fail(ERR_INVALID_DATA, "Resolved market analysis asset has empty cache key.")
		if cache_keys.has(cache_key):
			return OperationResult.fail(ERR_ALREADY_IN_USE, "Duplicate market analysis asset: %s" % str(spec.get("symbol", "")))

		cache_keys[cache_key] = true
		specs.append(spec)

	var request_id: int = _next_request_id
	_next_request_id += 1
	_pending_requests[request_id] = {
		"request_id": request_id,
		"assets": specs,
		"cache_keys": cache_keys,
		"start_date": clean_start_date,
		"end_date": clean_end_date,
		"minimum_positive_return_percent": minimum_positive_return_percent,
		"defensive_symbol": defensive_symbol.strip_edges().to_upper()
	}

	analysis_requested.emit(request_id, specs.duplicate(true))
	for spec in specs:
		_request_history_for_spec(spec)

	_try_complete_request(request_id)
	return OperationResult.ok({
		"request_id": request_id,
		"assets": specs
	}, "Market analysis request started.")


func request_asset_comparison_from_text(
	input_text: String,
	start_date: String = "",
	end_date: String = "",
	range_value: String = DEFAULT_HISTORY_RANGE,
	interval: String = DEFAULT_HISTORY_INTERVAL,
	minimum_positive_return_percent: float = 0.0,
	defensive_symbol: String = "CASH"
) -> OperationResult:
	var parsed_assets: PackedStringArray = _parse_asset_input_text(input_text)
	if parsed_assets.is_empty():
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Market analysis input text contains no assets.")

	var input_assets: Array = []
	for asset_symbol in parsed_assets:
		input_assets.append(asset_symbol)

	return request_asset_comparison(
		input_assets,
		start_date,
		end_date,
		range_value,
		interval,
		minimum_positive_return_percent,
		defensive_symbol
	)


func _resolve_asset_spec(input_value: Variant, range_value: String, interval: String) -> OperationResult:
	var input_data: Dictionary = {}
	if input_value is Dictionary:
		input_data = _copy_dictionary(input_value)
	else:
		input_data["symbol"] = str(input_value)

	var input_symbol: String = str(input_data.get("input", input_data.get("symbol", ""))).strip_edges()
	if input_symbol.is_empty():
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Market analysis asset input is empty.")

	var requested_provider: String = str(input_data.get("provider", "")).strip_edges().to_lower()
	var requested_asset_type: String = str(input_data.get("asset_type", "")).strip_edges().to_lower()
	var crypto_id: String = _crypto_id_from_alias(input_symbol)
	if requested_provider == PROVIDER_COINGECKO or requested_asset_type == AssetData.TYPE_CRYPTO or not crypto_id.is_empty():
		if crypto_id.is_empty():
			crypto_id = str(TickerResolver.resolve_for_coingecko(input_symbol).get("symbol", ""))

		return OperationResult.ok({
			"input": input_symbol,
			"provider": PROVIDER_COINGECKO,
			"symbol": crypto_id,
			"cache_key": crypto_id.to_lower(),
			"asset_type": AssetData.TYPE_CRYPTO,
			"range": range_value,
			"interval": interval,
			"warnings": PackedStringArray()
		})

	var yahoo_input: String = input_symbol
	var index_symbol: String = _index_symbol_from_alias(input_symbol)
	if not index_symbol.is_empty():
		yahoo_input = index_symbol
		requested_asset_type = AssetData.TYPE_INDEX

	var resolved_yahoo: Dictionary = TickerResolver.resolve_for_yahoo(yahoo_input)
	var yahoo_symbol: String = str(resolved_yahoo.get("symbol", "")).strip_edges().to_upper()
	if yahoo_symbol.is_empty():
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Yahoo Finance symbol is empty for input: %s" % input_symbol)

	var yahoo_asset_type: String = requested_asset_type
	if yahoo_asset_type.is_empty():
		yahoo_asset_type = AssetData.TYPE_ETF
	if not _is_supported_yahoo_asset_type(yahoo_asset_type):
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Unsupported Yahoo asset type: %s" % requested_asset_type)

	return OperationResult.ok({
		"input": input_symbol,
		"provider": PROVIDER_YAHOO,
		"symbol": yahoo_symbol,
		"cache_key": yahoo_symbol.to_lower(),
		"asset_type": yahoo_asset_type,
		"range": range_value,
		"interval": interval,
		"warnings": resolved_yahoo.get("warnings", PackedStringArray())
	})


func _request_history_for_spec(spec: Dictionary) -> void:
	var provider: String = str(spec.get("provider", ""))
	var symbol: String = str(spec.get("symbol", ""))
	var asset_type: String = str(spec.get("asset_type", ""))
	var range_value: String = str(spec.get("range", DEFAULT_HISTORY_RANGE))
	var interval: String = str(spec.get("interval", DEFAULT_HISTORY_INTERVAL))

	if provider == PROVIDER_COINGECKO:
		PortfolioManager.request_crypto_history(symbol, _days_from_history_range(range_value))
		return

	if asset_type == AssetData.TYPE_INDEX:
		PortfolioManager.request_index_history(symbol, range_value, interval)
	elif asset_type == AssetData.TYPE_STOCK:
		PortfolioManager.request_stock_history(symbol, range_value, interval)
	else:
		PortfolioManager.request_etf_history(symbol, range_value, interval)


func _try_complete_request(request_id: int) -> void:
	if not _pending_requests.has(request_id):
		return

	var request_data: Dictionary = _copy_dictionary(_pending_requests[request_id])
	var assets_result: OperationResult = _collect_ready_assets(request_data)
	if not assets_result.is_ok():
		if assets_result.error_code == ERR_BUSY:
			return

		_pending_requests.erase(request_id)
		analysis_failed.emit(request_id, assets_result.message)
		return

	if not (assets_result.data is Array):
		_pending_requests.erase(request_id)
		analysis_failed.emit(request_id, "Market analysis ready assets have invalid format.")
		return

	var ready_assets_raw: Variant = assets_result.data
	var ready_assets: Array = []
	ready_assets.assign(ready_assets_raw)

	var assets: Array[AssetData] = []
	for item in ready_assets:
		if item is AssetData:
			assets.append(item)

	var comparison_result: OperationResult = AssetComparisonService.new().build_common_start_comparison(
		assets,
		str(request_data.get("start_date", "")),
		str(request_data.get("end_date", ""))
	)
	if not comparison_result.is_ok():
		_pending_requests.erase(request_id)
		analysis_failed.emit(request_id, comparison_result.message)
		return

	if not (comparison_result.data is Dictionary):
		_pending_requests.erase(request_id)
		analysis_failed.emit(request_id, "Market analysis comparison has invalid format.")
		return

	var comparison: Dictionary = _copy_dictionary(comparison_result.data)
	var momentum_result: OperationResult = MomentumSignalService.new().build_signal(
		comparison,
		float(request_data.get("minimum_positive_return_percent", 0.0)),
		str(request_data.get("defensive_symbol", "CASH"))
	)
	if not momentum_result.is_ok():
		_pending_requests.erase(request_id)
		analysis_failed.emit(request_id, momentum_result.message)
		return

	if not (momentum_result.data is Dictionary):
		_pending_requests.erase(request_id)
		analysis_failed.emit(request_id, "Market analysis momentum signal has invalid format.")
		return

	var momentum_signal: Dictionary = _copy_dictionary(momentum_result.data)
	_pending_requests.erase(request_id)
	analysis_ready.emit(request_id, comparison, momentum_signal)


func _collect_ready_assets(request_data: Dictionary) -> OperationResult:
	var specs_raw: Variant = request_data.get("assets", [])
	if not (specs_raw is Array):
		return OperationResult.fail(ERR_INVALID_DATA, "Market analysis request assets have invalid format.")

	var cache_snapshot: Dictionary = PortfolioManager.get_cached_assets_snapshot()
	var assets: Array[AssetData] = []
	for item in specs_raw:
		if not (item is Dictionary):
			return OperationResult.fail(ERR_INVALID_DATA, "Market analysis asset spec has invalid format.")

		var spec: Dictionary = _copy_dictionary(item)
		var cache_key: String = str(spec.get("cache_key", ""))
		if not cache_snapshot.has(cache_key):
			return OperationResult.fail(ERR_BUSY, "Waiting for market history: %s" % str(spec.get("symbol", "")))

		var asset_raw: Variant = cache_snapshot[cache_key]
		if not (asset_raw is AssetData):
			return OperationResult.fail(ERR_INVALID_DATA, "Cached market asset has invalid format: %s" % cache_key)

		var asset: AssetData = asset_raw as AssetData
		if asset == null:
			return OperationResult.fail(ERR_INVALID_DATA, "Cached market asset is null: %s" % cache_key)
		if asset.get_history_price_points().size() < 2:
			return OperationResult.fail(ERR_BUSY, "Waiting for full market history: %s" % str(spec.get("symbol", "")))

		assets.append(asset)

	return OperationResult.ok(assets)


func _on_asset_history_updated(asset: AssetData) -> void:
	if asset == null:
		return

	var cache_key: String = str(asset.id).strip_edges().to_lower()
	var request_ids: Array = _pending_requests.keys()
	for request_id_raw in request_ids:
		var request_id: int = int(request_id_raw)
		if not _pending_requests.has(request_id):
			continue

		var request_data: Dictionary = _copy_dictionary(_pending_requests[request_id])
		var cache_keys_raw: Variant = request_data.get("cache_keys", {})
		if cache_keys_raw is Dictionary:
			var cache_keys: Dictionary = _copy_dictionary(cache_keys_raw)
			if cache_keys.has(cache_key):
				_try_complete_request(request_id)


func _on_asset_history_fetch_failed(asset_id: String, error_message: String) -> void:
	var cache_key: String = asset_id.strip_edges().to_lower()
	var request_ids: Array = _pending_requests.keys()
	for request_id_raw in request_ids:
		var request_id: int = int(request_id_raw)
		if not _pending_requests.has(request_id):
			continue

		var request_data: Dictionary = _copy_dictionary(_pending_requests[request_id])
		var failed_spec: Dictionary = _find_spec_by_cache_key(request_data, cache_key)
		if failed_spec.is_empty():
			continue

		_pending_requests.erase(request_id)
		analysis_asset_failed.emit(
			request_id,
			str(failed_spec.get("input", "")),
			str(failed_spec.get("symbol", asset_id)),
			error_message
		)
		analysis_failed.emit(request_id, "Cannot fetch market history for %s: %s" % [
			str(failed_spec.get("symbol", asset_id)),
			error_message
		])


func _find_spec_by_cache_key(request_data: Dictionary, cache_key: String) -> Dictionary:
	var specs_raw: Variant = request_data.get("assets", [])
	if not (specs_raw is Array):
		return {}

	for item in specs_raw:
		if item is Dictionary:
			var spec: Dictionary = _copy_dictionary(item)
			if str(spec.get("cache_key", "")) == cache_key:
				return spec

	return {}


func _validate_requested_dates(start_date: String, end_date: String) -> OperationResult:
	if not start_date.is_empty() and not DateUtils.is_valid_iso_date(start_date):
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Market analysis start date must use YYYY-MM-DD.")
	if not end_date.is_empty() and not DateUtils.is_valid_iso_date(end_date):
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Market analysis end date must use YYYY-MM-DD.")
	if not start_date.is_empty() and not end_date.is_empty():
		var compare_result: OperationResult = DateUtils.compare_iso_dates(start_date, end_date)
		if not compare_result.is_ok():
			return compare_result
		if int(compare_result.data) > 0:
			return OperationResult.fail(ERR_INVALID_PARAMETER, "Market analysis start date cannot be after end date.")

	return OperationResult.ok()


func _crypto_id_from_alias(input_symbol: String) -> String:
	var clean_symbol: String = input_symbol.strip_edges().to_lower()
	match clean_symbol:
		"btc", "xbt", "bitcoin":
			return "bitcoin"
		"eth", "ethereum":
			return "ethereum"

	return ""


func _index_symbol_from_alias(input_symbol: String) -> String:
	var clean_symbol: String = input_symbol.strip_edges().to_lower()
	match clean_symbol:
		"sp500", "s&p500", "s&p 500", "gspc", "^gspc":
			return "^GSPC"

	return ""


func _is_supported_yahoo_asset_type(asset_type: String) -> bool:
	if asset_type == AssetData.TYPE_ETF:
		return true
	if asset_type == AssetData.TYPE_STOCK:
		return true
	if asset_type == AssetData.TYPE_INDEX:
		return true
	if asset_type == AssetData.TYPE_OTHER:
		return true

	return false


func _clean_history_range(range_value: String) -> String:
	var clean_range: String = range_value.strip_edges().to_lower()
	if clean_range.is_empty():
		return DEFAULT_HISTORY_RANGE

	return clean_range


func _clean_history_interval(interval: String) -> String:
	var clean_interval: String = interval.strip_edges().to_lower()
	if clean_interval.is_empty():
		return DEFAULT_HISTORY_INTERVAL

	return clean_interval


func _days_from_history_range(range_value: String) -> int:
	var clean_range: String = range_value.strip_edges().to_lower()
	if clean_range.ends_with("mo"):
		var month_count: int = int(clean_range.substr(0, clean_range.length() - 2))
		if month_count > 0:
			return month_count * 31
	elif clean_range.ends_with("y"):
		var year_count: int = int(clean_range.substr(0, clean_range.length() - 1))
		if year_count > 0:
			return year_count * 365
	elif clean_range.ends_with("d"):
		var day_count: int = int(clean_range.substr(0, clean_range.length() - 1))
		if day_count > 0:
			return day_count

	var numeric_days: int = int(clean_range)
	if numeric_days > 0:
		return numeric_days

	return 365


func _parse_asset_input_text(input_text: String) -> PackedStringArray:
	var normalized_text: String = input_text.strip_edges()
	normalized_text = normalized_text.replace("\r\n", ",")
	normalized_text = normalized_text.replace("\n", ",")
	normalized_text = normalized_text.replace("\t", ",")
	normalized_text = normalized_text.replace(";", ",")
	normalized_text = normalized_text.replace("|", ",")

	var result: PackedStringArray = PackedStringArray()
	var seen_values: Dictionary = {}
	var parts: PackedStringArray = normalized_text.split(",", false)
	for raw_part in parts:
		var asset_symbol: String = str(raw_part).strip_edges()
		if asset_symbol.is_empty():
			continue

		var duplicate_key: String = asset_symbol.to_lower()
		if seen_values.has(duplicate_key):
			continue

		seen_values[duplicate_key] = true
		result.append(asset_symbol)

	return result


func _copy_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		for key in value:
			result[key] = value[key]

	return result
