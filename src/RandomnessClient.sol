// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IRandomnessClient} from "./interfaces/IRandomnessClient.sol";

contract RandomnessClient is IRandomnessClient {
    function getRandomness() external view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, block.coinbase, block.number)));
    }
}
