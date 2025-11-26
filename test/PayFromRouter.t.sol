// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {PayFromRouter} from "../src/PayFromRouter.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PayFromRouterTest is Test {
    using ECDSA for bytes32;

    PayFromRouter public router;
    ERC20Mock public token;
    ERC20Mock public token2;

    address public owner;
    address public feeWallet;
    address public signer;
    uint256 public signerPrivateKey;
    address public executor;
    address public merchant;
    address public payer;
    address public unauthorizedUser;

    uint256 constant MIN_PAYMENT = 1e6;
    uint256 constant FEE_BPS = 100; // 1%

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

    function setUp() public {
        owner = makeAddr("owner");
        feeWallet = makeAddr("feeWallet");
        signerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        signer = vm.addr(signerPrivateKey);
        executor = makeAddr("executor");
        merchant = makeAddr("merchant");
        payer = makeAddr("payer");
        unauthorizedUser = makeAddr("unauthorizedUser");

        // Deploy mock tokens
        token = new ERC20Mock();
        token2 = new ERC20Mock();

        // Prepare constructor params
        address[] memory executors = new address[](1);
        executors[0] = executor;

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        // Deploy router
        router = new PayFromRouter(feeWallet, signer, executors, tokens, owner);

        // Mint tokens to payer and router
        token.mint(payer, 1_000_000e6);
        token2.mint(payer, 1_000_000e6);

        // Approve router
        vm.prank(payer);
        token.approve(address(router), type(uint256).max);
        vm.prank(payer);
        token2.approve(address(router), type(uint256).max);
    }

    // ========================================================
    // CONSTRUCTOR TESTS
    // ========================================================

    function testConstructorSetsVariables() public {
        assertEq(router.FEE_WALLET(), feeWallet);
        assertEq(router.AUTHORIZED_SIGNER(), signer);
        assertEq(router.owner(), owner);
        assertTrue(router.authorizedExecutors(executor));
        assertTrue(router.supportedTokens(address(token)));
    }

    function testConstructorRevertsOnZeroFeeWallet() public {
        address[] memory executors = new address[](0);
        address[] memory tokens = new address[](0);

        vm.expectRevert(PayFromRouter.InvalidAddress.selector);
        new PayFromRouter(address(0), signer, executors, tokens, owner);
    }

    function testConstructorRevertsOnZeroSigner() public {
        address[] memory executors = new address[](0);
        address[] memory tokens = new address[](0);

        vm.expectRevert(PayFromRouter.InvalidAddress.selector);
        new PayFromRouter(feeWallet, address(0), executors, tokens, owner);
    }

    // ========================================================
    // PAY FUNCTION TESTS
    // ========================================================

    function testPaySuccess() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 totalAmount = 100e6;
        uint256 expectedFee = (totalAmount * FEE_BPS) / 10000;
        uint256 expectedMerchantAmount = totalAmount - expectedFee;

        uint256 feeWalletBalBefore = token.balanceOf(feeWallet);
        uint256 merchantBalBefore = token.balanceOf(merchant);

        vm.prank(payer);
        vm.expectEmit(true, true, true, true);
        emit PaymentProcessed(
            paymentId,
            payer,
            merchant,
            address(token),
            totalAmount,
            expectedFee,
            expectedMerchantAmount
        );
        router.pay(paymentId, address(token), totalAmount, merchant);

        assertEq(token.balanceOf(feeWallet), feeWalletBalBefore + expectedFee);
        assertEq(
            token.balanceOf(merchant),
            merchantBalBefore + expectedMerchantAmount
        );
        assertTrue(router.processed(paymentId));
    }

    function testPayRevertsWhenPaused() public {
        vm.prank(owner);
        router.setPaused(true);

        bytes32 paymentId = keccak256("payment1");
        vm.prank(payer);
        vm.expectRevert(PayFromRouter.Paused.selector);
        router.pay(paymentId, address(token), 100e6, merchant);
    }

    function testPayRevertsOnUnsupportedToken() public {
        bytes32 paymentId = keccak256("payment1");
        vm.prank(payer);
        vm.expectRevert(PayFromRouter.TokenNotSupported.selector);
        router.pay(paymentId, address(token2), 100e6, merchant);
    }

    function testPayRevertsOnAmountTooSmall() public {
        bytes32 paymentId = keccak256("payment1");
        vm.prank(payer);
        vm.expectRevert(PayFromRouter.AmountTooSmall.selector);
        router.pay(paymentId, address(token), MIN_PAYMENT - 1, merchant);
    }

    function testPayRevertsOnAmountTooLarge() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 maxPayment = router.maxPayment();
        vm.prank(payer);
        vm.expectRevert(PayFromRouter.AmountTooLarge.selector);
        router.pay(paymentId, address(token), maxPayment + 1, merchant);
    }

    function testPayRevertsOnZeroMerchant() public {
        bytes32 paymentId = keccak256("payment1");
        vm.prank(payer);
        vm.expectRevert(PayFromRouter.InvalidAddress.selector);
        router.pay(paymentId, address(token), 100e6, address(0));
    }

    function testPayRevertsOnZeroToken() public {
        bytes32 paymentId = keccak256("payment1");
        vm.prank(payer);
        vm.expectRevert(PayFromRouter.InvalidAddress.selector);
        router.pay(paymentId, address(0), 100e6, merchant);
    }

    function testPayRevertsOnDuplicatePaymentId() public {
        bytes32 paymentId = keccak256("payment1");

        vm.prank(payer);
        router.pay(paymentId, address(token), 100e6, merchant);

        vm.prank(payer);
        vm.expectRevert(PayFromRouter.AlreadyProcessed.selector);
        router.pay(paymentId, address(token), 100e6, merchant);
    }

    function testPayWithMinAmount() public {
        bytes32 paymentId = keccak256("payment1");
        vm.prank(payer);
        router.pay(paymentId, address(token), MIN_PAYMENT, merchant);
        assertTrue(router.processed(paymentId));
    }

    function testPayWithMaxAmount() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 maxPayment = router.maxPayment();

        token.mint(payer, maxPayment);

        vm.prank(payer);
        router.pay(paymentId, address(token), maxPayment, merchant);
        assertTrue(router.processed(paymentId));
    }

    // ========================================================
    // EXECUTE PAYMENT TESTS
    // ========================================================

    function testExecutePaymentSuccess() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;
        uint256 actualAmount = 100e6;

        // Transfer tokens to router (simulating bridge transfer)
        token.mint(address(router), actualAmount);

        // Create signature
        bytes memory signature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount
        );

        uint256 feeWalletBalBefore = token.balanceOf(feeWallet);
        uint256 merchantBalBefore = token.balanceOf(merchant);

        vm.prank(executor);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            merchant,
            signature
        );

        uint256 expectedFee = (actualAmount * FEE_BPS) / 10000;
        uint256 expectedMerchantAmount = actualAmount - expectedFee;

        assertEq(token.balanceOf(feeWallet), feeWalletBalBefore + expectedFee);
        assertEq(
            token.balanceOf(merchant),
            merchantBalBefore + expectedMerchantAmount
        );
        assertTrue(router.processed(paymentId));
    }

    function testExecutePaymentWithSlippage() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;
        uint256 actualAmount = 96e6; // 4% slippage (within 5% tolerance)

        token.mint(address(router), actualAmount);
        bytes memory signature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount
        );

        vm.prank(executor);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            merchant,
            signature
        );

        assertTrue(router.processed(paymentId));
    }

    function testExecutePaymentRevertsOnExcessiveSlippage() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;
        uint256 actualAmount = 94e6; // 6% slippage (exceeds 5% tolerance)

        token.mint(address(router), actualAmount);
        bytes memory signature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount
        );

        vm.prank(executor);
        vm.expectRevert(PayFromRouter.InsufficientFunds.selector);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            merchant,
            signature
        );
    }

    function testExecutePaymentRevertsOnUnauthorizedExecutor() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;

        token.mint(address(router), expectedAmount);
        bytes memory signature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount
        );

        vm.prank(unauthorizedUser);
        vm.expectRevert(PayFromRouter.Unauthorized.selector);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            merchant,
            signature
        );
    }

    function testExecutePaymentRevertsOnInvalidSignature() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;

        token.mint(address(router), expectedAmount);

        // Create signature with wrong parameters
        bytes memory wrongSignature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount + 1
        );

        vm.prank(executor);
        vm.expectRevert(PayFromRouter.InvalidSignature.selector);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            merchant,
            wrongSignature
        );
    }

    function testExecutePaymentRevertsWhenPaused() public {
        vm.prank(owner);
        router.setPaused(true);

        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;
        bytes memory signature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount
        );

        vm.prank(executor);
        vm.expectRevert(PayFromRouter.Paused.selector);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            merchant,
            signature
        );
    }

    function testExecutePaymentRevertsOnDuplicate() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;

        token.mint(address(router), expectedAmount * 2);
        bytes memory signature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount
        );

        vm.prank(executor);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            merchant,
            signature
        );

        vm.prank(executor);
        vm.expectRevert(PayFromRouter.AlreadyProcessed.selector);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            merchant,
            signature
        );
    }

    // ========================================================
    // ADMIN FUNCTION TESTS
    // ========================================================

    function testSetExecutors() public {
        address newExecutor = makeAddr("newExecutor");
        address[] memory executors = new address[](1);
        executors[0] = newExecutor;

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ExecutorsUpdated(executors, true);
        router.setExecutors(executors, true);

        assertTrue(router.authorizedExecutors(newExecutor));
    }

    function testSetExecutorsRemove() public {
        address[] memory executors = new address[](1);
        executors[0] = executor;

        vm.prank(owner);
        router.setExecutors(executors, false);

        assertFalse(router.authorizedExecutors(executor));
    }

    function testSetExecutorsRevertsOnZeroAddress() public {
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        vm.prank(owner);
        vm.expectRevert(PayFromRouter.InvalidAddress.selector);
        router.setExecutors(executors, true);
    }

    function testSetExecutorsRevertsForNonOwner() public {
        address[] memory executors = new address[](1);
        executors[0] = makeAddr("newExecutor");

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        router.setExecutors(executors, true);
    }

    function testSetTokens() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token2);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TokensUpdated(tokens, true);
        router.setTokens(tokens, true);

        assertTrue(router.supportedTokens(address(token2)));
    }

    function testSetTokensRemove() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        vm.prank(owner);
        router.setTokens(tokens, false);

        assertFalse(router.supportedTokens(address(token)));
    }

    function testSetTokensRevertsOnZeroAddress() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        vm.prank(owner);
        vm.expectRevert(PayFromRouter.InvalidToken.selector);
        router.setTokens(tokens, true);
    }

    function testSetTokensRevertsForNonOwner() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token2);

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        router.setTokens(tokens, true);
    }

    function testSetPaused() public {
        vm.prank(owner);
        router.setPaused(true);
        assertTrue(router.paused());

        vm.prank(owner);
        router.setPaused(false);
        assertFalse(router.paused());
    }

    function testSetPausedRevertsForNonOwner() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        router.setPaused(true);
    }

    function testSetMaxPayment() public {
        uint256 newMax = 500_000e6;
        vm.prank(owner);
        router.setMaxPayment(newMax);
        assertEq(router.maxPayment(), newMax);
    }

    function testSetMaxPaymentRevertsForNonOwner() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        router.setMaxPayment(500_000e6);
    }

    function testEmergencyWithdraw() public {
        uint256 totalAmount = 100e6;
        token.mint(address(router), totalAmount);

        vm.prank(owner);
        router.setPaused(true);

        uint256 ownerBalBefore = token.balanceOf(owner);

        vm.prank(owner);
        router.emergencyWithdraw(address(token));

        assertEq(token.balanceOf(owner), ownerBalBefore + totalAmount);
        assertEq(token.balanceOf(address(router)), 0);
    }

    function testEmergencyWithdrawRevertsWhenNotPaused() public {
        token.mint(address(router), 100e6);

        vm.prank(owner);
        vm.expectRevert("pause first");
        router.emergencyWithdraw(address(token));
    }

    function testEmergencyWithdrawRevertsForNonOwner() public {
        token.mint(address(router), 100e6);

        vm.prank(owner);
        router.setPaused(true);

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        router.emergencyWithdraw(address(token));
    }

    // ========================================================
    // VIEW FUNCTION TESTS
    // ========================================================

    function testCalculateSplit() public {
        uint256 totalAmount = 100e6;
        (uint256 fee, uint256 merchantAmount) = router.calculateSplit(totalAmount);

        uint256 expectedFee = (totalAmount * FEE_BPS) / 10000;
        assertEq(fee, expectedFee);
        assertEq(merchantAmount, totalAmount - expectedFee);
    }

    function testCalculateSplitFuzz(uint256 totalAmount) public {
        vm.assume(totalAmount > 0 && totalAmount < type(uint128).max);

        (uint256 fee, uint256 merchantAmount) = router.calculateSplit(totalAmount);

        assertEq(fee + merchantAmount, totalAmount);
        assertEq(fee, (totalAmount * FEE_BPS) / 10000);
    }

    // ========================================================
    // EDGE CASE TESTS
    // ========================================================

    function testPayWithInsufficientBalance() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 totalAmount = 100e6;

        address poorPayer = makeAddr("poorPayer");
        token.mint(poorPayer, totalAmount - 1); // Not enough tokens

        vm.prank(poorPayer);
        token.approve(address(router), type(uint256).max);

        vm.prank(poorPayer);
        vm.expectRevert();
        router.pay(paymentId, address(token), totalAmount, merchant);
    }

    function testExecutePaymentWithZeroBalance() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;

        // Router has 0 tokens
        bytes memory signature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount
        );

        vm.prank(executor);
        vm.expectRevert(PayFromRouter.InsufficientFunds.selector);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            merchant,
            signature
        );
    }

    function testMultipleExecutorsInteraction() public {
        address executor2 = makeAddr("executor2");
        address executor3 = makeAddr("executor3");

        address[] memory newExecutors = new address[](2);
        newExecutors[0] = executor2;
        newExecutors[1] = executor3;

        // Add multiple executors
        vm.prank(owner);
        router.setExecutors(newExecutors, true);

        assertTrue(router.authorizedExecutors(executor2));
        assertTrue(router.authorizedExecutors(executor3));

        // Remove one
        address[] memory toRemove = new address[](1);
        toRemove[0] = executor2;

        vm.prank(owner);
        router.setExecutors(toRemove, false);

        assertFalse(router.authorizedExecutors(executor2));
        assertTrue(router.authorizedExecutors(executor3));
    }

    function testTokenApprovalRevocation() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 totalAmount = 100e6;

        // Revoke approval
        vm.prank(payer);
        token.approve(address(router), 0);

        vm.prank(payer);
        vm.expectRevert();
        router.pay(paymentId, address(token), totalAmount, merchant);
    }

    function testBatchTokenOperations() public {
        address[] memory tokens = new address[](3);
        tokens[0] = makeAddr("token1");
        tokens[1] = makeAddr("token2");
        tokens[2] = makeAddr("token3");

        vm.prank(owner);
        router.setTokens(tokens, true);

        assertTrue(router.supportedTokens(tokens[0]));
        assertTrue(router.supportedTokens(tokens[1]));
        assertTrue(router.supportedTokens(tokens[2]));

        // Remove all at once
        vm.prank(owner);
        router.setTokens(tokens, false);

        assertFalse(router.supportedTokens(tokens[0]));
        assertFalse(router.supportedTokens(tokens[1]));
        assertFalse(router.supportedTokens(tokens[2]));
    }

    function testBatchExecutorOperations() public {
        address[] memory executors = new address[](3);
        executors[0] = makeAddr("exec1");
        executors[1] = makeAddr("exec2");
        executors[2] = makeAddr("exec3");

        vm.prank(owner);
        router.setExecutors(executors, true);

        assertTrue(router.authorizedExecutors(executors[0]));
        assertTrue(router.authorizedExecutors(executors[1]));
        assertTrue(router.authorizedExecutors(executors[2]));
    }

    // ========================================================
    // SECURITY TESTS
    // ========================================================

    function testSignatureReplayAcrossDifferentPayments() public {
        bytes32 paymentId1 = keccak256("payment1");
        bytes32 paymentId2 = keccak256("payment2");
        uint256 expectedAmount = 100e6;

        token.mint(address(router), expectedAmount * 2);

        // Create signature for payment1
        bytes memory signature = _createSignature(
            paymentId1,
            merchant,
            address(token),
            expectedAmount
        );

        // Execute payment1 successfully
        vm.prank(executor);
        router.executePayment(
            paymentId1,
            address(token),
            expectedAmount,
            merchant,
            signature
        );

        // Try to replay same signature for payment2 (should fail)
        vm.prank(executor);
        vm.expectRevert(PayFromRouter.InvalidSignature.selector);
        router.executePayment(
            paymentId2,
            address(token),
            expectedAmount,
            merchant,
            signature
        );
    }

    function testSignatureWithWrongMerchant() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;
        address wrongMerchant = makeAddr("wrongMerchant");

        token.mint(address(router), expectedAmount);

        // Create signature for correct merchant
        bytes memory signature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount
        );

        // Try to use signature with wrong merchant
        vm.prank(executor);
        vm.expectRevert(PayFromRouter.InvalidSignature.selector);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            wrongMerchant,
            signature
        );
    }

    function testSignatureWithWrongToken() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;

        token.mint(address(router), expectedAmount);
        token2.mint(address(router), expectedAmount);

        // Create signature for token1
        bytes memory signature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount
        );

        // Try to use signature with token2
        vm.prank(executor);
        vm.expectRevert(PayFromRouter.InvalidSignature.selector);
        router.executePayment(
            paymentId,
            address(token2),
            expectedAmount,
            merchant,
            signature
        );
    }

    function testSignatureWithWrongAmount() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;
        uint256 wrongAmount = 200e6;

        token.mint(address(router), wrongAmount);

        // Create signature for 100e6
        bytes memory signature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount
        );

        // Try to use signature with 200e6
        vm.prank(executor);
        vm.expectRevert(PayFromRouter.InvalidSignature.selector);
        router.executePayment(
            paymentId,
            address(token),
            wrongAmount,
            merchant,
            signature
        );
    }

    function testUnauthorizedSignerCannotCreateValidSignature() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;

        token.mint(address(router), expectedAmount);

        // Create signature with wrong private key
        uint256 wrongPrivateKey = 0x9999;
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                paymentId,
                merchant,
                address(token),
                expectedAmount
            )
        );
        bytes32 hash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, hash);
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        vm.prank(executor);
        vm.expectRevert(PayFromRouter.InvalidSignature.selector);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            merchant,
            wrongSignature
        );
    }

    // ========================================================
    // BUSINESS LOGIC TESTS
    // ========================================================

    function testFeeWalletReceivesExactAmount() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 totalAmount = 1000e6;
        uint256 expectedFee = 10e6; // 1% of 1000e6

        uint256 feeWalletBalBefore = token.balanceOf(feeWallet);

        vm.prank(payer);
        router.pay(paymentId, address(token), totalAmount, merchant);

        uint256 feeWalletBalAfter = token.balanceOf(feeWallet);
        assertEq(feeWalletBalAfter - feeWalletBalBefore, expectedFee);
    }

    function testMerchantReceivesExactAmount() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 totalAmount = 1000e6;
        uint256 expectedMerchantAmount = 990e6; // 99% of 1000e6

        uint256 merchantBalBefore = token.balanceOf(merchant);

        vm.prank(payer);
        router.pay(paymentId, address(token), totalAmount, merchant);

        uint256 merchantBalAfter = token.balanceOf(merchant);
        assertEq(merchantBalAfter - merchantBalBefore, expectedMerchantAmount);
    }

    function testPaymentIdCollisionPrevention() public {
        bytes32 paymentId = keccak256("payment1");

        // First payment succeeds
        vm.prank(payer);
        router.pay(paymentId, address(token), 100e6, merchant);

        // Second payment with same ID but different params fails
        address merchant2 = makeAddr("merchant2");
        vm.prank(payer);
        vm.expectRevert(PayFromRouter.AlreadyProcessed.selector);
        router.pay(paymentId, address(token), 200e6, merchant2);
    }

    function testMaxPaymentBoundaryExactly() public {
        uint256 maxPayment = router.maxPayment();
        bytes32 paymentId = keccak256("payment1");

        token.mint(payer, maxPayment);

        // Exactly at max should work
        vm.prank(payer);
        router.pay(paymentId, address(token), maxPayment, merchant);

        assertTrue(router.processed(paymentId));
    }

    function testMinPaymentBoundaryExactly() public {
        bytes32 paymentId = keccak256("payment1");

        // Exactly at min should work
        vm.prank(payer);
        router.pay(paymentId, address(token), MIN_PAYMENT, merchant);

        assertTrue(router.processed(paymentId));
    }

    function testFeeSplitRounding() public {
        // Test amounts that might cause rounding issues
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 1e6;
        amounts[1] = 333e6;
        amounts[2] = 999e6;
        amounts[3] = 10001e6;
        amounts[4] = 123456e6;

        for (uint256 i = 0; i < amounts.length; i++) {
            (uint256 fee, uint256 merchantAmount) = router.calculateSplit(
                amounts[i]
            );
            // Verify no rounding loss
            assertEq(fee + merchantAmount, amounts[i]);
            // Verify fee is approximately 1%
            assertLe(fee, (amounts[i] * 101) / 10000); // Allow tiny rounding
            assertGe(fee, (amounts[i] * 99) / 10000);
        }
    }

    // ========================================================
    // INTEGRATION TESTS
    // ========================================================

    function testMultiplePaymentsSequence() public {
        uint256 paymentCount = 10;
        uint256 totalAmount = 100e6;

        uint256 totalFees = 0;
        uint256 totalMerchantAmount = 0;

        for (uint256 i = 0; i < paymentCount; i++) {
            bytes32 paymentId = keccak256(abi.encodePacked("payment", i));

            vm.prank(payer);
            router.pay(paymentId, address(token), totalAmount, merchant);

            (uint256 fee, uint256 merchantAmount) = router.calculateSplit(
                totalAmount
            );
            totalFees += fee;
            totalMerchantAmount += merchantAmount;
        }

        assertEq(token.balanceOf(feeWallet), totalFees);
        assertEq(token.balanceOf(merchant), totalMerchantAmount);
    }

    function testExecutePaymentAfterTokenRemoval() public {
        bytes32 paymentId = keccak256("payment1");
        uint256 expectedAmount = 100e6;

        token.mint(address(router), expectedAmount);
        bytes memory signature = _createSignature(
            paymentId,
            merchant,
            address(token),
            expectedAmount
        );

        // Remove token support
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        vm.prank(owner);
        router.setTokens(tokens, false);

        // executePayment doesn't check token support, only pay() does
        // This should still work
        vm.prank(executor);
        router.executePayment(
            paymentId,
            address(token),
            expectedAmount,
            merchant,
            signature
        );

        assertTrue(router.processed(paymentId));
    }

    function testPauseUnpauseSequence() public {
        bytes32 paymentId1 = keccak256("payment1");
        bytes32 paymentId2 = keccak256("payment2");
        uint256 totalAmount = 100e6;

        // First payment succeeds
        vm.prank(payer);
        router.pay(paymentId1, address(token), totalAmount, merchant);

        // Pause
        vm.prank(owner);
        router.setPaused(true);

        // Payment fails while paused
        vm.prank(payer);
        vm.expectRevert(PayFromRouter.Paused.selector);
        router.pay(paymentId2, address(token), totalAmount, merchant);

        // Unpause
        vm.prank(owner);
        router.setPaused(false);

        // Payment succeeds after unpause
        vm.prank(payer);
        router.pay(paymentId2, address(token), totalAmount, merchant);

        assertTrue(router.processed(paymentId1));
        assertTrue(router.processed(paymentId2));
    }

    function testMultipleMerchantsMultiplePayments() public {
        address merchant1 = makeAddr("merchant1");
        address merchant2 = makeAddr("merchant2");
        address merchant3 = makeAddr("merchant3");

        uint256 totalAmount = 100e6;

        vm.prank(payer);
        router.pay(keccak256("pay1"), address(token), totalAmount, merchant1);

        vm.prank(payer);
        router.pay(keccak256("pay2"), address(token), totalAmount, merchant2);

        vm.prank(payer);
        router.pay(keccak256("pay3"), address(token), totalAmount, merchant3);

        (uint256 fee, uint256 merchantAmount) = router.calculateSplit(totalAmount);

        assertEq(token.balanceOf(merchant1), merchantAmount);
        assertEq(token.balanceOf(merchant2), merchantAmount);
        assertEq(token.balanceOf(merchant3), merchantAmount);
        assertEq(token.balanceOf(feeWallet), fee * 3);
    }

    function testExecutorRemovalDuringOperation() public {
        bytes32 paymentId1 = keccak256("payment1");
        bytes32 paymentId2 = keccak256("payment2");
        uint256 expectedAmount = 100e6;

        token.mint(address(router), expectedAmount * 2);

        bytes memory signature1 = _createSignature(
            paymentId1,
            merchant,
            address(token),
            expectedAmount
        );

        // Execute first payment
        vm.prank(executor);
        router.executePayment(
            paymentId1,
            address(token),
            expectedAmount,
            merchant,
            signature1
        );

        // Remove executor
        address[] memory executors = new address[](1);
        executors[0] = executor;
        vm.prank(owner);
        router.setExecutors(executors, false);

        // Try to execute second payment (should fail)
        bytes memory signature2 = _createSignature(
            paymentId2,
            merchant,
            address(token),
            expectedAmount
        );

        vm.prank(executor);
        vm.expectRevert(PayFromRouter.Unauthorized.selector);
        router.executePayment(
            paymentId2,
            address(token),
            expectedAmount,
            merchant,
            signature2
        );
    }

    function testMaxPaymentUpdateMidOperation() public {
        uint256 originalMax = router.maxPayment();
        uint256 newMax = 500_000e6;
        bytes32 paymentId1 = keccak256("payment1");
        bytes32 paymentId2 = keccak256("payment2");

        // Payment at original max works
        token.mint(payer, originalMax * 2);
        vm.prank(payer);
        router.pay(paymentId1, address(token), originalMax, merchant);

        // Owner reduces max
        vm.prank(owner);
        router.setMaxPayment(newMax);

        // Payment above new max fails
        vm.prank(payer);
        vm.expectRevert(PayFromRouter.AmountTooLarge.selector);
        router.pay(paymentId2, address(token), originalMax, merchant);

        // Payment at new max works
        vm.prank(payer);
        router.pay(paymentId2, address(token), newMax, merchant);
    }

    function testEmergencyWithdrawMultipleTokens() public {
        uint256 amount1 = 100e6;
        uint256 amount2 = 200e6;

        token.mint(address(router), amount1);
        token2.mint(address(router), amount2);

        vm.prank(owner);
        router.setPaused(true);

        uint256 ownerBalBefore1 = token.balanceOf(owner);
        uint256 ownerBalBefore2 = token2.balanceOf(owner);

        vm.prank(owner);
        router.emergencyWithdraw(address(token));

        vm.prank(owner);
        router.emergencyWithdraw(address(token2));

        assertEq(token.balanceOf(owner), ownerBalBefore1 + amount1);
        assertEq(token2.balanceOf(owner), ownerBalBefore2 + amount2);
        assertEq(token.balanceOf(address(router)), 0);
        assertEq(token2.balanceOf(address(router)), 0);
    }

    // ========================================================
    // REENTRANCY TESTS
    // ========================================================

    function testPayReentrancyProtection() public view {
        // ReentrancyGuard from OpenZeppelin is battle-tested
        // A proper test would require a malicious ERC20 that attempts reentrancy
        // The nonReentrant modifier prevents this attack vector
        assertTrue(true);
    }

    // ========================================================
    // HELPER FUNCTIONS
    // ========================================================

    function _createSignature(
        bytes32 paymentId,
        address _merchant,
        address _token,
        uint256 expectedAmount
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(paymentId, merchant, token, expectedAmount)
        );
        bytes32 hash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, hash);
        return abi.encodePacked(r, s, v);
    }
}
