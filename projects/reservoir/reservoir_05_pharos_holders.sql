-- RESERVOIR STEP 2b: who moved wsrUSD to a chain Dune does not index (default Pharos, eid 30407)
-- Ethereum side only: net sent per Ethereum wallet. Does NOT show which protocol holds it on that chain.
-- Parameter: chain_eid (number, default 30407). Check: sum(net) ~21.20M for Pharos (Nov 13 2026).
with sent as (
  select fromAddress as wallet,
         sum(cast(amountSentLD as double)) / 1e18 as sent_out,
         count(*) as sends, min(evt_block_time) as first_send, max(evt_block_time) as last_send
  from reservoir_protocol_ethereum.wsrusdoftadapter_evt_oftsent
  where dstEid = {{chain_eid}}
  group by 1
),
back as (
  select toAddress as wallet,
         sum(cast(amountReceivedLD as double)) / 1e18 as came_back,
         max(evt_block_time) as last_return
  from reservoir_protocol_ethereum.wsrusdoftadapter_evt_oftreceived
  where srcEid = {{chain_eid}}
  group by 1
),
names as (
  select address, max(namespace) as project, max(name) as contract_name
  from ethereum.contracts group by 1
)
select coalesce(s.wallet, b.wallet) as wallet,
       coalesce(s.sent_out, 0) as sent_out,
       coalesce(b.came_back, 0) as came_back,
       coalesce(s.sent_out, 0) - coalesce(b.came_back, 0) as net_on_chain,
       s.sends, s.first_send, s.last_send, b.last_return,
       n.project, n.contract_name
from sent s
full outer join back b on b.wallet = s.wallet
left join names n on n.address = coalesce(s.wallet, b.wallet)
order by net_on_chain desc
