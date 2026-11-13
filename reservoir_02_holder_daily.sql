-- RESERVOIR STEP 1b: daily balance per holder per token (rows only on days a holder moved)
with transfers as (
  select contract_address, "from", "to", value, evt_block_time from reservoir_protocol_ethereum.Stablecoin_evt_Transfer
  union all
  select contract_address, "from", "to", value, evt_block_time from reservoir_protocol_ethereum.Savingcoin_evt_Transfer
  union all
  select contract_address, "from", "to", value, evt_block_time from reservoir_protocol_ethereum.savingcoinv2_evt_transfer
),
moves as (
  select contract_address, "to" as holder,  cast(value as double) as raw, evt_block_time from transfers
  union all
  select contract_address, "from",         -cast(value as double),        evt_block_time from transfers
),
daily as (
  select m.contract_address, tk.symbol as token, m.holder,
         date_trunc('day', m.evt_block_time) as day,
         sum(m.raw) / power(10, tk.decimals) as net_change
  from moves m
  join tokens.erc20 tk on tk.blockchain = 'ethereum' and tk.contract_address = m.contract_address
  where m.holder <> 0x0000000000000000000000000000000000000000
  group by 1, 2, 3, 4, tk.decimals
)
select day, token, holder, net_change,
       sum(net_change) over (partition by contract_address, holder order by day) as balance
from daily
order by day desc, abs(net_change) desc
