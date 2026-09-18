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
Total receipt gas fees:0.00059168606614ETH. No token funds were transferred.

The marketplace is paused. Products/offers and collection metadata are not configured.
No reward period was opened. Game, collectors and frontend have not been switched to
these addresses. Mainnet prices must be reviewed before creating offers.

The delivery signer was generated separately from the owner and is retained in a
local secret file with0600 permissions. Install that key in the game runtime before
activating signed delivery. No private key is included in this evidence.

## Explorer verification

The official Blockscout API returned HTTP403 Cloudflare challenges for verification
and read requests. Source verification is therefore pending, not successful. Four
`*-standard-input.json` files and `constructor-args.json` are ready for submission.
Compiler0.8.30, optimizer200; Rewards uses Paris and the other contracts use Cancun.

## Scope

Owner authorized this mainnet deployment with the supplied mainnet signing key.
Existing testnet deployments and receipts were not modified. Completing the public
store requires catalogue pricing/publication, runtime configuration and acceptance.
