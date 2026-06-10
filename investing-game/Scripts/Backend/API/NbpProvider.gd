extends DataProvider
class_name NbpProvider

const NBP_TABLE_A_URL := "https://api.nbp.pl/api/exchangerates/tables/A?format=json"
const PLN_CODE := "PLN"


func fetch_price(asset_id: String) -> void:
	var symbol := asset_id.strip_edges().to_upper()
	var quote_currency := SettingsManager.base_currency.to_upper()

	if symbol.is_empty():
		fetch_failed.emit(asset_id, "NBP fiat symbol is empty.")
		return

	if symbol == quote_currency:
		var same_currency_asset := _create_fiat_asset(symbol.to_lower(), symbol, 1.0, quote_currency, _today_string(), "nbp:same-currency")
		fetch_successful.emit(same_currency_asset)
		return

	var http_request := HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed.bind(http_request, symbol, quote_currency))

	var error := http_request.request(NBP_TABLE_A_URL)
	if error != OK:
		fetch_failed.emit(symbol.to_lower(), "NBP request initialization failed: %s" % error_string(error))
		http_request.queue_free()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http_request: HTTPRequest,
	symbol: String,
	quote_currency: String
) -> void:
	http_request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		fetch_failed.emit(symbol.to_lower(), "NBP network error. Result: %s" % result)
		return

	if response_code == 429:
		fetch_failed.emit(symbol.to_lower(), "NBP rate limit exceeded.")
		return

	if response_code != 200:
		fetch_failed.emit(symbol.to_lower(), "NBP HTTP error: %s" % response_code)
		return

	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		fetch_failed.emit(symbol.to_lower(), "NBP JSON parse error.")
		return

	var data = json.data
	if not (data is Array) or data.is_empty():
		fetch_failed.emit(symbol.to_lower(), "NBP response does not contain table data.")
		return

	var table = data[0]
	if not (table is Dictionary) or not table.has("rates"):
		fetch_failed.emit(symbol.to_lower(), "NBP response has invalid table format.")
		return

	var rates_by_code := _build_rates_by_code(table["rates"])
	var price := _calculate_cross_rate(symbol, quote_currency, rates_by_code)
	if price < 0.0:
		fetch_failed.emit(symbol.to_lower(), "NBP cannot calculate %s/%s rate." % [symbol, quote_currency])
		return

	var effective_date := str(table.get("effectiveDate", _today_string()))
	var asset := _create_fiat_asset(symbol.to_lower(), symbol, price, quote_currency, effective_date, "nbp")
	fetch_successful.emit(asset)


func _build_rates_by_code(rates: Variant) -> Dictionary:
	var rates_by_code: Dictionary = {
		PLN_CODE: 1.0
	}

	if not (rates is Array):
		return rates_by_code

	for rate in rates:
		if rate is Dictionary and rate.has("code") and rate.has("mid"):
			rates_by_code[str(rate["code"]).to_upper()] = float(rate["mid"])

	return rates_by_code


func _calculate_cross_rate(symbol: String, quote_currency: String, rates_by_code: Dictionary) -> float:
	if not rates_by_code.has(symbol) or not rates_by_code.has(quote_currency):
		return -1.0

	var symbol_to_pln := float(rates_by_code[symbol])
	var quote_to_pln := float(rates_by_code[quote_currency])
	if quote_to_pln <= 0.0:
		return -1.0

	return symbol_to_pln / quote_to_pln


func _create_fiat_asset(
	asset_id: String,
	symbol: String,
	price: float,
	quote_currency: String,
	price_date: String,
	source: String
) -> AssetData:
	var asset := AssetData.new()
	asset.id = asset_id
	asset.symbol = symbol
	asset.name = symbol
	asset.asset_type = AssetData.TYPE_FIAT
	asset.quote_currency = quote_currency
	asset.add_price_point(price_date, price, quote_currency, source)
	return asset


func _today_string() -> String:
	var date_parts := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [
		int(date_parts["year"]),
		int(date_parts["month"]),
		int(date_parts["day"])
	]
