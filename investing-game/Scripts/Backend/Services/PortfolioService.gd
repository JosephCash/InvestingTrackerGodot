extends RefCounted
class_name PortfolioService

var repository := PortfolioRepository.new()


func create_portfolio(
	portfolio_id: String,
	name: String,
	portfolio_type: String = PortfolioData.TYPE_REGULAR,
	base_currency: String = "PLN",
	icon_name: String = "briefcase"
) -> OperationResult:
	var portfolio := PortfolioData.new()
	portfolio.id = portfolio_id.strip_edges()
	portfolio.name = name.strip_edges()
	portfolio.portfolio_type = portfolio_type.strip_edges().to_lower()
	portfolio.base_currency = MoneyData.normalize_currency(base_currency)
	portfolio.icon_name = icon_name.strip_edges()

	var validation_errors := portfolio.validate()
	if not validation_errors.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Portfolio is invalid: %s" % str(validation_errors))

	return repository.save_portfolio(portfolio)


func save_portfolio(portfolio: PortfolioData) -> OperationResult:
	return repository.save_portfolio(portfolio)


func load_portfolio(portfolio_id: String) -> OperationResult:
	return repository.load_portfolio(portfolio_id)


func load_all_portfolios() -> OperationResult:
	return repository.load_all_portfolios()


func delete_portfolio(portfolio_id: String) -> OperationResult:
	return repository.delete_portfolio(portfolio_id)


func update_portfolio_metadata(
	portfolio_id: String,
	name: String,
	portfolio_type: String,
	icon_name: String,
	base_currency: String
) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var update_error := portfolio.update_metadata(name, portfolio_type, icon_name, base_currency)
	if update_error != OK:
		return OperationResult.fail(update_error, "Cannot update portfolio metadata: %s" % error_string(update_error))

	return repository.save_portfolio(portfolio)


func add_deposit(
	portfolio_id: String,
	date: String,
	amount: float,
	currency: String,
	note: String = ""
) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var add_error := portfolio.add_deposit(date, amount, currency, note)
	if add_error != OK:
		return OperationResult.fail(add_error, "Cannot add deposit: %s" % error_string(add_error))

	return repository.save_portfolio(portfolio)


func update_deposit(
	portfolio_id: String,
	deposit_id: String,
	date: String,
	amount: float,
	currency: String,
	note: String = ""
) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var update_error := portfolio.update_deposit(deposit_id, date, amount, currency, note)
	if update_error != OK:
		return OperationResult.fail(update_error, "Cannot update deposit: %s" % error_string(update_error))

	return repository.save_portfolio(portfolio)


func delete_deposit(portfolio_id: String, deposit_id: String) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var delete_error := portfolio.delete_deposit(deposit_id)
	if delete_error != OK:
		return OperationResult.fail(delete_error, "Cannot delete deposit: %s" % error_string(delete_error))

	return repository.save_portfolio(portfolio)


func add_value_snapshot(
	portfolio_id: String,
	date: String,
	total_value: float,
	currency: String,
	note: String = ""
) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var add_error := portfolio.add_value_snapshot(date, total_value, currency, note)
	if add_error != OK:
		return OperationResult.fail(add_error, "Cannot add value snapshot: %s" % error_string(add_error))

	return repository.save_portfolio(portfolio)


func update_value_snapshot(
	portfolio_id: String,
	snapshot_id: String,
	date: String,
	total_value: float,
	currency: String,
	note: String = ""
) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var update_error := portfolio.update_value_snapshot(snapshot_id, date, total_value, currency, note)
	if update_error != OK:
		return OperationResult.fail(update_error, "Cannot update value snapshot: %s" % error_string(update_error))

	return repository.save_portfolio(portfolio)


func delete_value_snapshot(portfolio_id: String, snapshot_id: String) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var delete_error := portfolio.delete_value_snapshot(snapshot_id)
	if delete_error != OK:
		return OperationResult.fail(delete_error, "Cannot delete value snapshot: %s" % error_string(delete_error))

	return repository.save_portfolio(portfolio)


func add_bond_lot(portfolio_id: String, bond: BondLotData) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var add_error := portfolio.add_bond_lot(bond)
	if add_error != OK:
		return OperationResult.fail(add_error, "Cannot add bond lot: %s" % error_string(add_error))

	return repository.save_portfolio(portfolio)


func update_bond_lot(portfolio_id: String, bond_id: String, bond: BondLotData) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var update_error := portfolio.update_bond_lot(bond_id, bond)
	if update_error != OK:
		return OperationResult.fail(update_error, "Cannot update bond lot: %s" % error_string(update_error))

	return repository.save_portfolio(portfolio)


func delete_bond_lot(portfolio_id: String, bond_id: String) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var delete_error := portfolio.delete_bond_lot(bond_id)
	if delete_error != OK:
		return OperationResult.fail(delete_error, "Cannot delete bond lot: %s" % error_string(delete_error))

	return repository.save_portfolio(portfolio)


