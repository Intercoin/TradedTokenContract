// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";

contract ITR is Ownable, ERC777 {
    using SafeMath for uint256;
    
    address private constant deadAddress = 0x000000000000000000000000000000000000dEaD;
    
    uint256 internal constant WEEK = 604800;    // 7*24*60*60
    uint256 internal constant MONTH = 2592000;  // 30*24*60*60  30 days
    uint256 internal _maxTotalSupply = 200_000_000 * 10**18;
    
    address _claimToken;
    uint256 public _claimDuration;
    uint256 public _claimFraction;
    
    // this is the amount of ITR which can be sold before any percent restrictions kick in
    uint256 _claimExcepted;
    
    // every _claimDuration this gets added to _claimFraction
    uint256 _claimGrowth;
    
	uint256 internal constant MULTIPLIER = 100000;
    uint256 private deployedTime;
    
    // global restriction for claims
    uint256 internal _lastClaimedTime;
    uint256 internal _lastClaimedAmount;
    
    constructor() ERC777("Intercoin Investor Token", "ITR", new address[](0)) {
       init(
		   200_000_000 * 10**18,
		   0x6Ef5febbD2A56FAb23f18a69d3fB9F4E2A70440B,
		   2000,
		   MONTH,
		   30000 * 10 **18,
		   100
	   );
    }

	function init(
		uint256 maxTotalSupply, 
		address claimToken, 
		uint256 claimFraction,
		uint256 claimDuration, 
		uint256 claimExcepted, 
		uint256 claimGrowth
	) internal {
		(_maxTotalSupply, _claimToken, _claimFraction, _claimDuration, _claimExcepted, _claimGrowth) = 
		    (maxTotalSupply, claimToken, claimFraction, claimDuration, claimExcepted, claimGrowth);
		
		deployedTime = block.timestamp;
	}
    
    // cap of total supply
    function getMaxTotalSupply() public view returns(uint256) {
        return _maxTotalSupply;
    }
    
    // still available to claim
    function totalRemaining() public view returns(uint256) {
        return _maxTotalSupply.sub(totalSupply());
    }
	
	// how much to claim
	function getClaimFraction() public view returns (uint256) {
		return _claimFraction.add(_claimGrowth.mul(getGrowthDurationsPassed()));
	}
    
	// this function mints the tokens internally
    function claim(address to) external {
        uint256 a = IERC20(_claimToken).balanceOf(to);
        uint256 b = IERC20(_claimToken).balanceOf(address(this));

        require(b > 0, "nothing to claim");
       
        if ((b > _claimExcepted) && (b > (
			a.add(b).mul(getClaimFraction()).div(MULTIPLIER)
		))) {
            revert("please claim less tokens per month");
        }
         
		// restrict global amounts transferred in each period
        uint256 index = (block.timestamp)
			.div(_claimDuration)
			.mul(_claimDuration);
        if (index == _lastClaimedTime) {
            _lastClaimedAmount = _lastClaimedAmount.add(b);
        } else {
            _lastClaimedTime = index;
            _lastClaimedAmount = b;
        }
        
        require(
            (_maxTotalSupply).mul(getClaimFraction()).div(MULTIPLIER) >= _lastClaimedAmount, 
            "please wait, too many tokens already claimed this month"
        );
        
        require(totalSupply().add(b) <= _maxTotalSupply, 
			"this would exceed maxTotalSupply");
        _mint(to, b, "", "");
        IERC20(_claimToken).transfer(deadAddress, b);
        
    }
    
    function getGrowthDurationsPassed() internal view returns(uint256) {
        return (block.timestamp.sub(deployedTime)).div(_claimDuration);
    }
}