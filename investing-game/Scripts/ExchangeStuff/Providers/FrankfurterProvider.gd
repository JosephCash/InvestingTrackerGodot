extends DataProvider
class_name FrankfurterProvider

func fetch_price(asset_id: String) -> void:
	# 1. Pobieramy z ustawień aktualną walutę bazową (np. "EUR", "PLN", "USD")
	var target_currency = SettingsManager.base_currency.to_upper()
	
	# 2. Pobieramy symbol waluty, o którą prosi nas gra (np. "EUR", "USD", "JPY")
	var symbol = asset_id.to_upper()
	
	# 3. SPRAWDZENIE UNIWERSALNE: 
	# Nieważne, jakie to waluty. Jeśli pytamy o to samo (np. PLN -> PLN, JPY -> JPY), 
	# to wartość to zawsze 1.0. Omijamy w ogóle łączenie się z internetem!
	if symbol == target_currency:
		var new_asset = ExchangeAssetData.new(asset_id, symbol, 1.0)
		fetch_successful.emit(new_asset)
		return # 'return' przerywa funkcję, więc kod poniżej się nie wykona
	
	# Jeśli waluty są RÓŻNE, normalnie pytamy API
	var url = "https://api.frankfurter.app/latest?from=%s&to=%s" % [symbol, target_currency]
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed.bind(http_request, asset_id, target_currency))
	
	var error = http_request.request(url)
	if error != OK:
		fetch_failed.emit("Błąd sieci Frankfurter dla: " + asset_id)
		http_request.queue_free()

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest, original_id: String, target_currency: String) -> void:
	http_request.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		fetch_failed.emit("Błąd Frankfurter API. Kod: " + str(response_code))
		return
		
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result == OK:
		var data = json.data
		if data.has("rates") and data["rates"].has(target_currency):
			var price = data["rates"][target_currency]
			var new_asset = ExchangeAssetData.new(original_id, original_id.to_upper(), price)
			fetch_successful.emit(new_asset)
		else:
			fetch_failed.emit("Nie znaleziono kursu dla: " + original_id)
