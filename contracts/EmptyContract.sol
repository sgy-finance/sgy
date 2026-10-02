// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract EmptyContract is AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    error ErrorCallerNotManager();

    modifier onlyManager() {
        _onlyManager();
        _;
    }

    function _onlyManager() internal view {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert ErrorCallerNotManager();
    }

    function initialize() public virtual initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
    }
}
