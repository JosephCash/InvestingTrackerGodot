extends DataProvider
class_name YahooFinanceProvider


func fetch_price(asset_id: String) -> void:
	fetch_price_as(asset_id, AssetData.TYPE_OTHER)


func fetch_price_as(asset_id: String, preferred_asset_type: String) -> void:
	var resolved_symbol := TickerResolver.resolve_for_yahoo(asset_id)
	var symbol := str(resolved_symbol["symbol"])
	if symbol.is_empty():
		fetch_failed.emit(asset_id, "Yahoo Finance symbol is empty.")
		return

	var url := "https://query1.finance.yahoo.com/v8/finance/chart/%s?range=5d&interval=1d" % symbol.uri_encode()
	var headers := PackedStringArray([
		"User-Agent: Mozilla/5.0",
		"Accept: application/json"
	])

	var http_request := HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed.bind(http_request, symbol, preferred_asset_type))

	var error := http_request.request(url, headers)
	if error != OK:
		fetch_failed.emit(symbol, "Yahoo Finance request initialization failed: %s" % error_string(error))
		http_request.queue_free()


func fetch_history(asset_id: String, range_value: Variant = "1y", interval: String = "1d") -> void:
	fetch_history_as(asset_id, AssetData.TYPE_OTHER, str(range_value), interval)


func fetch_history_as(
	asset_id: String,
	preferred_asset_type: String,
	range_value: String = "1y",
	interval: String = "1d"
) -> void:
	var resolved_symbol := TickerResolver.resolve_for_yahoo(asset_id)
	var symbol := str(resolved_symbol["symbol"])
	if symbol.is_empty():
		fetch_history_failed.emit(asset_id, "Yahoo Finance history symbol is empty.")
		return

	var clean_range: String = range_value.strip_edges()
	if clean_range.is_empty():
		clean_range = "1y"

	var clean_interval: String = interval.strip_edges()
	if clean_interval.is_empty():
		clean_interval = "1d"

	var url := "https://query1.finance.yahoo.com/v8/finance/chart/%s?range=%s&interval=%s" % [
		symbol.uri_encode(),
		clean_range.uri_encode(),
		clean_interval.uri_encode()
	]
	var headers := PackedStringArray([
		"User-Agent: Mozilla/5.0",
		"Accept: application/json"
	])

	var http_request := HTTPRequest.new()
	http_request.timeout = 30.0
	add_child(http_request)
	http_request.request_completed.connect(_on_history_request_completed.bind(http_request, symbol, preferred_asset_type))

	var error := http_request.request(url, headers)
	if error != OK:
		fetch_history_failed.emit(symbol, "Yahoo Finance history request initialization failed: %s" % error_string(error))
		http_request.queue_free()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest,
	symbol: String,
	preferred_asset_type: String
) -> void:
	http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		fetch_failed.emit(symbol, "Yahoo Finance network error. Result: %s" % result)
		return

	if response_code == 429:
		fetch_failed.emit(symbol, "Yahoo Finance rate limit exceeded.")
		return

	if response_code == 404:
		fetch_failed.emit(symbol, "Yahoo Finance symbol not found.")
		return

	if response_code != 200:
		fetch_failed.emit(symbol, "Yahoo Finance HTTP error: %s" % response_code)
		return

	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		fetch_failed.emit(symbol, "Yahoo Finance JSON parse error.")
		return

	var data_raw: Variant = json.data
	if not (data_raw is Dictionary):
		fetch_failed.emit(symbol, "Yahoo Finance response root is invalid.")
		return

	var data: Dictionary = data_raw
	var chart_raw: Variant = data.get("chart", {})
	if not (chart_raw is Dictionary):
		fetch_failed.emit(symbol, "Yahoo Finance response does not contain chart data.")
		return

	var chart: Dictionary = chart_raw
	var chart_error: Variant = chart.get("error", null)
	if chart_error != null:
		fetch_failed.emit(symbol, "Yahoo Finance returned chart error: %s" % str(chart_error))
		return

	var results_raw: Variant = chart.get("result", [])
	if not (results_raw is Array):
		fetch_failed.emit(symbol, "Yahoo Finance response does not contain chart result.")
		return

	var results: Array = []
	results.assign(results_raw)
	if results.is_empty() or not (results[0] is Dictionary):
		fetch_failed.emit(symbol, "Yahoo Finance chart result is invalid.")
		return

	var result_data: Dictionary = results[0]
	var meta_raw: Variant = result_data.get("meta", {})
	if not (meta_raw is Dictionary):
		fetch_failed.emit(symbol, "Yahoo Finance chart metadata is invalid.")
		return

	var meta: Dictionary = meta_raw
	var price := _extract_latest_price(result_data, meta)
	if price < 0.0:
		fetch_failed.emit(symbol, "Yahoo Finance response does not contain a valid price.")
		return

	var quote_currency := str(meta.get("currency", "USD")).strip_edges().to_upper()
	if quote_currency.is_empty():
		quote_currency = "USD"

	var asset := AssetData.new()
	asset.id = symbol
	asset.symbol = str(meta.get("symbol", symbol)).strip_edges().to_upper()
	asset.name = asset.symbol
	asset.asset_type = _resolve_asset_type(meta, preferred_asset_type)
	asset.quote_currency = quote_currency
	asset.add_price_point(_date_from_meta(meta), price, quote_currency, "yahoo_finance")

	fetch_successful.emit(asset)


