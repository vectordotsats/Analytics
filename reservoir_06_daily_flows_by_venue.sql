-- RESERVOIR STEP 3a: daily money in / out per venue (all three tokens, in USD at last known price)
-- Venue = Ethereum protocol (from Dune labels), "Ethereum: wallets", a destination chain, or "Outside" (mint / redeem).
-- Checks: each day sum(net_usd) over all venues ~ 0 ; latest balance Monad ~$62.3M, Pharos ~$23.5M,
--         Ethereum: morpho_blue ~$7.2M, Ethereum: dolomite ~$1.2M, Outside ~ -$94.7M.
with eid_names (eid, chain) as (
  values (30101,'Ethereum'), (30102,'BNB'), (30106,'Avalanche'), (30110,'Arbitrum'), (30168,'Solana'),
         (30183,'Linea'), (30184,'Base'), (30280,'Sei'), (30319,'Worldchain'), (30320,'Unichain'),
         (30332,'Sonic'), (30362,'Berachain'), (30365,'XDC'), (30367,'HyperEVM'), (30370,'Plume'),
         (30375,'Katana'), (30383,'Plasma'), (30390,'Monad'), (30398,'MegaETH'), (30407,'Pharos'),
         (30410,'Tempo')
),
transfers as (
  select contract_address, "from", "to", value, evt_block_time from reservoir_protocol_ethereum.stablecoin_evt_transfer
  union all
  select contract_address, "from", "to", value, evt_block_time from reservoir_protocol_ethereum.savingcoin_evt_transfer
  union all
  select contract_address, "from", "to", value, evt_block_time from reservoir_protocol_ethereum.savingcoinv2_evt_transfer
),
tok as (
  select t.contract_address, tk.symbol as token, tk.decimals
  from (select distinct contract_address from transfers) t
  join tokens.erc20 tk on tk.blockchain = 'ethereum' and tk.contract_address = t.contract_address
),
adapters as (  -- bridge contracts: their balance is split by chain below instead
  select distinct contract_address as address from reservoir_protocol_ethereum.rusdoftadapter_evt_oftsent
  union
  select distinct contract_address from reservoir_protocol_ethereum.srusdoftadapter_evt_oftsent
  union
  select distinct contract_address from reservoir_protocol_ethereum.wsrusdoftadapter_evt_oftsent
),
legs as (
  select contract_address as token_address, "to" as holder,  cast(value as double) as raw, evt_block_time from transfers
  union all
  select contract_address,                  "from",         -cast(value as double),        evt_block_time from transfers
),
names as (
  select address, max(namespace) as project
  from ethereum.contracts
  where address in (select distinct holder from legs)
  group by 1
),
is_contract as (
  select distinct address from ethereum.creation_traces
  where address in (select distinct holder from legs)
),
eth_flows as (
  select cast(date_trunc('day', l.evt_block_time) as date) as day, l.token_address,
         case when l.holder = 0x0000000000000000000000000000000000000000 then 'Outside (mint / redeem)'
              when n.project is not null then 'Ethereum: ' || n.project
              when ic.address is not null then 'Ethereum: unlabeled contract'
              else 'Ethereum: wallets' end as venue,
         l.raw
  from legs l
  left join names n        on n.address = l.holder
  left join is_contract ic on ic.address = l.holder
  where l.holder not in (select address from adapters)
),
bridge as (  -- + arrives on the chain, - leaves it
  select evt_block_time, 'rUSD' as token, dstEid as eid,  cast(amountSentLD as double) as raw from reservoir_protocol_ethereum.rusdoftadapter_evt_oftsent
  union all select evt_block_time, 'rUSD',   srcEid, -cast(amountReceivedLD as double) from reservoir_protocol_ethereum.rusdoftadapter_evt_oftreceived
  union all select evt_block_time, 'srUSD',  dstEid,  cast(amountSentLD as double)     from reservoir_protocol_ethereum.srusdoftadapter_evt_oftsent
  union all select evt_block_time, 'srUSD',  srcEid, -cast(amountReceivedLD as double) from reservoir_protocol_ethereum.srusdoftadapter_evt_oftreceived
  union all select evt_block_time, 'wsrUSD', dstEid,  cast(amountSentLD as double)     from reservoir_protocol_ethereum.wsrusdoftadapter_evt_oftsent
  union all select evt_block_time, 'wsrUSD', srcEid, -cast(amountReceivedLD as double) from reservoir_protocol_ethereum.wsrusdoftadapter_evt_oftreceived
),
bridge_flows as (
  select cast(date_trunc('day', b.evt_block_time) as date) as day, k.contract_address as token_address,
         coalesce(n.chain, 'eid ' || cast(b.eid as varchar)) as venue, b.raw
  from bridge b
  join tok k            on k.token = b.token
  left join eid_names n on n.eid = b.eid
),
px as (
  select contract_address, max_by(cast(output_0 as double) / cast(shares as double), call_block_time) as price
  from reservoir_protocol_ethereum.savingcoinv2_call_converttoassets
  where call_success and shares > uint256 '0'
  group by 1
  union all
  select s.contract_address, p.price
  from (select distinct contract_address from reservoir_protocol_ethereum.savingcoin_evt_transfer) s
  cross join (select max_by(output_0 / 1e8, call_block_time) as price
              from reservoir_protocol_ethereum.savingmodule_call_currentprice where call_success) p
),
daily as (
  select f.day, f.venue,
         sum(case when f.raw > 0 then  f.raw else 0 end / power(10, k.decimals) * coalesce(p.price, 1)) as inflow_usd,
         sum(case when f.raw < 0 then -f.raw else 0 end / power(10, k.decimals) * coalesce(p.price, 1)) as outflow_usd
  from (select * from eth_flows union all select * from bridge_flows) f
  join tok k     on k.contract_address = f.token_address
  left join px p on p.contract_address = f.token_address
  group by 1, 2
),
running as (
  select day, venue, inflow_usd, outflow_usd,
         inflow_usd - outflow_usd as net_usd,
         sum(inflow_usd - outflow_usd) over (partition by venue order by day) as balance_usd
  from daily
)
select day, venue,
       round(inflow_usd, 0) as inflow_usd, round(outflow_usd, 0) as outflow_usd,
       round(net_usd, 0) as net_usd, round(balance_usd, 0) as balance_usd
from running
where day >= current_date - interval '{{days_back}}' day
order by day desc, abs(net_usd) desc
