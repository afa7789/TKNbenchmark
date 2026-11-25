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
        token = new Token(SUPPLY);
    }

    function test_Metadata() public view {
        assertEq(token.name(), "Bench Token");
        assertEq(token.symbol(), "BTK");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ConstructorEmitsTransfer() public {
        vm.expectEmit();
        emit IERC20.Transfer(address(0), address(this), SUPPLY);
        new Token(SUPPLY);
    }

    function test_Transfer() public {
        vm.expectEmit(address(token));
        emit IERC20.Transfer(address(this), alice, 100);
        assertTrue(token.transfer(alice, 100));
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
    }

    function test_ZeroValueTransferEmits() public {
        vm.expectEmit(address(token));
        emit IERC20.Transfer(address(this), alice, 0);
        assertTrue(token.transfer(alice, 0));
    }

    function test_RevertWhen_TransferExceedsBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transfer(bob, 1);
    }

    function test_RevertWhen_TransferToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transfer(address(0), 1);
    }

    function test_RevertWhen_ApproveZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_ApproveOverwrites() public {
        vm.expectEmit(address(token));
        emit IERC20.Approval(address(this), alice, 50);
        assertTrue(token.approve(alice, 50));
        assertTrue(token.approve(alice, 7));
        assertEq(token.allowance(address(this), alice), 7);
    }

    function test_TransferFrom() public {
        token.approve(alice, 50);
        vm.expectEmit(address(token));
        emit IERC20.Transfer(address(this), bob, 30);
        vm.prank(alice);
        assertTrue(token.transferFrom(address(this), bob, 30));
        assertEq(token.allowance(address(this), alice), 20);
        assertEq(token.balanceOf(bob), 30);
    }

    function test_RevertWhen_TransferFromExceedsAllowance() public {
        token.approve(alice, 50);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 50, 51));
        vm.prank(alice);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transferFrom(address(this), bob, 51);
        assertEq(token.allowance(address(this), alice), 50);
    }

    function test_InfiniteAllowance() public {
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        assertTrue(token.transferFrom(address(this), bob, 1000));
        assertEq(token.allowance(address(this), alice), type(uint256).max);
    }

    function testFuzz_TransferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to) + token.balanceOf(address(this)), SUPPLY);
    }
}
