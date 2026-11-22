-- RESERVOIR STEP 1a: who holds rUSD / srUSD / wsrUSD right now (Ethereum)
-- Check: sum(balance) per token must equal supply in the TVL query. No negative balances.
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
bal as (
  select m.contract_address, tk.symbol as token, m.holder,
         sum(m.raw) / power(10, tk.decimals) as balance,
         max(m.evt_block_time) as last_move
  from moves m
  join tokens.erc20 tk on tk.blockchain = 'ethereum' and tk.contract_address = m.contract_address
  where m.holder <> 0x0000000000000000000000000000000000000000
  group by 1, 2, 3, tk.decimals
),
px as (  -- last known price in rUSD; rUSD itself = 1
  select contract_address, max_by(cast(output_0 as double) / cast(shares as double), call_block_time) as price
  from reservoir_protocol_ethereum.savingcoinv2_call_converttoassets
  where call_success and shares > uint256 '0'
  group by 1
  union all
  select s.contract_address, p.price
  from (select distinct contract_address from reservoir_protocol_ethereum.Savingcoin_evt_Transfer) s
  cross join (select max_by(output_0 / 1e8, call_block_time) as price
              from reservoir_protocol_ethereum.savingmodule_call_currentprice where call_success) p
),
names as (
  select address, max(namespace) as project, max(name) as contract_name
  from ethereum.contracts group by 1
),
is_contract as (select distinct address from ethereum.creation_traces)
select b.token, b.holder,
       b.balance,
       b.balance * coalesce(p.price, 1) as usd,
       b.balance / sum(b.balance) over (partition by b.token) as share_of_token,
       ic.address is not null as is_contract,
       n.project, n.contract_name,
       b.last_move
from bal b
left join px p          on p.contract_address = b.contract_address
left join is_contract ic on ic.address = b.holder
left join names n        on n.address = b.holder
where abs(b.balance) > 1
order by usd desc
