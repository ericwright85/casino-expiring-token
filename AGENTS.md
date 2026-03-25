# AGENTS.md

## Project
This repository contains a Solidity smart contract project for a custom ERC-20 promotional token for a casino client.

## Non-negotiable rules
- This token is NOT USDT.
- Do not describe it as USDT, stablecoin, tether, or official dollar-backed token.
- It is a custom ERC-20 promotional credit token on an EVM-compatible chain.
- Each mint creates a distinct batch with its own expiry timestamp.
- Expiry must be preserved across transfers.
- Expired tokens must be non-transferable and non-spendable.
- Only unexpired balances count as active balances.
- Prefer correctness, testability, and auditability over cleverness.
- Do not deploy to mainnet.
- Do not handle private keys, wallet secrets, or real funds.
- Use current stable Solidity and OpenZeppelin.
- Include comprehensive tests for expiry and transfer edge cases.
- Document all tradeoffs and unresolved product questions.

## Preferred architecture
- Use Foundry unless there is a strong reason to use Hardhat instead.
- Use OpenZeppelin for ERC-20, access control, and pause support.
- Favor deterministic behavior.
- Default transfer spending rule: FIFO from oldest unexpired batches first.

## Required deliverables
- Production-structured Solidity project
- Main token contract
- Test suite
- Testnet deployment script only
- README with architecture, storage model, transfer algorithm, expiry model, gas/scaling concerns, and open client questions

## Required process
- Plan first before coding.
- After planning, implement contract(s).
- Then write tests.
- Then perform a self-review focused on correctness, ERC-20 compatibility, edge cases, and gas/scaling tradeoffs.