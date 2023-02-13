// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IRandomnessClient {
    function getRandomness() external view returns (uint256);
}
