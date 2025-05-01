# Monadsweeper Smart Contract Project

This project implements a Minesweeper game as a smart contract on the EVM compatible like Monad blockchain. The project is built using Hardhat and includes tests, deployment scripts, and configuration for the Monad testnet.

## Project Structure

```
.env                  - Environment variables (e.g., private keys)
hardhat.config.ts     - Hardhat configuration file
contracts/            - Solidity smart contracts
  Monadsweeper.sol     - Monadsweeper game contract
test/                 - Test files for the contracts
  Monadsweeper.ts      - Tests for the Monadsweeper contract
ignition/modules/     - Deployment modules for Hardhat Ignition
  Monadsweeper.ts      - Deployment script for the Monadsweeper contract
```

## Prerequisites

- Node.js (v16 or higher)
- Hardhat
- Monad testnet account with a funded wallet

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/thenguyenltv/monadsweeper.git
   cd hardhat
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Configure the `.env` file with your private key:
   ```env
   PRIVATE_KEY="your-private-key"
   ```

## Usage

### Compile Contracts

To compile the smart contracts, run:
```bash
npx hardhat compile
```

### Run Tests

To run the tests for the `Monadsweeper` contracts:
```bash
npx hardhat test
```

### Deploy Contracts

To deploy the `Monadsweeper` contract using Hardhat Ignition:
```bash
npx hardhat ignition deploy ./ignition/modules/Monadsweeper.ts
```

### Veridy Contracts on Monad

```bash
npx hardhat verify <contract_address> --network monadTestnet
```

### Start a Local Node

To start a local Hardhat node:
```bash
npx hardhat node
```

### Interact with the Monadsweeper Contract

1. Start a new game:
   ```solidity
   startGame()
   ```

2. Dig a cell:
   ```solidity
   dig(x, y)
   ```

3. Check if you are a winner:
   ```solidity
   isWinner()
   ```

## Configuration

The project is configured to work with the Monad testnet. Update the `hardhat.config.ts` file to add or modify networks.

### Monad Testnet Configuration
```ts
monadTestnet: {
  url: "https://testnet-rpc.monad.xyz",
  accounts: [PRIVATE_KEY],
  chainId: 10143,
  allowUnlimitedContractSize: true,
}
```

## Monadsweeper Contract Details

The Monadsweeper contract implements a 9x9 board with 10 mines (size and mineCount can be higher in future update). Key features include:

- **Game Mechanics**: Mines are generated after the first move to ensure fairness.
- **Bit Manipulation**: Each cell's state is stored in a single `uint8` for gas efficiency.
- **Events**: Emits events for game start, cell reveal, win, and loss.

### Key Functions

- `startGame()`: Starts a new game.
- `dig(uint16 x, uint16 y)`: Reveals a cell.
- `isWinner()`: Checks if the player has won.
- `testGetMineCount(uint8 cell)`: Public wrapper for testing mine count extraction.

> **Future Feature**: `flag(uint16 x, uint16 y)`: Flags or unflags a cell as a potential mine.

## License

This project is licensed under the MIT License.