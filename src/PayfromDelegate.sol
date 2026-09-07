// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PayfromDelegate {
    using ECDSA for bytes32;

    // Per-wallet: each delegated EOA runs this code against its own storage.
    uint256 public nonce;

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

    // Authorization comes from the signature alone, not the caller.
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

            if (c.target == address(this) || c.target == address(0))
                revert InvalidAddress();

            (bool success, ) = c.target.call{value: c.value}(c.data);
            if (!success) revert CallFailed(i);
        }

        emit OpsExecuted(currentNonce, calls.length);
    }

    // Lets a delegated EOA still receive plain native transfers.
    receive() external payable {}
}
