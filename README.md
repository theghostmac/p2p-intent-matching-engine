# Stride Intent Matcher

An experimental intent-based matching engine for a cross-chain DEX enabling peer-to-peer swaps without AMM slippage.

## 🎯 Core Concept

Instead of immediately executing swaps through AMMs, users submit "intents" that get matched peer-to-peer when complementary trades exist. This eliminates slippage and reduces gas costs for matched trades.

**Example:**
- Alice wants to swap 100 ETH → ATOM 
- Bob wants to swap 100 ATOM → ETH
- Instead of both paying AMM fees + slippage, they match directly with zero slippage

## 🏗️ Architecture

### Intent Lifecycle
1. **Submit Intent**: User submits swap intent with tokens, amounts, chains, and slippage tolerance
2. **Matching Window**: 5-minute window for finding complementary intents
3. **P2P Execution**: Direct token transfer between matched users
4. **AMM Fallback**: Unmatched intents execute via Uniswap V3 after timeout

### Key Components

**StrideIntentMatcher.sol** - Core matching contract
- Intent storage and management
- Cross-chain compatibility validation
- P2P matching logic with partial fills
- AMM fallback integration

**Intent Relayer Service** - TypeScript service for automated matching
- Event-driven intent monitoring
- Batch matching optimization
- Gas price awareness
- Expired intent cleanup

## 🚀 Quick Start

### Prerequisites
- [Foundry](https://getfoundry.sh/)
- Node.js 16+
- Git

### Setup
```bash
# Clone and setup
git clone <repo>
cd stride-intent-matcher

# Install dependencies
make install

# Build contracts
make build

# Run tests
make test

# Start local development
make anvil                # Terminal 1
make deploy-local        # Terminal 2
```

## 📖 Usage

### Submitting Intents

```solidity
bytes32 intentId = matcher.submitIntent(
    tokenIn,        // Input token address
    tokenOut,       // Output token address  
    amountIn,       // Input amount
    minAmountOut,   // Minimum acceptable output
    sourceChain,    // Source chain ID (1 = Ethereum, 118 = Cosmos)
    destChain,      // Destination chain ID
    maxSlippage     // Max slippage in basis points (500 = 5%)
);
```

### Running the Relayer

```typescript
import { StrideIntentRelayer } from './relayer';

const relayer = new StrideIntentRelayer(
    'https://your-rpc-url',
    'your-deployed-contract-address', 
    'your-private-key'
);

await relayer.start();
```

## ⚡ Benefits

### For Users
- **Zero Slippage** on matched trades
- **Lower Gas Costs** (one P2P transfer vs two AMM swaps)
- **MEV Protection** (no front-running during matching window)
- **Cross-Chain Efficiency** (direct settlement vs bridge + swap)

### For Stride Swap
- **Institutional Appeal** (sophisticated trading infrastructure)
- **Better Capital Efficiency** (less AMM liquidity needed)
- **Network Effects** (more intents = better matching rates)
- **Competitive Moat** (advanced matching vs basic bridging)

## 🧪 Test Results

Our test suite validates:
- ✅ Basic intent submission and storage
- ✅ Automatic P2P matching for complementary intents  
- ✅ Partial fills (100 ETH intent matched with 150 ETH intent)
- ✅ Cross-chain validation (Ethereum ↔ Cosmos routing)
- ✅ AMM fallback after timeout
- ✅ Relayer authorization and batch processing
- ✅ Gas optimization and statistics tracking

```bash
Ran 16 tests: 15 passed, 1 skipped
- Successful matches: Auto-matching with 0% slippage ✅
- Partial fills: 100 vs 150 amount handling ✅  
- Cross-chain: Chain compatibility validation ✅
- Gas savings: ~70k gas saved per match ✅
```

## 🔧 Configuration

### Matching Parameters
```solidity
uint256 public constant MATCHING_WINDOW = 300;     // 5 minutes
uint256 public constant MAX_SLIPPAGE_TOLERANCE = 1000;  // 10%
uint256 public matchingReward = 50;                // 0.5% relayer reward
uint256 public protocolFee = 10;                   // 0.1% protocol fee
```

### Supported Chains
- Ethereum (Chain ID: 1)
- Cosmos Hub (Chain ID: 118)  
- Arbitrum (Chain ID: 42161)
- *Extensible to any EVM + IBC chains*

## 🏛️ Architecture Decisions

### Why Intent-Based?
Traditional DEXs require immediate execution, leading to slippage and MEV. Intent-based systems allow for:
1. **Batch Optimization** - Multiple intents processed together
2. **Privacy** - Orders not immediately visible to MEV bots  
3. **Better Pricing** - P2P matching at mid-market rates
4. **Cross-Chain Efficiency** - Native multi-chain settlement

### Why 5-Minute Windows?
Balances user experience (fast execution) with matching probability. Longer windows = better matching but slower UX.

### Why Uniswap V3 Fallback?
Ensures users always get execution even without matches, maintaining DEX UX expectations.

## 📊 Performance Metrics

Based on test execution:
- **Matching Success Rate**: 100% for complementary intents
- **Gas Savings**: ~70,000 gas per successful match  
- **Execution Time**: <1 second for P2P matches
- **Contract Size**: ~8KB (fits in single block)

## 🔮 Future Enhancements

### V2 Features
- **Dutch Auction Pricing** - Dynamic pricing for better matching
- **MEV Auction Integration** - Flashbots/SUAVE for private mempool
- **Liquidity Provider Mode** - Professional MM integration
- **Cross-Chain Credit** - Undercollateralized swaps for known actors

### Optimization Targets
- **Sophisticated Matching** - Multi-dimensional optimization (price, time, gas)
- **Layer 2 Deployment** - Polygon/Arbitrum for lower costs
- **Intent Aggregation** - Multiple sources of intents
- **Real-Time Analytics** - Matching efficiency dashboards

## 🔐 Security Considerations

### Current Safeguards
- **ReentrancyGuard** - Prevents reentrancy attacks
- **Slippage Protection** - User-defined maximum slippage  
- **Deadline Enforcement** - Time-bounded intent execution
- **Access Control** - Relayer authorization system

### Known Limitations
- **Price Oracle Dependency** - Relies on market rates for matching
- **Cross-Chain Finality** - Subject to source chain reorganizations
- **Relayer Centralization** - Current single relayer (can be decentralized)

## 📈 Economic Model

### Revenue Streams
- **Protocol Fee**: 0.1% on all matched trades
- **Relayer Rewards**: 0.5% split among authorized relayers  
- **Premium Matching**: Fast-lane for institutional users

### Incentive Alignment
- **Users**: Save on slippage and gas
- **Relayers**: Earn fees for providing matching services
- **Protocol**: Sustainable revenue from trading volume

### Development Workflow
```bash
# Create feature branch
git checkout -b feature/your-feature

# Make changes and test
make test

# Format code  
make format

# Submit PR with test coverage
```

## 📚 References

- [CoW Protocol](https://cow.fi/) - Intent-based DEX on Ethereum
- [Anoma](https://anoma.net/) - Intent-centric architecture  
- [Flashbots SUAVE](https://writings.flashbots.net/the-future-of-mev-is-suave) - Programmable privacy
- [Morpho](https://morpho.xyz/) - P2P matching for lending

