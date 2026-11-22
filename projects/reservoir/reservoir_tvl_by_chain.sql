-- RESERVOIR TVL BY CHAIN (today) - corrected
-- Method: tokens only leave Ethereum through the 3 bridge adapters, so
--   chain balance = sent to that chain - returned from it ; Ethereum = supply - everything bridged out.
-- New chains appear on their own (as "eid NNNNN" until named below). Price = last known, never 1.
-- Check (Nov 13 2026): total ~$94.7M, Monad ~56.24M wsrUSD, Pharos ~21.20M wsrUSD.
with eid_names (eid, chain) as (  -- LayerZero docs, OFT quickstart "Find your chain" table
  values (30101,'Ethereum'), (30102,'BNB'), (30106,'Avalanche'), (30110,'Arbitrum'), (30168,'Solana'),
         (30183,'Linea'), (30184,'Base'), (30280,'Sei'), (30319,'Worldchain'), (30320,'Unichain'),
         (30332,'Sonic'), (30362,'Berachain'), (30365,'XDC'), (30367,'HyperEVM'), (30370,'Plume'),
         (30375,'Katana'), (30383,'Plasma'), (30390,'Monad'), (30398,'MegaETH'), (30407,'Pharos'),
         (30410,'Tempo')
),
transfers as (
  select contract_address, "from", "to", value from reservoir_protocol_ethereum.stablecoin_evt_transfer
  union all
  select contract_address, "from", "to", value from reservoir_protocol_ethereum.savingcoin_evt_transfer
  union all
  select contract_address, "from", "to", value from reservoir_protocol_ethereum.savingcoinv2_evt_transfer
),
supply as (  -- total minted minus burned, per token
  select t.contract_address, tk.symbol as token, tk.decimals,
         sum(case when t."from" = 0x0000000000000000000000000000000000000000 then  cast(t.value as double)
                  when t."to"   = 0x0000000000000000000000000000000000000000 then -cast(t.value as double)
                  else 0 end) / power(10, tk.decimals) as units
  from transfers t
  join tokens.erc20 tk on tk.blockchain = 'ethereum' and tk.contract_address = t.contract_address
  where t."from" = 0x0000000000000000000000000000000000000000
     or t."to"   = 0x0000000000000000000000000000000000000000
  group by 1, 2, 3
),
flows as (  -- + sent out of Ethereum, - came back
  select 'rUSD' as token, dstEid as eid,  cast(amountSentLD as double)     as raw from reservoir_protocol_ethereum.rusdoftadapter_evt_oftsent
  union all select 'rUSD',   srcEid, -cast(amountReceivedLD as double) from reservoir_protocol_ethereum.rusdoftadapter_evt_oftreceived
  union all select 'srUSD',  dstEid,  cast(amountSentLD as double)     from reservoir_protocol_ethereum.srusdoftadapter_evt_oftsent
  union all select 'srUSD',  srcEid, -cast(amountReceivedLD as double) from reservoir_protocol_ethereum.srusdoftadapter_evt_oftreceived
  union all select 'wsrUSD', dstEid,  cast(amountSentLD as double)     from reservoir_protocol_ethereum.wsrusdoftadapter_evt_oftsent
  union all select 'wsrUSD', srcEid, -cast(amountReceivedLD as double) from reservoir_protocol_ethereum.wsrusdoftadapter_evt_oftreceived
),
bridged as (
  select f.token, f.eid, sum(f.raw) / power(10, s.decimals) as units
  from flows f
  join supply s on s.token = f.token
  group by f.token, f.eid, s.decimals
),
bridged_total as (select token, sum(units) as units from bridged group by 1),
balances as (
  select token, eid, units from bridged
  union all
  select s.token, 30101, s.units - coalesce(b.units, 0)
  from supply s
  left join bridged_total b on b.token = s.token
),
px as (  -- last known price in rUSD
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
valued as (
  select coalesce(n.chain, 'eid ' || cast(b.eid as varchar)) as chain, b.token,
         b.units * coalesce(p.price, 1) as usd
  from balances b
  join supply s        on s.token = b.token
  left join px p       on p.contract_address = s.contract_address
  left join eid_names n on n.eid = b.eid
)
select chain,
       round(sum(case when token = 'rUSD'   then usd else 0 end), 2) as rUSD_usd,
       round(sum(case when token = 'srUSD'  then usd else 0 end), 2) as srUSD_usd,
       round(sum(case when token = 'wsrUSD' then usd else 0 end), 2) as wsrUSD_usd,
       round(sum(usd), 2) as total,
       round(100.0 * sum(usd) / sum(sum(usd)) over (), 2) as pct_of_total
from valued
group by 1
order by total desc
