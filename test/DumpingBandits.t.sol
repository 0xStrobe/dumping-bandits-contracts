// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/DumpingBandits.sol";
import "../src/RandomnessClient.sol";

contract DumpingBanditsTest is Test {
    RandomnessClient public rc;
    DumpingBandits public db;

    function setUp() public {
        rc = new RandomnessClient();
        db = new DumpingBandits(address(rc));
    }

    function testDummy() public {
        assert(true);
    }
}
