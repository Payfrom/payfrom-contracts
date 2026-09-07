// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {PayfromDelegate} from "../src/PayfromDelegate.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract PayfromDelegateTest is Test {
    PayfromDelegate public delegateImpl;
    ERC20Mock public token;

    address public feeRecipient;
    address public recipient;
    address public relayer;

    uint256 public userPrivateKey;
    address public user;

    function setUp() public {
        feeRecipient = makeAddr("feeRecipient");
        recipient = makeAddr("recipient");
        relayer = makeAddr("relayer");

        userPrivateKey = 0xa11ce;
        user = vm.addr(userPrivateKey);

        token = new ERC20Mock();
        delegateImpl = new PayfromDelegate(feeRecipient);

        token.mint(user, 1_000e6);
    }

    function _delegateUser() internal {
        vm.signAndAttachDelegation(address(delegateImpl), userPrivateKey);
    }

    function _sign(
        address token_,
        address recipient_,
        uint256 amount,
        uint256 fee,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encode(user, block.chainid, token_, recipient_, amount, fee, nonce, deadline)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_executeTransfer_movesUserBalance() public {
        _delegateUser();

        bytes memory sig = _sign(address(token), recipient, 100e6, 1e6, 0, block.timestamp + 1 hours);

        vm.prank(relayer);
        PayfromDelegate(payable(user)).executeTransfer(
            address(token), recipient, 100e6, 1e6, block.timestamp + 1 hours, sig
        );

        assertEq(token.balanceOf(user), 899e6);
        assertEq(token.balanceOf(recipient), 100e6);
        assertEq(token.balanceOf(feeRecipient), 1e6);
    }

    function test_executeTransfer_anyoneCanSubmitAValidlySignedTransfer() public {
        _delegateUser();

        bytes memory sig = _sign(address(token), recipient, 100e6, 0, 0, block.timestamp + 1 hours);

        // A completely unrelated, untrusted address submits it - still works,
        // because authorization comes from the signature, not the caller.
        vm.prank(makeAddr("randomSubmitter"));
        PayfromDelegate(payable(user)).executeTransfer(
            address(token), recipient, 100e6, 0, block.timestamp + 1 hours, sig
        );

        assertEq(token.balanceOf(recipient), 100e6);
    }

    function test_executeTransfer_revertsForWrongSigner() public {
        _delegateUser();

        uint256 attackerKey = 0xbad;
        bytes32 digest = keccak256(
            abi.encode(user, block.chainid, address(token), recipient, 100e6, uint256(0), uint256(0), block.timestamp + 1 hours)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerKey, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert(PayfromDelegate.InvalidSignature.selector);
        PayfromDelegate(payable(user)).executeTransfer(
            address(token), recipient, 100e6, 0, block.timestamp + 1 hours, badSig
        );
    }

    function test_executeTransfer_revertsOnReplay() public {
        _delegateUser();

        bytes memory sig = _sign(address(token), recipient, 50e6, 0, 0, block.timestamp + 1 hours);

        PayfromDelegate(payable(user)).executeTransfer(
            address(token), recipient, 50e6, 0, block.timestamp + 1 hours, sig
        );

        vm.expectRevert(PayfromDelegate.InvalidSignature.selector);
        PayfromDelegate(payable(user)).executeTransfer(
            address(token), recipient, 50e6, 0, block.timestamp + 1 hours, sig
        );
    }

    function test_executeTransfer_revertsWhenExpired() public {
        _delegateUser();

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(address(token), recipient, 100e6, 0, 0, deadline);

        vm.warp(deadline + 1);

        vm.expectRevert(PayfromDelegate.Expired.selector);
        PayfromDelegate(payable(user)).executeTransfer(address(token), recipient, 100e6, 0, deadline, sig);
    }

    function test_executeTransfer_zeroFeeSkipsFeeRecipientTransfer() public {
        _delegateUser();

        bytes memory sig = _sign(address(token), recipient, 100e6, 0, 0, block.timestamp + 1 hours);

        PayfromDelegate(payable(user)).executeTransfer(
            address(token), recipient, 100e6, 0, block.timestamp + 1 hours, sig
        );

        assertEq(token.balanceOf(feeRecipient), 0);
        assertEq(token.balanceOf(recipient), 100e6);
    }

    function test_executeTransfer_revertsWhenFeeExceedsAmount() public {
        _delegateUser();

        bytes memory sig = _sign(address(token), recipient, 100e6, 101e6, 0, block.timestamp + 1 hours);

        vm.expectRevert(PayfromDelegate.FeeExceedsAmount.selector);
        PayfromDelegate(payable(user)).executeTransfer(
            address(token), recipient, 100e6, 101e6, block.timestamp + 1 hours, sig
        );
    }

    function test_executeTransfer_revertsOnZeroAmount() public {
        _delegateUser();

        bytes memory sig = _sign(address(token), recipient, 0, 0, 0, block.timestamp + 1 hours);

        vm.expectRevert(PayfromDelegate.InvalidAmount.selector);
        PayfromDelegate(payable(user)).executeTransfer(
            address(token), recipient, 0, 0, block.timestamp + 1 hours, sig
        );
    }

    function test_delegatedAccount_canReceivePlainNativeTransfer() public {
        _delegateUser();

        address sender = makeAddr("sender");
        vm.deal(sender, 1 ether);

        vm.prank(sender);
        (bool success,) = user.call{value: 1 ether}("");

        assertTrue(success);
        assertEq(user.balance, 1 ether);
    }

    function test_feeRecipient_isImmutableAcrossDelegatedAccounts() public {
        assertEq(delegateImpl.feeRecipient(), feeRecipient);

        _delegateUser();
        assertEq(PayfromDelegate(payable(user)).feeRecipient(), feeRecipient);
    }

    function test_nonce_isPerWalletStorage() public {
        _delegateUser();

        bytes memory sig = _sign(address(token), recipient, 10e6, 0, 0, block.timestamp + 1 hours);
        PayfromDelegate(payable(user)).executeTransfer(
            address(token), recipient, 10e6, 0, block.timestamp + 1 hours, sig
        );

        assertEq(PayfromDelegate(payable(user)).nonce(), 1);
        assertEq(delegateImpl.nonce(), 0);
    }
}
