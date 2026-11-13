-- RESERVOIR STAGE 5a: inside Monad - daily wsrUSD balance per holder bucket (chart: stacked area)
-- Params: days_back (number, e.g. 120).
-- Check (Nov 13 2026): two bands, ~37.43M wsrUSD ($41.5M, Curvance collateral token cwsrUSD) and
--   ~18.80M wsrUSD ($20.8M, curvance BorrowableCToken). Stack total ~ $62.3M = Monad row of the by-chain query.
with token as (  -- wsrUSD on Monad = the contract that emits the bridge events
  select distinct contract_address from reservoir_protocol_monad.wsrusdoft_evt_oftreceived
),
legs as (
  select t."to" as holder,  cast(t.value as double) as raw, t.evt_block_time
  from erc20_monad.evt_transfer t join token k on k.contract_address = t.contract_address
  union all
  select t."from",         -cast(t.value as double),        t.evt_block_time
  from erc20_monad.evt_transfer t join token k on k.contract_address = t.contract_address
),
names as (
  select address, max(namespace) as project, max(name) as contract_name
  from monad.contracts
  where address in (select distinct holder from legs)
  group by 1
),
receipt_tokens as (  -- a holder that is itself a token (e.g. Curvance's cwsrUSD)
  select contract_address as address, max(symbol) as symbol
  from tokens.erc20
  where blockchain = 'monad' and contract_address in (select distinct holder from legs)
  group by 1
),
is_contract as (
  select distinct address from monad.creation_traces
  where address in (select distinct holder from legs)
),
flows as (
  select cast(date_trunc('day', l.evt_block_time) as date) as day,
         case when n.project is not null then n.project || ': ' || n.contract_name
              when r.symbol is not null  then 'token: ' || r.symbol
              when ic.address is not null then 'unlabeled contract'
              else 'wallets' end as venue,
         sum(l.raw) / 1e18 as net_units
  from legs l
  left join names n          on n.address = l.holder
  left join receipt_tokens r on r.address = l.holder
  left join is_contract ic   on ic.address = l.holder
  where l.holder <> 0x0000000000000000000000000000000000000000   -- 0x0 = the bridge minting / burning
  group by 1, 2
),
days as (
  select t.day
  from (select min(day) as d0 from flows) x
  cross join unnest(sequence(x.d0, current_date, interval '1' day)) as t(day)
),
price_raw as (
  select call_block_date as day,
         max_by(cast(output_0 as double) / cast(shares as double), call_block_time) as price
  from reservoir_protocol_ethereum.savingcoinv2_call_converttoassets
  where call_success and shares > uint256 '0'
  group by 1
),
px as (
  select d.day,
         coalesce(last_value(r.price) ignore nulls over (
                    order by d.day rows between unbounded preceding and current row), 1) as price
  from days d
  left join price_raw r on r.day = d.day
),
running as (
  select d.day, v.venue,
         sum(coalesce(f.net_units, 0)) over (partition by v.venue order by d.day) as units
  from days d
  cross join (select distinct venue from flows) v
  left join flows f on f.day = d.day and f.venue = v.venue
)
select r.day, r.venue,
       round(r.units, 0) as wsrusd,
       round(r.units * p.price, 0) as balance_usd
from running r
join px p on p.day = r.day
where r.day >= current_date - interval '{{days_back}}' day
  and abs(r.units) > 1
order by r.day, r.venue
