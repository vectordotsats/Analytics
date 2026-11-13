-- RESERVOIR TOTAL TVL (daily) - corrected
-- Fixes vs old version: price carried forward (no fallback to 1 on quiet days), every calendar day
-- present, no hardcoded addresses or decimals, wsrUSD price from any convertToAssets call.
-- Check: latest row ~ wsrUSD $93.9M, total $94.7M (holder snapshot, Nov 13 2026).
with transfers as (
  select contract_address, "from", "to", value, evt_block_time from reservoir_protocol_ethereum.stablecoin_evt_transfer
  union all
  select contract_address, "from", "to", value, evt_block_time from reservoir_protocol_ethereum.savingcoin_evt_transfer
  union all
  select contract_address, "from", "to", value, evt_block_time from reservoir_protocol_ethereum.savingcoinv2_evt_transfer
),
supply_daily as (  -- mints minus burns per day
  select t.contract_address, tk.symbol as token,
         cast(date_trunc('day', t.evt_block_time) as date) as day,
         sum(case when t."from" = 0x0000000000000000000000000000000000000000 then  cast(t.value as double)
                  when t."to"   = 0x0000000000000000000000000000000000000000 then -cast(t.value as double)
                  else 0 end) / power(10, tk.decimals) as net_mint
  from transfers t
  join tokens.erc20 tk on tk.blockchain = 'ethereum' and tk.contract_address = t.contract_address
  where t."from" = 0x0000000000000000000000000000000000000000
     or t."to"   = 0x0000000000000000000000000000000000000000
  group by 1, 2, 3, tk.decimals
),
days as (
  select t.day
  from (select min(day) as d0 from supply_daily) x
  cross join unnest(sequence(x.d0, current_date, interval '1' day)) as t(day)
),
tokens as (select distinct contract_address, token from supply_daily),
supply as (
  select d.day, k.contract_address, k.token,
         sum(coalesce(s.net_mint, 0)) over (partition by k.contract_address order by d.day) as supply
  from days d
  cross join tokens k
  left join supply_daily s on s.contract_address = k.contract_address and s.day = d.day
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
priced as (
  select s.day, s.token, s.supply,
         coalesce(last_value(p.price) ignore nulls over (
                    partition by s.contract_address order by s.day
                    rows between unbounded preceding and current row), 1) as price
  from supply s
  left join price_raw p on p.contract_address = s.contract_address and p.day = s.day
)
select day as date,
       round(sum(case when token = 'rUSD'   then supply * price else 0 end), 2) as rUSD,
       round(sum(case when token = 'srUSD'  then supply * price else 0 end), 2) as srUSD,
       round(sum(case when token = 'wsrUSD' then supply * price else 0 end), 2) as wsrUSD,
       round(sum(supply * price), 2) as total,
       round(max(case when token = 'srUSD'  then price end), 6) as srUSD_price,
       round(max(case when token = 'wsrUSD' then price end), 6) as wsrUSD_price
from priced
group by 1
order by 1 desc
