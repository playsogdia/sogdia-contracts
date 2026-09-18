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

The marketplace is now open with 176 primary offers. The game, observers and both
public frontends use these mainnet addresses. Collection publication, product
registration and sale activation are recorded below. No reward period was opened.

The delivery signer was generated separately from the owner and is retained in a
local secret file with0600 permissions. The dedicated key is installed as a
read-only game Docker secret; live delivery signatures passed verification.
No private key is included in this evidence.

## Explorer verification

The official Blockscout API returned HTTP403 Cloudflare challenges for verification
and read requests. Automated source verification remains blocked; the owner-reported result is recorded
below. Four
`*-standard-input.json` files and `constructor-args.json` are ready for submission.
Compiler0.8.30, optimizer200; Rewards uses Paris and the other contracts use Cancun.

## Scope

Owner authorized this mainnet deployment with the supplied mainnet signing key.
Existing testnet deployments and receipts were not modified. Catalogue publication, runtime configuration and public sale activation are
recorded below.

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

This metadata operation registered the collection catalogue without minting NFTs.
OpenSea indexing was not independently verified. Hidden storefront products
retain their separate visibility policy.

## Primary sale activation

The owner selected a fixed **$0.001 per SOG** calculation basis on 2026-09-19.
This is not a live market quotation. At $0.10 per native Silk, the rule yields
100 SOG per Silk, including **24,000 SOG** for the custom hat.

All **176 visible products** have exact-price, untimed primary offers; existing
supply caps are unchanged. The **32 hidden catalogue products** have no offers.
The shared hidden list remains 59 package codes. `sales-plan.json` records inputs.

A full mainnet-fork simulation passed before broadcast (`sales-simulation.json`).
All 176 offer transactions and the unpause transaction succeeded on mainnet;
readback verified every price, offer window and hidden-product exclusion.
`sales-registration.json` contains the receipts. Receipt gas fees total
0.000854475815496 ETH. Unpause transaction:
`0xca473b88ca807e02aaad0dc25c6607c0268728c6103c4d4ac6773a4a0e2de816`.

Public API checks before and after opening are recorded in
`sales-api-before-open.json` and `sales-api-live.json`; both game and marketplace
origins match all 176 prices, 208 products, chain4663 and SOG.
`sales-browser-live.json` records representative production product prices and
the shared hidden list. No wallet purchase was submitted by these checks,
and OpenSea indexing was not independently verified.
