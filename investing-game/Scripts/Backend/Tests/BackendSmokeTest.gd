extends RefCounted
class_name BackendSmokeTest

const TEST_PORTFOLIO_ID := "__smoke_test_portfolio__"


func run() -> void:
	_run_portfolio_domain_smoke_test()
	_run_portfolio_analytics_smoke_test()
	_run_currency_conversion_smoke_test()
	_run_ticker_resolver_smoke_test()
	_run_inflation_calculator_smoke_test()
	_run_bond_valuation_smoke_test()
	_run_asset_model_smoke_test()


func _run_portfolio_domain_smoke_test() -> void:
	var service := PortfolioService.new()
	service.delete_portfolio(TEST_PORTFOLIO_ID)

	var portfolio := PortfolioData.new()
	portfolio.id = TEST_PORTFOLIO_ID
	portfolio.name = "Smoke Test Portfolio"
	portfolio.portfolio_type = PortfolioData.TYPE_IKE
	portfolio.icon_name = "wallet"
	portfolio.base_currency = "PLN"

	var deposit_result := portfolio.add_deposit("2026-06-10", 1000.0, "PLN", "Initial test deposit")
	var snapshot_result := portfolio.add_value_snapshot("2026-06-10", 1025.50, "PLN", "Initial test snapshot")

	var save_result := service.save_portfolio(portfolio)
	var bond := BondLotData.create_fixed_rate("TOS_TEST", "2025-06-10", "2028-06-10", 10, 6.0, "Portfolio smoke bond")
	var add_bond_result := service.add_bond_lot(portfolio.id, bond)

	var deposit_id := ""
	if not portfolio.deposits.is_empty() and portfolio.deposits[0] != null:
		deposit_id = portfolio.deposits[0].id

	var snapshot_id := ""
	if not portfolio.value_snapshots.is_empty() and portfolio.value_snapshots[0] != null:
		snapshot_id = portfolio.value_snapshots[0].id

	var metadata_result := service.update_portfolio_metadata(portfolio.id, "Edited Demo Portfolio", PortfolioData.TYPE_IKZE, "chart", "PLN")
	var update_deposit_result := OperationResult.fail(ERR_DOES_NOT_EXIST, "Deposit update was not run.")
	var update_snapshot_result := OperationResult.fail(ERR_DOES_NOT_EXIST, "Snapshot update was not run.")
	var update_bond_result := OperationResult.fail(ERR_DOES_NOT_EXIST, "Bond update was not run.")

	if not deposit_id.is_empty():
		update_deposit_result = service.update_deposit(portfolio.id, deposit_id, "2026-06-10", 1200.0, "PLN", "Edited test deposit")

	if not snapshot_id.is_empty():
		update_snapshot_result = service.update_value_snapshot(portfolio.id, snapshot_id, "2026-06-10", 1300.0, "PLN", "Edited test snapshot")

	if not bond.id.is_empty():
		var updated_bond := BondLotData.create_fixed_rate("TOS_TEST", "2025-06-10", "2028-06-10", 10, 6.5, "Edited portfolio smoke bond")
		update_bond_result = service.update_bond_lot(portfolio.id, bond.id, updated_bond)

	var loaded_result := service.load_portfolio(portfolio.id)
	var summary_result := OperationResult.fail(ERR_DOES_NOT_EXIST, "Summary was not built.")
	if loaded_result.is_ok():
		var loaded_portfolio: PortfolioData = loaded_result.data
		summary_result = service.build_summary(loaded_portfolio)

	var bond_estimate_result := service.estimate_bond_lots(portfolio.id, "2026-06-10", _create_monthly_inflation(2025, 12, 100.0, 102.4))
	var all_result := service.load_all_portfolios()
	var portfolio_count := 0
	if all_result.is_ok() and all_result.data is Array:
		portfolio_count = all_result.data.size()

	var cleanup_result := service.delete_portfolio(TEST_PORTFOLIO_ID)

	var ok := (
		deposit_result == OK
		and snapshot_result == OK
		and portfolio.validate().is_empty()
		and save_result.is_ok()
		and add_bond_result.is_ok()
		and metadata_result.is_ok()
		and update_deposit_result.is_ok()
		and update_snapshot_result.is_ok()
		and update_bond_result.is_ok()
		and loaded_result.is_ok()
		and summary_result.is_ok()
		and bond_estimate_result.is_ok()
		and all_result.is_ok()
		and cleanup_result.is_ok()
	)

	print("[Smoke][Portfolio] ok=%s | portfolios_before_cleanup=%s" % [ok, portfolio_count])


