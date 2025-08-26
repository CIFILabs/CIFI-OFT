# CIFIOFT3 - Omnichain Fungible Token

[![Solidity](https://img.shields.io/badge/Solidity-^0.8.22-blue)](https://soliditylang.org/)
[![LayerZero](https://img.shields.io/badge/LayerZero-OFT-purple)](https://layerzero.network/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-Contracts-green)](https://openzeppelin.com/contracts/)

## Overview

CIFIOFT3 is an advanced Omnichain Fungible Token (OFT) implementation that enables seamless token transfers across multiple blockchains using LayerZero's messaging protocol. This contract extends the standard OFT functionality with enterprise-grade features including supply management, emergency controls, and comprehensive event logging.

## Features

### 🌐 Cross-Chain Capabilities
- **Omnichain transfers**: Send tokens seamlessly between any supported blockchain
- **Unified supply**: Maintains consistent total supply across all deployed chains
- **Chain-agnostic**: Deploy on Ethereum, BNB Chain, Avalanche, Polygon, Arbitrum, Optimism, and more

### 🔒 Security & Control
- **Emergency pause**: Instantly freeze all token operations in case of emergency
- **Access control**: Owner-only functions for critical operations
- **Custom error handling**: Gas-efficient error messages for failed transactions
- **Comprehensive events**: Full audit trail of all important actions

### 💰 Supply Management
- **Configurable max supply**: Set a hard cap or allow unlimited minting
- **Controlled minting**: Owner-exclusive minting with toggleable status
- **User burning**: Allow token holders to burn their tokens (toggleable)
- **Supply tracking**: Real-time visibility into mintable remaining supply

## Installation

### Prerequisites
- Node.js v16+ and npm/yarn
- Hardhat or Foundry development environment
- LayerZero endpoint addresses for target chains

### Dependencies

```bash
npm install @openzeppelin/contracts @layerzerolabs/oft-evm
```

Or with Foundry:

```bash
forge install OpenZeppelin/openzeppelin-contracts LayerZeroLabs/oft-evm
```

## Deployment

### Constructor Parameters

```solidity
constructor(
    string memory _name,        // Token name (e.g., "CIFI Token")
    string memory _symbol,      // Token symbol (e.g., "CIFI")
    address _lzEndpoint,        // LayerZero endpoint address for the chain
    address _delegate,          // Owner/admin address
    uint256 _maxSupply          // Maximum supply (use 0 for unlimited)
)
```

### Deployment Example (Hardhat)

```javascript
const { ethers } = require("hardhat");

async function main() {
    const CIFIOFT3 = await ethers.getContractFactory("CIFIOFT3");
    
    const token = await CIFIOFT3.deploy(
        "CIFI Token",                    // name
        "CIFI",                          // symbol
        "0x1a44076050125825900e736c501f859c50fe728c", // Ethereum mainnet endpoint
        "0xYourAdminAddress",            // delegate/owner
        ethers.parseEther("1000000000")  // 1 billion max supply
    );
    
    await token.waitForDeployment();
    console.log("CIFIOFT3 deployed to:", await token.getAddress());
}
```

### LayerZero Endpoint Addresses

| Network | Endpoint Address |
|---------|-----------------|
| Ethereum | `0x1a44076050125825900e736c501f859c50fe728c` |
| BNB Chain | `0x1a44076050125825900e736c501f859c50fe728c` |
| Avalanche | `0x1a44076050125825900e736c501f859c50fe728c` |
| Polygon | `0x1a44076050125825900e736c501f859c50fe728c` |
| Arbitrum | `0x1a44076050125825900e736c501f859c50fe728c` |
| Optimism | `0x1a44076050125825900e736c501f859c50fe728c` |
| Base | `0x1a44076050125825900e736c501f859c50fe728c` |

*Note: V2 endpoints have the same address across all chains*

## Usage

### Basic Token Operations

```javascript
// Transfer tokens (standard ERC20)
await token.transfer(recipientAddress, amount);

// Burn tokens (if burning is enabled)
await token.burn(amount);
```

### Cross-Chain Transfer

```javascript
// Prepare send parameters
const sendParam = {
    dstEid: 30101,                    // Destination endpoint ID (e.g., Arbitrum)
    to: ethers.zeroPadBytes(recipientAddress, 32),
    amountLD: ethers.parseEther("100"),
    minAmountLD: ethers.parseEther("100"),
    extraOptions: "0x",
    composeMsg: "0x",
    oftCmd: "0x"
};

// Quote the fee
const [nativeFee] = await token.quoteSend(sendParam, false);

// Send tokens cross-chain
await token.send(sendParam, { nativeFee }, senderAddress, {
    value: nativeFee
});
```

### Admin Functions

```javascript
// Mint new tokens (owner only)
await token.mint(recipientAddress, amount);

// Pause all operations
await token.pause();

// Resume operations
await token.unpause();

// Toggle minting capability
await token.setMintingEnabled(false);

// Toggle burning capability
await token.setBurningEnabled(true);
```

### View Functions

```javascript
// Check if minting is possible
const canMintAmount = await token.canMint(amount);

// Get remaining mintable supply
const mintable = await token.mintableSupply();

// Check current supply
const totalSupply = await token.totalSupply();

// Check max supply
const maxSupply = await token.maxSupply();
```

## Contract Architecture

### Inheritance Structure
```
OFT (LayerZero's Omnichain Fungible Token)
 ├── Ownable (OpenZeppelin)
 └── Pausable (OpenZeppelin)
      └── CIFIOFT3 (This Contract)
```

### Key Functions

| Function | Access | Description |
|----------|--------|-------------|
| `mint()` | Owner | Create new tokens up to max supply |
| `burn()` | Public | Destroy tokens from caller's balance |
| `pause()` | Owner | Freeze all token operations |
| `unpause()` | Owner | Resume token operations |
| `setMintingEnabled()` | Owner | Toggle minting capability |
| `setBurningEnabled()` | Owner | Toggle burning capability |
| `transfer()` | Public | Standard ERC20 transfer (pausable) |
| `transferFrom()` | Public | Standard ERC20 transferFrom (pausable) |

### Events

| Event | Description |
|-------|-------------|
| `EmergencyPause` | Emitted when contract is paused |
| `EmergencyUnpause` | Emitted when contract is unpaused |
| `TokensMinted` | Tracks new token creation |
| `TokensBurned` | Tracks token destruction |
| `MintingStatusChanged` | Minting enabled/disabled |
| `BurningStatusChanged` | Burning enabled/disabled |
| `CrossChainTransferSent` | Outgoing cross-chain transfer |
| `CrossChainTransferReceived` | Incoming cross-chain transfer |

## Security Considerations

### Audits
- [ ] Internal review completed
- [ ] External audit pending
- [ ] LayerZero OFT standard compliance verified

### Best Practices
1. **Multi-signature wallet**: Use a multi-sig for the owner/delegate address
2. **Gradual rollout**: Deploy to testnets first, then mainnets gradually
3. **Rate limiting**: Consider implementing rate limits for large transfers
4. **Monitor events**: Set up monitoring for all critical events
5. **Emergency plan**: Document pause procedures and recovery processes

### Known Limitations
- Owner has significant control (minting, pausing) - ensure proper key management
- Cross-chain transfers depend on LayerZero infrastructure availability
- Maximum supply cannot be changed after deployment

## Testing

Run the test suite:

```bash
# Hardhat
npx hardhat test

# Foundry
forge test
```

Example test coverage areas:
- ✅ Supply management (minting, burning, max supply enforcement)
- ✅ Pause functionality
- ✅ Access control
- ✅ Cross-chain transfer simulations
- ✅ Edge cases and error conditions

## Gas Optimization

The contract uses several gas optimization techniques:
- Custom errors instead of require strings
- Immutable variables for constants
- Efficient event emission
- Minimal storage operations

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is released under the UNLICENSED identifier. Please review the LICENSE file for details.

## Support

For questions and support:
- Open an issue in the GitHub repository
- Join our Discord community
- Read the [LayerZero documentation](https://docs.layerzero.network/)

## Disclaimer

This software is provided "as is", without warranty of any kind. Users should conduct their own security review before using in production.

---

**Built with ❤️ using LayerZero**
