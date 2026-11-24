// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";

contract TokenTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);

    Token internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new Token(1000);
    }

    function test_ZeroValueTransferEmits() public {
        vm.expectEmit(address(token));
        emit Transfer(address(this), alice, 0);
        assertTrue(token.transfer(alice, 0));
    }

    function test_RevertWhen_InsufficientBalance() public {
        vm.expectRevert();
        token.transfer(alice, 1001);
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.expectRevert();
        token.transfer(address(0), 1);
        vm.expectRevert();
        token.approve(address(0), 1);
    }

    function test_InfiniteAllowance() public {
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 10);
        assertEq(token.allowance(address(this), alice), type(uint256).max);
        assertEq(token.balanceOf(bob), 10);
    }

    function test_RevertWhen_AboveAllowance() public {
        token.approve(alice, 5);
        vm.prank(alice);
        vm.expectRevert();
        token.transferFrom(address(this), bob, 6);
    }
}
