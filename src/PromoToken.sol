// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Gas-optimized promo token for very high mint volume with 30-day expiry.
/// @dev This version optimizes for scale by tracking wallet balances in expiry buckets,
///      not per-mint lots. Mint batch history is preserved, but wallet state only keeps
///      aggregated amounts per normalized expiry bucket.
contract PromoTokenScaled is ERC20Pausable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint64 public constant EXPIRY_DURATION = 30 days;
    uint64 public constant EXPIRY_GRANULARITY = 1 days;

    error InvalidRecipient();
    error AmountMustBeGreaterThanZero();
    error InvalidExpiry(uint64 provided, uint64 currentTime);
    error InsufficientActiveBalance(address account, uint256 requested, uint256 available);
    error AmountTooLarge();

    event BatchMinted(uint256 indexed batchId, address indexed recipient, uint256 amount, uint64 mintedAt, uint64 expiresAt);
    event BatchTransferAllocation(
        address indexed from,
        address indexed to,
        uint64 indexed expiresAt,
        uint256 amount,
        uint256 fromBucketIndex,
        uint256 toBucketIndex
    );
    event ExpiredTokensBurned(address indexed account, uint256 amount, uint256 bucketsProcessed, uint256 newHead);

    struct BatchInfo {
        uint256 batchId;
        address originalRecipient;
        uint256 originalAmount;
        uint64 mintedAt;
        uint64 expiresAt;
        bool exists;
    }

    /// @dev Packed into a single storage slot.
    struct WalletBucket {
        uint64 expiresAt;
        uint192 amount;
    }

    uint256 public nextBatchId = 1;

    mapping(uint256 => BatchInfo) private _batches;
    mapping(address => WalletBucket[]) private _walletBuckets;
    mapping(address => uint256) private _walletHead;

    constructor(address admin, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        if (admin == address(0)) revert InvalidRecipient();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function mintBatch(address recipient, uint256 amount) external onlyRole(MINTER_ROLE) returns (uint256 batchId) {
        uint64 nowTs = uint64(block.timestamp);
        uint64 expiresAt = _normalizeExpiry(nowTs + EXPIRY_DURATION);
        return _mintBatchWithExpiry(recipient, amount, expiresAt, nowTs);
    }

    function mintBatchWithExpiry(address recipient, uint256 amount, uint64 expiresAt)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 batchId)
    {
        uint64 nowTs = uint64(block.timestamp);
        if (expiresAt <= nowTs) revert InvalidExpiry(expiresAt, nowTs);
        return _mintBatchWithExpiry(recipient, amount, _normalizeExpiry(expiresAt), nowTs);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function walletHeadOf(address account) external view returns (uint256) {
        return _walletHead[account];
    }

    function walletBucketCount(address account) external view returns (uint256) {
        return _walletBuckets[account].length;
    }

    function activeBalanceOf(address account) public view returns (uint256 active) {
        WalletBucket[] storage buckets = _walletBuckets[account];
        uint64 nowTs = uint64(block.timestamp);
        uint256 i = _walletHead[account];

        while (i < buckets.length) {
            WalletBucket storage bucket = buckets[i];
            if (bucket.amount == 0 || bucket.expiresAt <= nowTs) {
                unchecked {
                    ++i;
                }
                continue;
            }
            active += uint256(bucket.amount);
            unchecked {
                ++i;
            }
        }
    }

    function expiredBalanceOf(address account) external view returns (uint256 expired) {
        WalletBucket[] storage buckets = _walletBuckets[account];
        uint64 nowTs = uint64(block.timestamp);
        uint256 i = _walletHead[account];

        while (i < buckets.length) {
            WalletBucket storage bucket = buckets[i];
            if (bucket.amount == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }
            if (bucket.expiresAt > nowTs) break;
            expired += uint256(bucket.amount);
            unchecked {
                ++i;
            }
        }
    }

    function burnExpired(address account, uint256 maxBuckets)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 burnedAmount, uint256 bucketsProcessed)
    {
        if (account == address(0)) revert InvalidRecipient();
        if (maxBuckets == 0) revert AmountMustBeGreaterThanZero();
        return _burnExpiredFromHead(account, maxBuckets);
    }

    function burnMyExpired(uint256 maxBuckets) external returns (uint256 burnedAmount, uint256 bucketsProcessed) {
        if (maxBuckets == 0) revert AmountMustBeGreaterThanZero();
        return _burnExpiredFromHead(msg.sender, maxBuckets);
    }

    function getWalletBuckets(address account) external view returns (WalletBucket[] memory buckets) {
        buckets = _walletBuckets[account];
    }

    function getWalletBucketsSlice(address account, uint256 start, uint256 count)
        external
        view
        returns (WalletBucket[] memory buckets)
    {
        WalletBucket[] storage src = _walletBuckets[account];
        uint256 len = src.length;
        if (start >= len) return new WalletBucket[](0);

        uint256 end = start + count;
        if (end > len) end = len;

        buckets = new WalletBucket[](end - start);
        for (uint256 i = start; i < end; ) {
            buckets[i - start] = src[i];
            unchecked {
                ++i;
            }
        }
    }

    function getBatch(uint256 batchId) external view returns (BatchInfo memory) {
        BatchInfo memory batch = _batches[batchId];
        require(batch.exists, "Batch does not exist");
        return batch;
    }

    function normalizeExpiry(uint64 timestamp) external pure returns (uint64) {
        return _normalizeExpiry(timestamp);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20Pausable) {
        // Fail fast on paused state before doing any bucket bookkeeping.
        _requireNotPaused();

        if (from != address(0) && to != address(0) && value != 0) {
            uint256 available = activeBalanceOf(from);
            if (available < value) {
                revert InsufficientActiveBalance(from, value, available);
            }
            _consumeBucketsAndCreditRecipient(from, to, value);
        }

        super._update(from, to, value);
    }

    function _mintBatchWithExpiry(address recipient, uint256 amount, uint64 expiresAt, uint64 nowTs)
        internal
        returns (uint256 batchId)
    {
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (amount > type(uint192).max) revert AmountTooLarge();
        if (expiresAt <= nowTs) revert InvalidExpiry(expiresAt, nowTs);

        batchId = nextBatchId++;
        _batches[batchId] = BatchInfo({
            batchId: batchId,
            originalRecipient: recipient,
            originalAmount: amount,
            mintedAt: nowTs,
            expiresAt: expiresAt,
            exists: true
        });

        _mint(recipient, amount);
        _creditBucket(recipient, expiresAt, uint192(amount));

        emit BatchMinted(batchId, recipient, amount, nowTs, expiresAt);
    }

    function _burnExpiredFromHead(address account, uint256 maxBuckets)
        internal
        returns (uint256 burnedAmount, uint256 bucketsProcessed)
    {
        WalletBucket[] storage buckets = _walletBuckets[account];
        uint256 i = _walletHead[account];
        uint64 nowTs = uint64(block.timestamp);

        while (i < buckets.length && bucketsProcessed < maxBuckets) {
            WalletBucket storage bucket = buckets[i];

            if (bucket.amount == 0) {
                unchecked {
                    ++i;
                    ++bucketsProcessed;
                }
                continue;
            }

            if (bucket.expiresAt > nowTs) break;

            burnedAmount += uint256(bucket.amount);
            bucket.amount = 0;

            unchecked {
                ++i;
                ++bucketsProcessed;
            }
        }

        _walletHead[account] = i;

        if (burnedAmount > 0) {
            _burn(account, burnedAmount);
            emit ExpiredTokensBurned(account, burnedAmount, bucketsProcessed, i);
        }
    }

    function _consumeBucketsAndCreditRecipient(address from, address to, uint256 amountToMove) internal {
        WalletBucket[] storage senderBuckets = _walletBuckets[from];
        uint64 nowTs = uint64(block.timestamp);
        uint256 i = _walletHead[from];
        uint256 remaining = amountToMove;

        while (remaining > 0 && i < senderBuckets.length) {
            WalletBucket storage senderBucket = senderBuckets[i];

            if (senderBucket.amount == 0) {
                unchecked {
                    ++i;
                }
                continue;
            }

            if (senderBucket.expiresAt <= nowTs) {
                unchecked {
                    ++i;
                }
                continue;
            }

            uint256 available = uint256(senderBucket.amount);
            uint256 chunk = available <= remaining ? available : remaining;
            senderBucket.amount = uint192(available - chunk);
            remaining -= chunk;

            uint256 receiverBucketIndex = _creditBucket(to, senderBucket.expiresAt, uint192(chunk));
            emit BatchTransferAllocation(from, to, senderBucket.expiresAt, chunk, i, receiverBucketIndex);

            if (senderBucket.amount == 0) {
                unchecked {
                    ++i;
                }
            }
        }

        assert(remaining == 0);
        _walletHead[from] = i;
    }

    function _creditBucket(address owner, uint64 expiresAt, uint192 amount) internal returns (uint256 bucketIndex) {
        WalletBucket[] storage buckets = _walletBuckets[owner];
        uint256 head = _walletHead[owner];
        uint256 len = buckets.length;

        // Fast path: append or merge at tail. This is the dominant case for fresh mints.
        if (len == 0) {
            buckets.push(WalletBucket({expiresAt: expiresAt, amount: amount}));
            return 0;
        }

        WalletBucket storage tail = buckets[len - 1];
        if (tail.amount != 0 && tail.expiresAt == expiresAt) {
            tail.amount += amount;
            return len - 1;
        }

        if (tail.expiresAt < expiresAt) {
            buckets.push(WalletBucket({expiresAt: expiresAt, amount: amount}));
            return len;
        }

        // Search only the active window. With daily buckets and 30-day expiry this remains small.
        uint256 insertPos = len;
        while (insertPos > head) {
            WalletBucket storage prev = buckets[insertPos - 1];
            if (prev.expiresAt <= expiresAt) break;
            unchecked {
                --insertPos;
            }
        }

        if (insertPos > head) {
            WalletBucket storage left = buckets[insertPos - 1];
            if (left.amount != 0 && left.expiresAt == expiresAt) {
                left.amount += amount;
                return insertPos - 1;
            }
        }

        if (insertPos < len) {
            WalletBucket storage right = buckets[insertPos];
            if (right.amount != 0 && right.expiresAt == expiresAt) {
                right.amount += amount;
                return insertPos;
            }
        }

        buckets.push();
        for (uint256 idx = buckets.length - 1; idx > insertPos; ) {
            buckets[idx] = buckets[idx - 1];
            unchecked {
                --idx;
            }
        }
        buckets[insertPos] = WalletBucket({expiresAt: expiresAt, amount: amount});
        bucketIndex = insertPos;
    }

    function _normalizeExpiry(uint64 timestamp) internal pure returns (uint64) {
        uint64 remainder = timestamp % EXPIRY_GRANULARITY;
        if (remainder == 0) return timestamp;
        return timestamp + (EXPIRY_GRANULARITY - remainder);
    }
}
