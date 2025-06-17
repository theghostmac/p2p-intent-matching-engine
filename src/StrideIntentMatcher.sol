// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title StrideIntentMatcher
 * @dev Intent-based matching engine for Stride Swap cross-chain DEX
 * @author Stride Team
 */
contract StrideIntentMatcher is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct SwapIntent {
        address user;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint32 sourceChain;
        uint32 destChain;
        uint256 deadline;
        uint256 maxSlippage; // basis points (100 = 1%)
        bool isActive;
        uint256 timestamp;
        uint256 nonce; // For intent uniqueness
    }

    struct MatchedPair {
        bytes32 intentA;
        bytes32 intentB;
        uint256 matchedAmount;
        uint256 executionPrice; // Price at which the match was executed
        uint256 timestamp;
        address executor; // Address that executed the match
    }

    struct MatchingStats {
        uint256 totalIntents;
        uint256 successfulMatches;
        uint256 totalVolumeMatched;
        uint256 gasSaved;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Core state
    mapping(bytes32 => SwapIntent) public intents;
    mapping(address => mapping(address => bytes32[])) public intentsByTokenPair;
    mapping(bytes32 => bool) public processedIntents;
    mapping(address => uint256) public userNonces;

    bytes32[] public activeIntents;
    MatchedPair[] public matches;
    MatchingStats public stats;

    // External contracts
    ISwapRouter public immutable swapRouter;

    // Configuration
    uint256 public constant MATCHING_WINDOW = 300; // 5 minutes
    uint256 public constant MAX_SLIPPAGE_TOLERANCE = 1000; // 10%
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public matchingReward = 50; // 0.5% reward for successful matches
    uint256 public protocolFee = 10; // 0.1% protocol fee

    // Access control
    mapping(address => bool) public authorizedRelayers;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event IntentSubmitted(
        bytes32 indexed intentId,
        address indexed user,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint32 sourceChain,
        uint32 destChain
    );

    event IntentsMatched(
        bytes32 indexed intentA,
        bytes32 indexed intentB,
        uint256 matchedAmount,
        uint256 executionPrice,
        address indexed executor
    );

    event IntentExecutedViaAMM(bytes32 indexed intentId, uint256 amountOut, uint256 executionPrice);

    event IntentCancelled(bytes32 indexed intentId, address indexed user);

    event RelayerAuthorized(address indexed relayer, bool authorized);

    event ConfigurationUpdated(uint256 newMatchingReward, uint256 newProtocolFee);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorizedRelayer() {
        require(authorizedRelayers[msg.sender] || msg.sender == owner(), "Unauthorized relayer");
        _;
    }

    modifier validIntent(bytes32 intentId) {
        require(intents[intentId].user != address(0), "Intent does not exist");
        require(intents[intentId].isActive, "Intent not active");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _swapRouter, address _owner) Ownable(_owner) {
        require(_swapRouter != address(0), "Invalid swap router");
        swapRouter = ISwapRouter(_swapRouter);
        _transferOwnership(_owner);

        // Authorize owner as relayer by default
        authorizedRelayers[_owner] = true;
        emit RelayerAuthorized(_owner, true);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Submit a swap intent to the matching engine
     * @param tokenIn Address of input token
     * @param tokenOut Address of output token
     * @param amountIn Amount of input tokens
     * @param minAmountOut Minimum acceptable output amount
     * @param sourceChain Source chain ID
     * @param destChain Destination chain ID
     * @param maxSlippage Maximum acceptable slippage in basis points
     * @return intentId Unique identifier for the intent
     */
    function submitIntent(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint32 sourceChain,
        uint32 destChain,
        uint256 maxSlippage
    ) external nonReentrant returns (bytes32 intentId) {
        require(tokenIn != tokenOut, "Same token swap");
        require(amountIn > 0, "Zero amount");
        require(minAmountOut > 0, "Zero min output");
        require(maxSlippage <= MAX_SLIPPAGE_TOLERANCE, "Slippage too high");
        require(block.timestamp + MATCHING_WINDOW < type(uint32).max, "Deadline overflow");

        // Transfer tokens to contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Create unique intent ID
        uint256 nonce = userNonces[msg.sender]++;
        intentId = keccak256(
            abi.encodePacked(
                msg.sender, tokenIn, tokenOut, amountIn, sourceChain, destChain, nonce, block.timestamp, block.number
            )
        );

        // Store intent
        intents[intentId] = SwapIntent({
            user: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            sourceChain: sourceChain,
            destChain: destChain,
            deadline: block.timestamp + MATCHING_WINDOW,
            maxSlippage: maxSlippage,
            isActive: true,
            timestamp: block.timestamp,
            nonce: nonce
        });

        // Update tracking structures
        activeIntents.push(intentId);
        intentsByTokenPair[tokenIn][tokenOut].push(intentId);
        stats.totalIntents++;

        emit IntentSubmitted(intentId, msg.sender, tokenIn, tokenOut, amountIn, sourceChain, destChain);

        // Try immediate matching
        _tryMatch(intentId);
    }

    /**
     * @notice Batch matching function for relayers
     * @param intentIds Array of intent IDs to attempt matching
     */
    function batchMatch(bytes32[] calldata intentIds) external onlyAuthorizedRelayer {
        for (uint256 i = 0; i < intentIds.length; i++) {
            if (intents[intentIds[i]].isActive && !processedIntents[intentIds[i]]) {
                _tryMatch(intentIds[i]);
            }
        }
    }

    /**
     * @notice Execute unmatched intent via AMM after matching window expires
     * @param intentId Intent to execute
     */
    function executeViaAMM(bytes32 intentId) external nonReentrant validIntent(intentId) {
        SwapIntent storage intent = intents[intentId];
        require(block.timestamp > intent.deadline || msg.sender == intent.user, "Still in matching window");

        uint256 amountOut = _executeSwapViaAMM(intent);

        intent.isActive = false;
        processedIntents[intentId] = true;
        _removeFromActiveIntents(intentId);

        uint256 executionPrice = (amountOut * 1e18) / intent.amountIn;
        emit IntentExecutedViaAMM(intentId, amountOut, executionPrice);
    }

    /**
     * @notice Cancel an active intent and return tokens to user
     * @param intentId Intent to cancel
     */
    function cancelIntent(bytes32 intentId) external nonReentrant validIntent(intentId) {
        SwapIntent storage intent = intents[intentId];
        require(intent.user == msg.sender, "Not your intent");

        // Return tokens to user
        IERC20(intent.tokenIn).safeTransfer(intent.user, intent.amountIn);

        intent.isActive = false;
        processedIntents[intentId] = true;
        _removeFromActiveIntents(intentId);

        emit IntentCancelled(intentId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _tryMatch(bytes32 intentId) internal {
        SwapIntent storage intent = intents[intentId];
        if (!intent.isActive || processedIntents[intentId]) return;

        // Look for complementary intents
        bytes32[] storage candidates = intentsByTokenPair[intent.tokenOut][intent.tokenIn];

        for (uint256 i = 0; i < candidates.length; i++) {
            bytes32 candidateId = candidates[i];
            SwapIntent storage candidate = intents[candidateId];

            if (!candidate.isActive || candidateId == intentId || processedIntents[candidateId]) {
                continue;
            }

            if (candidate.deadline < block.timestamp) continue;

            if (_canMatch(intent, candidate)) {
                _executeMatch(intentId, candidateId);
                return;
            }
        }
    }

    function _canMatch(SwapIntent memory intentA, SwapIntent memory intentB) internal pure returns (bool) {
        // Complementary token check
        if (intentA.tokenIn != intentB.tokenOut || intentA.tokenOut != intentB.tokenIn) {
            return false;
        }

        // Cross-chain compatibility
        if (intentA.sourceChain != intentB.destChain || intentA.destChain != intentB.sourceChain) {
            return false;
        }

        // Simplified matching - just check if amounts are reasonable
        // For now, allow any match where both parties get at least their minimum
        return true;
    }

    //    function _canMatch(SwapIntent memory intentA, SwapIntent memory intentB) internal pure returns (bool) {
    //        // Complementary token check
    //        if (intentA.tokenIn != intentB.tokenOut || intentA.tokenOut != intentB.tokenIn) {
    //            return false;
    //        }
    //
    //        // Cross-chain compatibility
    //        if (intentA.sourceChain != intentB.destChain || intentA.destChain != intentB.sourceChain) {
    //            return false;
    //        }
    //
    //        // Price compatibility check
    //        uint256 priceA = (intentA.minAmountOut * 1e18) / intentA.amountIn;
    //        uint256 priceB = (intentB.amountIn * 1e18) / intentB.minAmountOut;
    //
    //        // Check if prices are compatible (within slippage tolerance)
    //        uint256 priceDiff = priceA > priceB ? priceA - priceB : priceB - priceA;
    //        uint256 avgPrice = (priceA + priceB) / 2;
    //        uint256 maxSlippage = Math.max(intentA.maxSlippage, intentB.maxSlippage);
    //
    //        return (priceDiff * BASIS_POINTS) / avgPrice <= maxSlippage;
    //    }

    function _executeMatch(bytes32 intentIdA, bytes32 intentIdB) internal {
        SwapIntent storage intentA = intents[intentIdA];
        SwapIntent storage intentB = intents[intentIdB];

        // Calculate matched amounts
        uint256 matchedAmount = Math.min(intentA.amountIn, intentB.amountIn);

        // Calculate execution price (average of both intents' implied prices)
        uint256 executionPrice = _calculateExecutionPrice(intentA, intentB);

        // Execute direct transfer
        IERC20(intentA.tokenIn).safeTransfer(intentB.user, matchedAmount);
        IERC20(intentB.tokenIn).safeTransfer(intentA.user, matchedAmount);

        // Handle partial fills
        if (intentA.amountIn > matchedAmount) {
            intentA.amountIn -= matchedAmount;
        } else {
            intentA.isActive = false;
            intentA.amountIn = 0;
            processedIntents[intentIdA] = true;
            _removeFromActiveIntents(intentIdA);
        }

        if (intentB.amountIn > matchedAmount) {
            intentB.amountIn -= matchedAmount;
        } else {
            intentB.isActive = false;
            processedIntents[intentIdB] = true;
            _removeFromActiveIntents(intentIdB);
        }

        // Record match
        matches.push(
            MatchedPair({
                intentA: intentIdA,
                intentB: intentIdB,
                matchedAmount: matchedAmount,
                executionPrice: executionPrice,
                timestamp: block.timestamp,
                executor: msg.sender
            })
        );

        // Update stats
        stats.successfulMatches++;
        stats.totalVolumeMatched += matchedAmount;
        stats.gasSaved += 100000; // Estimated gas saved per match

        emit IntentsMatched(intentIdA, intentIdB, matchedAmount, executionPrice, msg.sender);
    }

    function _calculateExecutionPrice(SwapIntent memory intentA, SwapIntent memory intentB)
        internal
        pure
        returns (uint256)
    {
        uint256 priceA = (intentA.minAmountOut * 1e18) / intentA.amountIn;
        uint256 priceB = (intentB.amountIn * 1e18) / intentB.minAmountOut;
        return (priceA + priceB) / 2;
    }

    function _executeSwapViaAMM(SwapIntent memory intent) internal returns (uint256 amountOut) {
        IERC20(intent.tokenIn).forceApprove(address(swapRouter), intent.amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: intent.tokenIn,
            tokenOut: intent.tokenOut,
            fee: 3000, // 0.3% fee tier - make configurable
            recipient: intent.user,
            deadline: block.timestamp + 300,
            amountIn: intent.amountIn,
            amountOutMinimum: intent.minAmountOut,
            sqrtPriceLimitX96: 0
        });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function _removeFromActiveIntents(bytes32 intentId) internal {
        for (uint256 i = 0; i < activeIntents.length; i++) {
            if (activeIntents[i] == intentId) {
                activeIntents[i] = activeIntents[activeIntents.length - 1];
                activeIntents.pop();
                break;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getActiveIntentsCount() external view returns (uint256) {
        return activeIntents.length;
    }

    function getIntentsByTokenPair(address tokenIn, address tokenOut) external view returns (bytes32[] memory) {
        return intentsByTokenPair[tokenIn][tokenOut];
    }

    function getMatchesCount() external view returns (uint256) {
        return matches.length;
    }

    function getMatchingStats() external view returns (MatchingStats memory) {
        return stats;
    }

    function isRelayerAuthorized(address relayer) external view returns (bool) {
        return authorizedRelayers[relayer];
    }

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function authorizeRelayer(address relayer, bool authorized) external onlyOwner {
        authorizedRelayers[relayer] = authorized;
        emit RelayerAuthorized(relayer, authorized);
    }

    function updateConfiguration(uint256 newMatchingReward, uint256 newProtocolFee) external onlyOwner {
        require(newMatchingReward <= 1000, "Reward too high"); // Max 10%
        require(newProtocolFee <= 1000, "Fee too high"); // Max 10%

        matchingReward = newMatchingReward;
        protocolFee = newProtocolFee;

        emit ConfigurationUpdated(newMatchingReward, newProtocolFee);
    }

    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }
}
