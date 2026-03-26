// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IErrors {
    error AmountMustBeGreaterThanZero();
    error InvalidRecipient();
    error InvalidExpiry(uint64 expiresAt, uint64 currentTime);
    error BatchDoesNotExist(uint256 batchId);
    error InsufficientActiveBalance(address owner, uint256 requested, uint256 available);
}
