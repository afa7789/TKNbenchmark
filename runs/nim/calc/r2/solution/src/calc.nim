## calc: a 64-bit signed integer expression evaluator.
##
## Reads one expression per line from stdin and prints its value or `error`.
## Parsing uses an explicit-stack operator-precedence algorithm so that deeply
## nested input cannot overflow the call stack.

import std/strutils

type
  CalcError = object of CatchableError

  OpKind = enum
    opAdd, opSub, opMul, opDiv, opMod, opNeg, opParen

const precedence: array[OpKind, int] =
  [opAdd: 1, opSub: 1, opMul: 2, opDiv: 2, opMod: 2, opNeg: 3, opParen: 0]

template fail() = raise newException(CalcError, "")

func checkedAdd(a, b: int64): int64 =
  if (b > 0 and a > high(int64) - b) or (b < 0 and a < low(int64) - b): fail()
  a + b

func checkedSub(a, b: int64): int64 =
  if (b < 0 and a > high(int64) + b) or (b > 0 and a < low(int64) + b): fail()
  a - b

func checkedMul(a, b: int64): int64 =
  if a == 0 or b == 0: return 0
  let overflow =
    if a > 0:
      (if b > 0: a > high(int64) div b else: b < low(int64) div a)
    else:
      (if b > 0: a < low(int64) div b else: b < high(int64) div a)
  if overflow: fail()
  a * b

func checkedDiv(a, b: int64): int64 =
  if b == 0 or (a == low(int64) and b == -1): fail()
  a div b

func checkedMod(a, b: int64): int64 =
  if b == 0: fail()
  if b == -1: return 0
  a mod b

func checkedNeg(a: int64): int64 =
  if a == low(int64): fail()
  -a

proc apply(values: var seq[int64], op: OpKind) =
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

func binaryOp(c: char): OpKind =
  case c
  of '+': opAdd
  of '-': opSub
  of '*': opMul
  of '/': opDiv
  of '%': opMod
  else: fail()

proc evaluate*(line: string): int64 =
  ## Evaluates one expression; raises `CalcError` on any syntax,
  ## division-by-zero or overflow error.
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
      of '-': ops.add opNeg
      of '(': ops.add opParen
      else: fail()
    else:
      case c
      of ')':
        while ops.len > 0 and ops[^1] != opParen:
          values.apply(ops.pop())
        if ops.len == 0: fail()
        discard ops.pop()
      else:
        let op = binaryOp(c)
        while ops.len > 0 and precedence[ops[^1]] >= precedence[op]:
          values.apply(ops.pop())
        ops.add op
        expectOperand = true
    inc i

  if expectOperand: fail()
  while ops.len > 0:
    let op = ops.pop()
    if op == opParen: fail()
    values.apply(op)
  if values.len != 1: fail()
  values[0]

func isBlank(line: string): bool =
  for c in line:
    if c notin {' ', '\t'}: return false
  true

proc main() =
  var output = newStringOfCap(4096)
  for line in stdin.readAll().split('\n'):
    if line.isBlank: continue
    try:
      output.add $line.evaluate()
    except CalcError:
      output.add "error"
    output.add '\n'
  stdout.write output
  stdout.flushFile()

when isMainModule:
  main()
