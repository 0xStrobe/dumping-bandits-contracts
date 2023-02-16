// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {RandomnessClient} from "../src/RandomnessClient.sol";
import {DumpingBandits} from "../src/DumpingBandits.sol";
import {BanditTreasury} from "../src/BanditTreasury.sol";

contract DeployDumpingBandits is Script {
    RandomnessClient public rc;
    BanditTreasury public treasury;
    DumpingBandits public dumpingBandits;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        rc = new RandomnessClient();
        console.log("Deployed RandomnessClient at", address(rc));
        treasury = new BanditTreasury();
        console.log("Deployed BanditTreasury at", address(treasury));

        dumpingBandits = new DumpingBandits(address(rc), address(treasury));
        console.log("Deployed DumpingBandits at", address(dumpingBandits));

        vm.stopBroadcast();
    }
}
