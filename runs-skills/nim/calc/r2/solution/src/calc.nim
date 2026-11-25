## calc: a 64-bit signed integer expression evaluator.
##
## Reads one expression per line from stdin and prints its value or `error`.
## Evaluation is iterative (operator-precedence parsing with explicit stacks),
## so deeply nested input cannot exhaust the call stack.

import std/options

type
  OpKind = enum
    opLParen, opAdd, opSub, opMul, opDiv, opMod, opNeg

  CalcError = object of CatchableError

func precedence(op: OpKind): int =
  case op
  of opLParen: 0
  of opAdd, opSub: 1
  of opMul, opDiv, opMod: 2
  of opNeg: 3

proc fail() {.noreturn.} =
  raise newException(CalcError, "")

func checkedAdd(a, b: int64): Option[int64] =
  if (b > 0 and a > high(int64) - b) or (b < 0 and a < low(int64) - b):
    none(int64)
  else:
    some(a + b)

func checkedSub(a, b: int64): Option[int64] =
  if (b < 0 and a > high(int64) + b) or (b > 0 and a < low(int64) + b):
    none(int64)
  else:
    some(a - b)

func checkedMul(a, b: int64): Option[int64] =
  if a == 0 or b == 0:
    return some(0'i64)
  if (a == -1 and b == low(int64)) or (b == -1 and a == low(int64)):
    return none(int64)
  let r = a *% b
  if r div b == a: some(r) else: none(int64)

proc unwrap(x: Option[int64]): int64 =
  if x.isNone: fail()
  x.unsafeGet

proc apply(op: OpKind; values: var seq[int64]) =
  if op == opNeg:
    if values.len < 1: fail()
    let v = values[^1]
    if v == low(int64): fail()
    values[^1] = -v
    return
  if values.len < 2: fail()
  let b = values.pop()
  let a = values[^1]
  values[^1] =
    case op
    of opAdd: unwrap checkedAdd(a, b)
    of opSub: unwrap checkedSub(a, b)
    of opMul: unwrap checkedMul(a, b)
    of opDiv:
      if b == 0 or (a == low(int64) and b == -1): fail()
      a div b
    of opMod:
      if b == 0: fail()
      if b == -1: 0'i64 else: a mod b
    of opLParen, opNeg: fail()

proc evaluate*(line: openArray[char]): int64 {.raises: [CalcError].} =
  ## Evaluates one expression; raises `CalcError` on any syntax or
  ## arithmetic error.
  var
    values: seq[int64]
    ops: seq[OpKind]
    expectOperand = true
    i = 0

  template reduceWhile(cond: untyped) =
    while ops.len > 0:
      let top {.inject.} = ops[^1]
      if not cond: break
      discard ops.pop()
      apply(top, values)

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
      values.add n
      expectOperand = false
    of '(':
      if not expectOperand: fail()
      ops.add opLParen
      inc i
    of ')':
      if expectOperand: fail()
      reduceWhile(top != opLParen)
      if ops.len == 0: fail()
      discard ops.pop()
      inc i
    of '-', '+', '*', '/', '%':
      inc i
      if expectOperand:
        # Only '-' may start an operand (unary minus; there is no unary '+').
        if c != '-': fail()
        ops.add opNeg
        continue
      let op =
        case c
        of '+': opAdd
        of '-': opSub
        of '*': opMul
        of '/': opDiv
        else: opMod
      let p = precedence(op)
      reduceWhile(precedence(top) >= p)
      ops.add op
      expectOperand = true
    else:
      fail()

  if expectOperand: fail()
  reduceWhile(true)
  if ops.len > 0 or values.len != 1: fail()
  values[0]

func isBlank(line: openArray[char]): bool =
  for c in line:
    if c notin {' ', '\t'}: return false
  true

proc main() =
  let input = stdin.readAll()
  var output = newStringOfCap(input.len)
  var start = 0
  while start < input.len:
    var stop = start
    while stop < input.len and input[stop] != '\n': inc stop
    if not input.toOpenArray(start, stop - 1).isBlank:
      try:
        output.add $evaluate(input.toOpenArray(start, stop - 1))
      except CalcError:
        output.add "error"
      output.add '\n'
    start = stop + 1
  stdout.write output

when isMainModule:
  main()
