extends Resource
class_name PortfolioSnapshotData

const SCHEMA_VERSION := 1

@export var id: String = ""
@export var date: String = ""
@export var total_value: MoneyData
@export var note: String = ""


static func create(date_value: String, amount: float, currency: String, note_value: String = "") -> PortfolioSnapshotData:
	var snapshot := PortfolioSnapshotData.new()
	snapshot.id = PortfolioSnapshotData.generate_id("snapshot")
	snapshot.date = date_value.strip_edges()
	snapshot.total_value = MoneyData.create(amount, currency)
	snapshot.note = note_value.strip_edges()
	return snapshot


func validate() -> PackedStringArray:
	var errors := PackedStringArray()

	if id.strip_edges().is_empty():
		errors.append("Snapshot id is empty.")

	if date.strip_edges().is_empty():
		errors.append("Snapshot date is empty.")

	if total_value == null:
		errors.append("Snapshot total value is null.")
	else:
		errors.append_array(total_value.validate(true))

	return errors


func to_dict() -> Dictionary:
	var amount := 0.0
	var currency := ""
	if total_value != null:
		amount = total_value.amount
		currency = total_value.currency

	return {
		"schema_version": SCHEMA_VERSION,
		"id": id,
		"date": date.strip_edges(),
		"total_value": amount,
		"currency": MoneyData.normalize_currency(currency),
		"note": note.strip_edges()
	}


static func from_dict(data: Dictionary) -> PortfolioSnapshotData:
	var snapshot := PortfolioSnapshotData.new()
	snapshot.id = str(data.get("id", ""))
	if snapshot.id.is_empty():
		snapshot.id = PortfolioSnapshotData.generate_id("snapshot")

	snapshot.date = str(data.get("date", "")).strip_edges()

	if data.has("money") and data["money"] is Dictionary:
		snapshot.total_value = MoneyData.from_dict(data["money"])
	elif data.has("total_value") and data["total_value"] is Dictionary:
		snapshot.total_value = MoneyData.from_dict(data["total_value"])
	else:
		snapshot.total_value = MoneyData.create(float(data.get("total_value", 0.0)), str(data.get("currency", "PLN")))

	snapshot.note = str(data.get("note", "")).strip_edges()
	return snapshot


static func generate_id(prefix: String) -> String:
	return "%s_%d_%d" % [
		prefix.strip_edges().to_lower(),
		int(Time.get_unix_time_from_system() * 1000.0),
		randi() % 100000
	]
