// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IRandomness {
    function generateRandomness() external view returns (uint256);
}
