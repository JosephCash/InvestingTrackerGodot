extends RefCounted
class_name BackendSmokeTest


func run() -> void:
	_run_portfolio_domain_smoke_test()
	_run_ticker_resolver_smoke_test()
	_run_inflation_calculator_smoke_test()
	_run_asset_model_smoke_test()


func _run_portfolio_domain_smoke_test() -> void:
	var service := PortfolioService.new()
	var portfolio := PortfolioData.new()
	portfolio.id = "demo_portfolio"
	portfolio.name = "Demo Portfolio"
	portfolio.portfolio_type = PortfolioData.TYPE_IKE
	portfolio.icon_name = "wallet"
	portfolio.base_currency = "PLN"

	var deposit_result := portfolio.add_deposit("2026-06-10", 1000.0, "PLN", "Initial test deposit")
	var snapshot_result := portfolio.add_value_snapshot("2026-06-10", 1025.50, "PLN", "Initial test snapshot")

	var save_result := service.save_portfolio(portfolio)

	var deposit_id := ""
	if not portfolio.deposits.is_empty() and portfolio.deposits[0] != null:
		deposit_id = portfolio.deposits[0].id

	var snapshot_id := ""
	if not portfolio.value_snapshots.is_empty() and portfolio.value_snapshots[0] != null:
		snapshot_id = portfolio.value_snapshots[0].id

	var metadata_result := service.update_portfolio_metadata(portfolio.id, "Edited Demo Portfolio", PortfolioData.TYPE_IKZE, "chart", "PLN")
	var update_deposit_result := OperationResult.fail(ERR_DOES_NOT_EXIST, "Deposit update was not run.")
	var update_snapshot_result := OperationResult.fail(ERR_DOES_NOT_EXIST, "Snapshot update was not run.")

	if not deposit_id.is_empty():
		update_deposit_result = service.update_deposit(portfolio.id, deposit_id, "2026-06-10", 1200.0, "PLN", "Edited test deposit")

	if not snapshot_id.is_empty():
		update_snapshot_result = service.update_value_snapshot(portfolio.id, snapshot_id, "2026-06-10", 1300.0, "PLN", "Edited test snapshot")

	var loaded_result := service.load_portfolio(portfolio.id)
	var summary_result := OperationResult.fail(ERR_DOES_NOT_EXIST, "Summary was not built.")
	if loaded_result.is_ok():
		var loaded_portfolio: PortfolioData = loaded_result.data
		summary_result = service.build_summary(loaded_portfolio)

	var all_result := service.load_all_portfolios()
	var portfolio_count := 0
	if all_result.is_ok() and all_result.data is Array:
		portfolio_count = all_result.data.size()

	var ok := (
		deposit_result == OK
		and snapshot_result == OK
		and portfolio.validate().is_empty()
		and save_result.is_ok()
		and metadata_result.is_ok()
		and update_deposit_result.is_ok()
		and update_snapshot_result.is_ok()
		and loaded_result.is_ok()
		and summary_result.is_ok()
		and all_result.is_ok()
	)

	print("[Smoke][Portfolio] ok=%s | portfolios=%s" % [ok, portfolio_count])


func _run_ticker_resolver_smoke_test() -> void:
	var yahoo_result := TickerResolver.resolve_for_yahoo("cndx.uk")
	var crypto_result := TickerResolver.resolve_for_coingecko("Ethereum")
	var fiat_result := TickerResolver.resolve_for_nbp("usd")

	var ok := (
		str(yahoo_result.get("symbol", "")) == "CNDX.L"
		and str(crypto_result.get("symbol", "")) == "ethereum"
		and str(fiat_result.get("symbol", "")) == "USD"
	)

	print("[Smoke][TickerResolver] ok=%s | cndx.uk=%s" % [ok, str(yahoo_result.get("symbol", ""))])


func _run_inflation_calculator_smoke_test() -> void:
	var monthly_inflation: Array[InflationData] = []
	monthly_inflation.append(_create_monthly_inflation(2025, 1, 101.0, 104.9))
	monthly_inflation.append(_create_monthly_inflation(2025, 2, 100.3, 104.9))

	var result := InflationCalculator.calculate_compounded_month_over_month_inflation(monthly_inflation)
	var compounded_rate := 0.0
	if result.is_ok() and result.data is Dictionary:
		compounded_rate = float(result.data.get("compounded_rate", 0.0))

	print("[Smoke][InflationCalculator] ok=%s | compounded_rate=%.4f%%" % [result.is_ok(), compounded_rate])


func _run_asset_model_smoke_test() -> void:
	var asset := AssetData.new()
	asset.id = "bitcoin"
	asset.symbol = "BTC"
	asset.name = "Bitcoin"
	asset.asset_type = AssetData.TYPE_CRYPTO
	asset.quote_currency = "USD"

	var price_result := asset.add_price_point("2026-06-10", 69000.0, "USD", "manual smoke test")
	var ok := price_result == OK and asset.validate().is_empty() and not asset.get_latest_price_point().is_empty()

	print("[Smoke][AssetData] ok=%s | symbol=%s" % [ok, asset.symbol])


func _create_monthly_inflation(year: int, month: int, month_over_month_index: float, year_over_year_index: float) -> InflationData:
	var inflation := InflationData.new()
	inflation.id = "test_cpi_%04d_%02d" % [year, month]
	inflation.name = "Test CPI monthly"
	inflation.country_code = "PL"
	inflation.period = InflationData.PERIOD_MONTHLY
	inflation.year = year
	inflation.month = month
	inflation.index_value = year_over_year_index
	inflation.inflation_rate = year_over_year_index - 100.0
	inflation.month_over_month_index = month_over_month_index
	inflation.month_over_month_rate = month_over_month_index - 100.0
	inflation.year_over_year_index = year_over_year_index
	inflation.year_over_year_rate = year_over_year_index - 100.0
	inflation.source = "manual smoke test"
	inflation.source_variable_id = "305"
	inflation.last_updated = Time.get_unix_time_from_system()
	return inflation
