// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PayfromDelegate {
    using ECDSA for bytes32;

    // Ordinary mutable storage is safe here even though this same code runs
    // against every delegated wallet's own blank storage - a nonce is meant
    // to differ per wallet, and each delegated EOA has its own private
    // storage space to keep one in.
    uint256 public nonce;

    // One arbitrary call the wallet has pre-authorized as part of an op
    // batch - e.g. an ERC20 transfer, an approve + third-party call for a
    // swap, or anything else - so new use cases never require redeploying
    // this contract.
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    event OpsExecuted(uint256 indexed nonceUsed, uint256 callCount);

    error InvalidAddress();
    error Expired();
    error InvalidSignature();
    error EmptyBatch();
    error CallFailed(uint256 index);

    /**
     * Authorization comes entirely from the signature: whoever calls this
     * (any relayer, doesn't matter which) can only run calls the wallet
     * itself already signed off on for this exact set of target/value/data
     * plus nonce/deadline - a compromised or arbitrary caller can't forge
     * an operation it doesn't already hold a valid signature for. All calls
     * in the batch either succeed together or the whole thing reverts.
     */
    function executeOps(
        Call[] calldata calls,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) revert Expired();
        if (calls.length == 0) revert EmptyBatch();

        uint256 currentNonce = nonce;
        bytes32 digest = keccak256(
            abi.encode(address(this), block.chainid, calls, currentNonce, deadline)
        );

        if (digest.recover(signature) != address(this))
            revert InvalidSignature();

        nonce = currentNonce + 1;

        for (uint256 i = 0; i < calls.length; i++) {
            Call calldata c = calls[i];

            if (c.target == address(this)) revert InvalidAddress();

            (bool success, ) = c.target.call{value: c.value}(c.data);
            if (!success) revert CallFailed(i);
        }

        emit OpsExecuted(currentNonce, calls.length);
    }

    // Required so a delegated EOA can still receive plain native transfers.
    receive() external payable {}
}
