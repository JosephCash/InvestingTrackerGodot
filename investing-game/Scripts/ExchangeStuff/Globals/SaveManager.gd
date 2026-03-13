extends Node
# SaveManager.gd - Odpowiada wyłącznie za zapis i odczyt danych z dysku

const CACHE_FILE_PATH = "user://exchange_cache.json" # ZMIENIONA NAZWA PLIKU
const SETTINGS_FILE_PATH = "user://settings.json"

# ZMIENIONA NAZWA FUNKCJI
func save_exchange_cache(cached_assets: Dictionary):
	var dict_to_save = {
		"cache_currency": SettingsManager.base_currency,
		"assets": {}
	}
	for key in cached_assets:
		var asset = cached_assets[key]
		dict_to_save["assets"][key] = {
			"id": asset.id,
			"symbol": asset.symbol,
			"price": asset.price,
			"last_updated": asset.last_updated
		}
	
	var file = FileAccess.open(CACHE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(dict_to_save))
		print("[SaveManager] Zapisano lodówkę na dysku dla waluty: ", SettingsManager.base_currency)

# ZMIENIONA NAZWA FUNKCJI
func load_exchange_cache() -> Dictionary:
	var restored_assets: Dictionary = {}
	
	if not FileAccess.file_exists(CACHE_FILE_PATH):
		print("[SaveManager] Brak pliku zapisu, zaczynamy z pustą lodówką.")
		return restored_assets
		
	var file = FileAccess.open(CACHE_FILE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var parsed_data = JSON.parse_string(json_string)
		
		if parsed_data is Dictionary:
			if parsed_data.has("cache_currency") and parsed_data.has("assets"):
				if parsed_data["cache_currency"] != SettingsManager.base_currency:
					print("[SaveManager] Waluta w cache (", parsed_data["cache_currency"], ") różni się od obecnej (", SettingsManager.base_currency, "). Ignoruję stary plik!")
					return restored_assets 
					
				var assets_data = parsed_data["assets"]
				for key in assets_data:
					var data = assets_data[key]
					var restored_asset = ExchangeAssetData.new(data["id"], data["symbol"], data["price"], data["last_updated"])
					restored_assets[key] = restored_asset
			else:
				print("[SaveManager] Wykryto stary format cache. Wymuszam pobranie nowych danych.")
				return restored_assets
				
			print("[SaveManager] Pomyślnie załadowano dane ", restored_assets.size(), " aktywów z dysku.")
			
	return restored_assets
	
	# --- ZAPIS I ODCZYT USTAWIEŃ ---

func save_settings(settings_dict: Dictionary):
	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings_dict))
		print("[SaveManager] Zapisano ustawienia.")

func load_settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_FILE_PATH):
		return {} 
		
	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var parsed_data = JSON.parse_string(json_string)
		
		if parsed_data is Dictionary:
			return parsed_data
			
	return {}
