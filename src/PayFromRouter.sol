// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title PayFromRouter
 * @notice Payment splitter: 1% to PayFrom, 99% to merchant
 * @dev Supports both same-chain and cross-chain payments
 * 
 * Same-chain: User calls pay() directly
 * Cross-chain: Bridge executor calls executePayment() after bridging funds
 */
contract PayFromRouter is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // ============ CONSTANTS ============
    
    /// @notice Platform fee in basis points (1% = 100 bps)
    uint256 public constant FEE_BPS = 100;
    
    uint256 public constant MIN_PAYMENT = 1e6;

    // ============ IMMUTABLE ============
    
    /// @notice Address receiving platform fees
    address public immutable feeWallet;
    
    /// @notice Authorized signer for cross-chain payments (AWS KMS public key)
    address public immutable authorizedSigner;

    // ============ STATE ============
    
    /// @notice Whitelisted tokens (USDC, USDT, etc.)
    mapping(address => bool) public supportedTokens;
    
    /// @notice Authorized bridge executors (LiFi Diamond, Across, etc.)
    mapping(address => bool) public authorizedExecutors;
    
    /// @notice Processed payment IDs to prevent replay attacks
    mapping(bytes32 => bool) public processedPayments;
    
    /// @notice Emergency pause switch
    bool public paused;
    
    /// @notice Maximum payment amount (anti-whale protection)
    uint256 public maxPayment = 1_000_000e6; // 1M USDC

    // ============ EVENTS ============
    
    /**
     * @notice Emitted when a payment is processed
     * @param paymentId Unique payment identifier
     * @param payer Address that initiated payment
     * @param merchant Address receiving payment
     * @param token Token used for payment
     * @param amount Total payment amount
     * @param fee Fee amount deducted
     */
    event PaymentProcessed(
        bytes32 indexed paymentId,
        address indexed payer,
        address indexed merchant,
        address token,
        uint256 amount,
        uint256 fee
    );
    
    /**
     * @notice Emitted when executors are updated
     * @param executors Array of executor addresses
     * @param authorized True if authorized, false if revoked
     */
    event ExecutorsUpdated(address[] executors, bool authorized);
    
    /**
     * @notice Emitted when supported tokens are updated
     * @param tokens Array of token addresses
     * @param supported True if supported, false if removed
     */
    event TokensUpdated(address[] tokens, bool supported);

    // ============ ERRORS ============
    
    error Unauthorized();
    error Paused();
    error InvalidAddress();
    error InvalidToken();
    error TokenNotSupported();
    error AmountTooSmall();
    error AmountTooLarge();
    error AlreadyProcessed();
    error InvalidSignature();
    error InsufficientFunds();

    // ============ CONSTRUCTOR ============
    
    /**
     * @notice Initialize the payment router
     * @param _feeWallet Address to receive platform fees
     * @param _signer Authorized signer for cross-chain payments
     * @param _initialExecutors Initial authorized executors (bridges)
     * @param _initialTokens Initial supported tokens
     * @param _owner Contract owner address
     */
    constructor(
        address _feeWallet,
        address _signer,
        address[] memory _initialExecutors,
        address[] memory _initialTokens,
        address _owner
    ) Ownable(_owner) {
        if (_feeWallet == address(0) || _signer == address(0))
            revert InvalidAddress();

        feeWallet = _feeWallet;
        authorizedSigner = _signer;

        // Setup initial executors
        for (uint256 i = 0; i < _initialExecutors.length; i++) {
            authorizedExecutors[_initialExecutors[i]] = true;
        }

        // Setup initial tokens
        for (uint256 i = 0; i < _initialTokens.length; i++) {
            supportedTokens[_initialTokens[i]] = true;
        }

        if (_initialExecutors.length > 0) {
            emit ExecutorsUpdated(_initialExecutors, true);
        }
        if (_initialTokens.length > 0) {
            emit TokensUpdated(_initialTokens, true);
        }
    }

    // ============ PAYMENT FUNCTIONS ============

    /**
     * @notice Process same-chain payment
     * @dev User must approve this contract to spend tokens first
     * @param paymentId Unique payment identifier (prevents replay)
     * @param token Token address (must be whitelisted)
     * @param amount Total payment amount
     * @param merchant Merchant receiving payment
     */
    function pay(
        bytes32 paymentId,
        address token,
        uint256 amount,
        address merchant
    ) external nonReentrant {
        // Common validations
        _validatePayment(paymentId, token, merchant);
        
        // Same-chain specific validations
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (amount < MIN_PAYMENT) revert AmountTooSmall();
        if (amount > maxPayment) revert AmountTooLarge();

        // Mark as processed
        _markProcessed(paymentId);

        // Calculate split
        (uint256 fee, uint256 merchantAmount) = _calculateSplit(amount);

        // Transfer from user to fee wallet and merchant
        IERC20(token).safeTransferFrom(msg.sender, feeWallet, fee);
        IERC20(token).safeTransferFrom(msg.sender, merchant, merchantAmount);

        emit PaymentProcessed(paymentId, msg.sender, merchant, token, amount, fee);
    }

    /**
     * @notice Process cross-chain payment (called by bridge executor)
     * @dev Funds must be in contract before calling this function
     * @param paymentId Unique payment identifier
     * @param token Token address
     * @param expectedAmount Expected amount (allows 5% slippage)
     * @param merchant Merchant receiving payment
     * @param signature Backend signature authorizing payment
     */
    function executePayment(
        bytes32 paymentId,
        address token,
        uint256 expectedAmount,
        address merchant,
        bytes calldata signature
    ) external nonReentrant {
        // Check caller is authorized executor (LiFi, Across, etc.)
        if (!authorizedExecutors[msg.sender]) revert Unauthorized();
        
        // Common validations
        _validatePayment(paymentId, token, merchant);
        
        // Verify backend signature
        _verifySignature(paymentId, merchant, token, expectedAmount, signature);

        // Check funds arrived (allow 5% slippage for bridge fees)
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < (expectedAmount * 95) / 100) revert InsufficientFunds();

        // Mark as processed
        _markProcessed(paymentId);

        // Calculate split based on actual received amount
        (uint256 fee, uint256 merchantAmount) = _calculateSplit(balance);

        // Transfer from contract to fee wallet and merchant
        IERC20(token).safeTransfer(feeWallet, fee);
        IERC20(token).safeTransfer(merchant, merchantAmount);

        emit PaymentProcessed(paymentId, msg.sender, merchant, token, balance, fee);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @notice Validate common payment requirements
     * @param paymentId Payment identifier
     * @param token Token address
     * @param merchant Merchant address
     */
    function _validatePayment(
        bytes32 paymentId,
        address token,
        address merchant
    ) internal view {
        if (paused) revert Paused();
        if (merchant == address(0) || token == address(0)) revert InvalidAddress();
        if (processedPayments[paymentId]) revert AlreadyProcessed();
    }

    /**
     * @notice Mark payment as processed
     * @param paymentId Payment identifier
     */
    function _markProcessed(bytes32 paymentId) internal {
        processedPayments[paymentId] = true;
    }

    /**
     * @notice Verify backend signature for cross-chain payment
     * @param paymentId Payment identifier
     * @param merchant Merchant address
     * @param token Token address
     * @param expectedAmount Expected amount
     * @param signature Backend signature
     */
    function _verifySignature(
        bytes32 paymentId,
        address merchant,
        address token,
        uint256 expectedAmount,
        bytes calldata signature
    ) internal view {
        bytes32 messageHash = keccak256(
            abi.encodePacked(paymentId, merchant, token, expectedAmount)
        );
        bytes32 ethSignedHash = messageHash.toEthSignedMessageHash();
        if (ethSignedHash.recover(signature) != authorizedSigner)
            revert InvalidSignature();
    }

    /**
     * @notice Calculate payment split (1% fee, 99% merchant)
     * @param amount Total payment amount
     * @return fee Platform fee amount
     * @return merchantAmount Amount for merchant
     */
    function _calculateSplit(uint256 amount) internal pure returns (uint256 fee, uint256 merchantAmount) {
        fee = (amount * FEE_BPS) / 10000;
        merchantAmount = amount - fee;
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Update authorized executors
     * @param executors Array of executor addresses
     * @param authorized True to authorize, false to revoke
     */
    function setExecutors(address[] calldata executors, bool authorized) external onlyOwner {
        for (uint256 i = 0; i < executors.length; i++) {
            if (executors[i] == address(0)) revert InvalidAddress();
            authorizedExecutors[executors[i]] = authorized;
        }
        emit ExecutorsUpdated(executors, authorized);
    }

    /**
     * @notice Update supported tokens
     * @param tokens Array of token addresses
     * @param supported True to support, false to remove
     */
    function setTokens(address[] calldata tokens, bool supported) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert InvalidToken();
            supportedTokens[tokens[i]] = supported;
        }
        emit TokensUpdated(tokens, supported);
    }

    /**
     * @notice Pause/unpause all payment processing
     * @param _paused True to pause, false to unpause
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /**
     * @notice Update maximum payment amount
     * @param _maxPayment New maximum payment amount
     */
    function setMaxPayment(uint256 _maxPayment) external onlyOwner {
        maxPayment = _maxPayment;
    }

    /**
     * @notice Emergency withdraw stuck tokens
     * @dev Can only be called when paused
     * @param token Token address to withdraw
     */
    function emergencyWithdraw(address token) external onlyOwner {
        require(paused, "Must pause first");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(owner(), balance);
    }

    // ============ VIEW FUNCTIONS ============
    function calculateSplit(uint256 amount) external pure returns (uint256 fee, uint256 merchantAmount) {
        return _calculateSplit(amount);
    }
}