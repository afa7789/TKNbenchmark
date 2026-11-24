## calc: a 64-bit signed integer expression evaluator.
##
## Reads one expression per line from stdin and prints its value or `error`.
## Parsing uses an explicit operator stack (shunting-yard), so arbitrarily
## deep nesting cannot overflow the call stack.

type
  OpKind = enum
    opAdd, opSub, opMul, opDiv, opMod, opNeg, opParen

  EvalError = object of CatchableError

func precedence(op: OpKind): int =
  case op
  of opAdd, opSub: 1
  of opMul, opDiv, opMod: 2
  of opNeg: 3
  of opParen: 0

template fail() =
  raise newException(EvalError, "")

func checkedAdd(a, b: int64): int64 {.raises: [EvalError].} =
  if (b > 0 and a > high(int64) - b) or (b < 0 and a < low(int64) - b): fail()
  a + b

func checkedSub(a, b: int64): int64 {.raises: [EvalError].} =
  if (b < 0 and a > high(int64) + b) or (b > 0 and a < low(int64) + b): fail()
  a - b

func checkedMul(a, b: int64): int64 {.raises: [EvalError].} =
  if a > 0:
    if b > 0:
      if a > high(int64) div b: fail()
    elif b < low(int64) div a: fail()
  elif a < 0:
    if b > 0:
      if a < low(int64) div b: fail()
    elif b != 0 and b < high(int64) div a: fail()
  a * b

func checkedDiv(a, b: int64): int64 {.raises: [EvalError].} =
  if b == 0 or (a == low(int64) and b == -1): fail()
  a div b

func checkedMod(a, b: int64): int64 {.raises: [EvalError].} =
  if b == 0: fail()
  if b == -1: 0'i64 else: a mod b

func checkedNeg(a: int64): int64 {.raises: [EvalError].} =
  if a == low(int64): fail()
  -a

proc apply(values: var seq[int64], op: OpKind) {.raises: [EvalError].} =
  if op == opNeg:
    if values.len < 1: fail()
    values[^1] = checkedNeg(values[^1])
    return
  if values.len < 2: fail()
  let b = values.pop()
  let a = values.pop()
  values.add:
    case op
    of opAdd: checkedAdd(a, b)
    of opSub: checkedSub(a, b)
    of opMul: checkedMul(a, b)
    of opDiv: checkedDiv(a, b)
    of opMod: checkedMod(a, b)
    of opNeg, opParen: fail()

proc evaluate*(line: string): int64 {.raises: [EvalError].} =
  ## Evaluates one expression; raises `EvalError` on any syntax or
  ## arithmetic error.
  var
    values: seq[int64]
    ops: seq[OpKind]
    expectOperand = true
    i = 0

  while i < line.len:
    let c = line[i]
    if c in {' ', '\t'}:
      inc i
      continue
    if expectOperand:
      case c
      of '-': ops.add opNeg
      of '(': ops.add opParen
      of '0'..'9':
        var v = 0'i64
        while i < line.len and line[i] in {'0'..'9'}:
          let d = int64(ord(line[i]) - ord('0'))
          if v > (high(int64) - d) div 10: fail()
          v = v * 10 + d
          inc i
        values.add v
        expectOperand = false
        continue
      else: fail()
    else:
      let op =
        case c
        of '+': opAdd
        of '-': opSub
        of '*': opMul
        of '/': opDiv
        of '%': opMod
        of ')': opParen
        else: fail()
      if c == ')':
        while ops.len > 0 and ops[^1] != opParen:
          apply(values, ops.pop())
        if ops.len == 0: fail()
        discard ops.pop()
      else:
        let prec = precedence(op)
        while ops.len > 0 and precedence(ops[^1]) >= prec:
          apply(values, ops.pop())
        ops.add op
        expectOperand = true
    inc i

  if expectOperand: fail()
  while ops.len > 0:
    let op = ops.pop()
    if op == opParen: fail()
    apply(values, op)
  if values.len != 1: fail()
  values[0]

func isBlank(line: string): bool =
  for c in line:
    if c notin {' ', '\t'}: return false
  true

proc main() =
  var
    line: string
    output = newStringOfCap(1 shl 16)
  while stdin.readLine(line):
    if line.isBlank: continue
    try:
      output.add $evaluate(line)
    except EvalError:
      output.add "error"
    output.add '\n'
    if output.len >= 1 shl 16:
      stdout.write output
      output.setLen 0
  stdout.write output
  stdout.flushFile()

when isMainModule:
  main()
