// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
// import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
// import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IStake.sol";

abstract contract StakeBase is IStake {

    uint256 private deployTime;
    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public tradedToken;
    address public stakingToken;
    uint16 bonusSharesRate;
    //constant WEEK = 60 * 60 * 24 * 7;

    mapping (uint64 => uint32) public sharesTotal;
    mapping (address => mapping (uint64 => uint32)) public sharesByStaker;
    mapping (address => Stake[]) public stakes;

    mapping (uint64 => uint256) public accumulatedPerShare; // mapping time to accumulated
    uint256 private lastAccumulatedPerShare;
    
    error EmptyTokenAddress();
    error InputAmountCanNotBeZero();
    error InsufficientAmount();

    function __StakeBaseInit(
        address tradedToken_,
        address stakingToken_,
        uint16 bonusSharesRate_,
        uint16 defaultStakeDuration_
    ) internal {
        
        if (tradedToken_ == address(0) || StakingToken == address(0)) {
            revert EmptyTokenAddress();
        }
        
        tradedToken = tradedToken_;
        stakingToken = StakingToken_;
        bonusSharesRate = bonusSharesRate_;
        defaultStakeDuration = defaultStakeDuration_;
        deployTime = block.timestamp;
    }

    /**
     * @notice stake some amount of StakingToken for a duration of time
     * @param amount amount of claiming token to stake
     * @param duration amount of seconds to stake for
     */
    function stake(
        uint256 amount, 
        uint32 duration
    ) public {
        address sender = _msgSender();
        ERC777Upgradeable(StakingToken).transferFrom(sender, amount)
        _stakeFromAddress(sender);
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
            Stake stake = stakes[sender][i];
            if (stake.endTime > 0) {
                continue; // stake already ended
            }
            if (stake.startTime + stake.durationMin > block.timestamp) {
                continue; // not yet for this one
            }
            stake.endTime = block.timestamp;
            sharesTotal -= stake.shares;
            amount += stake.amount;
        }
        ERC777Upgradeable(StakingToken).transfer(sender, amount);
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
        _claimTokens();
        for (i=0; i<stakes[sender].length; ++i) {
            Stake stake = stakes[sender][i];
            if (stake.endTime > 0) {
                continue; // stake already ended
            }
            if (stake.startTime + stake.durationMin > block.timestamp) {
                continue; // not yet for this one
            }
            rewards += _accumulate(stake);
        }
        ERC777Upgradeable(tradedToken).transfer(to, rewards);
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
        uint256 shares = amount * _multiplier(duration) / FRACTION;
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
        uint256 availableToClaim = ITradedToken(tradedToken).availableToClaim();
        ITradedToken(tradedToken).claim(availableToClaim, address(this));
        lastAccumulatedPerShare += availableToClaim / sharesTotal;
        accumulatedPerShare[block.timestamp] = lastAccumulatedPerShare;
    }

    /**
     * @notice returns the accumulated tokens based on shares
     * @param stake the stake being processed
     */
    function _accumulate(
        Stake storage stake
    ) internal {
        uint64 lastClaimTime = stake.startTime + stake.lastClaimOffset;
        uint256 rewardsPerShare = accumulatedPerShare[block.timestamp] - accumulatedPerShare[lastClaimTime];
        stake.lastClaimOffset = block.timestamp - stake.startTime;
        return rewardsPerShare * stake.shares;
    }

    function _multiplier(duration) {
        // let’s just hardcode the formula for now, but
        // in the future we should set an array of thresholds and bonuses during init
        return FRACTION + max(0, duration - defaultStakeDuration) / defaultStakeDuration * defaultStakeDuration) * bonusSharesRate;
    }

    function _msgSender() view internal {
        return msg.sender;
    }

}