# USCC on Aave Horizon — why did the balance fall ~74%?

Trigger: The Defiant, 24 Nov 2026 — USCC balance on Horizon fell ~74% from late Oct to 23 Nov,
most of it by early Nov; Horizon TVL rebounded 23 Nov; outstanding borrowing still ~24% below late Oct.
Article gives no cause, no dollar figures, no quotes.

## What USCC is
Bitwise Crypto Carry Fund (was Superstate Crypto Carry Fund). Tokenized private fund, Reg D,
qualified purchasers only, allowlisted wallets. Strategy: crypto basis (spot vs futures) + Treasuries.
$268.65M AUM, NAV $11.59, 30-day yield 5.09%, fee 0.75% (superstate.com, 24 Nov 2026).
On Horizon it is COLLATERAL: institutions supply USCC, borrow USDC / RLUSD / GHO against it.

## The question
Did money LEAVE Horizon, or ROTATE inside it (USCC -> USTB)? And was the exit orderly or forced?

## Addresses (Ethereum mainnet)
| What | Address | Source |
|---|---|---|
| USCC token (proxy) | 0x14d60e7fdc0d71d8611742720e4c50e7a974020c | Superstate docs |
| USTB token (proxy) | 0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e | Superstate docs |
| Allowlist V3 (proxy) | 0x02f1fa8b196d21c7b733eb2700b825611d8a38e5 | Superstate docs |
| Allowlist V4 (proxy) | 0xBcBC2b4FB2AbE1C598C9ea91E0b03338e4728D1f | Superstate docs |
| Chainlink USCC oracle | 0xAfFd8F5578E8590665de561bdE9E7BAdb99300d9 | Superstate docs |
| Chainlink USTB oracle | 0x289B5036cd942e619E1Ee48670F98d214E745AAC | Superstate docs |
| Horizon aToken "RWA USCC" (VERIFY) | 0x08b798c40b9ab931356d9ab4235f548325c4cb80 | StakingRewards — confirm on Etherscan |
| Horizon aToken "RWA USDC" (VERIFY) | 0x68215b6533c47ff9f7125ac95adf00fe4a62f79e | StakingRewards — confirm on Etherscan |
| Horizon contract, asset unknown (VERIFY) | 0x4e58a2e433a739726134c83d2f07b2562e8dfdb3 | StakingRewards |

## Conflicting figures — resolve these FIRST
| Source | USCC on Horizon | Date |
|---|---|---|
| DefiLlama (RWA page) | $25.84M DeFi active TVL | 24 Nov 2026 |
| Aavescan (Superstate page) | $100.6M supplied, change -$20.2M | 24 Nov 2026 |
| StakingRewards | $93M AUM, -23.57% / -$28.66M over 30d, 14 active users | 24 Nov 2026 |
| The Defiant (older piece) | $238M supplied when Horizon neared $540M | ~Nov 2025 |
A 4x spread between trackers. Ground truth = the aToken's total supply on-chain.

## The market is tiny and enumerable
StakingRewards reports **14 active users** on the USCC market. Every participant can be listed by
name-of-address. This is not a statistical problem, it is a roll call.

## Plan
1. Ground truth: aToken total supply daily, in TOKENS not dollars (NAV rises on its own).
2. Roll call: every address that held the USCC aToken in Oct, and its balance then vs now.
3. Rotation test: plot USCC supply against USTB supply, same axis, daily. Do the lines mirror?
4. Same-wallet test: did the addresses that left USCC appear in USTB? That proves rotation vs exit.
5. Health test: any liquidation events on Horizon in the window? Orderly withdraw vs forced sale.
6. Leverage test: USCC collateral down 74% vs borrowing down 24% -> is the remaining book thinner?
   Confirm whether "borrowing" is USCC-backed debt or Horizon-wide.
7. Cause: did the crypto basis compress in early Nov? If yes, the carry yield fell toward T-bill
   yield and rotation to USTB is rational. (Hypothesis, unproven.)

## Status
- [ ] 1 ground truth
- [ ] 2 roll call
- [ ] 3 rotation chart
- [ ] 4 same-wallet test
- [ ] 5 liquidations
- [ ] 6 leverage
- [ ] 7 cause
