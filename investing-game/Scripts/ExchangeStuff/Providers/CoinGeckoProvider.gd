extends DataProvider
class_name CoinGeckoProvider

func fetch_price(asset_id: String) -> void:
	# Pobieramy dynamicznie walutę bazową (np. "pln")
	var vs_currency = SettingsManager.base_currency.to_lower()
	var url = "https://api.coingecko.com/api/v3/simple/price?ids=%s&vs_currencies=%s" % [asset_id, vs_currency]
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed.bind(http_request, vs_currency))
	
	var error = http_request.request(url)
	if error != OK:
		fetch_failed.emit("Błąd inicjalizacji zapytania dla: " + asset_id)
		http_request.queue_free()

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest, target_currency: String) -> void:
	http_request.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		fetch_failed.emit("Błąd pobierania z API. Kod: " + str(response_code))
		return
		
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result == OK:
		var data = json.data
		if data.is_empty():
			fetch_failed.emit("Brak danych.")
			return
			
		var first_key = data.keys()[0] 
		# Zamiast "usd" pobieramy wartość dla target_currency
		var price = data[first_key][target_currency] 
		
		var new_asset = ExchangeAssetData.new(first_key, first_key.to_upper(), price)
		fetch_successful.emit(new_asset)
	else:
		fetch_failed.emit("Błąd parsowania JSON")
