extends Node

signal base_currency_changed(new_currency: String)

const SETTINGS_SCHEMA_VERSION := 1
const DEFAULT_BASE_CURRENCY := "USD"

var base_currency: String = DEFAULT_BASE_CURRENCY


func _ready() -> void:
	load_settings()


func load_settings() -> OperationResult:
	var settings: Dictionary = SaveManager.load_settings()
	if settings.is_empty():
		base_currency = DEFAULT_BASE_CURRENCY
		return OperationResult.ok(to_dict(), "Default settings loaded.")

	var currency: String = str(settings.get("base_currency", DEFAULT_BASE_CURRENCY))
	var result: OperationResult = _apply_base_currency(currency, false, false)
	if not result.is_ok():
		base_currency = DEFAULT_BASE_CURRENCY
		return OperationResult.fail(result.error_code, "Settings file contains invalid base currency: %s" % result.message)

	return OperationResult.ok(to_dict(), "Settings loaded.")


func set_base_currency(new_currency: String) -> OperationResult:
	return _apply_base_currency(new_currency, true, true)


func get_base_currency() -> String:
	return MoneyData.normalize_currency(base_currency)


func to_dict() -> Dictionary:
	return {
		"schema_version": SETTINGS_SCHEMA_VERSION,
		"base_currency": get_base_currency()
	}


func _apply_base_currency(new_currency: String, should_persist: bool, should_emit: bool) -> OperationResult:
	var clean_currency: String = MoneyData.normalize_currency(new_currency)
	if not _is_valid_currency_code(clean_currency):
		return OperationResult.fail(ERR_INVALID_PARAMETER, "Currency must be a 3-letter ISO-like code.")

	if base_currency == clean_currency:
		if should_persist:
			SaveManager.save_settings(to_dict())
		return OperationResult.ok(to_dict(), "Base currency unchanged.")

	base_currency = clean_currency
	if should_persist:
		SaveManager.save_settings(to_dict())

	if should_emit:
		base_currency_changed.emit(base_currency)

	return OperationResult.ok(to_dict(), "Base currency changed.")


func _is_valid_currency_code(currency: String) -> bool:
	if currency.length() != 3:
		return false

	for index in range(currency.length()):
		var code: int = currency.unicode_at(index)
		if code < 65 or code > 90:
			return false

	return true
