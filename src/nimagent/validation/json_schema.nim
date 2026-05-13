## nimagent – JSON Schema Validator
## ================================
## Lightweight JSON Schema validator for tool arguments.
## Validates JSON payloads against JSON Schema objects before tool execution.
## Supports : string, integer, number, boolean, object, array, enum, required.
## Not a full JSON Schema implementation ; covers the subset used by nimagent tools.

import std/[json, tables, sequtils]

# Forward declaration for recursive validation
proc validateNode*(value: JsonNode, schema: JsonNode, path: string = ""): seq[string]

proc validateType*(value: JsonNode, expectedType: string, path: string): seq[string] =
  ## Checks if a JsonNode matches the expected JSON Schema type.
  result = @[]
  let actualType = case value.kind:
    of JString:  "string"
    of JInt:     "integer"
    of JFloat:   "number"
    of JBool:    "boolean"
    of JNull:    "null"
    of JObject:  "object"
    of JArray:   "array"

  # "number" accepts both integer and float
  if expectedType == "number" and actualType in ["integer", "number"]:
    return
  if expectedType == "integer" and actualType == "number":
    # Accept float values that are mathematically integers
    if value.kind == JFloat and value.getFloat == float(int(value.getFloat)):
      return
  if actualType != expectedType:
    result.add("[" & path & "] Expected type '" & expectedType &
               "', got '" & actualType & "'")

proc validateString*(value: JsonNode, schema: JsonNode, path: string): seq[string] =
  ## Validates string constraints (minLength, maxLength, enum, pattern).
  result = @[]
  let s = value.getStr()

  if schema.hasKey("minLength"):
    let minLen = schema["minLength"].getInt()
    if s.len < minLen:
      result.add("[" & path & "] String too short (min " & $minLen & 
                 ", got " & $s.len & ")")

  if schema.hasKey("maxLength"):
    let maxLen = schema["maxLength"].getInt()
    if s.len > maxLen:
      result.add("[" & path & "] String too long (max " & $maxLen &
                 ", got " & $s.len & ")")

  if schema.hasKey("enum"):
    let allowed = schema["enum"].getElems().mapIt(it.getStr())
    if s notin allowed:
      result.add("[" & path & "] Value '" & s & "' not in enum " & $allowed)

proc validateNumber*(value: JsonNode, schema: JsonNode, path: string): seq[string] =
  ## Validates numeric constraints (minimum, maximum, exclusiveMinimum, exclusiveMaximum).
  result = @[]
  let num = if value.kind == JInt: float(value.getInt()) else: value.getFloat()

  if schema.hasKey("minimum"):
    let minVal = schema["minimum"].getFloat()
    if num < minVal:
      result.add("[" & path & "] Value " & $num & " < minimum " & $minVal)

  if schema.hasKey("maximum"):
    let maxVal = schema["maximum"].getFloat()
    if num > maxVal:
      result.add("[" & path & "] Value " & $num & " > maximum " & $maxVal)

proc validateArray*(value: JsonNode, schema: JsonNode, path: string): seq[string] =
  ## Validates array constraints (minItems, maxItems, items schema).
  result = @[]
  let arr = value.getElems()

  if schema.hasKey("minItems"):
    let minItems = schema["minItems"].getInt()
    if arr.len < minItems:
      result.add("[" & path & "] Array too short (min " & $minItems &
                 ", got " & $arr.len & ")")

  if schema.hasKey("maxItems"):
    let maxItems = schema["maxItems"].getInt()
    if arr.len > maxItems:
      result.add("[" & path & "] Array too long (max " & $maxItems &
                 ", got " & $arr.len & ")")

  if schema.hasKey("items"):
    let itemSchema = schema["items"]
    for i, item in arr:
      result.add(validateNode(item, itemSchema, path & "[" & $i & "]"))

proc validateObject*(value: JsonNode, schema: JsonNode, path: string): seq[string] =
  ## Validates object properties, required fields, and nested schemas.
  result = @[]
  let obj = value.getFields()

  # Check required fields
  if schema.hasKey("required"):
    for reqField in schema["required"].getElems():
      let fieldName = reqField.getStr()
      if not obj.hasKey(fieldName):
        result.add("[" & path & "] Missing required field: '" & fieldName & "'")

  # Validate properties
  if schema.hasKey("properties"):
    let props = schema["properties"]
    if props.kind == JObject:
      let propFields = props.getFields()
      for propName in propFields.keys:
        let propSchema = propFields[propName]
        if obj.hasKey(propName):
          result.add(validateNode(obj[propName], propSchema,
                      path & (if path.len > 0: "." else: "") & propName))

  # Validate additionalProperties (default: true, reject if false)
  let allowAdditional = if schema.hasKey("additionalProperties"):
                          schema["additionalProperties"].kind == JBool and
                          schema["additionalProperties"].getBool()
                        else: true
  if not allowAdditional:
    let allKeys = obj.keys.toSeq
    for key in allKeys:
      if not (schema["properties"].hasKey(key)):
        result.add("[" & path & "] Unexpected field: '" & key & "'")

proc validateNode*(value: JsonNode, schema: JsonNode, path: string = ""): seq[string] =
  ## Main entry point : validates a JsonNode against a JSON Schema.
  result = @[]

  # Short-circuit: null against a schema that allows it
  if value.kind == JNull:
    if schema.hasKey("type") and schema["type"].getStr() == "null":
      return
    else:
      result.add("[" & path & "] Unexpected null value")
      return

  # Extract type (handle array of types if ever needed)
  if not schema.hasKey("type"):
    return  # No type constraint → accept anything

  let expectedType = schema["type"].getStr()

  # Core type validation
  let typeErrors = validateType(value, expectedType, path)
  if typeErrors.len > 0:
    result.add(typeErrors)
    return  # Stop here if type is wrong ; no point checking constraints

  # Type-specific constraint validation
  case expectedType:
    of "string":  result.add(validateString(value, schema, path))
    of "integer", "number": result.add(validateNumber(value, schema, path))
    of "array":   result.add(validateArray(value, schema, path))
    of "object":  result.add(validateObject(value, schema, path))
    # "boolean" and "null" have no additional constraints in our subset
    else: discard

proc validateToolArguments*(args: JsonNode, schema: JsonNode): seq[string] =
  ## Validates tool arguments against the tool's JSON Schema.
  ## Returns a sequence of error strings (empty if valid).
  ##
  ## Usage:
  ##   let errors = validateToolArguments(argsJson, tool.schema)
  ##   if errors.len > 0:
  ##     return "Validation failed: " & errors.join(" ; ")
  ##   else:
  ##     return await tool.action(argsJson)
  ##
  return validateNode(args, schema)