// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    SafeERC20,
    IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title PayFromRouter
 * @notice Secure payment splitter: 1% to PayFrom, 99% to merchant
 * @dev Hardened version with token whitelist, replay protection, and direct transfers
 *
 * Security improvements:
 * - Token whitelist to prevent malicious tokens
 * - Direct transfers (no intermediate holding)
 * - Payment ID replay protection
 * - Configurable fee wallet
 * - Maximum payment limits
 * - Comprehensive event logging
 */
contract PayFromRouter is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // Configuration
    address public feeWallet;
    uint256 public constant FEE_BASIS_POINTS = 100; // 1%
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_PAYMENT = 1e6; // 1 USDC/USDT (6 decimals)
    uint256 public maxPayment = 1_000_000e6; // 1M USDC/USDT max by default

    // Security: Track processed payments to prevent replay attacks
    mapping(bytes32 => bool) public processedPayments;

    // Security: Token whitelist to prevent malicious tokens
    mapping(address => bool) public supportedTokens;

    // Events
    event PaymentProcessed(
        bytes32 indexed paymentId,
        address indexed payer,
        address indexed merchant,
        address token,
        uint256 amount,
        uint256 fee,
        uint256 merchantAmount
    );

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event FeeWalletUpdated(
        address indexed oldWallet,
        address indexed newWallet
    );
    event MaxPaymentUpdated(uint256 oldMax, uint256 newMax);
    event ContractPaused(address indexed by);
    event ContractUnpaused(address indexed by);
    event EmergencyWithdrawal(
        address indexed token,
        uint256 amount,
        address indexed to
    );

    // Custom Errors (gas efficient)
    error InvalidMerchant();
    error InvalidToken();
    error AmountTooSmall();
    error AmountTooLarge();
    error TokenNotSupported();
    error PaymentAlreadyProcessed();
    error InvalidFeeWallet();
    error InvalidMaxPayment();
    error NoTokensToRecover();

    constructor(address _feeWallet, address _owner) Ownable(_owner) {
        if (_feeWallet == address(0)) revert InvalidFeeWallet();
        feeWallet = _feeWallet;

        emit FeeWalletUpdated(address(0), _feeWallet);
    }

    /**
     * @notice Process payment with secure direct transfers
     * @param paymentId Unique payment ID (prevents replay attacks)
     * @param token Whitelisted token address (USDC, USDT, etc.)
     * @param amount Total amount (will be split: 1% fee, 99% merchant)
     * @param merchant Merchant's wallet address
     *
     * @dev Security features:
     * - Checks payment hasn't been processed before
     * - Validates token is whitelisted
     * - Uses direct transfers (no intermediate holding)
     * - Protected by reentrancy guard and pause mechanism
     */
    function pay(
        bytes32 paymentId,
        address token,
        uint256 amount,
        address merchant
    ) external nonReentrant whenNotPaused {
        // Validation checks
        if (merchant == address(0)) revert InvalidMerchant();
        if (token == address(0)) revert InvalidToken();
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (amount < MIN_PAYMENT) revert AmountTooSmall();
        if (amount > maxPayment) revert AmountTooLarge();

        // Replay protection: Check if payment already processed
        if (processedPayments[paymentId]) revert PaymentAlreadyProcessed();
        processedPayments[paymentId] = true;

        // Calculate split (merchant gets the remainder to avoid rounding issues)
        uint256 fee = (amount * FEE_BASIS_POINTS) / BASIS_POINTS;
        uint256 merchantAmount = amount - fee;

        // SECURITY FIX: Direct transfers - funds never touch this contract
        // This prevents any intermediate state exploitation
        IERC20(token).safeTransferFrom(msg.sender, feeWallet, fee);
        IERC20(token).safeTransferFrom(msg.sender, merchant, merchantAmount);

        emit PaymentProcessed(
            paymentId,
            msg.sender,
            merchant,
            token,
            amount,
            fee,
            merchantAmount
        );
    }

    // ============ TOKEN WHITELIST MANAGEMENT ============

    /**
     * @notice Add token to whitelist
     * @param token Token address to whitelist
     */
    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert InvalidToken();
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    /**
     * @notice Add multiple tokens to whitelist (gas efficient)
     * @param tokens Array of token addresses
     */
    function addSupportedTokens(address[] calldata tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert InvalidToken();
            supportedTokens[tokens[i]] = true;
            emit TokenAdded(tokens[i]);
        }
    }

    /**
     * @notice Remove token from whitelist
     * @param token Token address to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
        emit TokenRemoved(token);
    }

    // ============ CONFIGURATION MANAGEMENT ============

    /**
     * @notice Update fee wallet address
     * @param newFeeWallet New fee wallet address
     */
    function updateFeeWallet(address newFeeWallet) external onlyOwner {
        if (newFeeWallet == address(0)) revert InvalidFeeWallet();
        address oldWallet = feeWallet;
        feeWallet = newFeeWallet;
        emit FeeWalletUpdated(oldWallet, newFeeWallet);
    }

    /**
     * @notice Update maximum payment amount
     * @param newMaxPayment New maximum payment amount
     */
    function updateMaxPayment(uint256 newMaxPayment) external onlyOwner {
        if (newMaxPayment < MIN_PAYMENT) revert InvalidMaxPayment();
        uint256 oldMax = maxPayment;
        maxPayment = newMaxPayment;
        emit MaxPaymentUpdated(oldMax, newMaxPayment);
    }

    // ============ PAUSE CONTROLS ============

    /**
     * @notice Pause all payment processing
     * @dev Can be called by owner in case of emergency
     */
    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    /**
     * @notice Unpause payment processing
     */
    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    // ============ EMERGENCY FUNCTIONS ============

    /**
     * @notice Emergency token recovery
     * @dev Should rarely be needed since contract doesn't hold funds
     * @dev Only recovers tokens accidentally sent to contract
     * @param token Token address to recover
     * @param amount Amount to recover (0 = recover all)
     */
    function emergencyRecoverToken(
        address token,
        uint256 amount
    ) external onlyOwner {
        if (token == address(0)) revert InvalidToken();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NoTokensToRecover();

        uint256 recoverAmount = amount == 0 ? balance : amount;
        if (recoverAmount > balance) recoverAmount = balance;

        IERC20(token).safeTransfer(owner(), recoverAmount);
        emit EmergencyWithdrawal(token, recoverAmount, owner());
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Check if a payment has been processed
     * @param paymentId Payment ID to check
     * @return bool True if processed
     */
    function isPaymentProcessed(
        bytes32 paymentId
    ) external view returns (bool) {
        return processedPayments[paymentId];
    }

    /**
     * @notice Check if token is supported
     * @param token Token address to check
     * @return bool True if supported
     */
    function isTokenSupported(address token) external view returns (bool) {
        return supportedTokens[token];
    }

    /**
     * @notice Calculate fee and merchant amount for a given payment
     * @param amount Total payment amount
     * @return fee Fee amount
     * @return merchantAmount Amount merchant receives
     */
    function calculateSplit(
        uint256 amount
    ) external pure returns (uint256 fee, uint256 merchantAmount) {
        fee = (amount * FEE_BASIS_POINTS) / BASIS_POINTS;
        merchantAmount = amount - fee;
    }
}
