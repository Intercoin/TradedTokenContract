// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";

/**
 *
Make ERC777 with constructor parameter (totalSupply, claimToken, claimDuration = WEEK, claimFraction=500)

Contract itself will start out with totalSupply which is returned in balanceOf(self)

These tokens are distributed when people call claim()
No mint() or burn() function

Ownable interface where renounceOwnership posts same event data as SAFEMOON

And make function claim(address) which will check A = balance of claimToken on address, and check B = balance of claimToken on self. If (A + B) * claimFraction / 100000 < B then revert with message “please claim less tokens or wait longer for them to be unlocked”

Also ensure global restriction that the amount of claimed tokens per claimDuration is not more than totalSupply * claimFraction / 100000, otherwiwe revert “please wait, too many tokens already claimed during this time period”

Otherwise send same amount of  new token to address. Then send received balance of original token to 0x0 account .
 */
contract ITR is Ownable, ERC777 {
    using SafeMath for uint256;
    
    address private constant deadAddress = 0x000000000000000000000000000000000000dEaD;
    
    uint256 internal constant WEEK = 604800;    // 7*24*60*60
    uint256 internal constant MONTH = 2592000;  // 30*24*60*60  30 days

    // totalSupply is 200kk
    uint256 internal _maxTotalSupply = 200_000_000 * 10**18;
    
    
    // ITR(SRC20)
    address claimToken = 0x6Ef5febbD2A56FAb23f18a69d3fB9F4E2A70440B;
    
    //claimDuration = MONTH;
    uint256 public claimDuration = MONTH;
    
    //claimFraction=500
    // multiple by `multiplier` 
    // // 2000 = 2% = (0.02); 
    uint256 public claimFraction=2000;
    
    // this is the amount of ITR which can be sold before any percent restrictions kick in
    uint256 claimExcepted = 30000 * 10 **18;
    
    // (this represents adding 0.01 every `claimDuration`
    // multiple by `multiplier`. means  
    // 100000 = 100% = (1); 
    // 1000 = 1% = (0.01); 
    // 1 = 0.001% = (0.00001);
    uint256 claimGrowth = 100;
    
    
    uint256 private multiplier = 100000;
    uint256 private timeDeployed;
    
    // restriction variables
    uint256 internal lastClaimedTime;
    uint256 internal lastClaimedAmount;
    
    constructor() ERC777("ITR", "ITR", new address[](0)) {
        //_mint(address(this), initialSupply, "", "");
        timeDeployed = block.timestamp;
    }
    
    // cap of total supply
    function maxTotalSupply() public view returns(uint256) {
        return _maxTotalSupply;
    }
    
    // available to claim
    function totalRemaining() public view returns(uint256) {
        return _maxTotalSupply.sub(totalSupply());
    }
    
    /**
     * And make function claim(address) which will 
     * check A = balance of claimToken on address, 
     * and check B = balance of claimToken on self. 
     * If (A + B) * claimFraction / 100000 < B then revert with message “please claim less tokens or wait longer for them to be unlocked”
     */
    function claim(address to) public {
        uint256 a = IERC20(claimToken).balanceOf(to);
        uint256 b = IERC20(claimToken).balanceOf(address(this));

        require(
            b > 0, 
            "insufficient balance"
        );
        
        // require(
        //     (a.add(b)).mul(claimFraction).div(multiplier) >= b, 
        //     "please claim less tokens or wait longer for them to be unlocked"
        // );
        
        //if (B > claimExcepted) and (A + B) * claimFraction < B * (1 + claimGrowth * d) then REVERT
        //// dev
        // irb(main):027:0> 100*(1+0.01)
        // => 101.0
        // irb(main):034:0> 100*(1*100+(0.01)*100)/100.0
        // => 101.0
        // irb(main):035:0> 100*(1*10000+(0.01)*10000)/10000.0
        // => 101.0
        // -----
        if (
            (b > claimExcepted) &&
            
            // ((a.add(b)).mul(claimFraction).div(multiplier) < b.mul(
            //                                                         uint256(1).mul(multiplier).add(
            //                                                             claimGrowth.mul(getGrowthIntervalsPassed())
            //                                                             )
            //                                                       ) 
            // )
            
            //B > (A + B) * (claimFraction + claimGrowth * d) / 100000
            (
                b > (
                    (a.add(b)).mul(
                                claimFraction.mul(multiplier).add(
                                    claimGrowth.mul(getGrowthIntervalsPassed())
                                )
                            ).div(multiplier)
                )
            )
        ) {
            revert("please claim less tokens or wait longer for them to be unlocked");
        }
         
        uint256 indexInterval = (block.timestamp).div(claimDuration).mul(claimDuration);
        if (indexInterval == lastClaimedTime) {
            lastClaimedAmount = lastClaimedAmount.add(b);
        } else {
            indexInterval = lastClaimedTime;
            lastClaimedAmount = b;
        }
        
        require(
            (_maxTotalSupply).mul(claimFraction).div(multiplier) >= lastClaimedAmount, 
            "please wait, too many tokens already claimed during this time period"
        );
        
        
        // let's claim 
        _mint(to, b, "", "");
        //_send(address(this), to, b, "", "", false);
        IERC20(claimToken).transfer(deadAddress, b);
        
    }
    
    function getGrowthIntervalsPassed() internal view returns(uint256) {
        return (block.timestamp.sub(timeDeployed)).div(claimGrowth);
    }
}