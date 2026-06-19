extends RefCounted
class_name DashboardService


func build_dashboard(
	reference_currency: String,
	portfolios: Array[PortfolioData],
	fiat_assets: Dictionary,
	max_rate_age_seconds: float = 0.0
) -> OperationResult:
	var target_currency: String = MoneyData.normalize_currency(reference_currency)
	if target_currency.is_empty():
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Dashboard reference currency is empty.")

	var converter := CurrencyConversionService.new()
	var tiles: Array[Dictionary] = []
	var warnings: PackedStringArray = PackedStringArray()
	var total_value: float = 0.0
	var total_deposited: float = 0.0
	var available_count: int = 0
	var unavailable_count: int = 0

	for portfolio in portfolios:
		if portfolio == null:
			warnings.append("Skipped null portfolio.")
			unavailable_count += 1
			continue

		var tile: Dictionary = _build_portfolio_tile(portfolio, target_currency, converter, fiat_assets, max_rate_age_seconds)
		tiles.append(tile)

		if bool(tile.get("available", false)):
			available_count += 1
			total_value += float(tile.get("current_value", 0.0))
			total_deposited += float(tile.get("deposited", 0.0))
		else:
			unavailable_count += 1
			warnings.append("%s: %s" % [
				portfolio.id,
				str(tile.get("reason", "Portfolio dashboard tile is unavailable."))
			])

	var total_profit: float = total_value - total_deposited
	var total_profit_percent: float = 0.0
	if total_deposited > 0.0:
		total_profit_percent = total_profit / total_deposited * 100.0

	return OperationResult.ok({
		"reference_currency": target_currency,
		"portfolios": tiles,
		"portfolio_count": portfolios.size(),
		"available_portfolio_count": available_count,
		"unavailable_portfolio_count": unavailable_count,
		"total_value": total_value,
		"total_deposited": total_deposited,
		"total_profit": total_profit,
		"total_profit_percent": total_profit_percent,
		"warnings": warnings
	}, "Dashboard built.")


func collect_required_fiat_currencies(portfolios: Array[PortfolioData], reference_currency: String) -> PackedStringArray:
	var required: Dictionary = {}
	var target_currency: String = MoneyData.normalize_currency(reference_currency)
	if not target_currency.is_empty():
		required[target_currency] = true

	for portfolio in portfolios:
		if portfolio == null:
			continue

		var latest_snapshot: PortfolioSnapshotData = _latest_snapshot(portfolio)
		if latest_snapshot != null and latest_snapshot.total_value != null:
			var snapshot_currency: String = MoneyData.normalize_currency(latest_snapshot.total_value.currency)
			if not snapshot_currency.is_empty():
				required[snapshot_currency] = true

		for deposit in portfolio.deposits:
			if deposit == null or deposit.money == null:
				continue

			var deposit_currency: String = MoneyData.normalize_currency(deposit.money.currency)
			if not deposit_currency.is_empty():
				required[deposit_currency] = true

	var currencies: PackedStringArray = PackedStringArray()
	for currency in required:
		currencies.append(str(currency))

	currencies.sort()
	return currencies


func _build_portfolio_tile(
	portfolio: PortfolioData,
	target_currency: String,
	converter: CurrencyConversionService,
	fiat_assets: Dictionary,
	max_rate_age_seconds: float
) -> Dictionary:
	var validation_errors: PackedStringArray = portfolio.validate()
	if not validation_errors.is_empty():
		return _unavailable_tile(portfolio, target_currency, "Portfolio is invalid: %s" % str(validation_errors))

	var latest_snapshot: PortfolioSnapshotData = _latest_snapshot(portfolio)
	if latest_snapshot == null or latest_snapshot.total_value == null:
		return _unavailable_tile(portfolio, target_currency, "Portfolio has no value snapshot.")

	var current_result: OperationResult = converter.convert_money(
		latest_snapshot.total_value,
		target_currency,
		fiat_assets,
		max_rate_age_seconds
	)
	if not current_result.is_ok():
		return _unavailable_tile(portfolio, target_currency, "Cannot convert current value: %s" % current_result.message)

	var deposited_result: OperationResult = _convert_deposits(portfolio, target_currency, converter, fiat_assets, max_rate_age_seconds)
	if not deposited_result.is_ok():
		return _unavailable_tile(portfolio, target_currency, "Cannot convert deposits: %s" % deposited_result.message)

	var current_value: float = _converted_amount(current_result)
	var deposited: float = float(deposited_result.data)
	var profit: float = current_value - deposited
	var profit_percent: float = 0.0
	if deposited > 0.0:
		profit_percent = profit / deposited * 100.0

	return {
		"available": true,
		"portfolio_id": portfolio.id,
		"name": portfolio.name,
		"portfolio_type": portfolio.portfolio_type,
		"icon_name": portfolio.icon_name,
		"base_currency": portfolio.base_currency,
		"reference_currency": target_currency,
		"latest_snapshot_date": latest_snapshot.date,
		"current_value": current_value,
		"deposited": deposited,
		"profit": profit,
		"profit_percent": profit_percent
	}


func _convert_deposits(
	portfolio: PortfolioData,
	target_currency: String,
	converter: CurrencyConversionService,
	fiat_assets: Dictionary,
	max_rate_age_seconds: float
) -> OperationResult:
	var total: float = 0.0

	for deposit in portfolio.deposits:
		if deposit == null or deposit.money == null:
			continue

		var conversion_result: OperationResult = converter.convert_money(
			deposit.money,
			target_currency,
			fiat_assets,
			max_rate_age_seconds
		)
		if not conversion_result.is_ok():
			return conversion_result

		total += _converted_amount(conversion_result)

	return OperationResult.ok(total)


func _converted_amount(result: OperationResult) -> float:
	if result == null or not result.is_ok() or not (result.data is Dictionary):
		return 0.0

	var data_raw: Variant = result.data
	var data: Dictionary = _copy_dictionary(data_raw)
	return float(data.get("converted_amount", 0.0))


func _latest_snapshot(portfolio: PortfolioData) -> PortfolioSnapshotData:
	var latest: PortfolioSnapshotData = null
	var latest_key: int = -1

	for snapshot in portfolio.value_snapshots:
		if snapshot == null:
			continue

		var key: int = _date_key(snapshot.date)
		if key > latest_key:
			latest = snapshot
			latest_key = key

	return latest


func _date_key(date_value: String) -> int:
	var result: OperationResult = DateUtils.date_to_day_number(date_value)
	if not result.is_ok():
		return -1

	return int(result.data)


func _unavailable_tile(portfolio: PortfolioData, target_currency: String, reason: String) -> Dictionary:
	return {
		"available": false,
		"portfolio_id": portfolio.id,
		"name": portfolio.name,
		"portfolio_type": portfolio.portfolio_type,
		"icon_name": portfolio.icon_name,
		"base_currency": portfolio.base_currency,
		"reference_currency": target_currency,
		"reason": reason
	}


func _copy_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		for key in value:
			result[key] = value[key]

	return result
