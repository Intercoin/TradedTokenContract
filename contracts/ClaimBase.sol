// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IClaim.sol";
//import "hardhat/console.sol";
abstract contract ClaimBase is IClaim {

    uint256 private timeDeploy;
    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public tradedToken;
    address public claimingToken;
    PriceNumDen claimingTokenExchangePrice;
    /**
     * 
     * @notice claimFrequency
     */
    uint16 public claimFrequency;

    uint256 public wantToClaimTotal; // value that accumulated all users `wantToClaim requests`
    
    mapping(address => ClaimStruct) public wantToClaimMap;
    
    error EmptyTokenAddress();
    error InputAmountCanNotBeZero();
    error InsufficientAmount();
    error ClaimTooFast(uint256 untilTime);
    error InsufficientAmountToClaim(uint256 requested, uint256 maxAvailable);

    function __ClaimBaseInit(
        address tradedToken_,
        ClaimSettings memory claimSettings
    ) internal {
        
        if (tradedToken_ == address(0) || claimSettings.claimingToken == address(0)) {
            revert EmptyTokenAddress();
        }

        if (claimSettings.claimingTokenExchangePrice.denominator == 0
        || claimSettings.claimingTokenExchangePrice.numerator == 0) {
            revert InputAmountCanNotBeZero();
        }
        
        tradedToken = tradedToken_;
        claimingToken = claimSettings.claimingToken;
        claimingTokenExchangePrice.numerator = claimSettings.claimingTokenExchangePrice.numerator;
        claimingTokenExchangePrice.denominator = claimSettings.claimingTokenExchangePrice.denominator;
        
        claimFrequency = claimSettings.claimFrequency;

        timeDeploy = block.timestamp;
    }

    function getTradedToken() external view returns(address) {
        return tradedToken;
    }

    function availableToClaim(
    ) 
        public 
        view 
        returns(uint256) 
    {
        return availableToClaimByAddress(msg.sender); 
    }

    /**
    * @return (this is called clamping a value or sum to fit into a range, in this case 0….availableToClaimTotal).
    */
    function availableToClaimByAddress(
        address account
    ) 
        public 
        view 
        returns(uint256) 
    {
        uint256 a = IClaim(tradedToken).availableToClaim();
        uint256 w = wantToClaimMap[account].amount; 
        // console.log("a                  = ",a);
        // console.log("w                  = ",w);
        // console.log("wantToClaimTotal   = ",wantToClaimTotal);
        uint256 t = (w * claimingTokenExchangePrice.numerator) / claimingTokenExchangePrice.denominator;
        return wantToClaimTotal <= a ? t : t * a / wantToClaimTotal; 
        
    }
    
    function lastActionTime(address sender) internal view returns(uint256) {
        return wantToClaimMap[sender].lastActionTime == 0 ? timeDeploy : wantToClaimMap[sender].lastActionTime;
    }


    /**
     * @notice claims to account traded tokens instead external tokens(if set). external tokens will send to dead address
     * @param claimingTokenAmount amount of external token to claim traded token
     * @param account address to claim for
     */
    function _claim(uint256 claimingTokenAmount, address account) internal {
        if (claimingTokenAmount == 0) { 
            revert InputAmountCanNotBeZero();
        }

        if (claimingTokenAmount > claimingTokenAllowance(msg.sender, address(this))) {
            revert InsufficientAmount();
        }

        if (lastActionTime(msg.sender) + claimFrequency > block.timestamp) {
            revert ClaimTooFast(lastActionTime(msg.sender) + claimFrequency);
        }

        //ERC777(claimingToken).safeTransferFrom(msg.sender, DEAD_ADDRESS, claimingTokenAmount);
        claimingTokenTransferFrom(msg.sender, DEAD_ADDRESS, claimingTokenAmount);

        uint256 tradedTokenAmount = (claimingTokenAmount * claimingTokenExchangePrice.numerator) /
            claimingTokenExchangePrice.denominator;

        uint256 scalingMaxTradedTokenAmount = availableToClaimByAddress(msg.sender);

        if (scalingMaxTradedTokenAmount < tradedTokenAmount) {
            revert InsufficientAmountToClaim(tradedTokenAmount, scalingMaxTradedTokenAmount);
        }

        //_claim(tradedTokenAmount, account);
        IClaim(tradedToken).claim(tradedTokenAmount, account);

        wantToClaimMap[msg.sender].lastActionTime = block.timestamp;
        // wantToClaimTotal -= tradedTokenAmount;
        // wantToClaimMap[account].amount -= tradedTokenAmount;
        // or just empty all wantToClaimMap
        wantToClaimTotal -= wantToClaimMap[msg.sender].amount;
        delete wantToClaimMap[msg.sender].amount;
    }

    /**
    * If there is a claimingToken, then they have to pass an amount that is <= claimingToken.balanceOf(caller). 
    * If they pass zero here, it will actually look up and use their entire balance.
    */
    function _wantToClaim(
        uint256 amount
    ) 
        internal 
    {
        //address sender = _msgSender();
        //uint256 availableAmount = ERC777(claimingToken).balanceOf(msg.sender);
        uint256 availableAmount = getClaimingTokenBalanceOf(msg.sender);
        
        if (amount == 0) {
            amount = availableAmount;
        }

        if (availableAmount < amount || amount == 0) {
            revert InsufficientAmount();
        }

        wantToClaimTotal += amount - wantToClaimMap[msg.sender].amount;
        wantToClaimMap[msg.sender].amount = amount;

        wantToClaimMap[msg.sender].lastActionTime = block.timestamp;

    }

    function getClaimingTokenBalanceOf(address account) internal virtual view returns(uint256) ;
    function claimingTokenTransferFrom(address from, address to, uint256 claimingTokenAmount) internal virtual;
    function claimingTokenAllowance(address owner, address spender) internal virtual returns(uint256);

}