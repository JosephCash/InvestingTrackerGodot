extends Node


func _ready() -> void:
	BackendSmokeTest.new().run()

	PortfolioManager.portfolio_updated.connect(_on_portfolio_updated)
	PortfolioManager.asset_fetch_failed.connect(_on_asset_fetch_failed)
	MacroDataManager.inflation_updated.connect(_on_inflation_updated)
	MacroDataManager.monthly_inflation_updated.connect(_on_monthly_inflation_updated)
	MacroDataManager.macro_fetch_failed.connect(_on_macro_fetch_failed)

	PortfolioManager.request_crypto_price("bitcoin")
	PortfolioManager.request_crypto_price("ethereum")
	PortfolioManager.request_fiat_price("eur")
	PortfolioManager.request_fiat_price("usd")
	PortfolioManager.request_etf_price("CNDX.UK")
	PortfolioManager.request_etf_price("IB01.UK")
	PortfolioManager.request_etf_price("CBU0.UK")
	PortfolioManager.request_etf_price("EIMI.UK")
	PortfolioManager.request_stock_price("KOPN")
	MacroDataManager.request_latest_poland_inflation()
	MacroDataManager.request_latest_poland_monthly_inflation()


func _on_portfolio_updated(asset: AssetData) -> void:
	var latest_price := asset.get_latest_price_point()
	if latest_price.is_empty():
		print("[Price] ", asset.symbol, " has no price history.")
		return

	print(
		"[Price] %s (%s): %.6f %s | source=%s | date=%s" % [
			asset.symbol,
			asset.asset_type,
			float(latest_price["close"]),
			str(latest_price["currency"]),
			str(latest_price["source"]),
			str(latest_price["date"])
		]
	)


func _on_asset_fetch_failed(asset_id: String, error_message: String) -> void:
	print("[Price Error] %s -> %s" % [asset_id, error_message])


func _on_inflation_updated(inflation: InflationData) -> void:
	print(
		"[Inflation] %s %s: index=%.2f | rate=%.2f%% | source=%s:%s" % [
			inflation.country_code,
			inflation.year,
			inflation.index_value,
			inflation.inflation_rate,
			inflation.source,
			inflation.source_variable_id
		]
	)


func _on_monthly_inflation_updated(inflation: InflationData) -> void:
	print(
		"[Inflation Monthly] %s %s: MoM index=%.2f | MoM rate=%.2f%% | YoY index=%.2f | YoY rate=%.2f%% | source=%s:%s" % [
			inflation.country_code,
			inflation.get_period_label(),
			inflation.month_over_month_index,
			inflation.month_over_month_rate,
			inflation.year_over_year_index,
			inflation.year_over_year_rate,
			inflation.source,
			inflation.source_variable_id
		]
	)


func _on_macro_fetch_failed(source_id: String, error_message: String) -> void:
	print("[Macro Error] %s -> %s" % [source_id, error_message])
