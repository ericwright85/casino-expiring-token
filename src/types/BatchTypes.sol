// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library BatchTypes {
    struct BatchInfo {
        uint256 batchId;
        address originalRecipient;
        uint256 originalAmount;
        uint64 mintedAt;
        uint64 expiresAt;
        bool exists;
    }

    struct WalletBatchView {
        uint256 lotId;
        uint256 batchId;
        uint256 amount;
        uint64 mintedAt;
        uint64 expiresAt;
        bool expired;
    }
}