func _on_history_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest,
	symbol: String,
	preferred_asset_type: String
) -> void:
	http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		fetch_history_failed.emit(symbol, "Yahoo Finance history network error. Result: %s" % result)
		return

	if response_code == 429:
		fetch_history_failed.emit(symbol, "Yahoo Finance history rate limit exceeded.")
		return

	if response_code == 404:
		fetch_history_failed.emit(symbol, "Yahoo Finance history symbol not found.")
		return

	if response_code != 200:
		fetch_history_failed.emit(symbol, "Yahoo Finance history HTTP error: %s" % response_code)
		return

	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		fetch_history_failed.emit(symbol, "Yahoo Finance history JSON parse error.")
		return

	var data_raw: Variant = json.data
	if not (data_raw is Dictionary):
		fetch_history_failed.emit(symbol, "Yahoo Finance history response root is invalid.")
		return

	var data: Dictionary = data_raw
	var chart_raw: Variant = data.get("chart", {})
	if not (chart_raw is Dictionary):
		fetch_history_failed.emit(symbol, "Yahoo Finance history response does not contain chart data.")
		return

	var chart: Dictionary = chart_raw
	var chart_error: Variant = chart.get("error", null)
	if chart_error != null:
		fetch_history_failed.emit(symbol, "Yahoo Finance history returned chart error: %s" % str(chart_error))
		return

	var results_raw: Variant = chart.get("result", [])
	if not (results_raw is Array):
		fetch_history_failed.emit(symbol, "Yahoo Finance history response does not contain chart result.")
		return

	var results: Array = []
	results.assign(results_raw)
	if results.is_empty() or not (results[0] is Dictionary):
		fetch_history_failed.emit(symbol, "Yahoo Finance history chart result is invalid.")
		return

	var result_data: Dictionary = results[0]
	var meta_raw: Variant = result_data.get("meta", {})
	if not (meta_raw is Dictionary):
		fetch_history_failed.emit(symbol, "Yahoo Finance history chart metadata is invalid.")
		return

	var meta: Dictionary = meta_raw
	var timestamps_raw: Variant = result_data.get("timestamp", [])
	if not (timestamps_raw is Array):
		fetch_history_failed.emit(symbol, "Yahoo Finance history response does not contain timestamps.")
		return

	var quote_data_result: OperationResult = _quote_data_from_result(result_data)
	if not quote_data_result.is_ok():
		fetch_history_failed.emit(symbol, quote_data_result.message)
		return

	var quote_data: Dictionary = _copy_dictionary(quote_data_result.data)
	var close_values_raw: Variant = quote_data.get("close", [])
	if not (close_values_raw is Array):
		fetch_history_failed.emit(symbol, "Yahoo Finance history response does not contain close prices.")
		return

	var timestamps: Array = []
	timestamps.assign(timestamps_raw)
	var close_values: Array = []
	close_values.assign(close_values_raw)

	var quote_currency := str(meta.get("currency", "USD")).strip_edges().to_upper()
	if quote_currency.is_empty():
		quote_currency = "USD"

	var asset := AssetData.new()
	asset.id = symbol
	asset.symbol = str(meta.get("symbol", symbol)).strip_edges().to_upper()
	asset.name = asset.symbol
	asset.asset_type = _resolve_asset_type(meta, preferred_asset_type)
	asset.quote_currency = quote_currency

	for index in range(timestamps.size()):
		if index >= close_values.size():
			break

		var close_value: Variant = close_values[index]
		if close_value == null:
			continue

		var close_price: float = float(close_value)
		if close_price < 0.0:
			continue

		asset.add_price_point(
			_date_string_from_unix_time(float(timestamps[index])),
			close_price,
			quote_currency,
			"yahoo_finance:history"
		)

	if asset.price_history.is_empty():
		fetch_history_failed.emit(symbol, "Yahoo Finance history response contains no valid price points.")
		return

	fetch_history_successful.emit(asset)


