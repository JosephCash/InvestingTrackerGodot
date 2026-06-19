extends Node

signal dashboard_updated(dashboard: Dictionary)
signal dashboard_failed(error_message: String)
signal portfolio_saved(portfolio_id: String)
signal portfolio_deleted(portfolio_id: String)
signal portfolio_operation_failed(operation: String, error_message: String)

var _service: PortfolioService = PortfolioService.new()
var _dashboard_required_fiat: Dictionary = {}
var _last_dashboard_signature: String = ""
var _dashboard_refresh_suspended: bool = false
var _dashboard_refresh_pending: bool = false
var _pending_dashboard_reference_currency: String = ""


func _ready() -> void:
	PortfolioManager.portfolio_updated.connect(_on_price_asset_updated)
	PortfolioManager.asset_fetch_failed.connect(_on_price_asset_fetch_failed)
	SettingsManager.base_currency_changed.connect(_on_base_currency_changed)


func create_portfolio(
	portfolio_id: String,
	portfolio_name: String,
	portfolio_type: String = PortfolioData.TYPE_REGULAR,
	base_currency: String = "PLN",
	icon_name: String = "briefcase"
) -> OperationResult:
	var result: OperationResult = _service.create_portfolio(
		portfolio_id,
		portfolio_name,
		portfolio_type,
		base_currency,
		icon_name
	)
	return _handle_portfolio_mutation("create_portfolio", portfolio_id, result)


func create_portfolio_auto_id(
	portfolio_name: String,
	portfolio_type: String = PortfolioData.TYPE_REGULAR,
	base_currency: String = "PLN",
	icon_name: String = "briefcase"
) -> OperationResult:
	var portfolio_id_result: OperationResult = _generate_unique_portfolio_id(portfolio_name)
	if not portfolio_id_result.is_ok():
		portfolio_operation_failed.emit("create_portfolio_auto_id", portfolio_id_result.message)
		return portfolio_id_result

	var portfolio_id: String = str(portfolio_id_result.data)
	return create_portfolio(portfolio_id, portfolio_name, portfolio_type, base_currency, icon_name)


func update_portfolio_metadata(
	portfolio_id: String,
	portfolio_name: String,
	portfolio_type: String,
	icon_name: String,
	base_currency: String
) -> OperationResult:
	var result: OperationResult = _service.update_portfolio_metadata(
		portfolio_id,
		portfolio_name,
		portfolio_type,
		icon_name,
		base_currency
	)
	return _handle_portfolio_mutation("update_portfolio_metadata", portfolio_id, result)


func delete_portfolio(portfolio_id: String) -> OperationResult:
	var result: OperationResult = _service.delete_portfolio(portfolio_id)
	if result.is_ok():
		portfolio_deleted.emit(portfolio_id)
		_request_dashboard_refresh()
	else:
		portfolio_operation_failed.emit("delete_portfolio", result.message)

	return result


func add_deposit(
	portfolio_id: String,
	date: String,
	amount: float,
	currency: String,
	note: String = ""
) -> OperationResult:
	var result: OperationResult = _service.add_deposit(portfolio_id, date, amount, currency, note)
	return _handle_portfolio_mutation("add_deposit", portfolio_id, result)


func update_deposit(
	portfolio_id: String,
	deposit_id: String,
	date: String,
	amount: float,
	currency: String,
	note: String = ""
) -> OperationResult:
	var result: OperationResult = _service.update_deposit(portfolio_id, deposit_id, date, amount, currency, note)
	return _handle_portfolio_mutation("update_deposit", portfolio_id, result)


func delete_deposit(portfolio_id: String, deposit_id: String) -> OperationResult:
	var result: OperationResult = _service.delete_deposit(portfolio_id, deposit_id)
	return _handle_portfolio_mutation("delete_deposit", portfolio_id, result)


func add_value_snapshot(
	portfolio_id: String,
	date: String,
	total_value: float,
	currency: String,
	note: String = ""
) -> OperationResult:
	var result: OperationResult = _service.add_value_snapshot(portfolio_id, date, total_value, currency, note)
	return _handle_portfolio_mutation("add_value_snapshot", portfolio_id, result)


