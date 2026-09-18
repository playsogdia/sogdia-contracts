# Delivery authorization

Both delivery entry points require a game-issued permit before moving payment or an NFT.
The game authenticates the browser session, derives the buyer from its linked wallet,
checks the target character belongs to that account, validates the native package, and
requires a fresh observer snapshot matching the configured deployment.

## Signed payload

EIP-712 domain: `name = SogdiaMallDelivery`, `version = 2`, the actual `chainId`,
and `verifyingContract = the delivery contract address`.

```text
DeliveryAuthorization(address buyer,uint256 item,uint256 amount,uint64 character,uint8 action,uint256 expectedTotal,bytes32 nonce,uint64 deadline)
```

Fields are signed in exactly that order. `action = 0` authorizes `buyAndDeliver` at the
specified `expectedTotal`; `action = 1` authorizes `deliverOwned` with `expectedTotal = 0`.
`buyer` must equal the transaction caller. `nonce` is a nonzero random 32-byte value;
`deadline` is a Unix timestamp. Signatures use a dedicated EOA key and canonical 65-byte
ECDSA encoding, not an owner key or a player's wallet signature.

The game issues a 120-second permit. The contract accepts an unexpired deadline no more
than 300 seconds ahead of the block timestamp. These are application authorization policy,
not native gameplay timing. Every successful permit is consumed once. Any reverted purchase
or redemption rolls back nonce consumption together with payment and NFT state.

```text
buyAndDeliver(item, amount, expectedTotal, character, nonce, deadline, signature)
deliverOwned(item, amount, character, nonce, deadline, signature)
```

The old unsigned function selectors are unavailable. The constructor now takes
`(marketplace, reviewedCatalogHash, productIds, authorizationSigner)`.
The signer must be nonzero and is immutable, like the market and catalog binding.

## Trust and migration

The signer certifies off-chain character ownership; the contract cannot independently
verify it. A compromised signer can issue false ownership attestations. It cannot change
the buyer field without invalidating the signature, spend a different caller's balance,
or withdraw locked NFTs. The game still checks wallet and character ownership when
materializing the finalized receipt. Character ownership must remain valid through
finality; this protocol does not add character transfers, deletion recovery or NFT unlocks.

This source change does not patch existing deployed contracts. Roll out a new bridge,
pin its runtime hash and signer in the collector/server configuration, install the separate
signing key, then switch clients together after testing. Existing finalized receipts must
remain available until all pending deliveries are reconciled; do not repoint or discard an
old checkpoint to force a migration. An old unsigned bridge remains callable on chain even
when the new client refuses to use it.

The contract tests cover signature field binding, replay, expiry, wrong signer, changed
chain/deployment, legacy calls, conservation and rollback. This is engineering validation,
not an independent security audit.