func _extract_latest_price(result_data: Dictionary, meta: Dictionary) -> float:
	if meta.has("regularMarketPrice") and meta["regularMarketPrice"] != null:
		return float(meta["regularMarketPrice"])

	var quote_data_result: OperationResult = _quote_data_from_result(result_data)
	if not quote_data_result.is_ok():
		return -1.0

	var first_quote: Dictionary = _copy_dictionary(quote_data_result.data)
	var close_values_raw: Variant = first_quote.get("close", [])
	if not (close_values_raw is Array):
		return -1.0

	var close_values: Array = []
	close_values.assign(close_values_raw)
	if close_values.is_empty():
		return -1.0

	var index: int = close_values.size() - 1
	while index >= 0:
		var close_value: Variant = close_values[index]
		if close_value != null:
			return float(close_value)
		index -= 1

	return -1.0


func _quote_data_from_result(result_data: Dictionary) -> OperationResult:
	var indicators_raw: Variant = result_data.get("indicators", {})
	if not (indicators_raw is Dictionary):
		return OperationResult.fail(ERR_INVALID_DATA, "Yahoo Finance response does not contain indicators.")

	var indicators: Dictionary = indicators_raw
	var quote_list_raw: Variant = indicators.get("quote", [])
	if not (quote_list_raw is Array):
		return OperationResult.fail(ERR_INVALID_DATA, "Yahoo Finance response does not contain quote list.")

	var quote_list: Array = []
	quote_list.assign(quote_list_raw)
	if quote_list.is_empty() or not (quote_list[0] is Dictionary):
		return OperationResult.fail(ERR_INVALID_DATA, "Yahoo Finance quote data is invalid.")

	return OperationResult.ok(quote_list[0])


func _resolve_asset_type(meta: Dictionary, preferred_asset_type: String) -> String:
	var instrument_type := str(meta.get("instrumentType", "")).strip_edges().to_lower()

	if instrument_type == "etf":
		return AssetData.TYPE_ETF
	if instrument_type == "equity":
		return AssetData.TYPE_STOCK
	if not preferred_asset_type.strip_edges().is_empty() and preferred_asset_type != AssetData.TYPE_OTHER:
		return preferred_asset_type

	return AssetData.TYPE_OTHER


func _date_from_meta(meta: Dictionary) -> String:
	if meta.has("regularMarketTime") and meta["regularMarketTime"] != null:
		return _date_string_from_unix_time(float(meta["regularMarketTime"]))

	return _date_string_from_unix_time(Time.get_unix_time_from_system())


func _date_string_from_unix_time(unix_time: float) -> String:
	var date_parts := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return "%04d-%02d-%02d" % [
		int(date_parts["year"]),
		int(date_parts["month"]),
		int(date_parts["day"])
	]


func _copy_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		for key in value:
			result[key] = value[key]

	return result
