-- DRILL 01: net position of the cluster, per token. Stops the hop-by-hop spiral.
-- Params: wallets (text, comma-separated), start (date), end (date)
-- net ~ 0  = passed through (churn, ignore)   net > 0 = ended up holding   net < 0 = paid away
with cluster as (
  select from_hex(replace(replace(trim(w), '0x', ''), '0X', '')) as addr
  from unnest(split('{{wallets}}', ',')) as t(w)
),
real_tokens as (select distinct contract_address from prices.tokens where blockchain = 'ethereum'),
raw as (
  select t.evt_block_time, t.evt_tx_hash, t.contract_address, t."from", t."to", t.value
  from erc20_ethereum.evt_Transfer t
  where t.evt_block_time >= date '{{start}}' and t.evt_block_time < date '{{end}}'
    and t.contract_address in (select contract_address from real_tokens)
    and (t."from" in (select addr from cluster) or t."to" in (select addr from cluster))
),
moves as (
  select k.symbol,
         case when f.addr is not null and s.addr is not null then 'INTERNAL'
              when f.addr is not null then 'OUT' else 'IN' end as direction,
         r.value / power(10, k.decimals) as amount
  from raw r
  join tokens.erc20 k on k.blockchain = 'ethereum' and k.contract_address = r.contract_address
  left join cluster f on f.addr = r."from"
  left join cluster s on s.addr = r."to"
)
select symbol,
       round(sum(case when direction = 'IN'  then amount else 0 end), 2) as received,
       round(sum(case when direction = 'OUT' then amount else 0 end), 2) as sent,
       round(sum(case when direction = 'IN'  then amount
                      when direction = 'OUT' then -amount else 0 end), 2) as net
from moves
where direction <> 'INTERNAL'
group by 1
order by abs(sum(case when direction = 'IN' then amount when direction = 'OUT' then -amount else 0 end)) desc
