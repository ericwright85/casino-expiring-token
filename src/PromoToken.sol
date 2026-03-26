// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Pausable} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IPromoToken} from "./interfaces/IPromoToken.sol";
import {IErrors} from "./interfaces/IErrors.sol";
import {BatchTypes} from "./types/BatchTypes.sol";

contract PromoToken is ERC20Pausable, AccessControl, IPromoToken, IErrors {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    struct WalletLot {
        uint256 lotId;
        uint256 batchId;
        uint256 amount;
        uint64 mintedAt;
        uint64 expiresAt;
    }

    uint256 public nextBatchId = 1;
    uint256 public nextLotId = 1;

    mapping(uint256 => BatchTypes.BatchInfo) private _batches;
    mapping(address => uint256[]) private _walletLotIds;
    mapping(uint256 => WalletLot) private _walletLots;
    mapping(address => uint256) private _walletHead;

    constructor(address admin, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        if (admin == address(0)) revert InvalidRecipient();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function mintBatch(address recipient, uint256 amount, uint64 expiresAt)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 batchId)
    {
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount == 0) revert AmountMustBeGreaterThanZero();

        uint64 nowTs = uint64(block.timestamp);
        if (expiresAt <= nowTs) revert InvalidExpiry(expiresAt, nowTs);

        batchId = nextBatchId++;
        _batches[batchId] = BatchTypes.BatchInfo({
            batchId: batchId,
            originalRecipient: recipient,
            originalAmount: amount,
            mintedAt: nowTs,
            expiresAt: expiresAt,
            exists: true
        });

        _mint(recipient, amount);
        _insertLotSorted(recipient, batchId, amount, nowTs, expiresAt);

        emit BatchMinted(batchId, recipient, amount, nowTs, expiresAt);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function activeBalanceOf(address account) public view returns (uint256 active) {
        uint256[] storage lotIds = _walletLotIds[account];
        uint64 nowTs = uint64(block.timestamp);

        for (uint256 i = 0; i < lotIds.length; ++i) {
            WalletLot storage lot = _walletLots[lotIds[i]];
            if (lot.amount == 0 || lot.expiresAt <= nowTs) continue;
            active += lot.amount;
        }
    }

    function expiredBalanceOf(address account) external view returns (uint256 expired) {
        uint256[] storage lotIds = _walletLotIds[account];
        uint64 nowTs = uint64(block.timestamp);

        for (uint256 i = 0; i < lotIds.length; ++i) {
            WalletLot storage lot = _walletLots[lotIds[i]];
            if (lot.amount == 0 || lot.expiresAt > nowTs) continue;
            expired += lot.amount;
        }
    }

    function getWalletBatches(address account) external view returns (BatchTypes.WalletBatchView[] memory views_) {
        uint256[] storage lotIds = _walletLotIds[account];
        views_ = new BatchTypes.WalletBatchView[](lotIds.length);
        uint64 nowTs = uint64(block.timestamp);

        for (uint256 i = 0; i < lotIds.length; ++i) {
            WalletLot storage lot = _walletLots[lotIds[i]];
            views_[i] = BatchTypes.WalletBatchView({
                lotId: lot.lotId,
                batchId: lot.batchId,
                amount: lot.amount,
                mintedAt: lot.mintedAt,
                expiresAt: lot.expiresAt,
                expired: lot.expiresAt <= nowTs
            });
        }
    }

    function getBatch(uint256 batchId) external view returns (BatchTypes.BatchInfo memory) {
        BatchTypes.BatchInfo memory batch = _batches[batchId];
        if (!batch.exists) revert BatchDoesNotExist(batchId);
        return batch;
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        if (from != address(0) && to != address(0)) {
            if (value == 0) {
                super._update(from, to, value);
                return;
            }

            uint256 available = activeBalanceOf(from);
            if (available < value) {
                revert InsufficientActiveBalance(from, value, available);
            }

            _consumeLotsAndCreditRecipient(from, to, value);
        }

        super._update(from, to, value);
    }

    function _consumeLotsAndCreditRecipient(address from, address to, uint256 amountToMove) internal {
        uint256[] storage senderLotIds = _walletLotIds[from];
        uint64 nowTs = uint64(block.timestamp);

        uint256 i = _walletHead[from];
        uint256 remaining = amountToMove;

        while (remaining > 0 && i < senderLotIds.length) {
            WalletLot storage senderLot = _walletLots[senderLotIds[i]];

            if (senderLot.amount == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            if (senderLot.expiresAt <= nowTs) {
                unchecked {
                    ++i;
                }
                continue;
            }

            uint256 chunk = senderLot.amount <= remaining ? senderLot.amount : remaining;
            senderLot.amount -= chunk;
            remaining -= chunk;

            uint256 receiverLotId = _insertLotSorted(to, senderLot.batchId, chunk, senderLot.mintedAt, senderLot.expiresAt);

            emit BatchTransferAllocation(from, to, senderLot.batchId, chunk, senderLot.expiresAt, senderLot.lotId, receiverLotId);

            if (senderLot.amount == 0) {
                emit BatchLotDepleted(from, senderLot.lotId, senderLot.batchId);
                unchecked {
                    ++i;
                }
            }
        }

        _walletHead[from] = i;
    }

    function _insertLotSorted(address owner, uint256 batchId, uint256 amount, uint64 mintedAt, uint64 expiresAt)
        internal
        returns (uint256 lotId)
    {
        uint256[] storage lotIds = _walletLotIds[owner];

        if (lotIds.length > 0) {
            uint256 lastLotId = lotIds[lotIds.length - 1];
            WalletLot storage lastLot = _walletLots[lastLotId];
            if (
                lastLot.batchId == batchId && lastLot.expiresAt == expiresAt && lastLot.mintedAt == mintedAt && lastLot.amount > 0
            ) {
                lastLot.amount += amount;
                return lastLot.lotId;
            }
        }

        lotId = nextLotId++;
        _walletLots[lotId] = WalletLot({
            lotId: lotId,
            batchId: batchId,
            amount: amount,
            mintedAt: mintedAt,
            expiresAt: expiresAt
        });

        uint256 insertPos = lotIds.length;
        while (insertPos > _walletHead[owner]) {
            uint256 prevLotId = lotIds[insertPos - 1];
            WalletLot storage prevLot = _walletLots[prevLotId];
            if (prevLot.expiresAt <= expiresAt) break;
            insertPos--;
        }

        lotIds.push(lotId);
        uint256 len = lotIds.length;
        for (uint256 idx = len - 1; idx > insertPos; --idx) {
            lotIds[idx] = lotIds[idx - 1];
        }
        lotIds[insertPos] = lotId;
    }
}
