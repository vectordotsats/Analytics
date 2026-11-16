# DRILL 01 — Resolv USR incident (compliance trace)

Work it as if it is live. Do not read any post-mortem until your report is submitted.

## The alert
- When: Sunday 22 March 2026, about 02:21 UTC
- What: an unusually large mint of USR (Resolv's stablecoin) on Ethereum, about $50M in one transaction
- Your role: compliance analyst at an exchange that lists USR. Your head of risk wants answers.

## Time limit
3 hours total. Note your start time. Stop when the clock runs out, even if unfinished.

## Deliverables
| # | Question | Evidence expected |
|---|---|---|
| 1 | What happened? Which transactions, which contract function, who called it | tx hashes, caller address, function name |
| 2 | Why was it possible? | what the contract checks and what it does not |
| 3 | Who is the attacker? | wallet cluster: every address you tie to them and how you tied it |
| 4 | Where did the money go? | amounts per destination: DEX swaps, bridges, mixers, exchanges, still-held |
| 5 | Who is exposed? | protocols / pools / exchanges that received the bad USR or the proceeds, with amounts |
| 6 | What did the team do, and when? | pauses, role changes, multisig actions, with timestamps |
| 7 | What should we (the exchange) do right now? | 3 actions, each tied to a finding |

## The report (one page)
- Answer first, in one line.
- A timeline table (UTC).
- A money table: minted / sold / extracted / where it sits.
- Every claim tagged: CONFIRMED (on-chain proof), LIKELY (pattern), UNKNOWN.
- A "not verified" section.

## Rules
- Tools: Etherscan, Dune, Herd, Arkham or any label tool. No news articles, no post-mortems, no X threads about the hack.
- Queries must be dynamic: no pasted address lists except the starting contract and wallets you discovered yourself.
- Hints are allowed. Each hint costs 5 points.

## Scoring (100)
| Part | Points |
|---|---|
| 1 What happened | 15 |
| 2 Why possible | 10 |
| 3 Attacker cluster | 15 |
| 4 Where the money went (amounts within 10%) | 25 |
| 5 Exposure | 15 |
| 6 Team response timeline | 10 |
| 7 Actions | 5 |
| Report quality (tags, limits stated) | 5 |

Pass = 70. Graded against the public post-mortems after submission.

## Log
- Start time:
- Hints used:
- Submitted:
- Score:
