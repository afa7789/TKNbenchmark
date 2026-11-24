// Time is exact: anvil starts at GENESIS and steps pin each block's timestamp.
const GENESIS = 1700000000
const START = GENESIS + 1000
const DUR = 1000
const TOTAL = '1000000000'
const BASE = 10000n * 10n ** 18n // anvil's starting balance for @2
const deploy = (over = {}) => ({ contract: 'Vesting', ctor: 'constructor(address,uint64,uint64)', args: ['@2', START, DUR], value: TOTAL, ...over })
const vested = (t, v) => ({ call: 'vestedAmount(uint64)(uint256)', args: [t], expect: v })
const release = (at, amount, extra = {}) => ({ from: 0, send: 'release()', at, ...(amount && { event: { sig: 'Released(uint256)', args: [amount] } }), ...extra })
const benBalance = (gain) => ({ balance: '@2', expect: String(BASE + BigInt(gain)) })
const scenario = (name, steps, d = deploy()) => ({ name, genesis: GENESIS, deploy: d, steps })

export const visible = () => ({
  kind: 'evm',
  cases: [
    scenario('getters', [
      { call: 'beneficiary()(address)', expect: '@2' },
      { call: 'start()(uint64)', expect: String(START) },
      { call: 'duration()(uint64)', expect: String(DUR) },
      { call: 'released()(uint256)', expect: '0' },
    ]),
    scenario('vesting-schedule', [vested(START - 1, '0'), vested(START, '0'), vested(START + 250, '250000000'), vested(START + DUR, TOTAL), vested(START + 5000, TOTAL)]),
    scenario('release-midway', [release(START + 500, '500000000'), benBalance(500000000), { call: 'released()(uint256)', expect: '500000000' }]),
  ],
})

export const hidden = () => ({
  kind: 'evm',
  cases: [
    ...visible().cases,
    scenario('release-before-start-reverts', [release(START - 10, null, { revert: true }), benBalance(0)]),
    scenario('nothing-left-reverts', [release(START + DUR, TOTAL), release(START + DUR + 10, null, { revert: true }), benBalance(TOTAL)]),
    scenario('two-releases', [release(START + 250, '250000000'), release(START + 750, '500000000'), { call: 'released()(uint256)', expect: '750000000' }, benBalance(750000000)]),
    scenario('receive-adds-to-total', [{ from: 0, to: '@contract', value: TOTAL }, vested(START + 500, TOTAL), vested(START + DUR, '2000000000')]),
    scenario('rounds-down', [vested(START + 1, '1000000'), vested(START + 333, '333000000')], deploy({ value: '1000000000' })),
    scenario('odd-total-rounds-down', [vested(START + 1, '0'), vested(START + 999, '6')], deploy({ value: '7' })),
    scenario('zero-beneficiary-reverts', [], deploy({ args: ['@zero', START, DUR], revert: true })),
    scenario('zero-duration-reverts', [], deploy({ args: ['@2', START, 0], revert: true })),
  ],
})
