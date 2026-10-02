// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IWToken {
    function deposit() external payable;

    function decimals() external view returns (uint256);

    function withdraw(uint256) external;
}
