// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
// import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
// import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IClaim.sol";
import "./interfaces/IStake.sol";

abstract contract StakeBase is IStake {

    uint256 private deployTime;
    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint256 private constant FRACTION = 10000;

    address public tradedToken;
    address public stakingToken;
    uint16 bonusSharesRate;
    //constant WEEK = 60 * 60 * 24 * 7;

    mapping (uint64 => uint32) public sharesTotal;
    mapping (address => mapping (uint64 => uint32)) public sharesByStaker;
    mapping (address => Stake[]) public stakes;

    mapping (uint64 => uint256) public accumulatedPerShare; // mapping time to accumulated
    uint256 private lastAccumulatedPerShare;
    uint32 defaultStakeDuration;
    
    error EmptyTokenAddress();
    error InputAmountCanNotBeZero();
    error InsufficientAmount();

    function __StakeBaseInit(
        address tradedToken_,
        address stakingToken_,
        uint16 bonusSharesRate_,
        uint16 defaultStakeDuration_
    ) internal {
        
        if (tradedToken_ == address(0) || stakingToken_ == address(0)) {
            revert EmptyTokenAddress();
        }
        
        tradedToken = tradedToken_;
        stakingToken = stakingToken_;
        bonusSharesRate = bonusSharesRate_;
        defaultStakeDuration = defaultStakeDuration_;
        deployTime = block.timestamp;
    }

    /**
     * @notice stake some amount of stakingToken for a duration of time
     * @param amount amount of claiming token to stake
     * @param duration amount of seconds to stake for
     */
    function stake(
        uint256 amount, 
        uint32 duration
    ) public {
        address sender = _msgSender();
        _transferFrom(stakingToken, sender, amount);
        _stakeFromAddress(sender, amount, duration);
    }

    /**
     * @notice unstakes all stakes which have ended,
    *   transferring StakingToken and TradedToken to msg.sender
     */
    function unstake () public {
        address sender = _msgSender();
        uint32 amount = 0;
        uint256 i;
        uint256 accumulated = 0;
        claim();
        for (i=0; i<stakes[sender].length; ++i) {
            Stake storage st = stakes[sender][i];
            if (st.endTime > 0) {
                continue; // stake already ended
            }
            if (st.startTime + st.durationMin > block.timestamp) {
                continue; // not yet for this one
            }
            st.endTime = uint64(block.timestamp);
            sharesTotal -= st.shares;
            amount += st.amount;
        }
        _transfer(stakingToken, sender, amount);
    }

    /**
     * @notice claim any accumulated rewards, but don't change stakes
     */
    function claim() public {
        claimToAddress(_msgSender());
    }

    /**
     * @notice claim any accumulated rewards, but don't change stakes
     * @param to address to send the TradedToken to
     */
    function claimToAddress(
        address to
    ) public {
        uint256 i;
        uint256 rewards = 0;
        address sender = _msgSender();
        _claimTokens();
        for (i=0; i<stakes[sender].length; ++i) {
            Stake storage st = stakes[sender][i];
            if (st.endTime > 0) {
                continue; // stake already ended
            }
            if (st.startTime + st.durationMin > block.timestamp) {
                continue; // not yet for this one
            }
            rewards += _accumulate(st);
        }
        _transfer(tradedToken, to, rewards);
    }

    /**
     * @notice stake some amount of StakingToken for a duration of time
     * @param from the account that sent the StakingToken
     * @param amount amount of claiming token to stake
     * @param duration amount of seconds to stake for
     */
    function _stakeFromAddress(
        address from, 
        uint256 amount, 
        uint32 duration
    ) internal {
        uint32 shares = amount * _multiplier(duration) / FRACTION;
        sharesTotal += shares;
        stakes[from].push(
            Stake(block.timestamp, 0, duration, 0, shares, amount)
        );
        _claimTokens(); // need to set accumulatedPerShare[block.timestamp]
    }

    /**
     * @notice claims TradedToken and updates the accumulatedPerShare
     */
    function _claimTokens() internal {
        if (accumulatedPerShare[block.timestamp]) {
            return; // we've already done it this second
        }
        uint256 availableToClaim = IClaim(tradedToken).availableToClaim();
        IClaim(tradedToken).claim(availableToClaim, address(this));
        lastAccumulatedPerShare += availableToClaim / sharesTotal;
        accumulatedPerShare[block.timestamp] = lastAccumulatedPerShare;
    }

    /**
     * @notice returns the accumulated tokens based on shares
     * @param st the stake being processed
     */
    function _accumulate(
        Stake storage st
    ) 
        internal 
        returns(uint256)
    {
        uint64 lastClaimTime = st.startTime + st.lastClaimOffset;
        uint256 rewardsPerShare = accumulatedPerShare[block.timestamp] - accumulatedPerShare[lastClaimTime];
        st.lastClaimOffset = block.timestamp - st.startTime;
        return rewardsPerShare * st.shares;
    }

    function _multiplier(
        uint32 duration
    ) 
        internal 
        returns(uint256) 
    {
        // let’s just hardcode the formula for now, but
        // in the future we should set an array of thresholds and bonuses during init
        //return FRACTION + (max(0, duration - defaultStakeDuration) / defaultStakeDuration * defaultStakeDuration) * bonusSharesRate;
        return FRACTION + (subAndGetNoneZero(duration, defaultStakeDuration) / defaultStakeDuration * defaultStakeDuration) * bonusSharesRate;
    }

    function _msgSender() view internal returns(address){
        return msg.sender;
    }

    function subAndGetNoneZero(uint32 x1, uint16 x2) internal returns(uint256) {
        if (x1 > x2) {
            return x1 - x2;
        } else {
            return 0;
        }
    }

    function _transfer(address token, address to, uint256 amount) internal virtual;
    function _transferFrom(address token, address sender, uint256 amount) internal virtual;
}