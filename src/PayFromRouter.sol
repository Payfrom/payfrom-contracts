// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PayFromRouter is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    address public immutable feeWallet;
    uint256 public constant FEE_BASIS_POINTS = 100;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_PAYMENT = 1e6;

    event PaymentProcessed(
        bytes32 indexed paymentId,
        address indexed payer,
        address indexed merchant,
        address token,
        uint256 amount,
        uint256 fee
    );

    error InvalidMerchant();
    error InvalidToken();
    error AmountTooSmall();

    constructor(address _feeWallet, address _owner) Ownable(_owner) { // Initialize Ownable with _owner
        require(_feeWallet != address(0), "Invalid fee wallet");
        feeWallet = _feeWallet;
    }

    function pay(
        bytes32 paymentId,
        address token,
        uint256 amount,
        address merchant
    ) external nonReentrant whenNotPaused {
        if (merchant == address(0)) revert InvalidMerchant();
        if (token == address(0)) revert InvalidToken();
        if (amount < MIN_PAYMENT) revert AmountTooSmall();

        uint256 fee = (amount * FEE_BASIS_POINTS) / BASIS_POINTS;
        uint256 merchantAmount = amount - fee;

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).safeTransfer(feeWallet, fee);
        IERC20(token).safeTransfer(merchant, merchantAmount);

        emit PaymentProcessed(paymentId, msg.sender, merchant, token, amount, fee);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
