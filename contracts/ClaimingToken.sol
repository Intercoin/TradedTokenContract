// SPDX-License-Identifier: AGPL
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ClaimingToken
 * @dev Works with Claiming managers
 */
contract ClaimingToken is Ownable, ERC20 {
    
    constructor(
        string memory name_, 
        string memory symbol_
    ) 
        ERC20(name_, symbol_)
        Ownable()
    {
        
    }

    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }
}