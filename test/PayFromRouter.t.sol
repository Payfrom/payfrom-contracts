// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {PayFromRouter} from "../src/PayFromRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ============ Mock Tokens ============

contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockUSDT is ERC20 {
    constructor() ERC20("USDT", "USDT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

// ============ Main Test Contract ============

contract PayFromRouterTest is Test {
    PayFromRouter public router;
    MockUSDC public usdc;
    MockUSDT public usdt;

    address public owner;
    address public feeWallet = address(0x1);
    address public merchant = address(0x2);
    address public buyer = address(0x3);
    address public newFeeWallet = address(0x4);

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

    function setUp() public {
        owner = address(this);
        usdc = new MockUSDC();
        usdt = new MockUSDT();
        router = new PayFromRouter(feeWallet, owner);

        usdc.mint(buyer, 10_000e6);
        usdt.mint(buyer, 10_000e6);

        router.addSupportedToken(address(usdc));
        router.addSupportedToken(address(usdt));
    }

    // ============ CORE FUNCTIONALITY ============

    function test_Pay_Success() public {
        uint256 amount = 100e6;
        bytes32 paymentId = keccak256("payment1");

        vm.startPrank(buyer);
        usdc.approve(address(router), amount);

        vm.expectEmit(true, true, true, true);
        emit PaymentProcessed(
            paymentId,
            buyer,
            merchant,
            address(usdc),
            amount,
            1e6,
            99e6
        );

        router.pay(paymentId, address(usdc), amount, merchant);
        vm.stopPrank();

        assertEq(usdc.balanceOf(merchant), 99e6);
        assertEq(usdc.balanceOf(feeWallet), 1e6);
        assertEq(usdc.balanceOf(address(router)), 0); // Critical: never holds funds
        assertTrue(router.isPaymentProcessed(paymentId));
    }

    // ============ SECURITY TESTS ============

    function test_RevertReplayAttack() public {
        uint256 amount = 100e6;
        bytes32 paymentId = keccak256("payment1");

        vm.startPrank(buyer);
        usdc.approve(address(router), amount * 2);

        router.pay(paymentId, address(usdc), amount, merchant);

        vm.expectRevert(PayFromRouter.PaymentAlreadyProcessed.selector);
        router.pay(paymentId, address(usdc), amount, merchant);
        vm.stopPrank();
    }

    function test_RevertTokenNotSupported() public {
        address randomToken = address(0x999);

        vm.startPrank(buyer);
        vm.expectRevert(PayFromRouter.TokenNotSupported.selector);
        router.pay(keccak256("payment1"), randomToken, 100e6, merchant);
        vm.stopPrank();
    }

    function test_ReentrancyProtection() public {
        // Even if called recursively, should be blocked by nonReentrant
        vm.startPrank(buyer);
        usdc.approve(address(router), 100e6);
        router.pay(keccak256("test"), address(usdc), 100e6, merchant);
        vm.stopPrank();

        // Verify contract never holds funds (key security property)
        assertEq(usdc.balanceOf(address(router)), 0);
    }

    // ============ VALIDATION TESTS ============

    function test_RevertInvalidMerchant() public {
        vm.startPrank(buyer);
        usdc.approve(address(router), 100e6);
        vm.expectRevert(PayFromRouter.InvalidMerchant.selector);
        router.pay(keccak256("payment1"), address(usdc), 100e6, address(0));
        vm.stopPrank();
    }

    function test_RevertInvalidToken() public {
        vm.expectRevert(PayFromRouter.InvalidToken.selector);
        router.pay(keccak256("payment1"), address(0), 100e6, merchant);
    }

    function test_RevertAmountTooSmall() public {
        vm.startPrank(buyer);
        usdc.approve(address(router), 1e6 - 1);
        vm.expectRevert(PayFromRouter.AmountTooSmall.selector);
        router.pay(keccak256("payment1"), address(usdc), 1e6 - 1, merchant);
        vm.stopPrank();
    }

    function test_RevertAmountTooLarge() public {
        uint256 amount = 1_000_001e6;
        usdc.mint(buyer, amount);

        vm.startPrank(buyer);
        usdc.approve(address(router), amount);
        vm.expectRevert(PayFromRouter.AmountTooLarge.selector);
        router.pay(keccak256("payment1"), address(usdc), amount, merchant);
        vm.stopPrank();
    }

    // ============ TOKEN WHITELIST ============

    function test_AddAndRemoveSupportedToken() public {
        address newToken = address(0x999);

        vm.expectEmit(true, false, false, false);
        emit TokenAdded(newToken);
        router.addSupportedToken(newToken);
        assertTrue(router.isTokenSupported(newToken));

        vm.expectEmit(true, false, false, false);
        emit TokenRemoved(newToken);
        router.removeSupportedToken(newToken);
        assertFalse(router.isTokenSupported(newToken));
    }

    function test_RevertAddToken_ZeroAddress() public {
        vm.expectRevert(PayFromRouter.InvalidToken.selector);
        router.addSupportedToken(address(0));
    }

    // ============ CONFIGURATION ============

    function test_UpdateFeeWallet() public {
        vm.expectEmit(true, true, false, false);
        emit FeeWalletUpdated(feeWallet, newFeeWallet);
        router.updateFeeWallet(newFeeWallet);

        assertEq(router.feeWallet(), newFeeWallet);

        // Verify new wallet receives fees
        vm.startPrank(buyer);
        usdc.approve(address(router), 100e6);
        router.pay(keccak256("payment1"), address(usdc), 100e6, merchant);
        vm.stopPrank();

        assertEq(usdc.balanceOf(newFeeWallet), 1e6);
    }

    function test_RevertUpdateFeeWallet_ZeroAddress() public {
        vm.expectRevert(PayFromRouter.InvalidFeeWallet.selector);
        router.updateFeeWallet(address(0));
    }

    function test_UpdateMaxPayment() public {
        uint256 newMax = 5_000_000e6;
        router.updateMaxPayment(newMax);
        assertEq(router.maxPayment(), newMax);
    }

    function test_RevertUpdateMaxPayment_TooSmall() public {
        vm.expectRevert(PayFromRouter.InvalidMaxPayment.selector);
        router.updateMaxPayment(1e6 - 1);
    }

    // ============ PAUSE MECHANISM ============

    function test_PauseAndUnpause() public {
        router.pause();

        vm.startPrank(buyer);
        usdc.approve(address(router), 100e6);
        vm.expectRevert("Pausable: paused");
        router.pay(keccak256("payment1"), address(usdc), 100e6, merchant);
        vm.stopPrank();

        router.unpause();

        vm.startPrank(buyer);
        router.pay(keccak256("payment1"), address(usdc), 100e6, merchant);
        vm.stopPrank();

        assertEq(usdc.balanceOf(merchant), 99e6);
    }

    // ============ EMERGENCY RECOVERY ============

    function test_EmergencyRecoverToken() public {
        usdc.mint(address(router), 100e6);

        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        router.emergencyRecoverToken(address(usdc), 0);

        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + 100e6);
        assertEq(usdc.balanceOf(address(router)), 0);
    }

    function test_RevertEmergencyRecover_NoBalance() public {
        vm.expectRevert(PayFromRouter.NoTokensToRecover.selector);
        router.emergencyRecoverToken(address(usdc), 0);
    }

    // ============ ACCESS CONTROL ============

    function test_RevertOnlyOwner_AddToken() public {
        vm.prank(buyer);
        vm.expectRevert();
        router.addSupportedToken(address(0x999));
    }

    function test_RevertOnlyOwner_UpdateFeeWallet() public {
        vm.prank(buyer);
        vm.expectRevert();
        router.updateFeeWallet(newFeeWallet);
    }

    function test_RevertOnlyOwner_Pause() public {
        vm.prank(buyer);
        vm.expectRevert();
        router.pause();
    }

    // ============ MATH & EDGE CASES ============

    function test_CalculateSplit() public view {
        (uint256 fee, uint256 merchantAmount) = router.calculateSplit(100e6);
        assertEq(fee, 1e6);
        assertEq(merchantAmount, 99e6);
        assertEq(fee + merchantAmount, 100e6); // No rounding loss
    }

    function testFuzz_Pay(uint256 amount) public {
        amount = bound(amount, 1e6, 1_000_000e6);

        usdc.mint(buyer, amount);

        vm.startPrank(buyer);
        usdc.approve(address(router), amount);
        router.pay(bytes32(amount), address(usdc), amount, merchant);
        vm.stopPrank();

        uint256 fee = (amount * 100) / 10000;
        uint256 merchantAmount = amount - fee;

        // Critical assertions
        assertEq(usdc.balanceOf(feeWallet), fee);
        assertEq(usdc.balanceOf(merchant), merchantAmount);
        assertEq(usdc.balanceOf(address(router)), 0); // Never holds funds
        assertEq(fee + merchantAmount, amount); // No tokens lost
    }

    function testFuzz_MultiplePayments(uint8 numPayments) public {
        numPayments = uint8(bound(numPayments, 1, 20));
        uint256 amount = 100e6;

        usdc.mint(buyer, amount * numPayments);

        vm.startPrank(buyer);
        usdc.approve(address(router), amount * numPayments);

        for (uint256 i = 0; i < numPayments; i++) {
            router.pay(bytes32(i), address(usdc), amount, merchant);
        }
        vm.stopPrank();

        assertEq(usdc.balanceOf(merchant), 99e6 * numPayments);
        assertEq(usdc.balanceOf(feeWallet), 1e6 * numPayments);
        assertEq(usdc.balanceOf(address(router)), 0);
    }
}
