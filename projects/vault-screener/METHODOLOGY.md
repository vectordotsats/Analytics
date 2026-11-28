# Methodology v0.1 (2026-11-28)

## 1. Universe (v1)
- Underlying asset: USDC only (USDT added once the main USDC vaults are done). Token address read from Dune's price list
  (prices.tokens), never from a symbol alone (fake "USDC" tokens exist).
- Chain: Ethereum only.
- Size: TVL >= $5M on the measurement day.
- Vault type in v1: standard ERC-4626 vaults only. Non-standard vaults (Agua, primeUSD)
  come in v1.1 through a small registry.
- Out: AMM pools, vaults whose underlying is not USDC/USDT (USDT, sUSDe, USDS etc. come later).

## 2. Discovery (no hand-made vault list)
A contract is a candidate vault if it emits the ERC-4626 Deposit event AND, in the same
transaction, receives a USDC transfer equal to the event's `assets` amount.
That second check proves which asset the vault takes, from on-chain data alone.

## 3. Share price
price_per_share = assets / shares, taken from Deposit and Withdraw events,
each side scaled by its own decimals (shares often 18, USDC 6).
Daily price = last observation of the day, carried forward on days with no events.

## 4. Rate (realized, not advertised)
- Current rate = 7-day realized APY = (P_today / P_7d_ago)^(365/7) - 1
- 7D range = min and max of the daily 1-day APY over the last 7 days
- 30D range = same over the last 30 days
- Negative values are shown, never clipped (a price drop is information).

## 5. TVL
TVL = shares outstanding x price_per_share.
Shares outstanding = vault token mints minus burns (Transfer from/to 0x0).
Changes reported: 1D, 7D, 30D, in % and USD.

## 6. Known traps (check before trusting a number)
| Trap | What goes wrong | Guard |
|---|---|---|
| Entry/exit fees | assets/shares at deposit includes a fee, price looks wrong | Compare deposit-derived vs withdraw-derived price; flag gaps > 0.1% |
| Quiet vaults | No events for days, price goes stale | Show "last observed" date; no rate if no event in 7 days |
| Decimals | 18 vs 6 decimals gives prices off by 1e12 | Read decimals from the token, never assume |
| Donation / inflation spikes | One-off price jump inflates APY | Flag any 1-day APY > 100% for review |
| Bad debt / loss | Price drops | Shown as negative APY, never removed |

## 7. Score weights (v0, published)
| Component | Weight | Direction |
|---|---|---|
| Exit liquidity | 25% | more instant liquidity = higher score |
| Leverage | 20% | less leverage = higher score |
| Rate stability | 20% | narrower 30D range = higher score |
| Admin powers | 20% | timelock + caps + multisig = higher score |
| Collateral concentration | 15% | more diversified = higher score |
Yield is never part of the score. Normalisation (how each becomes 0-100) is set in Phase 4.

## 8. Validation
Phase 1 passes when realized 7D APY and TVL for 5 reference vaults are within
0.5 percentage points / 2% of an outside source (pigi, vault app), or the gap is explained.
