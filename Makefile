# Intent Matcher
.PHONY: help install build test test-verbose clean deploy deploy-local verify format lint gas

# Install dependencies
install:
	forge install

# Build contracts
build:
	forge build

# Run tests
test:
	forge test

# Run tests with verbose output
test-verbose:
	forge test -vvv

# Run tests with gas reporting
test-gas:
	forge test --gas-report

# Run specific test
test-match:
	forge test --match-test testSuccessfulMatch -vvv

# Clean build artifacts
clean:
	forge clean

# Deploy to local anvil (make sure anvil is running)
deploy-local:
	@echo "Deploying to local anvil..."
	forge script script/deploy/DeployStrideIntentMatcher.s.sol:DeployStrideIntentMatcher \
		--rpc-url http://localhost:8545 \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast

# Deploy to Sepolia testnet
deploy-sepolia:
	@echo "Deploying to Sepolia..."
	forge script script/deploy/DeployStrideIntentMatcher.s.sol:DeployStrideIntentMatcher \
		--rpc-url sepolia \
		--broadcast \
		--verify

# Format code
format:
	forge fmt

# Lint code
lint:
	forge fmt --check

# Generate gas snapshot
gas:
	forge snapshot

# Check contract sizes
sizes:
	forge build --sizes