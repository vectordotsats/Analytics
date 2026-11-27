# Stablecoin vault screener - build plan (v0, 2026-11-28)

Owner: Vector. Claude helps build; Vector decides scope and method.
Goal: one page per vault answering "what am I really exposed to, and can I get out?",
the same way for every vault, from on-chain data. Not an explorer (Herd), not a yield list (pigi).

## Design rules (the things to defend)
1. Measured, not advertised. Rates come from share-price growth on-chain, not the vault's UI.
2. Same method for every vault. Where a vault can't be measured, show "not measurable" - never a guess.
3. Risk and return are shown side by side, never blended. The score measures what sits behind the yield.
4. Discovery is dynamic. Vaults are found from on-chain events; a manual registry only for non-standard vaults (Agua, primeUSD).
5. Method is public. Weights, formulas and data sources published; every number traceable to a query.

## Vault types (each needs its own adapter)
| Type | Example | Gross vs net | Rate source |
|---|---|---|---|
| Curated lender (ERC-4626 over lending markets) | Gauntlet Prime, Steakhouse | gross = net (no borrowing) | share price |
| Looping / carry (allocator borrows) | Agua, IPOR loop vaults | gross > net | share price or set rate |
| Fixed-rate | Agua | as above | RateUpdated event |
| Permissioned RWA | Vault Street primeUSD | positions on Aave Horizon | PriceStorage.getPrice() |
| Credit pools | Maple/Syrup | loans off-chain | share price |

## Phases
0. Methodology (no code): universe rules, metric definitions, vault types. -> METHODOLOGY.md
1. Universe + rate + TVL: discover vaults; current rate, 7D/30D range; TVL change 1D/7D/30D. Validate vs pigi on 5 vaults.
2. Balance sheet: gross vs net, leverage, collateral mix - one adapter per vault type.
3. Exit + admin: instant exit liquidity, exit fees, timelock, withdraw caps, who holds admin.
4. Score: normalise each metric 0-100, apply published weights, backtest (Resolv USR, Mar 2026), sensitivity test.
5. Ship: site + free JSON API + weekly post.

## Validation gate per phase
Phase is done only when 5 known vaults (Agua, Arkis, Gauntlet Prime, Steakhouse HY, Syrup) match an
independent reference (pigi, vault app, block explorer) or the gap is explained.
