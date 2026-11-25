## calc: a 64-bit signed integer expression evaluator.
##
## Reads one expression per line from stdin and prints its value or `error`.

type
  CalcError* = object of CatchableError
    ## Raised for syntax errors, division by zero and overflow.

proc fail(msg: string) {.noreturn.} =
  raise newException(CalcError, msg)

# ---------- checked 64-bit arithmetic ----------

func checkedAdd(a, b: int64): int64 {.raises: [CalcError].} =
  result = a +% b
  if ((a xor result) and (b xor result)) < 0: fail("overflow")

func checkedSub(a, b: int64): int64 {.raises: [CalcError].} =
  result = a -% b
  if ((a xor b) and (a xor result)) < 0: fail("overflow")

func checkedNeg(a: int64): int64 {.raises: [CalcError].} =
  if a == low(int64): fail("overflow")
  -a

func checkedMul(a, b: int64): int64 {.raises: [CalcError].} =
  if a == 0 or b == 0: return 0
  if (a == -1 and b == low(int64)) or (b == -1 and a == low(int64)):
    fail("overflow")
  result = a *% b
  if result div b != a: fail("overflow")

func checkedDiv(a, b: int64): int64 {.raises: [CalcError].} =
  if b == 0: fail("division by zero")
  if a == low(int64) and b == -1: fail("overflow")
  a div b                      # truncates toward zero

func checkedMod(a, b: int64): int64 {.raises: [CalcError].} =
  if b == 0: fail("division by zero")
  if b == -1: return 0         # avoids the low(int64) mod -1 trap
  a mod b                      # sign follows the dividend

# ---------- evaluator ----------
#
# An iterative operator-precedence evaluator: explicit operand and operator
# stacks keep arbitrarily deep nesting off the call stack.

const
  Negate = 'n'                 ## operator-stack marker for unary minus
  BinaryOps = {'+', '-', '*', '/', '%'}

func precedence(op: char): int =
  case op
  of Negate: 3
  of '*', '/', '%': 2
  of '+', '-': 1
  else: 0                      # '(' never reduces

func apply(op: char; a, b: int64): int64 {.raises: [CalcError].} =
  case op
  of '+': checkedAdd(a, b)
  of '-': checkedSub(a, b)
  of '*': checkedMul(a, b)
  of '/': checkedDiv(a, b)
  else: checkedMod(a, b)

proc reduce(values: var seq[int64]; ops: var seq[char]) {.raises: [CalcError].} =
  ## Pops one operator and applies it to the operand stack.
  let op = ops.pop()
  if op == Negate:
    values[^1] = checkedNeg(values[^1])
  else:
    let rhs = values.pop()
    values[^1] = apply(op, values[^1], rhs)

proc parseNumber(s: string; pos: var int): int64 {.raises: [CalcError].} =
  while pos < s.len and s[pos] in {'0'..'9'}:
    let d = int64(ord(s[pos]) - ord('0'))
    if result > (high(int64) - d) div 10: fail("literal too large")
    result = result * 10 + d
    inc pos

proc evaluate*(line: string): int64 {.raises: [CalcError].} =
  ## Evaluates a complete expression; raises `CalcError` on any failure.
  var
    values: seq[int64]
    ops: seq[char]
    expectOperand = true
    pos = 0
  while true:
    while pos < line.len and line[pos] in {' ', '\t'}:
      inc pos
    if pos >= line.len: break
    let c = line[pos]
    if expectOperand:
      case c
      of '-': ops.add Negate; inc pos
      of '(': ops.add '('; inc pos
      of '0'..'9':
        values.add parseNumber(line, pos)
        expectOperand = false
      else: fail("expected operand")
    else:
      case c
      of BinaryOps:
        while ops.len > 0 and precedence(ops[^1]) >= precedence(c):
          reduce(values, ops)
        ops.add c
        expectOperand = true
        inc pos
      of ')':
        while ops.len > 0 and ops[^1] != '(':
          reduce(values, ops)
        if ops.len == 0: fail("unbalanced ')'")
        discard ops.pop()
        inc pos
      else: fail("expected operator")
  if expectOperand: fail("missing operand")
  while ops.len > 0:
    if ops[^1] == '(': fail("unbalanced '('")
    reduce(values, ops)
  values[0]

func isBlank(line: string): bool =
  for c in line:
    if c notin {' ', '\t'}: return false
  true

proc main() =
  for line in stdin.lines:
    if line.isBlank: continue
    try:
      stdout.writeLine($evaluate(line))
    except CalcError:
      stdout.writeLine("error")

when isMainModule:
  main()
