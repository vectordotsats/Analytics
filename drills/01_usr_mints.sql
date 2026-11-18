-- DRILL 01: every USR mint on 22 March 2026 (cheap: one contract, one day)
-- Mint = transfer out of the zero address. Params: token (text), day (date).
with tk as (
  select contract_address, decimals, symbol
  from tokens.erc20
  where blockchain = 'ethereum'
    and contract_address = from_hex(replace('{{token}}', '0x', ''))
)
select t.evt_block_time,
       t."to" as recipient,
       t.value / power(10, k.decimals) as minted,
       k.symbol,
       t.evt_tx_hash,
       t.evt_index
from erc20_ethereum.evt_Transfer t
join tk k on k.contract_address = t.contract_address
where t."from" = 0x0000000000000000000000000000000000000000
  and t.evt_block_time >= date '{{day}}'
  and t.evt_block_time <  date '{{day}}' + interval '1' day
order by minted desc
