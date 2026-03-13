extends Node
# SaveManager.gd - Odpowiada wyłącznie za zapis i odczyt danych z dysku

const CACHE_FILE_PATH = "user://crypto_cache.json"
const SETTINGS_FILE_PATH = "user://settings.json"

# Przyjmuje Słownik z danymi i zapisuje go do pliku
func save_crypto_cache(cached_assets: Dictionary):
	var dict_to_save = {}
	for key in cached_assets:
		var asset = cached_assets[key]
		dict_to_save[key] = {
			"id": asset.id,
			"symbol": asset.symbol,
			"price_usd": asset.price_usd,
			"last_updated": asset.last_updated
		}
	
	var file = FileAccess.open(CACHE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(dict_to_save))
		print("[SaveManager] Zapisano lodówkę na dysku.")

# Zwraca wczytany Słownik (lub pusty, jeśli plik nie istnieje)
func load_crypto_cache() -> Dictionary:
	var restored_assets: Dictionary = {}
	
	if not FileAccess.file_exists(CACHE_FILE_PATH):
		print("[SaveManager] Brak pliku zapisu, zaczynamy z pustą lodówką.")
		return restored_assets
		
	var file = FileAccess.open(CACHE_FILE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var parsed_data = JSON.parse_string(json_string)
		
		if parsed_data is Dictionary:
			for key in parsed_data:
				var data = parsed_data[key]
				var restored_asset = ExchangeAssetData.new(data["id"], data["symbol"], data["price_usd"], data["last_updated"])
				restored_assets[key] = restored_asset
				
			print("[SaveManager] Pomyślnie załadowano dane ", restored_assets.size(), " krypto z dysku.")
			
	return restored_assets
	
	# --- ZAPIS I ODCZYT USTAWIEŃ ---

func save_settings(settings_dict: Dictionary):
	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings_dict))
		print("[SaveManager] Zapisano ustawienia.")

func load_settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_FILE_PATH):
		return {} # Zwracamy pusty słownik, jeśli gracz odpala apkę pierwszy raz
		
	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var parsed_data = JSON.parse_string(json_string)
		
		if parsed_data is Dictionary:
			return parsed_data
			
	return {}
