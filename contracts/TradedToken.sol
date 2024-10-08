// SPDX-License-Identifier: AGPL
pragma solidity 0.8.24;

/**
 * @title TradedTokenContract
 * @notice A token designed to be traded on decentralized exchanges
 *   in an orderly and safe way with multiple guarantees.
 * @dev Works best with Uniswap v2 and its clones, like Pancakeswap
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "@intercoin/liquidity/contracts/interfaces/ILiquidityLib.sol";
import "@intercoin/sales/contracts/interfaces/ISales.sol";
import "@intercoin/sales/contracts/interfaces/IPresale.sol";

import "./libs/FixedPoint.sol";
import "./libs/TaxesLib.sol";
import "./minimums/libs/MinimumsLib.sol";
import "./helpers/Liquidity.sol";

import "./interfaces/ITradedToken.sol";
import "./interfaces/ITokenExchange.sol";
import "./interfaces/IStructs.sol";

//import "hardhat/console.sol";

contract TradedToken is Ownable, IERC777Recipient, IERC777Sender, ERC777, ReentrancyGuard, ITradedToken {
   // using FixedPoint for *;
    using MinimumsLib for MinimumsLib.UserStruct;
    using SafeERC20 for ERC777;
    using Address for address;
    using TaxesLib for TaxesLib.TaxesInfo;

    ILiquidityLib public immutable liquidityLib;
    Liquidity internal internalLiquidity;
    TaxesLib.TaxesInfo public taxesInfo;
    
    struct Bucket {
        uint256 remainingToSell;
        uint64 lastBucketTime;
    }

    struct RateLimit {
        uint32 duration; // for time ranges, 32 bits are enough, can also define constants like DAY, WEEK, MONTH
        uint32 fraction; // out of 10,000
    }

    struct TaxStruct {
        uint16 buyTaxMax;
        uint16 sellTaxMax;
        uint16 holdersMax;
    }
    struct BuySellStruct {
        address buySellToken;
        uint256 buyPrice;
        uint256 sellPrice;
    }

    struct CommonSettings {
        string tokenName;
        string tokenSymbol;
        address reserveToken; //” (USDC)
        uint256 priceDrop;
        uint64 durationSendBack;
    }

    struct SendBack {
        uint256 amount;
        uint64 untilTime;
    }

    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    
    uint64 public claimsEnabledTime;
  
    /**
     * 
     * @notice traded token address
     */
    address public immutable tradedToken;

    /**
     * 
     * @notice reserve token address
     */
    address public immutable reserveToken;

    RateLimit public panicSellRateLimit;

    /**
     * 
     * @notice uniswap v2 pair
     */
    address public immutable uniswapV2Pair;

    address internal immutable uniswapRouterFactory;
    address internal immutable uniswapRouter;
    
    bool internal buyPaused;
    bool private addedInitialLiquidityRun;

    uint64 internal constant FRACTION = 10000;
    uint64 internal constant LOCKUP_INTERVAL = 1 days; //24 * 60 * 60; // day in seconds
    
    uint64 internal immutable lockupDays;

    uint16 public immutable buyTaxMax;
    uint16 public immutable sellTaxMax;
    uint16 public holdersMax;
    uint16 public holdersCount;
    uint256 public holdersThreshold;

    uint256 public totalBought;

    /**
     * @notice address of token used to buy and sell, default is native coin
     */
    address public immutable buySellToken;
    /**
     * @notice TradedToken buy price in buySellToken, 0 means BuySellNotAvailable
     */
    uint256 public buyPrice;
    /**
     * @notice TradedToken sell price in buySellToken, should be less than buyPrice
     */
    uint256 public sellPrice;
    /**
     * @notice duration time when user can send previous amount back to exchange
     */
    uint64 durationSendBack;

    mapping(address => MinimumsLib.UserStruct) internal tokensLocked;

    mapping(address => uint64) public managers;
    mapping(address => uint64) public presales;
    mapping(address => uint64) public sales;
    mapping(address => Bucket) private _buckets;

    mapping(address => uint64) public communities;
    mapping(address => uint64) public exchanges;
    mapping(address => uint64) public sources;
    mapping(address => uint256) public availableToSell;
    mapping(address => SendBack) public canSendBack;

    address internal governor;
 
    event AddedLiquidity(uint256 tradedTokenAmount);
    event AddedManager(address account, address sender);
    event RemovedManager(address account, address sender);
    event AddedInitialLiquidity(uint256 tradedTokenAmount, uint256 reserveTokenAmount);
    event UpdatedTaxes(uint256 sellTax, uint256 buyTax);
    event Claimed(address account, uint256 amount);
    event Presale(address account, uint256 amount);
    event PresaleTokensBurned(address account, uint256 burnedAmount);
    event Sale(address saleContract, uint64 lockupDays);
    event PanicSellRateExceeded(address indexed holder, address indexed recipient, uint256 amount);
    event IncreasedHoldersMax(uint16 newHoldersMax);
    event IncreasedHoldersThreshold(uint256 newHoldersThreshold);
    event ClaimsEnabled(uint64 claimsEnabledTime);

    error AlreadyCalled();
    error BeforeInitialLiquidityRequired();
    error BuySellNotAvailable();
    error CantCreatePair(address tradedToken, address reserveToken);
    error CantRemove(uint64 untilTime);
    error CantBeZero();
    error CantSendBack();
    error ClaimsDisabled();
    error ClaimsEnabledTimeAlreadySetup();
    error EmptyAddress();
    error EmptyManagerAddress();
    error GovernorOnly();
    error InitialLiquidityRequired();
    error InvalidSellRateLimitFraction();
    error InsufficientAmount();
    error ManagersOnly();
    error MaxHoldersCountExceeded(uint256 count);
    error NotInTheWhiteList();
    error OwnerAndManagersOnly();
    error OwnerOrGovernorOnly();
    error OwnersOnly();
    error TaxesTooHigh();
    error ReserveTokenInvalid();
    error ZeroDenominator();

    /**
     * @param commonSettings imploded common variables to variables to avoid stuck too deep error
     *      tokenName_ token name
     *      tokenSymbol_ token symbol
     *      reserveToken_ reserve token address
     *      priceDrop_ price drop while add liquidity
     * @param claimSettings_ struct of claim settings
     *      minClaimPrice_ (numerator,denominator) minimum claim price that should be after "sell all claimed tokens"
     *      minClaimPriceGrow_ (numerator,denominator) minimum claim price grow
     * @param panicSellRateLimit_ (fraction, duration) if fraction != 0, can sell at most this fraction of balance per interval with this duration
     * @param taxStruct imploded variables to avoid stuck too deep error
     *      buyTaxMax - buyTaxMax
     *      sellTaxMax - sellTaxMax
     *      holdersMax - the maximum number of holders, may be increased by owner later
     * @param buySellStruct  imploded variables to avoid stuck too deep error
     *      buySellToken - token's address is a paying token 
     *      buyPrice - buy price
     *      sellPrice - sell price
     */
    constructor(
        CommonSettings memory commonSettings,
        IStructs.ClaimSettings memory claimSettings_,
        TaxesLib.TaxesInfoInit memory taxesInfoInit,
        RateLimit memory panicSellRateLimit_,
        TaxStruct memory taxStruct,
        BuySellStruct memory buySellStruct,
        IStructs.Emission memory emission_,
        address liquidityLib_
    ) ERC777(commonSettings.tokenName, commonSettings.tokenSymbol, new address[](0)) {

        //setup
        (buyTaxMax,  sellTaxMax,  holdersMax,  buySellToken,  buyPrice,  sellPrice) =
        (taxStruct.buyTaxMax, taxStruct.sellTaxMax, taxStruct.holdersMax, buySellStruct.buySellToken, buySellStruct.buyPrice, buySellStruct.sellPrice);

        tradedToken = address(this);
        reserveToken = commonSettings.reserveToken;
        durationSendBack = commonSettings.durationSendBack;

        // setup swap addresses
        liquidityLib = ILiquidityLib(liquidityLib_);
        (uniswapRouter, uniswapRouterFactory) = liquidityLib.uniswapSettings();
        
        panicSellRateLimit = panicSellRateLimit_;

        taxesInfo.init(taxesInfoInit);

        //validations
        if (sellPrice > buyPrice) {
            revert BuySellNotAvailable();
        }
        if (
            claimSettings_.minClaimPriceGrow.denominator == 0 ||
            claimSettings_.minClaimPrice.denominator == 0
        ) { 
            revert ZeroDenominator();
        }

        if (reserveToken == address(0)) {
            revert ReserveTokenInvalid();
        }

        if (commonSettings.reserveToken == address(0)) {
            revert EmptyAddress();
        }

        // check inputs
        if (uniswapRouter == address(0) || uniswapRouterFactory == address(0)) {
            revert EmptyAddress();
        }
       
        if (buyTaxMax > FRACTION || sellTaxMax > FRACTION) {
            revert TaxesTooHigh();
        }

        if (panicSellRateLimit_.fraction > FRACTION) {
            revert InvalidSellRateLimitFraction();
        }

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_SENDER_INTERFACE_HASH, address(this));
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        //create Pair
        uniswapV2Pair = IUniswapV2Factory(uniswapRouterFactory).createPair(tradedToken, reserveToken);

        if (uniswapV2Pair == address(0)) {
            revert CantCreatePair(tradedToken, reserveToken);
        }

        internalLiquidity = new Liquidity(tradedToken, reserveToken, uniswapV2Pair, commonSettings.priceDrop, liquidityLib_, emission_, claimSettings_);

        fillExchangesAndCommunities();
    }

    /**
     * @notice Fills the exchanges and communities mappings with initial values
     */
    function fillExchangesAndCommunities()  internal {
        communities[address(0)] = type(uint64).max; // minting
        communities[address(this)] = type(uint64).max;
        communities[owner()] = type(uint64).max;
        communities[address(internalLiquidity)] = type(uint64).max;

        //exchanges
        exchanges[address(uniswapV2Pair)] = type(uint64).max;
        
    }

    ////////////////////////////////////////////////////////////////////////
    // external section ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
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
     * @notice Adds a manager to the contract who can take certain actions even after ownership is renounced
     * @param manager The address of the manager to be added
     */
    function addManager(
        address manager
    )
        external
        onlyOwner
    {
        if (manager == address(0)) {revert EmptyManagerAddress();}
        managers[manager] = _currentBlockTimestamp();
        _manageCommunities(manager, type(uint64).max);

        emit AddedManager(manager, _msgSender());
    }

    /**
     * @notice Removes multiple managers from the contract
     * @param managers_ Array of manager addresses to be removed
     */
    function removeManagers(
        address[] memory managers_
    )
        external
        onlyOwner
    {
        for (uint256 i = 0; i < managers_.length; i++) {
            if (managers_[i] == address(0)) {revert EmptyManagerAddress();}
            delete managers[managers_[i]];
            _manageCommunities(managers_[i], 0);

            emit RemovedManager(managers_[i], _msgSender());
        }
    }

    /**
     * @notice set taxes that are burned when buying/selling
     *  from Uniswap v2 liquidity pool. Callable by owner.
     * @param newBuyTax Buy tax
     * @param newSellTax Sell tax
     * 
     */
    function setTaxes(uint16 newBuyTax, uint16 newSellTax) external onlyOwner {
        if (newBuyTax > buyTaxMax || newSellTax > sellTaxMax) {
            revert TaxesTooHigh();
        }

        taxesInfo.setTaxes(newBuyTax, newSellTax);
        emit UpdatedTaxes(taxesInfo.toSellTax, taxesInfo.toBuyTax);
    }
    
    /**
     * @notice increase the maximum number of holders of the token,
     *   which may be capped for legal reasons. A initial holdersMax of 0
     *   means there is no restriction on max holders.
     * @param newMax The new maximum amount of holders, must be higher than before
     * 
     */
    function increaseHoldersMax(uint16 newMax) external onlyOwner {
        if (newMax > holdersMax && holdersMax != 0) {
            holdersMax = newMax;
            emit IncreasedHoldersMax(holdersMax);
        }        
    }

    /**
     * @notice increase the threshold of what counts as a holder.
     *   By default, the threshold is 0, meaning any nonzero balance
     *   makes someone a holder.
     * @param newThreshold The new threshold
     * 
     */
    function increaseHoldersThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold > holdersThreshold) {
            holdersThreshold = newThreshold;
            emit IncreasedHoldersThreshold(holdersThreshold);
        }        
    }

    /**
     * @notice adds initial liquidity to a Uniswap v2 liquidity pool,
     *   which enables trading to take place. Subsequent liquidity
     *   can be added gradually by calling addLiquidity.
     *   Only callable by owner or managers.
     * @param amountTradedToken initial amount of traded tokens
     * @param amountReserveToken initial amount of reserve tokens
     * 
     */
    function addInitialLiquidity(uint256 amountTradedToken, uint256 amountReserveToken) external {
        onlyOwnerAndManagers();
        addLiquidityOnlyOnce();
        if (amountTradedToken == 0 || amountReserveToken == 0) {
            revert ZeroDenominator();
        }
        if (amountReserveToken > ERC777(reserveToken).balanceOf(address(this))) {
            revert InsufficientAmount();
        }
        ///
        __claim(amountTradedToken, address(internalLiquidity));
        ERC777(reserveToken).safeTransfer(address(internalLiquidity), amountReserveToken);

        internalLiquidity.addInitialLiquidity(amountTradedToken, amountReserveToken);
        //---------------------

        emit AddedInitialLiquidity(amountTradedToken, amountReserveToken);
    }

    /**
     * @notice mint some tokens into the account, subject to limits,
     *   only callable by owner or managers
     * @param tradedTokenAmount amount to attempt to claim
     * @param account the account to mint the tokens to
     */
    function claim(uint256 tradedTokenAmount, address account) external {
        onlyOwnerAndManagers();
        
        if (claimsEnabledTime == 0) {
            revert ClaimsDisabled();
        }
        
        internalLiquidity.validateClaim(tradedTokenAmount, account);
        
        _claim(tradedTokenAmount, account);
    }

    /**
     * @notice Enables claims
     */
    function enableClaims() external onlyOwner {
        if (claimsEnabledTime != 0) {
            revert ClaimsEnabledTimeAlreadySetup();
        }
        claimsEnabledTime = uint64(block.timestamp);
        emit ClaimsEnabled(claimsEnabledTime);
    }

    /**
     * @notice managers can restrict future claims to make sure
     *  that selling all claimed tokens will never drop price below
     *  the newMinimumPrice.
     * @param newMinimumPrice below which the token price on Uniswap v2 pair
     *  won't drop, if all claimed tokens were sold right after being minted.
     *  This price can't increase faster than minClaimPriceGrow per day.
     */
    function restrictClaiming(IStructs.PriceNumDen memory newMinimumPrice) external {
        onlyManagers();
        internalLiquidity.restrictClaiming(newMinimumPrice);
    }

    /**
     * @notice called by owner or managers to automatically sell some tokens and add liquidity
     * @param tradedTokenAmount the amount of tradedToken to use.
     *   Some of it is sold for reserveToken, and the rest is added, together with
     *   the obtained reserveToken, to both sides of the liquidity pool.
     *   Pass zero here to use the maximum amount.
     */
    function addLiquidity(uint256 tradedTokenAmount) external {
        initialLiquidityRequired();
        onlyOwnerAndManagers();
        
        uint256 traded2Swap;
        uint256 traded2Liq;

        (traded2Swap, traded2Liq) = internalLiquidity.calculateSellTradedAndAddLiquidity(tradedTokenAmount);

        _mint(address(internalLiquidity), traded2Swap + traded2Liq, "", "");

        internalLiquidity.swapAndAddLiquidity(traded2Swap, traded2Liq);

        emit AddedLiquidity(tradedTokenAmount);
    }

    /**
     * @notice Add an address to the list of communities.
     * @param addr The address to add to the communities list
     */
    function communitiesAdd(address addr, uint64 timestamp) external {
        onlyGovernor();
        if (timestamp == 0) {
            revert CantBeZero();
        }
        _manageCommunities(addr, timestamp);
    }

    /**
     * @notice Remove an address from the list of communities.
     * @param addr The address to remove from the communities list
     */
    function communitiesRemove(address addr) external {
        onlyGovernor();
        _validateRemoving(communities[addr]);
        _manageCommunities(addr, 0);
    }

    /**
     * @notice Add an address to the list of exchanges.
     * @param addr The address to add to the exchanges list
     */
    function exchangesAdd(address addr, uint64 timestamp) external {
        onlyGovernor();
        if (timestamp == 0) {
            revert CantBeZero();
        }
        _manageExchanges(addr, timestamp);
    }

    /**
     * @notice Remove an address from the list of exchanges.
     * @param addr The address to remove from the exchanges list
     */
    function exchangesRemove(address addr) external {
        onlyGovernor();
        _validateRemoving(exchanges[addr]);
        _manageExchanges(addr, 0);
    }

    /**
     * @notice Add an address to the list of sources.
     * @param addr The address to add to the sources list
     */
    function sourcesAdd(address addr, uint64 timestamp) external {
        onlyGovernor();
        if (timestamp == 0) {
            revert CantBeZero();
        }
        _manageSources(addr, timestamp);
    }

    /**
     * @notice Remove an address from the list of sources.
     * @param addr The address to remove from the sources list
     */
    function sourcesRemove(address addr) external {
        onlyGovernor();
        _validateRemoving(sources[addr]);
        _manageSources(addr, 0);
    }

    /**
     * @notice Set the governor address.
     * @param addr The address to set as the governor
     */
    function setGovernor(address addr) external {
        onlyOwnerAndGovernor();
        governor = addr;
    }
    /**
     * @notice update average price
     */
    function updateAveragePrice() external {
        internalLiquidity.updateAveragePrice();
    }
    
    /**
     * @notice Get the amount of tokens available to claim.
     * @return tradedTokenAmount The amount of tokens available to claim
     */
    function availableToClaim() external view returns(uint256 tradedTokenAmount) {
        bool priceMayBecomeLowerThanMinClaimPrice;
        (tradedTokenAmount,,priceMayBecomeLowerThanMinClaimPrice,,,,,,) = internalLiquidity._availableToClaim(0);
        if (priceMayBecomeLowerThanMinClaimPrice) {
            tradedTokenAmount = 0;
        }
    }

    

    ////////////////////////////////////////////////////////////////////////
    // public section //////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice standard ERC-20 function called by token holder to transfer some amount to recipient
     * @param recipient who to transfer to
     * @param amount the amount to transfer
     * @return bool returns true if transfer is successful
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        // inject into transfer and burn tax from sender
        // two ways:
        // 1. make calculations, burn taxes from sender and do transaction with subtracted values
        if (uniswapV2Pair == _msgSender()) {
            if(!addedInitialLiquidityRun) {
                // prevent added liquidity manually with presale tokens (before adding initial liquidity from here)
                revert InitialLiquidityRequired();
            }
            
            amount = _burnTaxes(_msgSender(), amount, buyTax());
            
        } else {
            //The way a user sends tokens directly to a Uniswap pair in the hope of executing a flash swap.
            amount = _handleTransferToUniswap(_msgSender(), recipient, amount);
        }

        return super.transfer(recipient, amount);

        // 2. do usual transaction, then make calculation and burn tax from sides(buyer or seller)
        // we DON'T USE this case, because have callbacks in _move method: _callTokensToSend and _callTokensReceived
        // and than be send to some1 else in recipient contract callback
    }

    /**
     * @notice standard ERC-20 function called to transfer some amount from holder to recipient
     * @param holder from whom to transfer
     * @param recipient who to transfer to
     * @param amount the amount to transfer
     * @return bool returns true if transfer is successful
     */
    function transferFrom(address holder, address recipient,uint256 amount) public virtual override returns (bool) {
        amount = _handleTransferToUniswap(holder, recipient, amount);
        return super.transferFrom(holder, recipient, amount);
    }

    /**
     * @notice Buys tokens for a fixed price in reserveToken
     * @param amount Amount to buy
     */
    function buy(uint256 amount) public payable {
        if (buyPrice == 0 || buyPaused) {
            revert BuySellNotAvailable();
        }

        if (buySellToken == address(0)) {
            amount = msg.value;
        } else {
            IERC20(buySellToken).transferFrom(msg.sender, address(this), amount);
        }
        _mint(msg.sender, amount * FRACTION / buyPrice, "", "");
        totalBought += amount;
    }

    /**
     * @notice Sells TradedTokens for a fixed price in reserveToken
     * @param amount Amount to sell
     */
    function sell(uint256 amount) public {
        if (sellPrice == 0) {
            revert BuySellNotAvailable();
        }
        uint256 out = amount * sellPrice / FRACTION;
        if (buySellToken == address(0)) {
            if (address(this).balance < out) {
                revert InsufficientAmount();
            }
            // see https://ethereum.stackexchange.com/a/56760/19734
            (bool sent, /*bytes memory data*/) = address(msg.sender).call{value: out}("");
            if (!sent) {
                revert BuySellNotAvailable();
            }
        } else {
            if (IERC20(buySellToken).balanceOf(address(this)) < out) {
                revert InsufficientAmount();
            }
            IERC20(buySellToken).transfer(msg.sender, amount);
        }
    }

    /**
     * @notice used to pause buying, e.g. if buySellToken is compromised
     * @param status New status of buying
     */
    function pauseBuy(bool status) public {
        //onlyOwnerAndManagers();
        onlyOwnerAndGovernor();
        buyPaused = status;
    }

    /**
     * @notice register a presale that can take place before trading begins
     * @dev The presale contract must have a method called endTime() which returns uint64 timestamp,
     *  and which occurs at least two hours after block.timestamp
     * @param contract_ the address of the contract that will manage the presale.
     * @param amount amount of tokens to mint to the contract, this is the maximum taht can be sold in the presale
     * @param presaleLockupDays the number of days people who obtained the token in the presale cannot transfer tokens for
     */
    function startPresale(address contract_, uint256 amount, uint64 presaleLockupDays) public onlyOwner {

        onlyBeforeInitialLiquidity();
        if (contract_ == address(0)) {
            revert EmptyAddress();
        }
        uint64 endTime = IPresale(contract_).endTime();

        // give at least two hours for the presale because burnRemaining can be called in the second hour
        if (block.timestamp < endTime - 3600 * 2) {
            _mint(contract_, amount, "", "");
            presales[contract_] = sales[contract_] = presaleLockupDays;
            _manageExchanges(contract_, type(uint64).max);
            emit Presale(contract_, amount);
        }
    }
	
    /**
    * @notice owner of a smart contract can designate it as a Sale contract
	*   to enforce lockups and exclude it from MaxHolders checks
    * @param contract_ the sale contract but msg.sender must be the owner
    * @param saleLockupDays the number of days people who obtained the token in the sale cannot transfer tokens for
    */
	function startSale(address contract_, uint64 saleLockupDays) public {

        if (contract_ == address(0)) {
            revert EmptyAddress();
        }
        
        if (ISales(contract_).owner() != msg.sender) {
			revert OwnersOnly();
		}
        
		if (sales[contract_] != 0) {
			revert AlreadyCalled();
		}
		sales[contract_] = saleLockupDays;
        _manageExchanges(contract_, type(uint64).max);
		emit Sale(contract_, saleLockupDays);
	}

    /**
    * @notice starting one hour before a presale's endTime(),
    *  anyone can call this function to burn its remaining tokens.
    *  Someone should do it before endTime() in case the presale
    *  contract allows someone to withdraw the remianing tokens later.
    * @param contract_ the presale contract
    */
    function burnRemaining(address contract_) public {
        uint64 endTime = IPresale(contract_).endTime();

        // allow it one hour before the endTime, so owner can't withdraw money
        if (block.timestamp <= endTime - 3600) {
            return;
        }

        uint256 toBurn = balanceOf(contract_);
        if (toBurn == 0) {
            return;
        }

        _burn(contract_, toBurn, "", "");
        emit PresaleTokensBurned(contract_, toBurn);
    }

    /**
     * @notice Retrieves the locked amount for an address
     * @param from Address for which the locked amount is to be retrieved
     * @return The locked amount
     */
    function getLockedAmount(address from) public view returns(uint256) {
        return tokensLocked[from]._getMinimum();
    }
    
    /**
     * @notice get the current buy tax
     * @return the fraction out of 10000 representing the tax
     */
    function buyTax() public view returns(uint16) {
        return taxesInfo.buyTax();
    }

    /**
     * @notice get the current sell tax
     * @return the fraction out of 10000 representing the tax
     */
    function sellTax() public view returns(uint16) {
        return taxesInfo.sellTax();
    }

    ////////////////////////////////////////////////////////////////////////
    // internal section ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    /**
     * @notice burn taxes during a transfer
     * @param holder from whom to transfer
     * @param amount the amount to transfer
     * @param tax the fraction out of 10000 representing the tax
     * @return amount remaining
     */
    function _burnTaxes(address holder, uint256 amount, uint16 tax) internal returns(uint256) {
        uint256 taxAmount = (amount * tax) / FRACTION;
        if (taxAmount != 0) {
            amount -= taxAmount;
            _burn(holder, taxAmount, "", "");
        }
        return amount > 1 ? amount : 1; // to avoid transferring 0 in edge cases, transfer a tiny amount
    }

    /**
     * @notice Prevents panic selling by limiting the amount a holder can sell
     * @param holder The address of the holder
     * @param recipient The address of the recipient
     * @param amount The amount of tokens to transfer
     * @return adjustedAmount The adjusted amount based on the panic sell rate limit
     */
    function _preventPanic(address holder, address recipient, uint256 amount) internal returns(uint256 adjustedAmount) {
        if (
            holder == address(internalLiquidity) ||
            recipient == address(internalLiquidity) ||
            panicSellRateLimit.fraction == 0 ||
            panicSellRateLimit.duration == 0

        ) {
            return amount;
        }
        
        uint256 currentBalance = balanceOf(holder);

        if (block.timestamp / panicSellRateLimit.duration * panicSellRateLimit.duration > _buckets[holder].lastBucketTime) {
            _buckets[holder].lastBucketTime = uint64(block.timestamp);
            _buckets[holder].remainingToSell = currentBalance * panicSellRateLimit.fraction / FRACTION;
        }

        if (_buckets[holder].remainingToSell == 0) {
            emit PanicSellRateExceeded(holder, recipient, amount);
            return 5;
        }

        if (amount > _buckets[holder].remainingToSell) {
            amount = _buckets[holder].remainingToSell;
        }

        _buckets[holder].remainingToSell -= amount;
        return amount;
    }

    function holdersCheckBeforeTransfer(address from, address to, uint256 amount) internal {
        
        if (to != address(0) && from != to) {
        
            uint256 toBalanceOf = balanceOf(to);

            if (
                toBalanceOf <= holdersThreshold && 
                toBalanceOf + amount > holdersThreshold           
            ) {

				if (sales[to] == 0) {
					++holdersCount;
				}

                if (holdersMax != 0) {
                    // onlyOwnerAndManagers and internalLiquidity and presales
                    // with lockups can send tokens to new users, in that case.
                    // here we exclude transactions such as:
                    // 1. address(this) -> internalLiquidity
                    // 2. internalLiquidity -> uniswap
                    // 3. presale -> early buyer of locked-up tokens
                    if (from != address(this)
                    && from != address(internalLiquidity)
                    && from != address(0)
                    && presales[from] == 0
					&& sales[to] == 0) {
                        onlyOwnerAndManagers();
                    }
                    
                    if (holdersCount > holdersMax) {
                        revert MaxHoldersCountExceeded(holdersMax);
                    }
                }
            }
        }

        if (from != address(0) && from != to) {
            uint256 fromBalanceOf = balanceOf(from);
            if (fromBalanceOf < amount) {
                // will revert inside transferFrom or transfer method
            } else {
                if (
                    fromBalanceOf > holdersThreshold
                    && fromBalanceOf - amount <= holdersThreshold
                    
                ) {
                    if ((sales[from]) == 0) {
                        --holdersCount;
                    }
                }
            }
        }
    }

    // can only add liquidity once
    function addLiquidityOnlyOnce() internal {
        if (addedInitialLiquidityRun) {
            revert AlreadyCalled();
        }
        addedInitialLiquidityRun = true;
    }

    // called before any transfer
    function _beforeTokenTransfer(address /*operator*/, address from, address to, uint256 amount) internal virtual override {
        //communities can receive from anyone, and send to anyone (subject to optional maxHolders threshold)
        //exchanges can only send, not receive unless it is from a community
        //3 regular accounts can send to communities (this was already described in 1)
        bool willRevert = true;
        if (
            communities[from] != 0 || 
            communities[to] != 0 || 
            exchanges[from] != 0
        ) {
            willRevert = false;
        }

        if (sources[from] != 0) {
            availableToSell[to] += amount;
            willRevert = false;
        }
        /*
        if (exchanges[to] != 0 && (availableToSell[from] >= amount)) {
            availableToSell[from] -= amount;
            willRevert = false;
        }

        if (
            from != address(internalLiquidity) && //exclude check addingLiquidity
            exchanges[to] != 0
        ) {
            if
            (
                canSendBack[from].amount >= amount && 
                canSendBack[from].untilTime >= uint64(block.timestamp)
            ) {
                canSendBack[from].amount -= amount;
                canSendBack[from].untilTime = 0;
            } else {
                revert CantSendBack();
            }
        }
        */
       if (
            from != address(internalLiquidity) && //exclude check addingLiquidity
            exchanges[to] != 0
        ) {
            if (availableToSell[from] >= amount) {
                availableToSell[from] -= amount;
                willRevert = false;
            } else if (
                canSendBack[from].amount >= amount && 
                canSendBack[from].untilTime >= uint64(block.timestamp)
            ) {
                canSendBack[from].amount -= amount;
                canSendBack[from].untilTime = 0;
            } else {
                revert CantSendBack();
            }
        }

        if (willRevert) {
            revert NotInTheWhiteList();
        }       

        

        // save amount which user can send back to exchange
        if (exchanges[from] != 0) {
            _setSendBackAmount(to, amount);
        }      

        holdersCheckBeforeTransfer(from, to, amount);
        if (sales[from] != 0) {
            if (ISales(from).owner() != to) {
                tokensLocked[to]._minimumsAdd(amount, sales[from], LOCKUP_INTERVAL, true);
            }
        }
        if (
            // if minted
            (from == address(0)) ||
            // or burnt itself
            (from == address(this) && to == address(0)) // ||
        ) {
            //skip validation
        } else {
            uint256 balance = balanceOf(from);
            uint256 locked = tokensLocked[from]._getMinimum();

            if (balance - locked < amount) {
                revert InsufficientAmount();
            }

         }
    }

    /**
     * @notice do claim to the `account` and locked tokens if
     */
    function _claim(uint256 tradedTokenAmount, address account) internal {

        _setSendBackAmount(account, tradedTokenAmount);

        __claim(tradedTokenAmount, account);
        
        emit Claimed(account, tradedTokenAmount);
    }

    function __claim(uint256 tradedTokenAmount, address account) internal {
        _mint(account, tradedTokenAmount, "", "");
    }

    function _manageCommunities(address addr, uint64 timestamp) internal {
        communities[addr] = timestamp;
    }

    function _manageExchanges(address addr, uint64 timestamp) internal {
        exchanges[addr] = timestamp;
    }
    function _manageSources(address addr, uint64 timestamp) internal {
        sources[addr] = timestamp;
    }

    function _validateRemoving(uint64 timestamp) internal view {
        if (block.timestamp < timestamp)  {
            revert CantRemove(timestamp);
        }
    }

    function _handleTransferToUniswap(address holder, address recipient, uint256 amount) internal returns(uint256) {
        if (isUniswapV2Pair(recipient)) {
            if(!addedInitialLiquidityRun) {
                // prevent added liquidity manually with presale tokens (before adding initial liquidity from here)
                revert InitialLiquidityRequired();
            }
            if(holder != address(internalLiquidity)) {
                // prevent panic when user will sell to uniswap
                amount = _preventPanic(holder, recipient, amount);
                // burn taxes from remainder
                amount = _burnTaxes(holder, amount, sellTax());
            }
        }
        return amount;
    }

    function _setSendBackAmount(address account, uint256 amount) internal {
        canSendBack[account].amount = amount;
        canSendBack[account].untilTime = uint64(block.timestamp) + durationSendBack;
    }
    
    /**
     * @notice Checks if the message sender is the owner or a manager
     */
    function onlyOwnerAndManagers() internal view {
        if (owner() != _msgSender() && managers[_msgSender()] == 0) {
            revert OwnerAndManagersOnly();
        }
    }

    /**
     * @notice Checks if the message sender is a manager only
     */
    function onlyManagers() internal view {
        if (managers[_msgSender()] == 0) {
            revert ManagersOnly();
        }
    }

    /**
     * @notice Checks if the message sender is the owner or governor
     */
    function onlyOwnerAndGovernor() internal view {
        if (owner() != _msgSender() && governor != _msgSender()) {
            revert OwnerOrGovernorOnly();
        }
    }

    /**
     * @notice Checks if the message sender is the governor only
     */
    function onlyGovernor() internal view {
        if (governor != _msgSender()) {
            revert GovernorOnly();
        }
    }

    /**
     * @notice Retrieves the current block timestamp within the range of uint32
     * @return The current block timestamp
     */
    function _currentBlockTimestamp() internal view returns (uint64) {
        return uint64(block.timestamp);
    }

    /**
     * @notice Ensures that initial liquidity has been added
     */
    function initialLiquidityRequired() internal view {
        if (!addedInitialLiquidityRun) {
            revert InitialLiquidityRequired();
        }
    }

    /**
     * @notice Ensures that it is before initial liquidity has been added
     */
    function onlyBeforeInitialLiquidity() internal view{
        if (addedInitialLiquidityRun) {
            revert BeforeInitialLiquidityRequired();
        }
    }

    /**
     * @notice Checks if the recipient is a Uniswap V2 pair contract
     * @param addr The address to check
     * @return True if the address is a Uniswap V2 pair contract, false otherwise
     */
    function isUniswapV2Pair(address addr) internal view returns(bool) {
        if (addr.isContract()) {
            try IUniswapV2Pair(addr).factory() returns (address f) {
                if (f == uniswapRouterFactory) {
                    return true;
                }
            } catch Error(string memory/* _err*/) {
                // do nothing
            } catch (bytes memory/* _err*/) {
                // do nothing
            }
        }
        return false;
    }
    
}
