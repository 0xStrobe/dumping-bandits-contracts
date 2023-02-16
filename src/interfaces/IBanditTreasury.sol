// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IBanditTreasury {
    function manager() external view returns (address);

    function withdrawers(address) external view returns (bool);

    function setManager(address _manager) external;

    function setWithdrawer(address _withdrawer, bool _allowed) external;

    function withdraw(address _token, address _to, uint256 _amount) external;

    function withdrawEth(address payable _to, uint256 _amount) external;
}
