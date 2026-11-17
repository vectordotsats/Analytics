-- DRILL 01 helper: same data, rolled up per counterparty = "where did the money go"
-- Same params. Run the ledger first; use this for the money table in your report.
with cluster as (
  select from_hex(replace(replace(trim(w), '0x', ''), '0X', '')) as addr
  from unnest(split('{{wallets}}', ',')) as t(w)
),
moves as (
  select t.symbol,
         case when f.addr is not null and s.addr is not null then 'INTERNAL'
              when f.addr is not null then 'OUT' else 'IN' end as direction,
         t.amount_usd,
         case when f.addr is not null then t."to" else t."from" end as counterparty,
         t.block_time, t.tx_hash
  from tokens.transfers t
  left join cluster f on f.addr = t."from"
  left join cluster s on s.addr = t."to"
  where t.blockchain = 'ethereum'
    and (f.addr is not null or s.addr is not null)
    and t.block_time >= timestamp '{{start}}'
),
lab as (
  select address, max(name) as label, max(category) as category
  from labels.all where blockchain = 'ethereum' group by 1
)
select m.direction, m.counterparty, l.label, l.category,
       count(*) as transfers,
       count(distinct m.tx_hash) as txs,
       array_join(array_agg(distinct m.symbol), ', ') as tokens,
       round(sum(m.amount_usd), 0) as usd,
       min(m.block_time) as first_seen, max(m.block_time) as last_seen
from moves m
left join lab l on l.address = m.counterparty
group by 1, 2, 3, 4
order by usd desc
