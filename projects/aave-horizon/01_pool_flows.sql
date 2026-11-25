-- AAVE HORIZON: every supply and withdraw, all 13 reserves, from the Pool's own events.
-- Pool: 0xAe05Cd22df81871bc7cC2a04BeCfb516bFe332C8  (one contract -> cheap)
-- BEFORE RUNNING: replace the two topic0 hashes below. Get them from Etherscan:
--   Pool address -> Events tab -> find a Supply and a Withdraw row -> copy each topic0.
-- Event shapes (Aave V3):
--   Supply  (reserve indexed, user, onBehalfOf indexed, amount, referralCode indexed)
--           -> topic1 reserve, topic2 onBehalfOf, data word0 user, data word1 amount
--   Withdraw(reserve indexed, user indexed, to indexed, amount)
--           -> topic1 reserve, topic2 user, topic3 to, data word0 amount
with reserves as (
  select contract_address, symbol, decimals
  from tokens.erc20
  where blockchain = 'ethereum'
    and contract_address in (
      0x43415eb6ff9db7e26a15b704e7a3edce97d31c4e,  -- USTB
      0x14d60e7fdc0d71d8611742720e4c50e7a974020c,  -- USCC
      0x2255718832bc9fd3be1caf75084f4803da14ff01,  -- VBILL
      0x8292bb45bf1ee4d140127049757c2e0ff06317ed,  -- RLUSD
      0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48,  -- USDC
      0x40d16fc0246ad3160ccc09b8d0d3a2cd28ae6c2f,  -- GHO
      0x7433806912eae67919e66aea853d46fa0aef98a8,  -- mGLOBAL
      0x136471a34f6ef19fe571effc1ca711fdb8e49f2b,  -- USYC
      0x5a0f93d040de44e78f251b03c43be9cf317dcf64,  -- JAAA
      0x015c477a4e2881c4b3bb8999f59ee4a04e812344,  -- HINC
      0x4e72025984424e52838cf8953e2863eff036b67a,  -- mWIN
      0x8c213ee79581ff4984583c6a801e5263418c4b86,  -- JTRSY
      0x17418038ecf73ba4026c4f428547bf099706f27b   -- ACRED
    )
),
raw as (
  select l.block_time, l.tx_hash, l.topic0,
         bytearray_substring(l.topic1, 13, 20) as reserve,
         bytearray_substring(l.topic2, 13, 20) as actor,
         l.data
  from ethereum.logs l
  where l.contract_address = 0xAe05Cd22df81871bc7cC2a04BeCfb516bFe332C8
    and l.topic0 in (
      0xSUPPLY_TOPIC0_HERE,
      0xWITHDRAW_TOPIC0_HERE
    )
    and l.block_time >= date '{{start}}'
),
moves as (
  select r.block_time, r.tx_hash, r.actor, k.symbol,
         case when r.topic0 = 0xSUPPLY_TOPIC0_HERE then 'SUPPLY' else 'WITHDRAW' end as action,
         (case when r.topic0 = 0xSUPPLY_TOPIC0_HERE
               then bytearray_to_uint256(bytearray_substring(r.data, 33, 32))   -- word 1
               else bytearray_to_uint256(bytearray_substring(r.data,  1, 32))   -- word 0
          end) / power(10, k.decimals) as amount
  from raw r
  join reserves k on k.contract_address = r.reserve
)
select cast(date_trunc('day', block_time) as date) as day,
       symbol,
       round(sum(case when action = 'SUPPLY'   then amount else 0 end), 2) as supplied,
       round(sum(case when action = 'WITHDRAW' then amount else 0 end), 2) as withdrawn,
       round(sum(case when action = 'SUPPLY'   then amount else -amount end), 2) as net_tokens,
       count(distinct actor) as actors
from moves
group by 1, 2
having sum(case when action = 'SUPPLY' then amount else amount end) > 0
order by day desc, abs(sum(case when action = 'SUPPLY' then amount else -amount end)) desc
