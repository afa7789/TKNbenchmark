/** Signals any failure while evaluating an expression: syntax, division by zero, or overflow. */
export class CalcError extends Error {
  override name = 'CalcError'
}
