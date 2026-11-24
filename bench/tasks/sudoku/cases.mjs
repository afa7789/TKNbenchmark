const S = [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]
const PUZZLE = [1, 0, 0, 4, 0, 4, 1, 0, 2, 0, 0, 3, 0, 3, 2, 0]
const LATIN = [1, 2, 3, 4, 2, 3, 4, 1, 3, 4, 1, 2, 4, 1, 2, 3] // rows and columns fine, boxes not
const BAD_COLUMN = [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 3, 4, 1, 2] // rows and boxes fine, column 0 repeats
const P_MINUS_1 = '21888242871839275222246405745257275088548364400416034343698204186575808495616'
const c = (name, puzzle, solution, expect) => ({ name, input: { puzzle: puzzle.map(String), solution: solution.map(String) }, expect })
const zeros = Array(16).fill(0)
const swap = (a, i, j) => a.map((v, k) => (k === i ? a[j] : k === j ? a[i] : v))
const set = (a, i, v) => a.map((x, k) => (k === i ? v : x))

export const visible = () => ({
  kind: 'zk',
  cases: [
    c('valid-solution', PUZZLE, S, 'accept'),
    c('disagrees-with-clue', set(PUZZLE, 1, 3), S, 'reject'),
    c('row-duplicate', zeros, swap(S, 0, 4), 'reject'),
  ],
})

export const hidden = () => ({
  kind: 'zk',
  cases: [
    ...visible().cases,
    c('empty-puzzle', zeros, S, 'accept'),
    c('full-puzzle', S, S, 'accept'),
    c('box-violation-only', zeros, LATIN, 'reject'),
    c('column-violation-only', zeros, BAD_COLUMN, 'reject'),
    c('value-five', zeros, set(S, 0, 5), 'reject'),
    c('value-zero', zeros, set(S, 5, 0), 'reject'),
    c('huge-field-element', zeros, set(S, 3, P_MINUS_1), 'reject'),
  ],
})
