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

    function setUp() public {
        rc = new RandomnessClient();
        treasury = new BanditTreasury();
        dumpingBandits = new DumpingBandits(address(rc), address(treasury));
    }

    function testDummy() public pure {
        assert(true);
    }
}
