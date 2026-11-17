-- DRILL 01 helper: every value movement in or out of a wallet cluster (Ethereum)
-- Params: wallets (text, comma-separated, grows as you discover addresses), start (text, e.g. 2026-03-21)
-- Use this instead of a transaction list: it catches ERC-20 moves and internal ETH the tx list misses.
with cluster as (
  select from_hex(replace(replace(trim(w), '0x', ''), '0X', '')) as addr
  from unnest(split('{{wallets}}', ',')) as t(w)
),
moves as (
  select t.block_time, t.tx_hash, t.symbol, t.token_standard,
         case when f.addr is not null and s.addr is not null then 'INTERNAL'
              when f.addr is not null then 'OUT' else 'IN' end as direction,
         t.amount, t.amount_usd,
         case when f.addr is not null then t."to" else t."from" end as counterparty
  from tokens.transfers t
  left join cluster f on f.addr = t."from"
  left join cluster s on s.addr = t."to"
  where t.blockchain = 'ethereum'
    and (f.addr is not null or s.addr is not null)
    and t.block_time >= timestamp '{{start}}'
),
lab as (  -- who is the counterparty: CEX deposit wallet, bridge, DEX router, contract name
  select address, max(name) as label, max(category) as category
  from labels.all
  where blockchain = 'ethereum'
  group by 1
)
select m.block_time, m.direction, m.symbol,
       round(m.amount, 4) as amount,
       round(m.amount_usd, 0) as usd,
       m.counterparty,
       l.label, l.category,
       m.tx_hash
from moves m
left join lab l on l.address = m.counterparty
order by m.block_time, m.usd desc
