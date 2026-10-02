// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface ICommunity {
    function addReferrer(uint256 uid_, address referrer_) external;
    function referrerOf(uint256 uid_, address depositor_) external view returns (address);
}
