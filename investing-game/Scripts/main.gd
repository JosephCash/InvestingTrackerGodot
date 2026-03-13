extends Node

func _ready():
	PortfolioManager.portfolio_updated.connect(_on_portfolio_updated)
	
	# Prosimy o krypto
	PortfolioManager.request_crypto_price("bitcoin")
	
	# Prosimy o fiat (np. Euro i Polski Złoty)
	PortfolioManager.request_fiat_price("eur")
	PortfolioManager.request_fiat_price("usd") # Skoro bazową walutą jest PLN, sprawdźmy wartość USD!

func _on_portfolio_updated(asset: ExchangeAssetData):
	var currency_symbol = SettingsManager.base_currency.to_upper()
	# Wyświetlamy np. "Otrzymano BITCOIN: 250000.00 PLN"
	print("Otrzymano %s: %f %s" % [asset.symbol, asset.price, currency_symbol])
