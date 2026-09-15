# Sogdia contracts

[![test](https://github.com/playsogdia/sogdia-contracts/actions/workflows/test.yml/badge.svg)](https://github.com/playsogdia/sogdia-contracts/actions/workflows/test.yml)

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
                        └── mintPurchase / escrow ──▶ SogdiaCosmetics (ERC-1155)
```

## Trust model

None of the contracts is upgradeable. Every owner is a single address set through two-step
ownership transfer; the planned production owner is a Safe multisig.

### What the owner can do

- **SogdiaCosmetics:** create a new product (id, supply cap, metadata URI), once per id; bind the
  marketplace, once; set the collection-level `contractURI`; set the ERC-2981 royalty receiver and
  rate for external marketplaces, up to 10% (`MAX_ROYALTY_BPS`).
- **SogdiaMarketplace:** create an offer for a product, then change its price and sale window;
  pause and unpause primary purchases, new listings and listing purchases.
- **SogdiaRewards:** open a reward period and finalize it with a Merkle root and the totals earned.

### What the owner cannot do

- Mint items outside a paid purchase, change a product's cap or metadata, or move or burn anyone's items.
- Replace the bound marketplace.
- Change the payment token, the reward pool address or the resale commission.
- Take tokens out of the marketplace or the reward pool: there is no withdrawal function. Payments go
  straight from the buyer to the pool and the seller.
- Take escrowed listings or stop sellers from cancelling them: `cancel` is never paused.
- Renounce ownership of the marketplace or the reward pool.
- Charge a buyer a price changed after the buyer's quote: purchases take an `expectedTotal` and revert
  on any difference.
- In the reward pool: change the period length, the per-period budget cap or the claim window;
  run two periods at once; replace a finalized root; redirect a claim to another address.

`SogdiaMallDelivery` has no owner at all. Its accepted product ids are fixed at deployment.

### What you still have to trust

- **Reward amounts.** The owner decides who earned what from game data and publishes the Merkle root.
  A proof shows that a claim is in the tree, not that the tree is complete or fair, so a dishonest
  owner could leave players out or pay its own addresses. The contract bounds the damage: one period
  at a time, a budget of at most `maxBudgetBps` of the uncommitted pool, and unclaimed rewards returning to the pool after `claimSeconds`.
- **In-game delivery.** `SogdiaMallDelivery` only records the request; the game server delivers the
  item. A redeemed item stays locked in the contract.
- **Royalties elsewhere.** Royalties from external marketplaces such as OpenSea go to the owner's
  royalty wallet [`0xA9080bF47e6Bf20aA263A00258601Dae33AD01E0`](https://robinhoodchain.blockscout.com/address/0xA9080bF47e6Bf20aA263A00258601Dae33AD01E0), not to a contract. Half of what accumulates is planned to be converted to SOG and
  deposited into the reward pool with `fund`, which emits a public `Funded` event; this is a manual
  commitment, not enforced on-chain. Whether an external marketplace pays ERC-2981 royalties at all is
  up to that marketplace.
- **The payment token.** Only plain ERC-20 tokens are supported. Balance checks reject fee-on-transfer
  and rebasing behaviour, but they are not a defence against a malicious token.

### Planned production parameters

| Parameter | Value |
|---|---|
| Reward period length (`periodSeconds`) | 7 days |
| Largest share of the uncommitted pool per period (`maxBudgetBps`) | 200 (2%) |
| Claim window (`claimSeconds`) | 90 days |
| Resale commission on SogdiaMarketplace (`feeBps`) | 250 (2.5%) |

These are constructor arguments and cannot be changed after deployment. The ERC-2981 royalty for external
marketplaces is planned at 500 (5%) and can be changed by the owner up to 10%.

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
