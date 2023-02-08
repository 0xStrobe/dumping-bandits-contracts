// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IRandomness} from "./interfaces/IRandomness.sol";

contract Randomness is IRandomness {
    function generateRandomness() external view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, block.coinbase, block.number)));
    }
}
