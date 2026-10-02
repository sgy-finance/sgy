// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20Token} from "./interfaces/IERC20Token.sol";
import {EmptyContract} from "./EmptyContract.sol";

contract MinePool is EmptyContract {
    using SafeERC20Upgradeable for IERC20Token;

    bytes32 public constant ROOT_MANAGER = keccak256("ROOT_MANAGER");

    address public immutable SGY;

    MerkleData public merkleData;
    mapping(address => mapping(uint256 => bool)) public userClaimedState;
    mapping(address => uint256) public merkleClaimedAmountsStatic;
    mapping(address => uint256) public merkleClaimedAmountsDynamic;

    struct MerkleData {
        bytes32 merkleRoot;
        uint256 merkleVersion;
        uint256 merkleTotalReward;
        uint256 nextMerkleUpdateTime;
        uint256 merkleTotalClaimed;
    }

    error ErrorCallerNotRootManager();
    error ErrorPoolZeroAddress();
    error ErrorRewardType();
    error ErrorAlreadyClaimed();
    error ErrorClaimedEpoch();
    error ErrorInvalidProof();
    error ErrorMerkleRootEmpty();
    error ErrorTimeWindow();
    error ErrorRewardAmount();
    error ErrorVersionNumber();

    modifier onlyRootManager() {
        if (!hasRole(ROOT_MANAGER, msg.sender)) revert ErrorCallerNotRootManager();
        _;
    }

    /* ======== INITIALIZATION ======== */
    constructor( address SGY_ ) {
        if (SGY_ == address(0)) revert ErrorPoolZeroAddress();
        SGY = SGY_;
    }

    function reinitialize(address rootWallet_) public reinitializer(2) onlyManager {
        _grantRole(ROOT_MANAGER, rootWallet_);

        merkleData.nextMerkleUpdateTime = (block.timestamp / 86400 + 1) * 86400 - 28800;
    }

    function getTokenBalanceSum(address token_, address[] calldata users_) external view returns (uint256[] memory balances_, uint256 sum_) {
        balances_ = new uint256[](users_.length);
        sum_ = 0;
        for(uint256 i=0;i<users_.length;i++) {
            balances_[i] = IERC20Token(token_).balanceOf(users_[i]);
            sum_ += balances_[i];
        }
    }

    function claim(
        uint256 uid_,
        uint256 totalAmountStatic_,
        uint256 totalAmountDynamic_,
        bytes32[] calldata merkleProof_
    ) external nonReentrant whenNotPaused {
        bytes32 root_ = merkleData.merkleRoot;
        if (root_ == "") revert ErrorRewardType();
        address account_ = msg.sender;
        uint256 merkleVersion_ = merkleData.merkleVersion;
        if (userClaimedState[account_][merkleVersion_]) revert ErrorClaimedEpoch();

        {
            bytes32 leaf_ = keccak256(
                abi.encodePacked(account_, uid_, totalAmountStatic_, totalAmountDynamic_)
            );
            bool isValidProof_ = MerkleProof.verifyCalldata(
                merkleProof_,
                root_,
                leaf_
            );
            if (!isValidProof_) revert ErrorInvalidProof();
        }
        uint256 claimedAmtStatic_ = merkleClaimedAmountsStatic[account_];
        uint256 claimedAmtDynamic_ = merkleClaimedAmountsDynamic[account_];
        if (claimedAmtStatic_ > totalAmountStatic_
            || claimedAmtDynamic_ > totalAmountDynamic_
        ) revert ErrorRewardAmount();
        uint256 rewardStatic_ = totalAmountStatic_ - claimedAmtStatic_;
        uint256 rewardDynamic_ = totalAmountDynamic_ - claimedAmtDynamic_;
        uint256 reward_ = rewardStatic_ + rewardDynamic_;
        if (reward_ == 0) revert ErrorAlreadyClaimed();

        merkleClaimedAmountsStatic[account_] = totalAmountStatic_;
        merkleClaimedAmountsDynamic[account_] = totalAmountDynamic_;
        merkleData.merkleTotalClaimed += reward_;
        userClaimedState[account_][merkleVersion_] = true;

        IERC20Token(SGY).safeTransfer(account_, reward_);

        emit EventClaim(uid_, account_, reward_, totalAmountStatic_, totalAmountDynamic_);
    }

    function updateMerkleRoot(bytes32 merkleRoot_, uint256 merkleVersion_, uint256 newTotalReward_) external onlyRootManager {
        if (merkleRoot_ == "") revert ErrorMerkleRootEmpty();
        uint256 nextMerkleUpdateTime_ = merkleData.nextMerkleUpdateTime;
        if (!(nextMerkleUpdateTime_ < block.timestamp && nextMerkleUpdateTime_ + 86400 > block.timestamp)) revert ErrorTimeWindow();

        if (newTotalReward_ < merkleData.merkleTotalReward) revert ErrorRewardAmount();
        if (merkleVersion_ <= merkleData.merkleVersion) revert ErrorVersionNumber();

        merkleData.merkleRoot = merkleRoot_;
        uint256 addTotalReward_ = newTotalReward_ - merkleData.merkleTotalReward;
        merkleData.merkleTotalReward = newTotalReward_;
        merkleData.merkleVersion = merkleVersion_;
        merkleData.nextMerkleUpdateTime += 86400;

        emit EventUpdateMerkleRoot(merkleRoot_, merkleVersion_, newTotalReward_, addTotalReward_);
    }

    function setNextMerkleUpdateTime(uint256 time_) external onlyManager {
        merkleData.nextMerkleUpdateTime = time_;
    }

    event EventClaim(uint256 uid, address user, uint256 reward, uint256 totalAmountStatic, uint256 totalAmountDynamic);
    event EventUpdateMerkleRoot(bytes32 merkleRoot, uint256 merkleVersion, uint256 newTotalReward, uint256 addReward);
}
