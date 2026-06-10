extends RefCounted
class_name TickerResolver

const PROVIDER_YAHOO := "yahoo_finance"
const PROVIDER_COINGECKO := "coingecko"
const PROVIDER_NBP := "nbp"


static func resolve_for_yahoo(input_symbol: String) -> Dictionary:
	var original_symbol := input_symbol.strip_edges()
	var normalized_symbol := original_symbol.to_upper()
	var warnings := PackedStringArray()

	if normalized_symbol.ends_with(".UK"):
		normalized_symbol = normalized_symbol.substr(0, normalized_symbol.length() - 3) + ".L"
		warnings.append("Mapped .UK suffix to Yahoo Finance .L suffix.")

	return {
		"provider": PROVIDER_YAHOO,
		"input": original_symbol,
		"symbol": normalized_symbol,
		"warnings": warnings
	}


static func resolve_for_coingecko(input_asset_id: String) -> Dictionary:
	var original_id := input_asset_id.strip_edges()
	var normalized_id := original_id.to_lower()

	return {
		"provider": PROVIDER_COINGECKO,
		"input": original_id,
		"symbol": normalized_id,
		"warnings": PackedStringArray()
	}


static func resolve_for_nbp(input_currency: String) -> Dictionary:
	var original_currency := input_currency.strip_edges()
	var normalized_currency := original_currency.to_upper()

	return {
		"provider": PROVIDER_NBP,
		"input": original_currency,
		"symbol": normalized_currency,
		"warnings": PackedStringArray()
	}
