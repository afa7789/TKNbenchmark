const P_MINUS_1 = '21888242871839275222246405745257275088548364400416034343698204186575808495616'
const c = (name, age, threshold, expect) => ({ name, input: { age: String(age), threshold: String(threshold) }, expect })

export const visible = () => ({
  kind: 'zk',
  cases: [c('above-threshold', 25, 18, 'accept'), c('equal-to-threshold', 18, 18, 'accept'), c('below-threshold', 17, 18, 'reject')],
})

export const hidden = () => ({
  kind: 'zk',
  cases: [
    ...visible().cases,
    c('max-age-zero-threshold', 255, 0, 'accept'),
    c('both-zero', 0, 0, 'accept'),
    c('both-max', 255, 255, 'accept'),
    c('age-256', 256, 0, 'reject'),
    c('age-300', 300, 18, 'reject'),
    c('just-below-max', 254, 255, 'reject'),
    c('threshold-256', 5, 256, 'reject'),
    c('huge-field-element', P_MINUS_1, 0, 'reject'),
    c('zero-below-one', 0, 1, 'reject'),
  ],
})
