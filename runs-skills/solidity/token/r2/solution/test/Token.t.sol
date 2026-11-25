// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Token} from "../src/Token.sol";

contract TokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000 ether;
    Token internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        token = new Token(SUPPLY);
    }

    function test_Metadata() public view {
        assertEq(token.name(), "Bench Token");
        assertEq(token.symbol(), "BTK");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroValueTransferEmits() public {
        vm.expectEmit(address(token));
        emit IERC20.Transfer(address(this), alice, 0);
        assertTrue(token.transfer(alice, 0));
    }

    function test_RevertWhen_TransferExceedsBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_RevertWhen_TransferToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    function test_RevertWhen_ApproveZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_TransferFromDecreasesAllowance() public {
        token.approve(alice, 100);
        vm.prank(alice);
        assertTrue(token.transferFrom(address(this), bob, 40));
        assertEq(token.allowance(address(this), alice), 60);
        assertEq(token.balanceOf(bob), 40);
    }

    function test_RevertWhen_TransferFromExceedsAllowance() public {
        token.approve(alice, 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 10, 11));
        token.transferFrom(address(this), bob, 11);
    }

    function test_InfiniteAllowance() public {
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 500);
        assertEq(token.allowance(address(this), alice), type(uint256).max);
    }

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
    }
}
