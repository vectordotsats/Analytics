-- RESERVOIR STEP 2b: who holds wsrUSD on Pharos right now
-- Check: sum(balance) must be ~21.20M (the net bridged to Pharos). If not, direct chain-to-chain moves exist.
with token as (  -- Pharos is not decoded on Dune, so take the wsrUSD address from Monad (Reservoir deploys it at the same address on new chains; if wrong, the sum check fails)
  select distinct contract_address from reservoir_protocol_monad.wsrusdoft_evt_oftreceived
),
moves as (
  select t.contract_address, t."to" as holder,  cast(t.value as double) as raw, t.evt_block_time
  from erc20_pharos.evt_transfer t join token k on k.contract_address = t.contract_address
  union all
  select t.contract_address, t."from",         -cast(t.value as double),        t.evt_block_time
  from erc20_pharos.evt_transfer t join token k on k.contract_address = t.contract_address
),
bal as (
  select m.holder,
         sum(m.raw) / power(10, coalesce(max(tk.decimals), 18)) as balance,
         max(m.evt_block_time) as last_move
  from moves m
  left join tokens.erc20 tk on tk.blockchain = 'pharos' and tk.contract_address = m.contract_address
  where m.holder <> 0x0000000000000000000000000000000000000000
  group by 1
),
px as (
  select max_by(cast(output_0 as double) / cast(shares as double), call_block_time) as price
  from reservoir_protocol_ethereum.savingcoinv2_call_converttoassets
  where call_success and shares > uint256 '0'
),
names as (
  select address, max(namespace) as project, max(name) as contract_name
  from pharos.contracts group by 1
),
is_contract as (select distinct address from pharos.creation_traces)
select b.holder, b.balance,
       b.balance * p.price as usd,
       b.balance / sum(b.balance) over () as share,
       ic.address is not null as is_contract,
       n.project, n.contract_name, b.last_move
from bal b
cross join px p
left join is_contract ic on ic.address = b.holder
left join names n        on n.address = b.holder
where abs(b.balance) > 1
order by usd desc
