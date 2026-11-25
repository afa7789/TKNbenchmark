## calc: a 64-bit signed integer expression evaluator.
##
## Reads one expression per line from stdin and prints its value or `error`.
## Parsing uses an explicit operator stack (shunting-yard), so arbitrarily
## deep nesting cannot overflow the call stack.

import std/[options, strutils]

type
  OpKind = enum
    opAdd, opSub, opMul, opDiv, opMod, opNeg, opParen

  CalcError = object of CatchableError

func precedence(op: OpKind): int =
  case op
  of opAdd, opSub: 1
  of opMul, opDiv, opMod: 2
  of opNeg: 3
  of opParen: 0

proc fail() {.noreturn.} =
  raise newException(CalcError, "")

func checkedAdd(a, b: int64): int64 {.raises: [CalcError].} =
  if (b > 0 and a > high(int64) - b) or (b < 0 and a < low(int64) - b): fail()
  a + b

func checkedSub(a, b: int64): int64 {.raises: [CalcError].} =
  if (b < 0 and a > high(int64) + b) or (b > 0 and a < low(int64) + b): fail()
  a - b

func checkedMul(a, b: int64): int64 {.raises: [CalcError].} =
  if a == 0 or b == 0: return 0
  if (a == -1 and b == low(int64)) or (b == -1 and a == low(int64)): fail()
  result = a *% b
  if result div b != a: fail()

func checkedDiv(a, b: int64): int64 {.raises: [CalcError].} =
  if b == 0 or (a == low(int64) and b == -1): fail()
  a div b

func checkedMod(a, b: int64): int64 {.raises: [CalcError].} =
  if b == 0: fail()
  if b == -1: 0'i64 else: a mod b

proc apply(values: var seq[int64]; op: OpKind) {.raises: [CalcError].} =
  if op == opNeg:
    if values.len < 1: fail()
    if values[^1] == low(int64): fail()
    values[^1] = -values[^1]
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

proc evaluate(line: string): int64 {.raises: [CalcError].} =
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
        var n = 0'i64
        while i < line.len and line[i] in {'0'..'9'}:
          let d = int64(ord(line[i]) - ord('0'))
          if n > (high(int64) - d) div 10: fail()
          n = n * 10 + d
          inc i
        values.add n
        expectOperand = false
        continue
      else: fail()
    else:
      case c
      of '+', '-', '*', '/', '%':
        let op =
          case c
          of '+': opAdd
          of '-': opSub
          of '*': opMul
          of '/': opDiv
          else: opMod
        while ops.len > 0 and precedence(ops[^1]) >= precedence(op):
          values.apply(ops.pop())
        ops.add op
        expectOperand = true
      of ')':
        while ops.len > 0 and ops[^1] != opParen:
          values.apply(ops.pop())
        if ops.len == 0: fail()
        discard ops.pop()
      else: fail()
    inc i
  if expectOperand: fail()
  while ops.len > 0:
    let op = ops.pop()
    if op == opParen: fail()
    values.apply(op)
  if values.len != 1: fail()
  values[0]

proc isBlank(line: string): bool =
  for c in line:
    if c notin {' ', '\t'}: return false
  true

proc tryEvaluate(line: string): Option[int64] =
  try: some(evaluate(line))
  except CalcError: none(int64)

proc main() =
  let input = stdin.readAll()
  var output = newStringOfCap(input.len)
  var start = 0
  while start < input.len:
    var stop = input.find('\n', start)
    if stop < 0: stop = input.len
    let line = input[start ..< stop]
    start = stop + 1
    if line.isBlank: continue
    let value = tryEvaluate(line)
    if value.isSome: output.add $value.get
    else: output.add "error"
    output.add '\n'
  stdout.write output
  stdout.flushFile()

when isMainModule:
  main()