func update_value_snapshot(
	portfolio_id: String,
	snapshot_id: String,
	date: String,
	total_value: float,
	currency: String,
	note: String = ""
) -> OperationResult:
	var result: OperationResult = _service.update_value_snapshot(
		portfolio_id,
		snapshot_id,
		date,
		total_value,
		currency,
		note
	)
	return _handle_portfolio_mutation("update_value_snapshot", portfolio_id, result)


func delete_value_snapshot(portfolio_id: String, snapshot_id: String) -> OperationResult:
	var result: OperationResult = _service.delete_value_snapshot(portfolio_id, snapshot_id)
	return _handle_portfolio_mutation("delete_value_snapshot", portfolio_id, result)


func add_bond_lot(portfolio_id: String, bond: BondLotData) -> OperationResult:
	var result: OperationResult = _service.add_bond_lot(portfolio_id, bond)
	return _handle_portfolio_mutation("add_bond_lot", portfolio_id, result)


func update_bond_lot(portfolio_id: String, bond_id: String, bond: BondLotData) -> OperationResult:
	var result: OperationResult = _service.update_bond_lot(portfolio_id, bond_id, bond)
	return _handle_portfolio_mutation("update_bond_lot", portfolio_id, result)


func delete_bond_lot(portfolio_id: String, bond_id: String) -> OperationResult:
	var result: OperationResult = _service.delete_bond_lot(portfolio_id, bond_id)
	return _handle_portfolio_mutation("delete_bond_lot", portfolio_id, result)


func load_all_portfolios() -> OperationResult:
	return _service.load_all_portfolios()


func build_statistics(
	portfolio_id: String,
	monthly_inflation: Array[InflationData] = []
) -> OperationResult:
	return _service.build_statistics(portfolio_id, monthly_inflation)


func begin_batch_operations() -> void:
	_dashboard_refresh_suspended = true
	_dashboard_refresh_pending = false
	_pending_dashboard_reference_currency = ""


func end_batch_operations(refresh_dashboard_after: bool = true, reference_currency: String = "") -> void:
	var should_refresh: bool = _dashboard_refresh_pending and refresh_dashboard_after
	var refresh_currency: String = reference_currency.strip_edges()
	if refresh_currency.is_empty():
		refresh_currency = _pending_dashboard_reference_currency

	_dashboard_refresh_suspended = false
	_dashboard_refresh_pending = false
	_pending_dashboard_reference_currency = ""

	if should_refresh:
		refresh_dashboard(refresh_currency)


func refresh_dashboard(reference_currency: String = "") -> void:
	_dashboard_required_fiat.clear()
	_last_dashboard_signature = ""

	var resolved_reference_currency: String = _dashboard_reference_currency(reference_currency)
	var currencies_result: OperationResult = _service.collect_dashboard_fiat_currencies(resolved_reference_currency)
	if not currencies_result.is_ok():
		dashboard_failed.emit("Cannot collect required fiat currencies: %s" % currencies_result.message)
		return

	var currencies: PackedStringArray = _packed_string_array_from_result(currencies_result)
	for currency in currencies:
		_dashboard_required_fiat[currency] = false

	if _dashboard_required_fiat.is_empty():
		_try_emit_dashboard(resolved_reference_currency)
		return

	for currency in currencies:
		PortfolioManager.request_fiat_price(currency)

	_try_emit_dashboard(resolved_reference_currency)


func _generate_unique_portfolio_id(portfolio_name: String) -> OperationResult:
	var base_id: String = _slugify_portfolio_id(portfolio_name)
	if base_id.is_empty():
		base_id = "portfolio"

	var existing_ids: Dictionary = {}
	var load_result: OperationResult = _service.load_all_portfolios()
	if not load_result.is_ok():
		return load_result

	if load_result.data is Array:
		for item in load_result.data:
			if item is PortfolioData:
				var portfolio: PortfolioData = item as PortfolioData
				if portfolio == null:
					continue

				existing_ids[portfolio.id.strip_edges().to_lower()] = true

	var candidate: String = base_id
	var suffix: int = 2
	while existing_ids.has(candidate):
		candidate = "%s_%d" % [base_id, suffix]
		suffix += 1

	return OperationResult.ok(candidate)


func _slugify_portfolio_id(value: String) -> String:
	var clean_value: String = value.strip_edges().to_lower()
	var result: String = ""
	var last_was_separator: bool = false

	for character_index in range(clean_value.length()):
		var character: String = clean_value.substr(character_index, 1)
		if _is_slug_character(character):
			result += character
			last_was_separator = false
		elif not last_was_separator:
			result += "_"
			last_was_separator = true

	while result.begins_with("_"):
		result = result.substr(1)

	while result.ends_with("_"):
		result = result.substr(0, result.length() - 1)

	return result


