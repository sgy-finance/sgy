// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter, ISwapFactory} from "./interfaces/token/ISwapRouter.sol";
import {TokenPool} from "./TokenPool.sol";


contract TokenSGY is ERC20, ERC20Permit, AccessControl {
    using SafeERC20 for IERC20;

    address public constant BLACK_HOLE =
        0x000000000000000000000000000000000000dEaD;
    bytes32 public constant INTERN_SYSTEM_MANAGER =
        keccak256("INTERN_SYSTEM_MANAGER");
    bytes32 public constant INTERN_SYSTEM = keccak256("INTERN_SYSTEM");
    bytes32 public constant TOKEN_MANAGER = keccak256("TOKEN_MANAGER");

    ISwapRouter public constant SWAPROUTER =
        ISwapRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    uint256 internal constant _MAX_BASE = 100e3;

    address public immutable MINEPOOL;
    address public immutable FOUNDATION_BUY;
    address public immutable FOUNDATION_SELL;
    address public immutable FOUNDATION_BEFORE;
    address public immutable FEEPOOL;

    address public immutable LP_TOKEN_BNB;
    uint256 public immutable STARTDAY;

    uint256 public burnFeeRate = 1e3;
    uint256 public buyFeeRate = 3e3;
    uint256 public sellFeeRate = 5e3;
    uint256 public lastDay;
    uint256 public miningAmount = 210 * 1e22; // 2100,000
    uint256 public miningAddRate = 10e3;
    uint256 public miningDay;
    uint256 public openTime = 1791288480;
    uint256 public minFeeAmount = 1e21;
    bool public isAllotFee = true;
    uint256 public feeAmountBuy = 0;
    uint256 public feeAmountBefore = 0;

    error ErrorCallerNotManager();
    error ErrorAddressZero();
    error ErrorFailureTransfer();
    error ErrorValue();

    modifier onlyTokenManager() {
        if (!hasRole(TOKEN_MANAGER, msg.sender)) revert ErrorCallerNotManager();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address minePool_,
        address foundationBuy_,
        address foundationSell_,
        address foundationBefore_,
        address holder_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (minePool_ == address(0)
            || foundationBuy_ == address(0)
            || foundationSell_ == address(0)
            || foundationBefore_ == address(0)
            || holder_ == address(0)
        ) revert ErrorAddressZero();

        _setRoleAdmin(INTERN_SYSTEM, INTERN_SYSTEM_MANAGER);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(TOKEN_MANAGER, msg.sender);
        _grantRole(INTERN_SYSTEM, msg.sender);
        _grantRole(INTERN_SYSTEM, address(this));
        _grantRole(INTERN_SYSTEM, minePool_);
        _grantRole(INTERN_SYSTEM, holder_);
        _grantRole(INTERN_SYSTEM, foundationBuy_);
        _grantRole(INTERN_SYSTEM, foundationSell_);
        _grantRole(INTERN_SYSTEM, foundationBefore_);

        FEEPOOL = address(new TokenPool(WBNB));
        _grantRole(INTERN_SYSTEM, FEEPOOL);

        MINEPOOL = minePool_;
        FOUNDATION_BUY = foundationBuy_;
        FOUNDATION_SELL = foundationSell_;
        FOUNDATION_BEFORE = foundationBefore_;

        address factory_ = SWAPROUTER.factory();
        LP_TOKEN_BNB = ISwapFactory(factory_).createPair(address(this), WBNB);

        super._approve(address(this), address(SWAPROUTER), type(uint256).max);

        STARTDAY = _getDay(block.timestamp);
        lastDay = STARTDAY - 1;

        // total supply, 2100,000,000
        _mint(holder_, 2100 * 1e4 * 1e18);
        _mint(BLACK_HOLE, 207900 * 1e4 * 1e18);
    }

    receive() external payable {}

    function setLastDay(uint256 time_) external onlyTokenManager {
        lastDay = _getDay(time_);
    }

    function setFeeRatio(uint256 burnFeeRate_, uint256 buyFeeRate_, uint256 sellFeeRate_) external onlyTokenManager {
        if (burnFeeRate_ > buyFeeRate_
            || burnFeeRate_ > sellFeeRate_
            || buyFeeRate_ > _MAX_BASE
            || sellFeeRate_ > _MAX_BASE
        ) revert ErrorValue();
        burnFeeRate = burnFeeRate_;
        buyFeeRate = buyFeeRate_;
        sellFeeRate = sellFeeRate_;
    }

    function setMinFeeAmount(uint256 value_) external onlyTokenManager {
        minFeeAmount = value_;
    }

    function setAllotFee(bool isTo_) external onlyTokenManager {
        isAllotFee = isTo_;
    }

    function setOpenTime(uint256 value_) external onlyTokenManager {
        openTime = value_;
    }

    function rescueToken(address token_, uint256 amount_) external onlyTokenManager {
        uint256 balance_ = address(this).balance;
        if (balance_ > 0) {
            (bool success_, ) = msg.sender.call{value: balance_}("");
            if (!success_) {
                revert ErrorFailureTransfer();
            }
        }
        if (token_ != address(this)) {
            IERC20(token_).safeTransfer(msg.sender, amount_);
        }
    }

    function mining() external {
        _mining();
    }

    function calculateMiningAmount(uint256 miningDay_) external view returns(uint256, uint256) {
        uint256 amount_ = miningAmount;
        uint256 rate_ = miningAddRate;
        if (miningDay_ > 0 && miningDay_ % 30 == 0) {
            if (miningDay_ % (30*12*2) == 0) {
                rate_ = rate_ / 2;
            }
            amount_ += amount_ * rate_ / _MAX_BASE;
        }
        return (rate_, amount_);
    }

    function _transfer(
        address sender_,
        address recipient_,
        uint256 amount_
    ) internal override {
        _mining();

        bool _senderIs = hasRole(INTERN_SYSTEM, sender_);
        bool _recipientIs = hasRole(INTERN_SYSTEM, recipient_);
        if (_senderIs || _recipientIs) {
            super._transfer(sender_, recipient_, amount_);
            return;
        }

        if (sender_ == LP_TOKEN_BNB || recipient_ == LP_TOKEN_BNB) {
            uint256 burnAmount_ = _burnRegular(sender_, amount_ * burnFeeRate / _MAX_BASE);
            emit EventToBurnFee(sender_, recipient_, burnAmount_);

            uint256 feeAmount_;
            if (sender_ == LP_TOKEN_BNB){
                feeAmount_ = amount_ * buyFeeRate / _MAX_BASE - burnAmount_;
                feeAmountBuy += feeAmount_;
            } else {
                feeAmount_ = amount_ * sellFeeRate / _MAX_BASE - burnAmount_;
            }
            if (block.timestamp < openTime) {
                uint256 beforeFeeAmount_ = amount_ * 30e3 / _MAX_BASE;
                feeAmountBefore += beforeFeeAmount_;
                feeAmount_ += beforeFeeAmount_;
            }
            super._transfer(sender_, address(this), feeAmount_);
            emit EventToFee(sender_, recipient_, feeAmount_);
            amount_ = amount_ - burnAmount_ - feeAmount_;
            if (recipient_ == LP_TOKEN_BNB) {
                _allotFee();
            }
        }
        super._transfer(sender_, recipient_, amount_);
    }

    function _burnRegular(address sender_, uint256 feeAmount_) internal returns(uint256) {
        if (feeAmount_ == 0) return 0;
        uint256 totalSupply_ = this.totalSupply();
        if (totalSupply_ <= 2100*1e22) {
            return 0;
        } else {
            uint256 maxBurn_ = totalSupply_ - 2100*1e22;
            feeAmount_ = feeAmount_ <= maxBurn_ ? feeAmount_ : maxBurn_;
        }
        super._burn(sender_, feeAmount_);
        return feeAmount_;
    }

    function _mining() internal {
        uint256 nowDay_ = _getDay(block.timestamp);
        if (nowDay_ > lastDay) {
            lastDay = nowDay_;
            uint256 balance_ = this.balanceOf(BLACK_HOLE);
            if (balance_ == 0) return;
            uint256 amount_ = _getAndUpdateMiningAmount();
            if (balance_ < amount_){
                amount_ = balance_;
            }
            super._transfer(BLACK_HOLE, MINEPOOL, amount_);
            emit EventToMining(MINEPOOL, balance_, amount_);
        }
    }

    function _getAndUpdateMiningAmount() internal returns(uint256) {
        uint256 amount_ = miningAmount;
        uint256 rate_ = miningAddRate;
        uint256 miningDay_ = miningDay;
        if (miningDay_ > 0 && miningDay_ % 30 == 0) {
            if (miningDay_ % (30*12*2) == 0) {
                rate_ = rate_ / 2;
                miningAddRate = rate_;
            }
            amount_ += amount_ * rate_ / _MAX_BASE;
            miningAmount = amount_;

            emit EventUpdateMiningParam(miningDay_, rate_, amount_);
        }
        miningDay += 1;
        return amount_ / 30;
    }

    function _allotFee() internal {
        uint256 feeAmount_ = this.balanceOf(address(this));
        if (feeAmount_ < minFeeAmount) {
            return;
        }
        uint256 buyAmount_ = feeAmountBuy;
        uint256 beforeAmount_ = feeAmountBefore;
        uint256 sellAmount_ = feeAmount_ - buyAmount_ - beforeAmount_;
        feeAmountBuy = 0;
        feeAmountBefore = 0;
        if (!isAllotFee) {
            if(buyAmount_>0) this.transfer(FOUNDATION_BUY, buyAmount_);
            if(sellAmount_>0) this.transfer(FOUNDATION_SELL, sellAmount_);
            if(beforeAmount_>0) this.transfer(FOUNDATION_BEFORE, beforeAmount_);
            emit EventAllotFee(
                block.timestamp,
                feeAmount_,
                buyAmount_,
                beforeAmount_,
                0
            );
            return;
        }
        uint256 outAmount_ = _swapTokens(_toWBNBPath(), feeAmount_, FEEPOOL);
        if (buyAmount_ > 0) {
            IERC20(WBNB).safeTransferFrom(FEEPOOL, FOUNDATION_BUY, outAmount_ * buyAmount_ / feeAmount_);
        }
        if (beforeAmount_ > 0) {
            IERC20(WBNB).safeTransferFrom(FEEPOOL, FOUNDATION_BEFORE, outAmount_ * beforeAmount_ / feeAmount_);
        }
        if (sellAmount_ > 0) {
            IERC20(WBNB).safeTransferFrom(FEEPOOL, FOUNDATION_SELL, outAmount_ * sellAmount_ / feeAmount_);
        }

        emit EventAllotFee(
            block.timestamp,
            feeAmount_,
            buyAmount_,
            beforeAmount_,
            outAmount_
        );
    }

    function _swapTokens(
        address[] memory path_,
        uint256 amountIn_,
        address recipient_
    ) internal returns (uint256) {
        address outToken_ = path_[path_.length - 1];

        uint256 valueBefore_ = IERC20(outToken_).balanceOf(recipient_);
        SWAPROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn_,
            1,
            path_,
            recipient_,
            block.timestamp
        );
        return IERC20(outToken_).balanceOf(recipient_) - valueBefore_;
    }

    function _toWBNBPath() internal view returns (address[] memory path_) {
        path_ = new address[](2);
        path_[0] = address(this);
        path_[1] = WBNB;
    }

    function _getDay(uint256 time_) internal pure returns (uint256) {
        return (time_ + 28800)/86400;
    }

    event EventToFee(address sender, address recipient, uint256 feeAmtAdd);
    event EventToBurnFee(address sender, address recipient, uint256 feeAmt);
    event EventToMining(address recipient, uint256 balance, uint256 reward);
    event EventUpdateMiningParam(uint256 day, uint256 rate, uint256 miningAmount);
    event EventAllotFee(
        uint256 allotTime,
        uint256 amount,
        uint256 amountBuy,
        uint256 amountBefore,
        uint256 amountBNB
    );

}