func estimate_bond_lots(
	portfolio_id: String,
	valuation_date: String,
	latest_monthly_inflation: InflationData = null
) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var valuation_service := BondValuationService.new()
	var valuation_results: Array[Dictionary] = []
	var errors := PackedStringArray()
	var totals_by_currency: Dictionary = {}

	for bond in portfolio.bond_lots:
		if bond == null:
			errors.append("Bond lot is null.")
			continue

		var result := valuation_service.estimate_value(bond, valuation_date, latest_monthly_inflation)
		if not result.is_ok():
			errors.append("%s: %s" % [bond.id, result.message])
			continue

		var valuation_data_raw: Variant = result.data
		if not (valuation_data_raw is Dictionary):
			errors.append("%s: valuation result has invalid format." % bond.id)
			continue

		var valuation: Dictionary = _copy_dictionary(valuation_data_raw)
		valuation_results.append(valuation)

		var currency := MoneyData.normalize_currency(str(valuation.get("currency", portfolio.base_currency)))
		var net_value: float = float(valuation.get("net_value", 0.0))
		totals_by_currency[currency] = float(totals_by_currency.get(currency, 0.0)) + net_value

	if not errors.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Some bond lots could not be valued: %s" % str(errors), {
			"valuations": valuation_results,
			"totals_by_currency": totals_by_currency
		})

	return OperationResult.ok({
		"portfolio_id": portfolio.id,
		"valuation_date": valuation_date.strip_edges(),
		"valuations": valuation_results,
		"totals_by_currency": totals_by_currency
	}, "Bond lots valued.")


func build_statistics(
	portfolio_id: String,
	monthly_inflation: Array[InflationData] = []
) -> OperationResult:
	var load_result := repository.load_portfolio(portfolio_id)
	if not load_result.is_ok():
		return load_result

	var portfolio: PortfolioData = load_result.data
	var analytics_service := PortfolioAnalyticsService.new()
	return analytics_service.calculate_portfolio_statistics(portfolio, monthly_inflation)


func build_dashboard(
	reference_currency: String,
	fiat_assets: Dictionary,
	max_rate_age_seconds: float = 0.0
) -> OperationResult:
	var load_result := repository.load_all_portfolios()
	if not load_result.is_ok():
		return load_result

	var portfolios: Array[PortfolioData] = []
	if load_result.data is Array:
		for item in load_result.data:
			if item is PortfolioData:
				portfolios.append(item)

	var dashboard_service := DashboardService.new()
	return dashboard_service.build_dashboard(reference_currency, portfolios, fiat_assets, max_rate_age_seconds)


func collect_dashboard_fiat_currencies(reference_currency: String) -> OperationResult:
	var load_result := repository.load_all_portfolios()
	if not load_result.is_ok():
		return load_result

	var portfolios: Array[PortfolioData] = []
	if load_result.data is Array:
		for item in load_result.data:
			if item is PortfolioData:
				portfolios.append(item)

	var dashboard_service := DashboardService.new()
	return OperationResult.ok(dashboard_service.collect_required_fiat_currencies(portfolios, reference_currency))


func build_summary(portfolio: PortfolioData) -> OperationResult:
	if portfolio == null:
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Cannot summarize null portfolio.")

	var validation_errors := portfolio.validate()
	if not validation_errors.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Cannot summarize invalid portfolio: %s" % str(validation_errors))

	var latest_snapshot := portfolio.get_latest_value_snapshot()
	var deposits_by_currency := portfolio.get_total_deposits()
	var nominal_result := _calculate_nominal_result(latest_snapshot, deposits_by_currency)
	var bond_principal_by_currency := _calculate_bond_principal_by_currency(portfolio.bond_lots)

	return OperationResult.ok({
		"portfolio_id": portfolio.id,
		"name": portfolio.name,
		"portfolio_type": portfolio.portfolio_type,
		"icon_name": portfolio.icon_name,
		"base_currency": portfolio.base_currency,
		"latest_snapshot": latest_snapshot,
		"deposits_by_currency": deposits_by_currency,
		"bond_lots_count": portfolio.bond_lots.size(),
		"bond_principal_by_currency": bond_principal_by_currency,
		"nominal_result": nominal_result
	})


func _calculate_nominal_result(latest_snapshot: Dictionary, deposits_by_currency: Dictionary) -> Dictionary:
	if latest_snapshot.is_empty():
		return {
			"available": false,
			"reason": "No value snapshot."
		}

	var currency := MoneyData.normalize_currency(str(latest_snapshot.get("currency", "")))
	if currency.is_empty() or not deposits_by_currency.has(currency):
		return {
			"available": false,
			"reason": "No deposits in snapshot currency."
		}

	var deposited := float(deposits_by_currency[currency])
	var current_value := float(latest_snapshot.get("total_value", 0.0))
	var profit := current_value - deposited
	var profit_percent := 0.0
	if deposited > 0.0:
		profit_percent = profit / deposited * 100.0

	return {
		"available": true,
		"currency": currency,
		"deposited": deposited,
		"current_value": current_value,
		"profit": profit,
		"profit_percent": profit_percent
	}


func _calculate_bond_principal_by_currency(bond_lots: Array[BondLotData]) -> Dictionary:
	var totals: Dictionary = {}

	for bond in bond_lots:
		if bond == null:
			continue

		var currency := MoneyData.normalize_currency(bond.currency)
		totals[currency] = float(totals.get(currency, 0.0)) + bond.get_principal()

	return totals


func _copy_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		for key in value:
			result[key] = value[key]

	return result
