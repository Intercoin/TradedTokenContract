// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import "@intercoin/sales/contracts/interfaces/ISales.sol";

contract SaleMock is IERC777Recipient, ISales {

    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    address private _owner;
    constructor() {
        _owner = msg.sender;
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function init(
        address _sellingToken,
        PriceSettings[] memory _priceSettings,
        uint64 _endTime,
        ThresholdBonuses[] memory _bonusSettings,
        EnumWithdraw _ownerCanWithdraw,
        IWhitelist.WhitelistStruct memory _whitelistData,
        LockedInPrice memory _lockedInPrice,
        address _costManager,
        address _producedBy
    ) external {
        //dummy
    }

    function owner() external view returns(address) {
        return _owner;
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