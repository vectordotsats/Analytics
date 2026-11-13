-- RESERVOIR 07: daily BALANCE per venue (for the balance-over-time chart, not for reading as a table)
-- Venue = Ethereum protocol (from Dune labels), "Ethereum: wallets", a destination chain, or "Outside" (mint / redeem).
-- Params: days_back (number, e.g. 180), min_venue_usd (number, e.g. 500000; smaller venues fold into 'Other').
-- Chart: stacked area, x = day, y = balance_usd, group by venue. Check: latest day stack total ~ $94.7M.
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
flows as (  -- token units per day / venue / token
  select f.day, f.venue, f.token_address,
         sum(case when f.raw > 0 then  f.raw else 0 end) / power(10, k.decimals) as inflow,
         sum(case when f.raw < 0 then -f.raw else 0 end) / power(10, k.decimals) as outflow
  from (select * from eth_flows union all select * from bridge_flows) f
  join tok k on k.contract_address = f.token_address
  group by f.day, f.venue, f.token_address, k.decimals
),
days as (
  select t.day
  from (select min(day) as d0 from flows) x
  cross join unnest(sequence(x.d0, current_date, interval '1' day)) as t(day)
),
price_raw as (  -- last price seen each day, in rUSD
  select contract_address, call_block_date as day,
         max_by(cast(output_0 as double) / cast(shares as double), call_block_time) as price
  from reservoir_protocol_ethereum.savingcoinv2_call_converttoassets
  where call_success and shares > uint256 '0'
  group by 1, 2
  union all
  select s.contract_address, p.day, p.price
  from (select distinct contract_address from reservoir_protocol_ethereum.savingcoin_evt_transfer) s
  cross join (select call_block_date as day, max_by(output_0 / 1e8, call_block_time) as price
              from reservoir_protocol_ethereum.savingmodule_call_currentprice
              where call_success group by 1) p
),
px as (  -- every day has a price: carry the last known one forward
  select d.day, k.contract_address,
         coalesce(last_value(r.price) ignore nulls over (
                    partition by k.contract_address order by d.day
                    rows between unbounded preceding and current row), 1) as price
  from days d
  cross join tok k
  left join price_raw r on r.contract_address = k.contract_address and r.day = d.day
),
grid as (  -- every day for every venue + token that ever had a flow
  select d.day, v.venue, v.token_address
  from days d
  cross join (select distinct venue, token_address from flows) v
),
running as (
  select g.day, g.venue, g.token_address,
         coalesce(f.inflow, 0)  as inflow,
         coalesce(f.outflow, 0) as outflow,
         sum(coalesce(f.inflow, 0) - coalesce(f.outflow, 0))
           over (partition by g.venue, g.token_address order by g.day) as units
  from grid g
  left join flows f on f.day = g.day and f.venue = g.venue and f.token_address = g.token_address
),
valued as (
  select r.day, r.venue,
         sum(r.inflow  * p.price) as inflow_usd,
         sum(r.outflow * p.price) as outflow_usd,
         sum(r.units   * p.price) as balance_usd
  from running r
  join px p on p.day = r.day and p.contract_address = r.token_address
  group by 1, 2
),
ranked as (  -- drop the mint/redeem mirror; find each venue's peak in the window
  select day, venue, balance_usd,
         max(balance_usd) over (partition by venue) as peak_usd
  from valued
  where day >= current_date - interval '{{days_back}}' day
    and venue <> 'Outside (mint / redeem)'
)
select day,
       case when peak_usd >= {{min_venue_usd}} then venue else 'Other' end as venue,
       round(sum(balance_usd), 0) as balance_usd
from ranked
group by 1, 2
order by 1, 2
