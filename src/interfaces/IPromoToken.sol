// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BatchTypes} from "../types/BatchTypes.sol";

interface IPromoToken {
    event BatchMinted(
        uint256 indexed batchId,
        address indexed recipient,
        uint256 amount,
        uint64 mintedAt,
        uint64 expiresAt
    );

    event BatchTransferAllocation(
        address indexed from,
        address indexed to,
        uint256 indexed batchId,
        uint256 amount,
        uint64 expiresAt,
        uint256 fromLotId,
        uint256 toLotId
    );

    event BatchLotDepleted(address indexed owner, uint256 indexed lotId, uint256 indexed batchId);

    function mintBatch(address recipient, uint256 amount, uint64 expiresAt) external returns (uint256 batchId);
    function activeBalanceOf(address account) external view returns (uint256);
    function expiredBalanceOf(address account) external view returns (uint256);
    function getWalletBatches(address account) external view returns (BatchTypes.WalletBatchView[] memory);
    function getBatch(uint256 batchId) external view returns (BatchTypes.BatchInfo memory);
}
