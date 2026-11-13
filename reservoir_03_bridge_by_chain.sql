-- RESERVOIR STEP 1c: where the bridged wsrUSD went (net per destination chain)
-- Check: sum(net_on_chain) must be close to the adapter balance (77.47M wsrUSD on Nov 13 2026)
-- Table names follow Dune's decoded naming for WsrusdOftAdapter; confirm in the schema explorer.
with sent as (
  select dstEid as eid, sum(cast(amountSentLD as double)) / 1e18 as sent_out,
         count(*) as sends, max(evt_block_time) as last_send
  from reservoir_protocol_ethereum.WsrusdOftAdapter_evt_OFTSent
  group by 1
),
back as (
  select srcEid as eid, sum(cast(amountReceivedLD as double)) / 1e18 as came_back,
         max(evt_block_time) as last_return
  from reservoir_protocol_ethereum.WsrusdOftAdapter_evt_OFTReceived
  group by 1
)
select coalesce(s.eid, b.eid) as layerzero_chain_id,
       coalesce(s.sent_out, 0) as sent_out,
       coalesce(b.came_back, 0) as came_back,
       coalesce(s.sent_out, 0) - coalesce(b.came_back, 0) as net_on_chain,
       s.sends, s.last_send, b.last_return
from sent s
full outer join back b on b.eid = s.eid
order by net_on_chain desc
