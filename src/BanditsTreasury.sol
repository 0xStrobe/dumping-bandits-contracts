// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

error NOT_MANAGER();
error NOT_WITHDRAWER();
error ZERO_ADDRESS();

contract BanditsTreasury {
    address public manager;
    mapping(address => bool) public withdrawers;

    constructor() {
        manager = msg.sender;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert NOT_MANAGER();
        _;
    }

    modifier onlyWithdrawer() {
        if (!withdrawers[msg.sender]) revert NOT_WITHDRAWER();
        _;
    }

    function setManager(address _manager) external onlyManager {
        if (_manager == address(0)) revert ZERO_ADDRESS();
        manager = _manager;
    }

    function setWithdrawer(address _withdrawer, bool _allowed) external onlyManager {
        if (_withdrawer == address(0)) revert ZERO_ADDRESS();
        withdrawers[_withdrawer] = _allowed;
    }

    function withdraw(address _token, address _to, uint256 _amount) external onlyWithdrawer {
        SafeTransferLib.safeTransfer(ERC20(_token), _to, _amount);
    }

    function withdrawEth(address payable _to, uint256 _amount) external onlyWithdrawer {
        SafeTransferLib.safeTransferETH(_to, _amount);
    }
}
