// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Token} from "../src/Token.sol";

contract TokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000 ether;

    Token internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new Token(SUPPLY);
    }

    function test_Metadata() public view {
        assertEq(token.name(), "Bench Token");
        assertEq(token.symbol(), "BTK");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ConstructorEmitsMint() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), address(this), 42);
        new Token(42);
    }

    function test_Transfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 100);
        assertTrue(token.transfer(alice, 100));
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
    }

    function test_ZeroValueTransferEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 0);
        assertTrue(token.transfer(alice, 0));
    }

    function test_RevertWhen_TransferExceedsBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1);
    }

    function test_RevertWhen_TransferToZero() public {
        vm.expectRevert();
        token.transfer(address(0), 1);
    }

    function test_RevertWhen_ApproveZero() public {
        vm.expectRevert();
        token.approve(address(0), 1);
    }

    function test_ApproveOverwrites() public {
        token.approve(alice, 50);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), alice, 7);
        assertTrue(token.approve(alice, 7));
        assertEq(token.allowance(address(this), alice), 7);
    }

    function test_TransferFrom() public {
        token.approve(alice, 50);
        vm.prank(alice);
        assertTrue(token.transferFrom(address(this), bob, 30));
        assertEq(token.allowance(address(this), alice), 20);
        assertEq(token.balanceOf(bob), 30);
    }

    function test_RevertWhen_TransferFromExceedsAllowance() public {
        token.approve(alice, 50);
        vm.prank(alice);
        vm.expectRevert();
        token.transferFrom(address(this), bob, 51);
        assertEq(token.allowance(address(this), alice), 50);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_InfiniteAllowance() public {
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 1000);
        assertEq(token.allowance(address(this), alice), type(uint256).max);
    }

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice), SUPPLY);
    }
}
