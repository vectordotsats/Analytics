-- MIDNIGHT: who originated the loans (lenders + borrowers), both chains
-- Rule (verified on raw ETH Take logs, Nov 12 2026):
--   lender = buyer of units = maker if offerIsBuy else taker ; borrower = the other side
--   new loan only when totalUnitsDelta > 0 ; amount = buyerAssets (cash moved)
with takes as (
  select 'base' as chain, block_time, topic1 as market_id,
         bytearray_substring(topic2,13,20) as maker,
         bytearray_substring(topic3,13,20) as taker,
         bytearray_to_uint256(bytearray_substring(data, 2*32+1,32)) as offer_is_buy,
         bytearray_to_uint256(bytearray_substring(data, 7*32+1,32)) as buyer_assets,
         bytearray_to_int256 (bytearray_substring(data,12*32+1,32)) as units_delta
  from base.logs
  where contract_address = 0xadedd8ab6de832766fedf0fac4992e5c4d3ea18a
    and topic0 = 0xbd88656d0ee14d32d4f74f814f6ccb5c750a4c542d6fdf83ee00ddca4edebff0
  union all
  select 'ethereum', block_time, topic1,
         bytearray_substring(topic2,13,20), bytearray_substring(topic3,13,20),
         bytearray_to_uint256(bytearray_substring(data, 2*32+1,32)),
         bytearray_to_uint256(bytearray_substring(data, 7*32+1,32)),
         bytearray_to_int256 (bytearray_substring(data,12*32+1,32))
  from ethereum.logs
  where contract_address = 0x471686c42792F93528B000beF54bC10E3aa2045f
    and topic0 = 0xbd88656d0ee14d32d4f74f814f6ccb5c750a4c542d6fdf83ee00ddca4edebff0
),
mkt as (
  select 'base' as chain, id_ as market_id, from_hex(substr(json_extract_scalar(market,'$.loanToken'),3)) as loan
  from morpho_midnight_base.midnight_evt_marketcreated
  union all
  select 'ethereum', id_, from_hex(substr(json_extract_scalar(market,'$.loanToken'),3))
  from morpho_midnight_ethereum.midnight_evt_marketcreated
),
px as (
  select blockchain, contract_address, price,
         row_number() over (partition by blockchain, contract_address order by minute desc) rn
  from prices.usd
  where blockchain in ('base','ethereum') and minute > now() - interval '15' day
),
loans as (
  select t.chain, t.block_time,
         if(t.offer_is_buy = 1, t.maker, t.taker) as lender,
         if(t.offer_is_buy = 1, t.taker, t.maker) as borrower,
         t.buyer_assets / power(10, tk.decimals) * p.price as usd
  from takes t
  join mkt m          on m.chain = t.chain and m.market_id = t.market_id
  join tokens.erc20 tk on tk.blockchain = t.chain and tk.contract_address = m.loan
  join px p           on p.blockchain = t.chain and p.contract_address = m.loan and p.rn = 1  -- inner join drops junk tokens
  where t.units_delta > 0
    and t.block_time >= timestamp '{{start}}' and t.block_time < timestamp '{{end}}'   -- e.g. 2026-10-20 / 2026-11-06
)
select 'lender' as role, chain, lender as address, sum(usd) as usd, count(*) as fills from loans group by 1,2,3
union all
select 'borrower', chain, borrower, sum(usd), count(*) from loans group by 1,2,3
order by usd desc
