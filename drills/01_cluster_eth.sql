-- DRILL 01: native ETH in/out for the cluster (traces catch internal transfers a tx list misses)
-- Params: wallets (text, comma-separated), start (date), end (date)
with cluster as (
  select from_hex(replace(replace(trim(w), '0x', ''), '0X', '')) as addr
  from unnest(split('{{wallets}}', ',')) as t(w)
)
select tr.block_time,
       case when f.addr is not null then 'OUT' else 'IN' end as direction,
       tr.value / 1e18 as eth,
       case when f.addr is not null then tr."to" else tr."from" end as counterparty,
       tr.tx_hash
from ethereum.traces tr
left join cluster f on f.addr = tr."from"
left join cluster s on s.addr = tr."to"
where tr.block_time >= date '{{start}}'
  and tr.block_time <  date '{{end}}'
  and tr.value > uint256 '0'
  and tr.success
  and (tr."from" in (select addr from cluster) or tr."to" in (select addr from cluster))
order by tr.block_time
