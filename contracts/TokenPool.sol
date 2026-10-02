// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenPool {
    constructor(address token) {
        IERC20(token).approve(msg.sender, type(uint256).max);
    }
}
