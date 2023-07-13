// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IPresale.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";

contract PresaleMock is IERC777Recipient, IPresale {

    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    uint64 endTimeTs;

    constructor() {
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }
    function setEndTime(uint64 i) public {
        endTimeTs = i;
    }
    function endTime() external view returns (uint64) {
        return endTimeTs;
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {

    }

    function transferTokens(address token, address to, uint256 amount) external {
        IERC777(token).send(to, amount, bytes(""));
    }
}