func _run_portfolio_analytics_smoke_test() -> void:
	var service := PortfolioService.new()
	service.delete_portfolio(TEST_PORTFOLIO_ID)

	var portfolio := PortfolioData.new()
	portfolio.id = TEST_PORTFOLIO_ID
	portfolio.name = "Analytics Smoke Portfolio"
	portfolio.portfolio_type = PortfolioData.TYPE_REGULAR
	portfolio.icon_name = "chart"
	portfolio.base_currency = "PLN"

	portfolio.add_deposit("2025-06-10", 1000.0, "PLN", "Initial analytics test deposit")
	portfolio.add_deposit("2025-12-10", 200.0, "PLN", "Second analytics test deposit")
	portfolio.add_value_snapshot("2025-12-31", 1120.0, "PLN", "Mid analytics test snapshot")
	portfolio.add_value_snapshot("2026-06-10", 1400.0, "PLN", "Final analytics test snapshot")

	var save_result := service.save_portfolio(portfolio)
	var inflation_series: Array[InflationData] = _create_flat_monthly_inflation_series(2025, 6, 13, 100.2)
	var analytics_result := service.build_statistics(portfolio.id, inflation_series)
	var cleanup_result := service.delete_portfolio(TEST_PORTFOLIO_ID)

	var investing_months := 0
	var cagr_rate := 0.0
	var real_available := false
	var chart_points := 0

	if analytics_result.is_ok() and analytics_result.data is Dictionary:
		var stats_raw: Variant = analytics_result.data
		var stats: Dictionary = _copy_dictionary(stats_raw)
		investing_months = int(stats.get("investing_months", 0))

		var cagr_raw: Variant = stats.get("cagr", {})
		if cagr_raw is Dictionary:
			var cagr: Dictionary = _copy_dictionary(cagr_raw)
			cagr_rate = float(cagr.get("rate", 0.0))

		var real_result_raw: Variant = stats.get("real_result", {})
		if real_result_raw is Dictionary:
			var real_result: Dictionary = _copy_dictionary(real_result_raw)
			real_available = bool(real_result.get("available", false))

		var chart_series_raw: Variant = stats.get("chart_series", {})
		if chart_series_raw is Dictionary:
			var chart_series: Dictionary = _copy_dictionary(chart_series_raw)
			var capital_history_raw: Variant = chart_series.get("capital_history", {})
			if capital_history_raw is Dictionary:
				var capital_history: Dictionary = _copy_dictionary(capital_history_raw)
				var deposits_raw: Variant = capital_history.get("deposits", [])
				var value_raw: Variant = capital_history.get("portfolio_value", [])
				if deposits_raw is Array:
					chart_points += deposits_raw.size()
				if value_raw is Array:
					chart_points += value_raw.size()

	var ok := (
		save_result.is_ok()
		and analytics_result.is_ok()
		and cleanup_result.is_ok()
		and investing_months == 13
		and real_available
		and chart_points >= 4
	)

	print("[Smoke][Analytics] ok=%s | months=%s | cagr=%.4f%% | chart_points=%s" % [
		ok,
		investing_months,
		cagr_rate,
		chart_points
	])


