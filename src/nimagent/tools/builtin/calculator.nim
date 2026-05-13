import std/math
## Calculator Tool - Deterministic Demo Tool
## Demo for llmTool and schema generation

import ../../utils/async_compat
import ../../utils/json_compat
import ../registry
import std/strutils

llmTool "Perform basic arithmetic calculations safely. Supports addition (+), subtraction (-), multiplication (*), and division (/). Returns the numerical result as a string.":
  proc calculator(expression: string): Future[string] {.async.} =
    ## Safe calculator for deterministic demos
    ## Only supports: +, -, *, /, digits, spaces, and decimal points
    try:
      # Validate characters
      for c in expression:
        if c notin {'0'..'9', '+', '-', '*', '/', '.', ' ', '(', ')', '^'}:
          return "Error: Invalid characters in expression. Only numbers and operators allowed."

      # Simple evaluation (limited for safety)
      # Parse numbers and operators
      var numbers: seq[float] = @[]
      var operators: seq[char] = @[]
      var currentNum = ""

      for c in expression:
        if c in {'0'..'9', '.'}:
          currentNum.add(c)
        elif c in {'+', '-', '*', '/', '^'}:
          if currentNum.len > 0:
            numbers.add(parseFloat(currentNum))
            currentNum = ""
          operators.add(c)

      if currentNum.len > 0:
        numbers.add(parseFloat(currentNum))

      if numbers.len == 0:
        return "Error: No numbers found in expression"

      # Calculate left to right
      var result = numbers[0]
      var numIdx = 1

      for op in operators:
        if numIdx >= numbers.len:
          break
        let b = numbers[numIdx]
        numIdx += 1

        case op:
          of '+': result = result + b
          of '-': result = result - b
          of '*': result = result * b
          of '/':
            if b == 0:
              return "Error: Division by zero"
            result = result / b
          of '^': result = result.pow(b)
          else:
            return "Error: Unsupported operator '" & op & "'"

      return $result
    except CatchableError as e:
      return "Error: " & e.msg
