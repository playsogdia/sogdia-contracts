# Robinhood mainnet deployment — 2026-09-19

Source commit: `427e397`. Chain:4663. Payment token: `0x2513aa8c23426968402b57ab76ed61fc4aF9d8F6`.
Owner/deployer: `0x97906F9CF391a9506A141cF8C0c6AA7A4c965BE4`.

| Contract | Address |
|---|---|
| SogdiaRewards | `0x26C2E78D3b78A3207f940E6bf3E84026926cc87C` |
| SogdiaCosmetics | `0x9927d68d0EfaEA91011Aa321C799786d91Cc518D` |
| SogdiaMarketplace | `0x9883aA58e9fc669c0039bf7E54babe72fC0C62DF` |
| SogdiaMallDelivery | `0xe1457BfbB3B7c7d1B01c4c7D5529A7A095a04Ced` |

## Verified on chain

All seven transactions succeeded. Four deployed runtime hashes match the pre-broadcast
mainnet-fork simulation. Owners, token, collection/market/reserve bindings, commission,
royalty receiver/rate,97 accepted delivery IDs and the separate authorization signer
were read back and matched. See `broadcast.json` and `simulation.json`.

Parameters:604800-second periods,200bps maximum reward budget,7776000-second claims,
250bps resale fee and500bps external royalty to `0xA9080bF47e6Bf20aA263A00258601Dae33AD01E0`.
Deployment receipt gas fees:0.00059168606614ETH. Subsequent funding is recorded below.

The marketplace is paused. Offers are not configured. Collection publication and
product registration are recorded in the metadata evidence files.
No reward period was opened. Game, collectors and frontend have not been switched to
these addresses. Mainnet prices must be reviewed before creating offers.

The delivery signer was generated separately from the owner and is retained in a
local secret file with0600 permissions. Install that key in the game runtime before
activating signed delivery. No private key is included in this evidence.

## Explorer verification

The official Blockscout API returned HTTP403 Cloudflare challenges for verification
and read requests. Automated source verification remains blocked; the owner-reported result is recorded
below. Four
`*-standard-input.json` files and `constructor-args.json` are ready for submission.
Compiler0.8.30, optimizer200; Rewards uses Paris and the other contracts use Cancun.

## Scope

Owner authorized this mainnet deployment with the supplied mainnet signing key.
Existing testnet deployments and receipts were not modified. Completing the public
store requires catalogue pricing/publication, runtime configuration and acceptance.

## Initial reward-pool funding

The owner instructed depositing the complete SOG balance of the deployment wallet.
`fund()` deposited **104477611.940298507462686567 SOG** into SogdiaRewards.
Transaction: `0xfeb5d6bbcd72a1c581fbf1e99dabe6b823c9e8f997d1effb97761489679f5c2f`.

The receipt succeeded and its Funded event matched the sender and exact amount.
Readback confirmed the full pool balance,zero remaining sender SOG and zero remaining
allowance. See `funding.json`. Funding does not itself open a reward period or enable
player claims.

The owner reported successfully verifying SogdiaRewards through the Blockscout UI.
This report is distinct from our blocked automated verification requests; the other
three contracts are not recorded as verified.

## Collection metadata and product registration

The collection name is **Sogdia**, both on chain and in collection metadata.
`contractURI()` points to:
`https://assets.sogdia.gg/assets/v8/nft-20260919-mainnet/collection.json`.

All 208 product IDs were registered with their existing reviewed supply caps and
individual metadata URLs. The 209 published JSON files matched their local SHA-256
hashes, and all 210 referenced images responded successfully. Existing R2 artwork
was reused; testnet fixture wording was removed from the new metadata documents.

The operation passed a mainnet-fork simulation before broadcast. All 209 mainnet
transactions succeeded (one collection URI plus 208 products). Final on-chain
readback verified every product URI and cap, the collection name and contract URI,
zero minted items, and the marketplace's paused state. A transient RPC failure was
resumed from the saved transaction journal without duplicate registration.

Receipt gas fees: 0.002238413369914 ETH.
See `metadata-plan.json`, `metadata-publication.json`, `metadata-simulation.json`
and `metadata-registration.json` for inputs, publication checks and receipts.

This registers the collection catalogue; offers/prices and runtime activation are
still pending. No NFT was minted and OpenSea indexing was not independently
verified by this operation. Hidden storefront products retain their separate
visibility policy.
