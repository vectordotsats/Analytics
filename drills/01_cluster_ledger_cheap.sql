-- DRILL 01: token movements for a wallet cluster, narrow window (cheap replacement for the timed-out version)
-- Anchored to erc20_ethereum.evt_Transfer + a few days, so it reads little.
-- Params: wallets (text, comma-separated), start (date), end (date)
-- Native ETH is NOT here (ERC-20 only) -- see 01_cluster_eth.sql for that leg.
with cluster as (
  select from_hex(replace(replace(trim(w), '0x', ''), '0X', '')) as addr
  from unnest(split('{{wallets}}', ',')) as t(w)
),
raw as (
  select t.evt_block_time, t.evt_tx_hash, t.contract_address, t."from", t."to", t.value
  from erc20_ethereum.evt_Transfer t
  where t.evt_block_time >= date '{{start}}'
    and t.evt_block_time <  date '{{end}}'
    and (t."from" in (select addr from cluster) or t."to" in (select addr from cluster))
)
select r.evt_block_time,
       case when f.addr is not null and s.addr is not null then 'INTERNAL'
            when f.addr is not null then 'OUT' else 'IN' end as direction,
       k.symbol,
       r.value / power(10, k.decimals) as amount,
       case when f.addr is not null then r."to" else r."from" end as counterparty,
       r.evt_tx_hash
from raw r
join tokens.erc20 k on k.blockchain = 'ethereum' and k.contract_address = r.contract_address
left join cluster f on f.addr = r."from"
left join cluster s on s.addr = r."to"
order by r.evt_block_time
