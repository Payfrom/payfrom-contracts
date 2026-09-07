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
        delegateImpl = new PayfromDelegate();

        token.mint(user, 1_000e6);
    }

    function _delegateUser() internal {
        vm.signAndAttachDelegation(address(delegateImpl), userPrivateKey);
    }

    function _sign(
        PayfromDelegate.Call[] memory calls,
        uint256 nonce_,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encode(user, block.chainid, calls, nonce_, deadline));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _transferCall(address to, uint256 amount) internal view returns (PayfromDelegate.Call memory) {
        return PayfromDelegate.Call({
            target: address(token),
            value: 0,
            data: abi.encodeCall(token.transfer, (to, amount))
        });
    }

    function test_executeOps_movesUserBalance() public {
        _delegateUser();

        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](2);
        calls[0] = _transferCall(recipient, 100e6);
        calls[1] = _transferCall(feeRecipient, 1e6);
        bytes memory sig = _sign(calls, 0, block.timestamp + 1 hours);

        vm.prank(relayer);
        PayfromDelegate(payable(user)).executeOps(calls, block.timestamp + 1 hours, sig);

        assertEq(token.balanceOf(user), 899e6);
        assertEq(token.balanceOf(recipient), 100e6);
        assertEq(token.balanceOf(feeRecipient), 1e6);
    }

    function test_executeOps_anyoneCanSubmitAValidlySignedOp() public {
        _delegateUser();

        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](1);
        calls[0] = _transferCall(recipient, 100e6);
        bytes memory sig = _sign(calls, 0, block.timestamp + 1 hours);

        // A completely unrelated, untrusted address submits it - still works,
        // because authorization comes from the signature, not the caller.
        vm.prank(makeAddr("randomSubmitter"));
        PayfromDelegate(payable(user)).executeOps(calls, block.timestamp + 1 hours, sig);

        assertEq(token.balanceOf(recipient), 100e6);
    }

    function test_executeOps_runsAllCallsAtomically() public {
        _delegateUser();

        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](2);
        calls[0] = PayfromDelegate.Call({
            target: address(token),
            value: 0,
            data: abi.encodeCall(token.approve, (recipient, 100e6))
        });
        calls[1] = _transferCall(recipient, 100e6);
        bytes memory sig = _sign(calls, 0, block.timestamp + 1 hours);

        PayfromDelegate(payable(user)).executeOps(calls, block.timestamp + 1 hours, sig);

        assertEq(token.balanceOf(user), 900e6);
        assertEq(token.balanceOf(recipient), 100e6);
        // approve() and transfer() are independent ops - plain transfer()
        // never touches the allowance approve() set (unlike transferFrom()).
        assertEq(token.allowance(user, recipient), 100e6);
    }

    function test_executeOps_revertsWholeBatchIfOneCallFails() public {
        _delegateUser();

        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](2);
        calls[0] = PayfromDelegate.Call({
            target: address(token),
            value: 0,
            data: abi.encodeCall(token.approve, (recipient, 10_000e6))
        });
        // Transfer more than the wallet holds - must revert, taking the
        // approve above down with it.
        calls[1] = _transferCall(recipient, 10_000e6);
        bytes memory sig = _sign(calls, 0, block.timestamp + 1 hours);

        // Exact CallFailed(index, reason) payload is covered separately by
        // test_executeOps_callFailed_carriesUnderlyingRevertReason.
        vm.expectRevert();
        PayfromDelegate(payable(user)).executeOps(calls, block.timestamp + 1 hours, sig);

        assertEq(token.allowance(user, recipient), 0);
    }

    function test_executeOps_callFailed_carriesUnderlyingRevertReason() public {
        _delegateUser();

        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](1);
        calls[0] = _transferCall(recipient, 10_000e6);
        bytes memory sig = _sign(calls, 0, block.timestamp + 1 hours);

        bytes memory returndata = _callAndCaptureRevert(calls, sig);

        (uint256 index, bytes memory reason) = abi.decode(
            _stripSelector(returndata), (uint256, bytes)
        );
        assertEq(index, 0);
        assertGt(reason.length, 0);
    }

    function _callAndCaptureRevert(
        PayfromDelegate.Call[] memory calls,
        bytes memory sig
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = address(uint160(user)).call(
            abi.encodeCall(PayfromDelegate.executeOps, (calls, block.timestamp + 1 hours, sig))
        );
        assertFalse(success);
        return returndata;
    }

    function _stripSelector(bytes memory data) internal pure returns (bytes memory result) {
        result = new bytes(data.length - 4);
        for (uint256 i = 4; i < data.length; i++) {
            result[i - 4] = data[i];
        }
    }

    function test_executeOps_revertsForWrongSigner() public {
        _delegateUser();

        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](1);
        calls[0] = _transferCall(recipient, 100e6);
        bytes32 digest = keccak256(abi.encode(user, block.chainid, calls, uint256(0), block.timestamp + 1 hours));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xbad, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert(PayfromDelegate.InvalidSignature.selector);
        PayfromDelegate(payable(user)).executeOps(calls, block.timestamp + 1 hours, badSig);
    }

    function test_executeOps_revertsOnReplay() public {
        _delegateUser();

        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](1);
        calls[0] = _transferCall(recipient, 50e6);
        bytes memory sig = _sign(calls, 0, block.timestamp + 1 hours);

        PayfromDelegate(payable(user)).executeOps(calls, block.timestamp + 1 hours, sig);

        vm.expectRevert(PayfromDelegate.InvalidSignature.selector);
        PayfromDelegate(payable(user)).executeOps(calls, block.timestamp + 1 hours, sig);
    }

    function test_executeOps_revertsWhenExpired() public {
        _delegateUser();

        uint256 deadline = block.timestamp + 1 hours;
        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](1);
        calls[0] = _transferCall(recipient, 100e6);
        bytes memory sig = _sign(calls, 0, deadline);

        vm.warp(deadline + 1);

        vm.expectRevert(PayfromDelegate.Expired.selector);
        PayfromDelegate(payable(user)).executeOps(calls, deadline, sig);
    }

    function test_executeOps_revertsOnEmptyBatch() public {
        _delegateUser();

        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](0);
        bytes memory sig = _sign(calls, 0, block.timestamp + 1 hours);

        vm.expectRevert(PayfromDelegate.EmptyBatch.selector);
        PayfromDelegate(payable(user)).executeOps(calls, block.timestamp + 1 hours, sig);
    }

    function test_executeOps_revertsWhenCallTargetsSelf() public {
        _delegateUser();

        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](1);
        calls[0] = PayfromDelegate.Call({target: user, value: 0, data: ""});
        bytes memory sig = _sign(calls, 0, block.timestamp + 1 hours);

        vm.expectRevert(PayfromDelegate.InvalidAddress.selector);
        PayfromDelegate(payable(user)).executeOps(calls, block.timestamp + 1 hours, sig);
    }

    function test_executeOps_revertsWhenCallTargetsZeroAddress() public {
        _delegateUser();

        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](1);
        calls[0] = PayfromDelegate.Call({target: address(0), value: 0, data: ""});
        bytes memory sig = _sign(calls, 0, block.timestamp + 1 hours);

        vm.expectRevert(PayfromDelegate.InvalidAddress.selector);
        PayfromDelegate(payable(user)).executeOps(calls, block.timestamp + 1 hours, sig);
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

    function test_nonce_isPerWalletStorage() public {
        _delegateUser();

        PayfromDelegate.Call[] memory calls = new PayfromDelegate.Call[](1);
        calls[0] = _transferCall(recipient, 10e6);
        bytes memory sig = _sign(calls, 0, block.timestamp + 1 hours);
        PayfromDelegate(payable(user)).executeOps(calls, block.timestamp + 1 hours, sig);

        assertEq(PayfromDelegate(payable(user)).nonce(), 1);
        assertEq(delegateImpl.nonce(), 0);
    }
}
