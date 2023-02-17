// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {RandomnessClient} from "../src/RandomnessClient.sol";
import {DumpingBandits} from "../src/DumpingBandits.sol";
import {BanditTreasury} from "../src/BanditTreasury.sol";

contract DumpingBanditsTest is Test {
    RandomnessClient public rc;
    BanditTreasury public treasury;
    DumpingBandits public dumpingBandits;
    uint256 t0 = block.timestamp;

    function setUp() public {
        rc = new RandomnessClient();
        treasury = new BanditTreasury();
        dumpingBandits = new DumpingBandits(address(rc), address(treasury));

        dumpingBandits.setPrice(0.02 ether);
        dumpingBandits.setFinalizerReward(0.01 ether);
    }

    function testDummy() public pure {
        assert(true);
    }

    function testFinalizeRound() public {
        uint256 t1 = t0 + 1 minutes;
        uint256 t2 = t1 + 1 minutes;
        uint256 t3 = t2 + 1 minutes;
        uint256 t4 = t0 + 16 minutes;
        // invoke dumpingBandits.participate() several times with 0.02 ether each
        vm.deal(0x1234567890123456789012345678901234567890, 2 ether);
        vm.startPrank(0x1234567890123456789012345678901234567890);
        vm.warp(t1);
        dumpingBandits.participate{value: 0.02 ether}();
        vm.warp(t2);
        dumpingBandits.participate{value: 0.02 ether}();
        vm.warp(t3);
        dumpingBandits.participate{value: 0.02 ether}();
        dumpingBandits.participate{value: 0.02 ether}();

        vm.warp(t4);
        dumpingBandits.finalizeRound();

        vm.warp(t4 + 1 minutes);
        dumpingBandits.participate{value: 0.02 ether}();
    }
}
