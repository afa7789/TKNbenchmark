// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

import {Test} from "forge-std/Test.sol";
import {Vesting} from "../src/Vesting.sol";

contract VestingTest is Test {
    uint64 constant START = 1_700_001_000;
    uint64 constant DURATION = 1000;
    uint256 constant AMOUNT = 1 ether;

    address beneficiary = makeAddr("beneficiary");
    Vesting vesting;

    function setUp() public {
        vm.warp(1_700_000_000);
        vesting = new Vesting{value: AMOUNT}(beneficiary, START, DURATION);
    }

    function test_Getters() public view {
        assertEq(vesting.beneficiary(), beneficiary);
        assertEq(vesting.start(), START);
        assertEq(vesting.duration(), DURATION);
        assertEq(vesting.released(), 0);
    }

    function test_RevertWhen_ZeroBeneficiary() public {
        vm.expectRevert(Vesting.ZeroBeneficiary.selector);
        new Vesting(address(0), START, DURATION);
    }

    function test_RevertWhen_ZeroDuration() public {
        vm.expectRevert(Vesting.ZeroDuration.selector);
        new Vesting(beneficiary, START, 0);
    }

    function test_Schedule() public view {
        assertEq(vesting.vestedAmount(START - 1), 0);
        assertEq(vesting.vestedAmount(START), 0);
        assertEq(vesting.vestedAmount(START + 250), AMOUNT / 4);
        assertEq(vesting.vestedAmount(START + DURATION), AMOUNT);
        assertEq(vesting.vestedAmount(type(uint64).max), AMOUNT);
    }

    function test_RevertWhen_NothingReleasable() public {
        vm.expectRevert(Vesting.NothingToRelease.selector);
        vesting.release();
    }

    function test_ReleaseMidwayThenRest() public {
        vm.warp(START + 500);
        vm.expectEmit(address(vesting));
        emit Vesting.Released(AMOUNT / 2);
        vesting.release();
        assertEq(beneficiary.balance, AMOUNT / 2);
        assertEq(vesting.released(), AMOUNT / 2);
        assertEq(vesting.releasable(), 0);

        (bool ok,) = address(vesting).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(vesting.releasable(), 0.5 ether);

        vm.warp(START + DURATION);
        vesting.release();
        assertEq(beneficiary.balance, 2 ether);
        assertEq(address(vesting).balance, 0);
    }

    function testFuzz_VestedMonotonic(uint64 a, uint64 b) public view {
        (a, b) = a < b ? (a, b) : (b, a);
        assertLe(vesting.vestedAmount(a), vesting.vestedAmount(b));
    }
}
