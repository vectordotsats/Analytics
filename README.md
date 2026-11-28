# Analytics — Vector

On-chain analysis work: dashboards, investigation drills, project logs.

## Folders

| Folder | What's in it |
|---|---|
| `projects/` | One folder per protocol: queries and the running log for each |
| `drills/` | Investigation practice. Each drill has a brief, helper queries and a scored report |
| `reference/` | Reusable across everything: doctrine, SQL notes, backlog, session handoff |
| `career/` | CV, outreach targets, pitch prep |
| `archive/` | Superseded copies kept for safety, not current |

## Projects

| Folder | Status |
|---|---|
| `projects/reservoir/` | rUSD / srUSD / wsrUSD. Where every dollar sits across chains, daily flows per venue. Dashboard live |
| `projects/midnight-tenor/` | Morpho Midnight loan origination + Tenor's share of it |
| `projects/arc/` | Arc FX, lending, Morpho on Arc |
| `projects/meteora-hawkfi/` | Solana LP strategy and screens |
| `projects/morpho/` | Morpho work incl. Coinbase tokenized stocks incentives |
| `projects/other/` | Tenbin Labs |

## Drills

Practice investigations on real past incidents, worked without reading the
post-mortem first, then scored against it.

| Drill | Case | Status |
|---|---|---|
| 01 | Resolv USR — $80M mint from a compromised key, 22 Mar 2026 | In progress |

Start with the brief: `drills/01_resolv_usr_brief.md`.

## Conventions

- Queries are dynamic: no hardcoded addresses, decimals, prices or token lists.
  Anything that can be derived on-chain is derived.
- Parameters over edits: `{{wallets}}`, `{{start}}`, `{{days_back}}` so a query
  is reused rather than rewritten.
- Every project log states what is verified and what is not.

Stablecoin vault screener moved to its own repo: https://github.com/vectordotsats/ashborne
