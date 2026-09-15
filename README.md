# Sogdia contracts

Smart contracts for [Sogdia](https://sogdia.gg), a browser MMORPG: the item store, the player
marketplace and the player reward pool. They are written for Robinhood Chain (testnet chain id
46630, mainnet 4663) and paid in the SOG token.

**Status:** not deployed to mainnet and not audited.

## Contracts

| Contract | Purpose |
|---|---|
| [`SogdiaCosmetics`](src/SogdiaCosmetics.sol) | ERC-1155 collection of game items. Each product has an immutable metadata URI and supply cap (0 = unlimited). Only the bound marketplace can mint. |
| [`SogdiaMarketplace`](src/SogdiaMarketplace.sol) | Primary store and escrow resale for the collection, paid in one ERC-20. Primary sales pay the full price to the reward pool; resales pay a commission (`feeBps`) to the pool and the rest to the seller. |
| [`SogdiaRewards`](src/SogdiaRewards.sol) | The reward pool. Funded in the same ERC-20, paid out to players in fixed-length periods through Merkle claims. |
| [`SogdiaMallDelivery`](src/SogdiaMallDelivery.sol) | One-way redemption: an item handed to this contract is locked for good and a `DeliveryQueued` event tells the game server what to deliver to which character. |

How the pieces connect:

```
buyer ── SOG ──▶ SogdiaMarketplace ── full price / commission ──▶ SogdiaRewards ── claims ──▶ players
                        │
                        └── mintPurchase / escrow ──▶ SogdiaCosmetics (ERC-1155, ERC-2981 royalty to the pool)
```

## Build and test

Requires [Foundry](https://getfoundry.sh) and Node.js.

```sh
npm ci
forge build
forge test
```

Compiler settings are pinned in [`foundry.toml`](foundry.toml): Solidity 0.8.30, optimizer 200 runs,
EVM target Cancun (the OpenZeppelin ERC-1155 implementation uses `MCOPY`), with `SogdiaRewards`
compiled for Paris. OpenZeppelin Contracts is pinned to 5.6.1 in `package-lock.json`.

## License

[MIT](LICENSE)