func _run_currency_conversion_smoke_test() -> void:
	var service := CurrencyConversionService.new()
	var fiat_cache: Dictionary = {}
	fiat_cache["eur"] = _create_fiat_asset("eur", "EUR", 1.20, "USD")
	fiat_cache["pln"] = _create_fiat_asset("pln", "PLN", 0.25, "USD")
	fiat_cache["usd"] = _create_fiat_asset("usd", "USD", 1.00, "USD")

	var eur_pln_result := service.convert_amount(10.0, "EUR", "PLN", fiat_cache, 900.0)
	var usd_pln_result := service.convert_amount(100.0, "USD", "PLN", fiat_cache, 900.0)
	var pln_usd_result := service.convert_amount(100.0, "PLN", "USD", fiat_cache, 900.0)
	var same_result := service.convert_amount(7.5, "PLN", "PLN", fiat_cache, 900.0)

	var eur_pln: float = _converted_amount(eur_pln_result)
	var usd_pln: float = _converted_amount(usd_pln_result)
	var pln_usd: float = _converted_amount(pln_usd_result)
	var same_amount: float = _converted_amount(same_result)

	var ok := (
		eur_pln_result.is_ok()
		and usd_pln_result.is_ok()
		and pln_usd_result.is_ok()
		and same_result.is_ok()
		and _is_close(eur_pln, 48.0)
		and _is_close(usd_pln, 400.0)
		and _is_close(pln_usd, 25.0)
		and _is_close(same_amount, 7.5)
	)

	print("[Smoke][CurrencyConversion] ok=%s | 10EUR_PLN=%.4f | 100USD_PLN=%.4f | 100PLN_USD=%.4f" % [
		ok,
		eur_pln,
		usd_pln,
		pln_usd
	])


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


func _run_bond_valuation_smoke_test() -> void:
	var service := BondValuationService.new()

	var fixed_bond := BondLotData.create_fixed_rate("TOS_TEST", "2025-06-10", "2028-06-10", 10, 6.0, "Fixed smoke test")
	var fixed_result := service.estimate_value(fixed_bond, "2026-06-10")

	var inflation_bond := BondLotData.create_inflation_indexed("COI_TEST", "2024-06-10", "2028-06-10", 10, 6.0, 1.5, "Inflation smoke test")
	var inflation := _create_monthly_inflation(2025, 12, 100.0, 102.4)
	var inflation_result := service.estimate_value(inflation_bond, "2026-06-10", inflation)

	print("[Smoke][BondValuation] fixed_ok=%s | inflation_ok=%s" % [fixed_result.is_ok(), inflation_result.is_ok()])


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


func _create_flat_monthly_inflation_series(
	start_year: int,
	start_month: int,
	months: int,
	month_over_month_index: float
) -> Array[InflationData]:
	var result: Array[InflationData] = []
	var year: int = start_year
	var month: int = start_month

	for _index in range(months):
		result.append(_create_monthly_inflation(year, month, month_over_month_index, 100.0))

		month += 1
		if month > 12:
			month = 1
			year += 1

	return result


func _create_fiat_asset(asset_id: String, symbol: String, rate: float, quote_currency: String) -> AssetData:
	var asset := AssetData.new()
	asset.id = asset_id.strip_edges().to_lower()
	asset.symbol = symbol.strip_edges().to_upper()
	asset.name = asset.symbol
	asset.asset_type = AssetData.TYPE_FIAT
	asset.quote_currency = MoneyData.normalize_currency(quote_currency)
	asset.add_price_point("2026-06-12", rate, asset.quote_currency, "manual smoke test")
	return asset


func _converted_amount(result: OperationResult) -> float:
	if result == null or not result.is_ok():
		return -1.0

	if not (result.data is Dictionary):
		return -1.0

	var data_raw: Variant = result.data
	var data: Dictionary = _copy_dictionary(data_raw)
	return float(data.get("converted_amount", -1.0))


func _is_close(left: float, right: float) -> bool:
	return absf(left - right) < 0.0001


func _copy_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		for key in value:
			result[key] = value[key]

	return result
