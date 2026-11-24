## calc: a 64-bit signed integer expression evaluator.
##
## Reads one expression per line from stdin and prints its value or `error`.
## Evaluation uses an iterative operator-precedence (shunting-yard) parser, so
## arbitrarily deep nesting cannot overflow the call stack.

type
  CalcError = object of CatchableError

  Op = enum
    opAdd, opSub, opMul, opDiv, opMod, opNeg, opParen

const
  precedence: array[Op, int] = [
    opAdd: 1, opSub: 1, opMul: 2, opDiv: 2, opMod: 2, opNeg: 3, opParen: 0]

proc fail() {.noreturn, noinline.} =
  raise newException(CalcError, "error")

func wrapMul(a, b: int64): int64 {.inline.} =
  cast[int64](cast[uint64](a) * cast[uint64](b))

proc checkedAdd(a, b: int64): int64 =
  if (b > 0 and a > high(int64) - b) or (b < 0 and a < low(int64) - b): fail()
  a + b

proc checkedSub(a, b: int64): int64 =
  if (b < 0 and a > high(int64) + b) or (b > 0 and a < low(int64) + b): fail()
  a - b

proc checkedMul(a, b: int64): int64 =
  if a == 0 or b == 0: return 0
  if (a == -1 and b == low(int64)) or (b == -1 and a == low(int64)): fail()
  result = wrapMul(a, b)
  if result div b != a: fail()

proc checkedDiv(a, b: int64): int64 =
  if b == 0: fail()
  if b == -1:
    if a == low(int64): fail()
    return -a
  a div b          # Nim's `div` truncates toward zero

proc checkedMod(a, b: int64): int64 =
  if b == 0: fail()
  if b == -1: return 0
  a mod b          # sign follows the dividend

proc checkedNeg(a: int64): int64 =
  if a == low(int64): fail()
  -a

type
  Evaluator = object
    values: seq[int64]
    ops: seq[Op]

proc popValue(ev: var Evaluator): int64 {.inline.} =
  if ev.values.len == 0: fail()
  ev.values.pop()

proc apply(ev: var Evaluator, op: Op) =
  if op == opNeg:
    ev.values.add checkedNeg(ev.popValue())
    return
  let b = ev.popValue()
  let a = ev.popValue()
  ev.values.add:
    case op
    of opAdd: checkedAdd(a, b)
    of opSub: checkedSub(a, b)
    of opMul: checkedMul(a, b)
    of opDiv: checkedDiv(a, b)
    of opMod: checkedMod(a, b)
    of opNeg, opParen: fail()

proc reduceWhile(ev: var Evaluator, minPrec: int) =
  ## Applies stacked operators whose precedence is at least `minPrec`
  ## (all binary operators are left-associative).
  while ev.ops.len > 0 and ev.ops[^1] != opParen and
      precedence[ev.ops[^1]] >= minPrec:
    ev.apply(ev.ops.pop())

proc binaryOp(c: char): Op =
  case c
  of '+': opAdd
  of '-': opSub
  of '*': opMul
  of '/': opDiv
  of '%': opMod
  else: fail()

proc evaluate(ev: var Evaluator, line: openArray[char]): int64 =
  ## Evaluates one expression; raises `CalcError` on any error.
  ev.values.setLen(0)
  ev.ops.setLen(0)
  var
    i = 0
    expectOperand = true
  while i < line.len:
    let c = line[i]
    case c
    of ' ', '\t':
      inc i
    of '0'..'9':
      if not expectOperand: fail()
      var n = 0'i64
      while i < line.len and line[i] in {'0'..'9'}:
        let d = int64(ord(line[i]) - ord('0'))
        if n > (high(int64) - d) div 10: fail()
        n = n * 10 + d
        inc i
      ev.values.add n
      expectOperand = false
    of '(':
      if not expectOperand: fail()
      ev.ops.add opParen
      inc i
    of ')':
      if expectOperand: fail()
      ev.reduceWhile(0)
      if ev.ops.len == 0: fail()   # unbalanced: no matching '('
      discard ev.ops.pop()
      inc i
    of '+', '-', '*', '/', '%':
      if expectOperand:
        if c != '-': fail()       # no unary '+'
        ev.ops.add opNeg
      else:
        let op = binaryOp(c)
        ev.reduceWhile(precedence[op])
        ev.ops.add op
        expectOperand = true
      inc i
    else:
      fail()
  if expectOperand: fail()
  ev.reduceWhile(0)
  if ev.ops.len != 0 or ev.values.len != 1: fail()   # leftover '('
  ev.values[0]

func isBlank(line: openArray[char]): bool =
  for c in line:
    if c notin {' ', '\t'}: return false
  true

proc main() =
  let input = stdin.readAll()
  var
    output = newStringOfCap(input.len)
    ev = Evaluator()
    start = 0
  while start < input.len:
    var stop = start
    while stop < input.len and input[stop] != '\n': inc stop
    if not input.toOpenArray(start, stop - 1).isBlank:
      try:
        output.add $ev.evaluate(input.toOpenArray(start, stop - 1))
      except CalcError:
        output.add "error"
      output.add '\n'
    start = stop + 1
  stdout.write output
  stdout.flushFile()

when isMainModule:
  main()
