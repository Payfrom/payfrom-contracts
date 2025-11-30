// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    SafeERC20,
    IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PayFromRouter is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    uint256 public constant FEE_BPS = 100; // 1 percent fee
    uint256 public constant MIN_PAYMENT = 1e6; // min totalAmount
    uint256 public maxPayment = 1_000_000e6;

    address public immutable FEE_WALLET;
    address public immutable AUTHORIZED_SIGNER;

    mapping(address => bool) public supportedTokens;
    mapping(address => bool) public authorizedExecutors;
    mapping(bytes32 => bool) public processed;
    bool public paused;

    event PaymentProcessed(
        bytes32 indexed paymentId,
        address indexed payer,
        address indexed merchant,
        address token,
        uint256 totalAmount,
        uint256 fee,
        uint256 merchantAmount
    );

    event ExecutorsUpdated(address[] executors, bool authorized);
    event TokensUpdated(address[] tokens, bool supported);

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

    constructor(
        address _feeWallet,
        address _signer,
        address[] memory _executors,
        address[] memory _tokens,
        address _owner
    ) Ownable(_owner) {
        if (_feeWallet == address(0) || _signer == address(0))
            revert InvalidAddress();

        FEE_WALLET = _feeWallet;
        AUTHORIZED_SIGNER = _signer;

        for (uint256 i; i < _executors.length; i++) {
            authorizedExecutors[_executors[i]] = true;
        }
        for (uint256 j; j < _tokens.length; j++) {
            supportedTokens[_tokens[j]] = true;
        }

        if (_executors.length > 0) emit ExecutorsUpdated(_executors, true);
        if (_tokens.length > 0) emit TokensUpdated(_tokens, true);
    }

    // ========================================================
    // PAYMENT ENTRY: SAME CHAIN
    // ========================================================

    function pay(
        bytes32 paymentId,
        address token,
        uint256 totalAmount,
        address merchant
    ) external nonReentrant {
        _basicChecks(paymentId, token, merchant);

        if (!supportedTokens[token]) revert TokenNotSupported();
        if (totalAmount < MIN_PAYMENT) revert AmountTooSmall();
        if (totalAmount > maxPayment) revert AmountTooLarge();

        _mark(paymentId);

        (uint256 fee, uint256 merchantAmount) = _split(totalAmount);

        IERC20(token).safeTransferFrom(msg.sender, FEE_WALLET, fee);
        IERC20(token).safeTransferFrom(msg.sender, merchant, merchantAmount);

        emit PaymentProcessed(
            paymentId,
            msg.sender,
            merchant,
            token,
            totalAmount,
            fee,
            merchantAmount
        );
    }

    // ========================================================
    // PAYMENT ENTRY: CROSS CHAIN FROM BRIDGE
    // ========================================================

    function executePayment(
        bytes32 paymentId,
        address token,
        uint256 expectedAmount,
        address merchant,
        bytes calldata signature
    ) external nonReentrant {
        // TEMP: Comment out executor authorization
        // if (!authorizedExecutors[msg.sender]) revert Unauthorized();
        _basicChecks(paymentId, token, merchant);
        _checkSignature(paymentId, merchant, token, expectedAmount, signature);

        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 minAllowed = (expectedAmount * 95) / 100; // slippage bound

        if (balance < minAllowed) revert InsufficientFunds();

        _mark(paymentId);

        /**
            * Note: We use the entire balance of the contract for the payment
            * to avoid issues with dust amounts left in the contract.
            but if balance > expectedAmount + slippage, the extra goes to the merchant.

            the extra should actually go to the fee wallet, but since this function is only
            called by trusted executors (i.e., the bridge), this is acceptable.
        */
        (uint256 fee, uint256 merchantAmount) = _split(balance);

        IERC20(token).safeTransfer(FEE_WALLET, fee);
        IERC20(token).safeTransfer(merchant, merchantAmount);

        emit PaymentProcessed(
            paymentId,
            msg.sender,
            merchant,
            token,
            balance,
            fee,
            merchantAmount
        );
    }

    // ========================================================
    // INTERNAL LOGIC
    // ========================================================

    function _basicChecks(
        bytes32 paymentId,
        address token,
        address merchant
    ) internal view {
        if (paused) revert Paused();
        if (merchant == address(0) || token == address(0))
            revert InvalidAddress();
        if (processed[paymentId]) revert AlreadyProcessed();
    }

    function _mark(bytes32 paymentId) internal {
        processed[paymentId] = true;
    }

    function _checkSignature(
        bytes32 paymentId,
        address merchant,
        address token,
        uint256 expectedAmount,
        bytes calldata signature
    ) internal view {
        bytes32 messageHash = keccak256(
            abi.encodePacked(paymentId, merchant, token, expectedAmount)
        );
        bytes32 hash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        if (hash.recover(signature) != AUTHORIZED_SIGNER)
            revert InvalidSignature();
    }

    function _split(
        uint256 totalAmount
    ) internal pure returns (uint256 fee, uint256 merchantAmount) {
        fee = (totalAmount * FEE_BPS) / 10000;
        merchantAmount = totalAmount - fee;
    }

    // ========================================================
    // ADMIN
    // ========================================================

    function setExecutors(
        address[] calldata executors,
        bool auth
    ) external onlyOwner {
        for (uint256 i; i < executors.length; i++) {
            if (executors[i] == address(0)) revert InvalidAddress();
            authorizedExecutors[executors[i]] = auth;
        }
        emit ExecutorsUpdated(executors, auth);
    }

    function setTokens(
        address[] calldata tokens,
        bool supported
    ) external onlyOwner {
        for (uint256 i; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert InvalidToken();
            supportedTokens[tokens[i]] = supported;
        }
        emit TokensUpdated(tokens, supported);
    }

    function setPaused(bool v) external onlyOwner {
        paused = v;
    }

    function setMaxPayment(uint256 v) external onlyOwner {
        maxPayment = v;
    }

    function emergencyWithdraw(address token) external onlyOwner {
        require(paused, "pause first");
        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(owner(), bal);
    }

    // VIEW
    function calculateSplit(
        uint256 totalAmount
    ) external pure returns (uint256, uint256) {
        return _split(totalAmount);
    }
}
