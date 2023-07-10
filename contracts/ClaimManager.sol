// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IClaimManager.sol";
import "./interfaces/IClaim.sol";

//import "hardhat/console.sol";

contract ClaimManager is IClaimManager, IERC777Recipient, IERC777Sender, ReentrancyGuard {
    using SafeERC20 for ERC777;
    uint256 private timeDeploy;
    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public immutable tradedToken;
    address public immutable claimingToken;
    PriceNumDen claimingTokenExchangePrice;
    /**
     * @custom:shortd claimFrequency
     * @notice claimFrequency
     */
    uint16 public immutable claimFrequency;

    uint256 public wantToClaimTotal; // value that accomulated all users `wantToClaim requests`
    
    mapping(address => ClaimStruct) public wantToClaimMap;
    
    error EmptyTokenAddress();
    error InputAmountCanNotBeZero();
    error InsufficientAmount();
    error ClaimTooFast(uint256 untilTime);
    error InsufficientAmountToClaim(uint256 requested, uint256 maxAvailable);

    constructor (
        address tradedToken_,
        ClaimSettings memory claimSettings
        
    ) {
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

    /**
     * @notice part of IERC777Recipient
     */
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {}

    /**
     * @notice part of IERC777Sender
     */
    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {}

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
        return wantToClaimTotal <= a ? w : w * a / wantToClaimTotal; 
        
    }

    /**
     * @notice claims to account traded tokens instead external tokens(if set). external tokens will send to dead address
     * @param claimingTokenAmount amount of external token to claim traded token
     * @param account address to claim for
     */
    function claim(uint256 claimingTokenAmount, address account) external nonReentrant() {

        //address sender = _msgSender();

        if (claimingTokenAmount == 0) { 
            revert InputAmountCanNotBeZero();
        }
        
        if (claimingTokenAmount > ERC777(claimingToken).allowance(msg.sender, address(this))) {
            revert InsufficientAmount();
        }
        
        if (lastActionTime(msg.sender) + claimFrequency > block.timestamp) {
            revert ClaimTooFast(lastActionTime(msg.sender) + claimFrequency);
        }
        
        ERC777(claimingToken).safeTransferFrom(msg.sender, DEAD_ADDRESS, claimingTokenAmount);

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
        wantToClaimTotal -= wantToClaimMap[account].amount;
        delete wantToClaimMap[account].amount;
        
        
    }

     /**
    * If there is a claimingToken, then they have to pass an amount that is <= claimingToken.balanceOf(caller). 
    * If they pass zero here, it will actually look up and use their entire balance.
    */
    function wantToClaim(
        uint256 amount
    ) 
        external 
    {
        //address sender = _msgSender();
        uint256 availableAmount = ERC777(claimingToken).balanceOf(msg.sender);
        
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

    function lastActionTime(address sender) internal view returns(uint256) {
        return wantToClaimMap[sender].lastActionTime == 0 ? timeDeploy : wantToClaimMap[sender].lastActionTime;
    }

}

