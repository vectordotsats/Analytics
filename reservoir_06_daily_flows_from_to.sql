-- RESERVOIR STEP 3a (v3): daily money moves, one row = "from venue -> to venue -> amount"
-- Read any way you like: each row is a complete sentence. No balance column (balances live in reservoir_07).
-- Pass-through contracts and wallet-to-wallet transfers drop out (netted per transaction).
-- Params: days_back (number, e.g. 30), min_usd (number, e.g. 1000). Each day valued at that day's price.
-- Checks (Nov 2026): Nov 13 "Ethereum: morpho_blue -> Redeemed" ~$114.6k ; Nov 10 Monad -> wallets -> Pharos ~$2.45M.
with eid_names (eid, chain) as (
  values (30101,'Ethereum'), (30102,'BNB'), (30106,'Avalanche'), (30110,'Arbitrum'), (30168,'Solana'),
         (30183,'Linea'), (30184,'Base'), (30280,'Sei'), (30319,'Worldchain'), (30320,'Unichain'),
         (30332,'Sonic'), (30362,'Berachain'), (30365,'XDC'), (30367,'HyperEVM'), (30370,'Plume'),
         (30375,'Katana'), (30383,'Plasma'), (30390,'Monad'), (30398,'MegaETH'), (30407,'Pharos'),
         (30410,'Tempo')
),
transfers as (
  select contract_address, "from", "to", cast(value as double) as raw, evt_block_time, evt_tx_hash
  from reservoir_protocol_ethereum.stablecoin_evt_transfer
  where evt_block_time >= current_date - interval '{{days_back}}' day
  union all
  select contract_address, "from", "to", cast(value as double), evt_block_time, evt_tx_hash
  from reservoir_protocol_ethereum.savingcoin_evt_transfer
  where evt_block_time >= current_date - interval '{{days_back}}' day
  union all
  select contract_address, "from", "to", cast(value as double), evt_block_time, evt_tx_hash
  from reservoir_protocol_ethereum.savingcoinv2_evt_transfer
  where evt_block_time >= current_date - interval '{{days_back}}' day
),
tok as (
  select t.contract_address, tk.decimals
  from (select distinct contract_address from transfers) t
  join tokens.erc20 tk on tk.blockchain = 'ethereum' and tk.contract_address = t.contract_address
),
oft as (  -- which chain each bridge transfer went to / came from
  select distinct contract_address as adapter, evt_tx_hash, 'out' as dir, dstEid as eid, cast(amountSentLD as double) as amt
  from reservoir_protocol_ethereum.rusdoftadapter_evt_oftsent
  union select distinct contract_address, evt_tx_hash, 'out', dstEid, cast(amountSentLD as double)     from reservoir_protocol_ethereum.srusdoftadapter_evt_oftsent
  union select distinct contract_address, evt_tx_hash, 'out', dstEid, cast(amountSentLD as double)     from reservoir_protocol_ethereum.wsrusdoftadapter_evt_oftsent
  union select distinct contract_address, evt_tx_hash, 'in',  srcEid, cast(amountReceivedLD as double) from reservoir_protocol_ethereum.rusdoftadapter_evt_oftreceived
  union select distinct contract_address, evt_tx_hash, 'in',  srcEid, cast(amountReceivedLD as double) from reservoir_protocol_ethereum.srusdoftadapter_evt_oftreceived
  union select distinct contract_address, evt_tx_hash, 'in',  srcEid, cast(amountReceivedLD as double) from reservoir_protocol_ethereum.wsrusdoftadapter_evt_oftreceived
),
adapters as (select distinct adapter as address from oft),
legs as (  -- each transfer = one leg in (+) and one leg out (-)
  select t.evt_tx_hash, t.evt_block_time, t.contract_address as token_address, t."to" as holder, t.raw,
         a.address is not null as is_bridge, o.eid
  from transfers t
  left join adapters a on a.address = t."to"
  left join oft o on o.adapter = a.address and o.dir = 'out' and o.evt_tx_hash = t.evt_tx_hash and o.amt = t.raw
  union all
  select t.evt_tx_hash, t.evt_block_time, t.contract_address, t."from", -t.raw,
         a.address is not null, o.eid
  from transfers t
  left join adapters a on a.address = t."from"
  left join oft o on o.adapter = a.address and o.dir = 'in' and o.evt_tx_hash = t.evt_tx_hash and o.amt = t.raw
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
tx_net as (  -- net change per venue inside one transaction: pass-throughs cancel to zero
  select cast(date_trunc('day', l.evt_block_time) as date) as day, l.evt_tx_hash, l.token_address,
         case when l.holder = 0x0000000000000000000000000000000000000000 then 'OUTSIDE'
              when l.is_bridge then coalesce(e.chain, 'eid ' || cast(l.eid as varchar), 'Bridge (chain not matched)')
              when n.project is not null then 'Ethereum: ' || n.project
              when ic.address is not null then 'Ethereum: unlabeled contract'
              else 'Ethereum: wallets' end as venue,
         sum(l.raw) as net
  from legs l
  left join eid_names e    on e.eid = l.eid
  left join names n        on n.address = l.holder
  left join is_contract ic on ic.address = l.holder
  group by 1, 2, 3, 4
),
pairs as (  -- match what left (negative) with where it arrived (positive), same tx and token
  select s.day, s.token_address, s.venue as from_venue, d.venue as to_venue,
         -s.net * d.net / sum(d.net) over (partition by s.evt_tx_hash, s.token_address, s.venue) as raw
  from tx_net s
  join tx_net d on d.evt_tx_hash = s.evt_tx_hash and d.token_address = s.token_address and d.net > 0
  where s.net < 0
),
price_raw as (
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
days as (
  select t.day
  from (select min(day) as d0 from price_raw) x
  cross join unnest(sequence(x.d0, current_date, interval '1' day)) as t(day)
),
px as (  -- that day's price, carried forward over quiet days
  select d.day, k.contract_address,
         last_value(r.price) ignore nulls over (
           partition by k.contract_address order by d.day
           rows between unbounded preceding and current row) as price
  from days d
  cross join (select distinct contract_address from price_raw) k
  left join price_raw r on r.contract_address = k.contract_address and r.day = d.day
),
moves as (
  select p.day, p.from_venue, p.to_venue,
         sum(p.raw / power(10, k.decimals) * coalesce(x.price, 1)) as usd
  from pairs p
  join tok k     on k.contract_address = p.token_address
  left join px x on x.contract_address = p.token_address and x.day = p.day
  group by 1, 2, 3
)
select date_format(day, '%Y-%m-%d') as day,
       case when from_venue = 'OUTSIDE' then 'New mint' else from_venue end as money_left,
       case when to_venue   = 'OUTSIDE' then 'Redeemed (left Reservoir)' else to_venue end as money_arrived,
       round(usd, 0) as usd
from moves
where usd >= {{min_usd}}
order by day desc, usd desc
