extends Node

func _ready():
	PortfolioManager.portfolio_updated.connect(_on_portfolio_updated)
	
	# Prosimy o krypto
	PortfolioManager.request_crypto_price("bitcoin")
	
	# Prosimy o fiat (np. Euro i Polski Złoty)
	PortfolioManager.request_fiat_price("eur")
	PortfolioManager.request_fiat_price("pln")

func _on_portfolio_updated(asset: ExchangeAssetData):
	print("Otrzymano %s: $%f" % [asset.symbol, asset.price_usd])
