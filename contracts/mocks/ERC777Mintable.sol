// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC777/ERC777.sol";

contract ERC777Mintable is ERC777 {
    
    /**
     * 
     */
    constructor (
    ) ERC777 ("erc777name", "erc777symbol", new address[](0))
    {

    }
    
    /**
     * @dev Creates `amount` tokens and send to account.
     *
     * See {ERC20-_mint}.
     */
    function mint(address account, uint256 amount) public virtual {
        _mint(account, amount, "", "");
    }
    
}