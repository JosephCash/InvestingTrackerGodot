extends Node
# PortfolioManager.gd

signal portfolio_updated(asset: ExchangeAssetData) 

const CACHE_DURATION = 18000 # 5 godzin

var cached_assets: Dictionary = {}

# Mamy dwóch specjalistów
var crypto_api: CoinGeckoProvider
var fiat_api: FrankfurterProvider

func _ready():
	cached_assets = SaveManager.load_crypto_cache()
	
	# Inicjujemy Kucharza Krypto
	crypto_api = CoinGeckoProvider.new()
	add_child(crypto_api)
	crypto_api.fetch_successful.connect(_on_asset_fetched)
	
	# Inicjujemy Kucharza Fiat
	fiat_api = FrankfurterProvider.new()
	add_child(fiat_api)
	fiat_api.fetch_successful.connect(_on_asset_fetched)

# Funkcja uniwersalna do sprawdzania Cache'a (żeby nie powtarzać kodu)
func _check_cache(asset_id: String) -> bool:
	if cached_assets.has(asset_id):
		var asset = cached_assets[asset_id]
		if Time.get_unix_time_from_system() - asset.last_updated < CACHE_DURATION:
			print("[Cache] Dane aktualne dla: ", asset_id)
			portfolio_updated.emit(asset)
			return true
	return false

# Brama dla krypto
func request_crypto_price(crypto_id: String):
	if not _check_cache(crypto_id):
		print("[API] Pobieram krypto: ", crypto_id)
		crypto_api.fetch_price(crypto_id)

# Brama dla walut tradycyjnych (Fiat)
func request_fiat_price(fiat_id: String):
	if not _check_cache(fiat_id):
		print("[API] Pobieram fiat: ", fiat_id)
		fiat_api.fetch_price(fiat_id)

func _on_asset_fetched(asset: ExchangeAssetData):
	cached_assets[asset.id] = asset 
	SaveManager.save_crypto_cache(cached_assets) 
	portfolio_updated.emit(asset)
