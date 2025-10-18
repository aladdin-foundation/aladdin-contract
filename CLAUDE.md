# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Aladdin Contract is an Ethereum-based Agent marketplace smart contract system that enables users to hire AI agents, manage USDT payment escrow, and handle employment relationships on-chain.

## Development Commands

### Compilation
```bash
npx hardhat compile
```

### Testing
```bash
# Run all tests (uses Hardhat)
npx hardhat test

# Clean and recompile if needed
npx hardhat clean && npx hardhat compile
```

### Deployment
```bash
# Deploy to Sepolia testnet
npx hardhat run scripts/deploy.js --network sepolia

# Verify contracts on Etherscan
npx hardhat verify --network sepolia <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
```

## Architecture

### Core Contracts

**AgentMarket.sol** - Main marketplace contract
- Manages Agent registration with skills and daily rates
- Handles Employment creation with multi-agent support (up to 20 agents)
- Implements USDT-based payment escrow
- Distributes payments proportionally based on agent rates and duration
- Charges 2% platform fee (200 basis points)
- Uses OpenZeppelin's SafeERC20, Ownable, and ReentrancyGuard

**AladdinToken.sol** - Test token for development
- ERC20 token used for testing (represents USDT in tests)
- Includes mint functionality for test setup

### Key Architecture Details

**Employment Payment Distribution:**
- When an employment completes, payment is distributed proportionally among agents
- Distribution formula: `agentShare = totalPayment * (agentRate * duration) / sumOfAllAgentRates`
- Platform fee is deducted first, then remaining amount is split among agents

**Struct Return Values:**
- The `employments` mapping returns 6 values (not 7) because Solidity's auto-generated getters skip dynamic arrays
- When destructuring `employments(id)`, omit the `agents` array field
- Correct destructuring: `(user, startTime, duration, payment, isActive, isCompleted)`

### Testing Framework

Tests are written in Solidity using Foundry's forge-std library:
- Located in `contracts/AgentMarket.t.sol`
- Uses Forge test conventions (`test_*` function names)
- Helper function `_registerAgent()` for test setup
- All test assertion messages with Chinese characters must use `unicode"..."` syntax

## Important Notes

**Solidity Version:** 0.8.20 with optimizer enabled (200 runs)

**Unicode Strings:** When writing assertion messages or strings with Chinese characters, always use the `unicode"..."` literal syntax, not regular `"..."` strings.

**Network Configuration:**
- Sepolia testnet USDT: `0x7169D38820dfd117C3FA1f22a697dBA58d90BA06`
- Requires environment variables: `SEPOLIA_RPC_URL`, `SEPOLIA_PRIVATE_KEY`, `ETHERSCAN_API_KEY`

**Security Features:**
- ReentrancyGuard on all state-changing functions
- Ownable access control
- SafeERC20 for token transfers
- Custom errors for gas optimization