func _is_slug_character(character: String) -> bool:
	var code: int = character.unicode_at(0)
	var is_digit: bool = code >= 48 and code <= 57
	var is_lowercase_letter: bool = code >= 97 and code <= 122
	return is_digit or is_lowercase_letter


func _handle_portfolio_mutation(operation: String, portfolio_id: String, result: OperationResult) -> OperationResult:
	if result.is_ok():
		portfolio_saved.emit(portfolio_id)
		_request_dashboard_refresh()
	else:
		portfolio_operation_failed.emit(operation, result.message)

	return result


func _request_dashboard_refresh(reference_currency: String = "") -> void:
	if _dashboard_refresh_suspended:
		_dashboard_refresh_pending = true
		var clean_currency: String = MoneyData.normalize_currency(reference_currency)
		if not clean_currency.is_empty():
			_pending_dashboard_reference_currency = clean_currency
		return

	refresh_dashboard(reference_currency)


func _on_price_asset_updated(asset: AssetData) -> void:
	if asset.asset_type != AssetData.TYPE_FIAT:
		return

	var currency: String = MoneyData.normalize_currency(asset.symbol)
	if _dashboard_required_fiat.has(currency):
		_dashboard_required_fiat[currency] = true

	_try_emit_dashboard()


func _on_price_asset_fetch_failed(asset_id: String, error_message: String) -> void:
	var currency: String = MoneyData.normalize_currency(asset_id)
	if _dashboard_required_fiat.has(currency):
		dashboard_failed.emit("Cannot fetch fiat rate for %s: %s" % [currency, error_message])


func _on_base_currency_changed(new_currency: String) -> void:
	refresh_dashboard(new_currency)


func _try_emit_dashboard(reference_currency: String = "") -> void:
	if not _dashboard_fiat_ready():
		return

	var resolved_reference_currency: String = _dashboard_reference_currency(reference_currency)
	var dashboard_result: OperationResult = _service.build_dashboard(
		resolved_reference_currency,
		PortfolioManager.get_cached_assets_snapshot(),
		PortfolioManager.CACHE_DURATION_SECONDS
	)
	if not dashboard_result.is_ok():
		dashboard_failed.emit(dashboard_result.message)
		return

	if not (dashboard_result.data is Dictionary):
		dashboard_failed.emit("Dashboard result has invalid format.")
		return

	var dashboard_raw: Variant = dashboard_result.data
	var dashboard: Dictionary = _copy_dictionary(dashboard_raw)
	var signature: String = _dashboard_signature(dashboard)
	if signature == _last_dashboard_signature:
		return

	_last_dashboard_signature = signature
	dashboard_updated.emit(dashboard)


func _dashboard_fiat_ready() -> bool:
	for currency in _dashboard_required_fiat:
		if not bool(_dashboard_required_fiat[currency]):
			return false

	return true


func _dashboard_reference_currency(reference_currency: String = "") -> String:
	var clean_currency: String = MoneyData.normalize_currency(reference_currency)
	if clean_currency.is_empty():
		clean_currency = SettingsManager.get_base_currency()

	return clean_currency


func _dashboard_signature(dashboard: Dictionary) -> String:
	return "%s|%s|%.4f|%.4f|%.4f" % [
		str(dashboard.get("reference_currency", "")),
		str(dashboard.get("portfolio_count", "")),
		float(dashboard.get("total_value", 0.0)),
		float(dashboard.get("total_profit", 0.0)),
		float(dashboard.get("total_profit_percent", 0.0))
	]


func _packed_string_array_from_result(result: OperationResult) -> PackedStringArray:
	var values: PackedStringArray = PackedStringArray()
	if result == null or not result.is_ok():
		return values

	var raw_values: Variant = result.data
	if raw_values is PackedStringArray:
		for item in raw_values:
			values.append(str(item))
	elif raw_values is Array:
		for item in raw_values:
			values.append(str(item))

	return values


func _copy_dictionary(value: Variant) -> Dictionary:
	var result: Dictionary = {}

	if value is Dictionary:
		for key in value:
			result[key] = value[key]

	return result
