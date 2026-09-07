// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {
    SafeERC20,
    IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PayfromDelegate {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // Where the fee goes. Immutable for the same reason a shared config value
    // always has to be here: a delegated EOA runs this code against its own
    // blank storage, so a mutable variable set here would read as zero there.
    address public immutable feeRecipient;

    // Ordinary mutable storage IS safe here, unlike feeRecipient above - a
    // nonce is meant to differ per wallet, and each delegated EOA already has
    // its own private storage space to keep one in.
    uint256 public nonce;

    event TransferExecuted(
        address indexed token,
        address indexed recipient,
        uint256 amount,
        uint256 fee
    );

    error InvalidAddress();
    error InvalidAmount();
    error FeeExceedsAmount();
    error Expired();
    error InvalidSignature();

    constructor(address _feeRecipient) {
        if (_feeRecipient == address(0)) revert InvalidAddress();
        feeRecipient = _feeRecipient;
    }

    /**
     * Authorization comes entirely from the signature: whoever calls this
     * (any relayer, doesn't matter which) can only move funds the wallet
     * itself has already signed off on for this exact token/recipient/
     * amount/fee/nonce/deadline - a compromised or arbitrary caller can't
     * forge a transfer they don't already hold a valid signature for.
     */
    function executeTransfer(
        address token,
        address recipient,
        uint256 amount,
        uint256 fee,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) revert Expired();
        if (token == address(0) || recipient == address(0))
            revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();
        if (fee > amount) revert FeeExceedsAmount();

        uint256 currentNonce = nonce;
        bytes32 digest = keccak256(
            abi.encode(
                address(this),
                block.chainid,
                token,
                recipient,
                amount,
                fee,
                currentNonce,
                deadline
            )
        );

        if (digest.recover(signature) != address(this))
            revert InvalidSignature();

        nonce = currentNonce + 1;

        IERC20(token).safeTransfer(recipient, amount);
        if (fee > 0) {
            IERC20(token).safeTransfer(feeRecipient, fee);
        }

        emit TransferExecuted(token, recipient, amount, fee);
    }

    // Required so a delegated EOA can still receive plain native transfers.
    receive() external payable {}
}
