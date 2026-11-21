-- DRILL 01: counterparty roles. Separates swap venues (money passes through) from real endpoints.
-- is_swap_venue = appears on BOTH sides of the same transaction -> he traded with it, did not send to it.
-- Params: wallets, start, end
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
  select r.evt_tx_hash, k.symbol, r.value / power(10, k.decimals) as amount,
         case when f.addr is not null and s.addr is not null then 'INTERNAL'
              when f.addr is not null then 'OUT' else 'IN' end as direction,
         case when f.addr is not null then r."to" else r."from" end as counterparty
  from raw r
  join tokens.erc20 k on k.blockchain = 'ethereum' and k.contract_address = r.contract_address
  left join cluster f on f.addr = r."from"
  left join cluster s on s.addr = r."to"
),
two_sided as (
  select distinct m.counterparty
  from moves m
  join moves n on n.evt_tx_hash = m.evt_tx_hash
              and n.counterparty = m.counterparty
              and n.direction <> m.direction
),
lab as (
  select address, max(namespace) as project
  from ethereum.contracts
  where address in (select counterparty from moves)
  group by 1
)
select m.counterparty, l.project,
       t.counterparty is not null as is_swap_venue,
       count(distinct m.evt_tx_hash) as txs,
       array_join(array_agg(distinct m.symbol), ', ') as tokens,
       round(sum(case when m.direction = 'IN'  then m.amount else 0 end), 2) as sent_to_cluster,
       round(sum(case when m.direction = 'OUT' then m.amount else 0 end), 2) as received_from_cluster
from moves m
left join two_sided t on t.counterparty = m.counterparty
left join lab l        on l.address = m.counterparty
where m.direction <> 'INTERNAL'
group by 1, 2, 3
order by is_swap_venue, received_from_cluster desc
