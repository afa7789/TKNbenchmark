// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

import {Test} from "forge-std/Test.sol";
import {Vesting} from "../src/Vesting.sol";

contract Rejecter {
    receive() external payable {
        revert();
    }
}

contract VestingTest is Test {
    address internal beneficiary = makeAddr("beneficiary");
    uint64 internal constant START = 1_700_001_000;
    uint64 internal constant DURATION = 1000;
    Vesting internal vesting;

    function setUp() public {
        vm.warp(1_700_000_000);
        vesting = new Vesting{value: 1 ether}(beneficiary, START, DURATION);
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
        assertEq(vesting.vestedAmount(START + 250), 0.25 ether);
        assertEq(vesting.vestedAmount(START + DURATION), 1 ether);
        assertEq(vesting.vestedAmount(type(uint64).max), 1 ether);
    }

    function test_RevertWhen_NothingReleasable() public {
        vm.expectRevert(Vesting.NothingToRelease.selector);
        vesting.release();
    }

    function test_ReleaseMidwayAndFull() public {
        vm.warp(START + 500);
        vm.expectEmit(address(vesting));
        emit Vesting.Released(0.5 ether);
        vesting.release();
        assertEq(beneficiary.balance, 0.5 ether);
        assertEq(vesting.released(), 0.5 ether);
        assertEq(vesting.releasable(), 0);

        vm.expectRevert(Vesting.NothingToRelease.selector);
        vesting.release();

        vm.warp(START + DURATION);
        vesting.release();
        assertEq(beneficiary.balance, 1 ether);
        assertEq(address(vesting).balance, 0);
    }

    function test_ReceiveAddsToTotal() public {
        vm.warp(START + 500);
        vesting.release();
        (bool ok,) = address(vesting).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(vesting.vestedAmount(START + 500), 1 ether);
        assertEq(vesting.releasable(), 0.5 ether);
    }

    function test_RevertWhen_TransferFails() public {
        Vesting v = new Vesting{value: 1 ether}(address(new Rejecter()), START, DURATION);
        vm.warp(START + DURATION);
        vm.expectRevert(Vesting.TransferFailed.selector);
        v.release();
    }

    function testFuzz_ReleasedNeverExceedsTotal(uint64 t1, uint64 t2) public {
        t1 = uint64(bound(t1, START, START + 2 * DURATION));
        t2 = uint64(bound(t2, t1, START + 2 * DURATION));
        vm.warp(t1);
        if (vesting.releasable() > 0) vesting.release();
        vm.warp(t2);
        if (vesting.releasable() > 0) vesting.release();
        assertEq(beneficiary.balance + address(vesting).balance, 1 ether);
        assertEq(beneficiary.balance, vesting.vestedAmount(t2));
    }
}
