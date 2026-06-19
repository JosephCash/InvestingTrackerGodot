extends RefCounted
class_name CurrencyConversionService


func convert_money(
	money: MoneyData,
	target_currency: String,
	fiat_assets: Dictionary,
	max_age_seconds: float = 0.0
) -> OperationResult:
	if money == null:
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Cannot convert null money.")

	var validation_errors: PackedStringArray = money.validate(true)
	if not validation_errors.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "Money is invalid: %s" % str(validation_errors))

	return convert_amount(money.amount, money.currency, target_currency, fiat_assets, max_age_seconds)


func convert_amount(
	amount: float,
	source_currency: String,
	target_currency: String,
	fiat_assets: Dictionary,
	max_age_seconds: float = 0.0
) -> OperationResult:
	var source: String = MoneyData.normalize_currency(source_currency)
	var target: String = MoneyData.normalize_currency(target_currency)

	if source.is_empty() or target.is_empty():
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Source and target currencies are required.")

	if source == target:
		return OperationResult.ok(_build_conversion_result(
			amount,
			source,
			target,
			1.0,
			amount,
			PackedStringArray([source]),
			"same_currency",
			PackedStringArray()
		), "Currency converted.")

	var rates: Array[Dictionary] = _collect_rates(fiat_assets, max_age_seconds)
	if rates.is_empty():
		return OperationResult.fail(ERR_INVALID_DATA, "No fiat exchange rates are available.")

	var direct_result: OperationResult = _find_direct_or_reverse_rate(amount, source, target, rates)
	if direct_result.is_ok():
		return direct_result

	var cross_result: OperationResult = _find_cross_rate(amount, source, target, rates)
	if cross_result.is_ok():
		return cross_result

	return OperationResult.fail(ERR_DOES_NOT_EXIST, "Missing fiat exchange rate path: %s -> %s." % [source, target])


func _collect_rates(fiat_assets: Dictionary, max_age_seconds: float) -> Array[Dictionary]:
	var rates: Array[Dictionary] = []
	var now: float = Time.get_unix_time_from_system()

	for key in fiat_assets:
		var asset_raw: Variant = fiat_assets[key]
		if not (asset_raw is AssetData):
			continue

		var asset: AssetData = asset_raw as AssetData
		if asset == null:
			continue

		if asset.asset_type.strip_edges().to_lower() != AssetData.TYPE_FIAT:
			continue

		var validation_errors: PackedStringArray = asset.validate()
		if not validation_errors.is_empty():
			continue

		if max_age_seconds > 0.0:
			var age_seconds: float = now - asset.last_updated
			if age_seconds > max_age_seconds:
				continue

		var latest_price: Dictionary = asset.get_latest_price_point()
		if latest_price.is_empty():
			continue

		var base_currency: String = MoneyData.normalize_currency(asset.symbol)
		var quote_currency: String = MoneyData.normalize_currency(str(latest_price.get("currency", asset.quote_currency)))
		var rate: float = float(latest_price.get("close", -1.0))
		if base_currency.is_empty() or quote_currency.is_empty() or rate <= 0.0:
			continue

		rates.append({
			"base": base_currency,
			"quote": quote_currency,
			"rate": rate,
			"source": str(latest_price.get("source", "")),
			"date": str(latest_price.get("date", "")),
			"cache_key": str(key)
		})

	return rates


func _find_direct_or_reverse_rate(
	amount: float,
	source: String,
	target: String,
	rates: Array[Dictionary]
) -> OperationResult:
	for rate_data in rates:
		var base: String = str(rate_data.get("base", ""))
		var quote: String = str(rate_data.get("quote", ""))
		var rate: float = float(rate_data.get("rate", 0.0))

		if base == source and quote == target:
			var converted_amount: float = amount * rate
			return OperationResult.ok(_build_conversion_result(
				amount,
				source,
				target,
				rate,
				converted_amount,
				PackedStringArray([source, target]),
				str(rate_data.get("source", "")),
				PackedStringArray()
			), "Currency converted.")

		if base == target and quote == source and rate > 0.0:
			var reverse_rate: float = 1.0 / rate
			var reverse_converted_amount: float = amount * reverse_rate
			return OperationResult.ok(_build_conversion_result(
				amount,
				source,
				target,
				reverse_rate,
				reverse_converted_amount,
				PackedStringArray([source, target]),
				str(rate_data.get("source", "")),
				PackedStringArray(["Used reverse fiat rate."])
			), "Currency converted.")

	return OperationResult.fail(ERR_DOES_NOT_EXIST, "Direct fiat exchange rate is not available.")


func _find_cross_rate(
	amount: float,
	source: String,
	target: String,
	rates: Array[Dictionary]
) -> OperationResult:
	for source_rate_data in rates:
		var source_base: String = str(source_rate_data.get("base", ""))
		var common_quote: String = str(source_rate_data.get("quote", ""))
		var source_rate: float = float(source_rate_data.get("rate", 0.0))

		if source_base != source or common_quote.is_empty() or source_rate <= 0.0:
			continue

		for target_rate_data in rates:
			var target_base: String = str(target_rate_data.get("base", ""))
			var target_quote: String = str(target_rate_data.get("quote", ""))
			var target_rate: float = float(target_rate_data.get("rate", 0.0))

			if target_base != target or target_quote != common_quote or target_rate <= 0.0:
				continue

			var cross_rate: float = source_rate / target_rate
			var converted_amount: float = amount * cross_rate
			var source_name: String = "%s+%s" % [
				str(source_rate_data.get("source", "")),
				str(target_rate_data.get("source", ""))
			]

			return OperationResult.ok(_build_conversion_result(
				amount,
				source,
				target,
				cross_rate,
				converted_amount,
				PackedStringArray([source, common_quote, target]),
				source_name,
				PackedStringArray(["Used cross fiat rate through %s." % common_quote])
			), "Currency converted.")

	return OperationResult.fail(ERR_DOES_NOT_EXIST, "Cross fiat exchange rate is not available.")


func _build_conversion_result(
	amount: float,
	source_currency: String,
	target_currency: String,
	rate: float,
	converted_amount: float,
	route: PackedStringArray,
	source: String,
	warnings: PackedStringArray
) -> Dictionary:
	return {
		"amount": amount,
		"source_currency": source_currency,
		"target_currency": target_currency,
		"rate": rate,
		"converted_amount": converted_amount,
		"route": route,
		"source": source,
		"warnings": warnings
	}
