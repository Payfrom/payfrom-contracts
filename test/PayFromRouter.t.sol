// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/PayFromRouter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract PayFromRouterTest is Test {
    PayFromRouter public router;
    MockUSDC public usdc;

    address public OWNER; // Declared as a state variable
    address feeWallet = address(0x1);
    address merchant = address(0x2);
    address buyer = address(0x3);
x
    function setUp() public {
        OWNER = address(this);

        usdc = new MockUSDC();
        router = new PayFromRouter(feeWallet, OWNER);
        
        usdc.mint(buyer, 10000e6);
    }

    function test_Pay() public {
        uint256 amount = 100e6;
        
        vm.startPrank(buyer);
        usdc.approve(address(router), amount);
        
        router.pay(
            bytes32("payment1"),
            address(usdc),
            amount,
            merchant
        );
        vm.stopPrank();

        assertEq(usdc.balanceOf(merchant), 99e6);
        assertEq(usdc.balanceOf(feeWallet), 1e6);
        assertEq(usdc.balanceOf(address(router)), 0);
    }

    function test_RevertInvalidMerchant() public {
        vm.startPrank(buyer);
        usdc.approve(address(router), 100e6);
        
        vm.expectRevert(PayFromRouter.InvalidMerchant.selector);
        router.pay(
            bytes32("payment1"),
            address(usdc),
            100e6,
            address(0)
        );
        vm.stopPrank();
    }
}
