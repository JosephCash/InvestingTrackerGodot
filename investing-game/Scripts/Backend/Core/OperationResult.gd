extends RefCounted
class_name OperationResult

var success: bool = false
var error_code: Error = FAILED
var message: String = ""
var data: Variant = null


static func ok(result_data: Variant = null, result_message: String = "") -> OperationResult:
	var result := OperationResult.new()
	result.success = true
	result.error_code = OK
	result.message = result_message
	result.data = result_data
	return result


static func fail(code: Error, error_message: String, result_data: Variant = null) -> OperationResult:
	var result := OperationResult.new()
	result.success = false
	result.error_code = code
	result.message = error_message
	result.data = result_data
	return result


func is_ok() -> bool:
	return success and error_code == OK
