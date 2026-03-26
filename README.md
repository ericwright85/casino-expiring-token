# Casino Expiring Promotional Credit Token

Custom ERC-20 promotional credit token for an EVM-compatible chain.

> Important: This token is **not** USDT, not a stablecoin, and does not represent an official dollar-backed instrument.

## Architecture

- **Framework**: Foundry-style project structure.
- **Core contract**: `PromoToken.sol`.
- **Base standards**:
  - OpenZeppelin ERC-20 as baseline fungible token interface.
  - OpenZeppelin AccessControl for admin/role permissions.
  - OpenZeppelin ERC20Pausable for emergency controls.
- **Extension model**: ERC-20 compatibility with explicit batch/expiry-aware enforcement in transfer logic.

## Contract roles

- `DEFAULT_ADMIN_ROLE`: role administration.
- `MINTER_ROLE`: can mint new batches.
- `PAUSER_ROLE`: can pause and unpause transfers.

## Storage model

### Batch registry
Each mint creates one immutable batch record:

- `batchId`
- `originalRecipient`
- `originalAmount`
- `mintedAt`
- `expiresAt`
- `exists`

Stored in `mapping(uint256 => BatchInfo)`.

### Wallet lot accounting
Balances are tracked in **lots** tied to originating batches:

- `lotId`
- `batchId`
- `amount` (remaining amount for that lot)
- `mintedAt`
- `expiresAt`

Stored via:
- `mapping(address => uint256[]) walletLotIds`
- `mapping(uint256 => WalletLot) walletLots`

A wallet head pointer (`walletHead`) enables skipping exhausted/expired prefix lots during FIFO spending scans.

## Expiry model

- Expiry is attached to the original batch and carried into recipient lots during transfers.
- A lot is **active** when `expiresAt > block.timestamp`.
- A lot is **expired** when `expiresAt <= block.timestamp`.
- Expired lots remain in storage for historical inspection and accounting queries.

## Transfer algorithm (FIFO oldest unexpired first)

For any non-mint/non-burn transfer:

1. Compute sender active balance from wallet lots.
2. Revert if requested amount exceeds active balance.
3. Walk sender lots from `walletHead` forward.
4. Skip empty or expired lots.
5. Consume amount from the oldest unexpired lot first.
6. Credit recipient with lots preserving `batchId`, `mintedAt`, and `expiresAt`.
7. Continue until full transfer amount is allocated.
8. Update ERC-20 balances through standard `_update` flow.

This ensures:
- no expired tokens can move,
- expiry metadata survives every transfer,
- deterministic FIFO behavior.

## Read APIs

- `activeBalanceOf(address)` — spendable/unexpired balance.
- `expiredBalanceOf(address)` — expired/non-spendable balance.
- `getWalletBatches(address)` — wallet lot view for audit/debug/UI.
- `getBatch(batchId)` — original batch metadata.

## Events

- `BatchMinted` for mint-level audit trail.
- `BatchTransferAllocation` for per-lot transfer attribution.
- `BatchLotDepleted` when a sender lot is fully consumed.

## ERC-20 compatibility notes

- Standard ERC-20 methods/events are retained (`transfer`, `transferFrom`, `approve`, `Transfer`, `Approval`).
- `balanceOf` remains nominal ERC-20 balance (can include expired amounts).
- Spendability is governed by `activeBalanceOf` and expiry checks inside transfer path.

Tradeoff: some integrators may assume `balanceOf` is fully spendable; this token intentionally separates nominal holdings from spendable promotional credit.

## Gas/scaling considerations

### Known costs
- Transfer cost grows with number of lots scanned/consumed.
- Wallets with many tiny lots can create higher transfer gas usage.

### Mitigations in current design
- head pointer avoids repeatedly scanning old depleted prefix lots.
- merge heuristic on append when consecutive lot metadata matches.
- deterministic in-contract enforcement (no off-chain dependency).

### Future optimization options (not yet implemented)
- stronger lot compaction strategies.
- per-expiry bucketization.
- capped per-transfer lot traversal with resumable mechanics.

## Test strategy

- Unit tests for mint, FIFO transfers, expiry lockout, allowance path, and pause behavior.
- Fuzz test for accounting relationship (`active <= nominal`).
- Invariant test for active-vs-nominal consistency.

## Deployment

Use **testnet only** script:

`script/DeployTestnet.s.sol`

Required env vars:
- `PROMO_TOKEN_ADMIN`
- `PROMO_TOKEN_NAME`
- `PROMO_TOKEN_SYMBOL`

## Open product questions

1. Should `balanceOf` include expired amounts (current design: yes)?
2. Should expired balances ever be admin-burnable/sweepable?
3. Are there strict max/min expiry windows for mints?
4. Should transfer trail preserve exact batch lineage forever, or allow aggressive merging for gas?
5. Is additional reporting metadata required by casino compliance workflows?

## Security and scope

- No upgradeability included by design (simpler trust and audit surface).
- No oracle logic or price-pegging behavior.
- No private key handling in this repository.
- Intended for testnet development and validation; no mainnet deployment script included.
