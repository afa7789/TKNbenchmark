// Scenarios run against a fresh anvil per case. @0/@1/@2 are anvil's dev accounts, @zero is 0x0.
const SUPPLY = '1000000000000000000000000'
const MAX = '115792089237316195423570985008687907853269984665640564039457584007913129639935'
const T = 'Transfer(address indexed,address indexed,uint256)'
const A = 'Approval(address indexed,address indexed,uint256)'
const deploy = { contract: 'Token', ctor: 'constructor(uint256)', args: [SUPPLY], event: { sig: T, args: ['@zero', '@0', SUPPLY] } }
const bal = (who, v) => ({ call: 'balanceOf(address)(uint256)', args: [who], expect: v })
const allowance = (o, s, v) => ({ call: 'allowance(address,address)(uint256)', args: [o, s], expect: v })
const tx = (from, send, args, extra = {}) => ({ from, send, args, ...extra })
const scenario = (name, steps) => ({ name, deploy, steps })

export const visible = () => ({
  kind: 'evm',
  cases: [
    scenario('metadata-and-mint', [
      { call: 'name()(string)', expect: 'Bench Token' },
      { call: 'symbol()(string)', expect: 'BTK' },
      { call: 'decimals()(uint8)', expect: '18' },
      { call: 'totalSupply()(uint256)', expect: SUPPLY },
      bal('@0', SUPPLY),
    ]),
    scenario('transfer', [
      tx(0, 'transfer(address,uint256)', ['@1', '100'], { event: { sig: T, args: ['@0', '@1', '100'] } }),
      bal('@1', '100'),
      bal('@0', '999999999999999999999900'),
    ]),
    scenario('approve-and-transfer-from', [
      tx(0, 'approve(address,uint256)', ['@1', '50'], { event: { sig: A, args: ['@0', '@1', '50'] } }),
      allowance('@0', '@1', '50'),
      tx(1, 'transferFrom(address,address,uint256)', ['@0', '@2', '30'], { event: { sig: T, args: ['@0', '@2', '30'] } }),
      allowance('@0', '@1', '20'),
      bal('@2', '30'),
    ]),
  ],
})

export const hidden = () => ({
  kind: 'evm',
  cases: [
    ...visible().cases,
    scenario('transfer-above-balance-reverts', [tx(1, 'transfer(address,uint256)', ['@0', '1'], { revert: true }), bal('@1', '0'), bal('@0', SUPPLY)]),
    scenario('transfer-from-above-allowance-reverts', [
      tx(0, 'approve(address,uint256)', ['@1', '10']),
      tx(1, 'transferFrom(address,address,uint256)', ['@0', '@2', '11'], { revert: true }),
      allowance('@0', '@1', '10'),
      bal('@2', '0'),
    ]),
    scenario('zero-address-reverts', [
      tx(0, 'transfer(address,uint256)', ['@zero', '1'], { revert: true }),
      tx(0, 'approve(address,uint256)', ['@zero', '1'], { revert: true }),
      bal('@0', SUPPLY),
    ]),
    scenario('infinite-allowance', [
      tx(0, 'approve(address,uint256)', ['@1', MAX]),
      tx(1, 'transferFrom(address,address,uint256)', ['@0', '@2', '100']),
      allowance('@0', '@1', MAX),
      bal('@2', '100'),
    ]),
    scenario('approve-overwrites', [tx(0, 'approve(address,uint256)', ['@1', '10']), tx(0, 'approve(address,uint256)', ['@1', '3']), allowance('@0', '@1', '3')]),
    scenario('zero-value-transfer', [tx(0, 'transfer(address,uint256)', ['@1', '0'], { event: { sig: T, args: ['@0', '@1', '0'] } }), bal('@1', '0')]),
    scenario('self-transfer', [tx(0, 'transfer(address,uint256)', ['@0', '5'], { event: { sig: T, args: ['@0', '@0', '5'] } }), bal('@0', SUPPLY)]),
    scenario('transfer-from-drains-allowance', [
      tx(0, 'approve(address,uint256)', ['@1', '40']),
      tx(1, 'transferFrom(address,address,uint256)', ['@0', '@1', '40']),
      allowance('@0', '@1', '0'),
      tx(1, 'transferFrom(address,address,uint256)', ['@0', '@1', '1'], { revert: true }),
    ]),
  ],
})
