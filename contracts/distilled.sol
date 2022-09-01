// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./libs/SwapSettingsLib.sol";
import "./libs/FixedPoint.sol";
import "./minimums/libs/MinimumsLib.sol";
import "./ExecuteManager.sol";
import "./Liquidity.sol";
contract Main is Ownable, IERC777Recipient, IERC777Sender, ERC777, ExecuteManager {
    using FixedPoint for *;
    using MinimumsLib for MinimumsLib.UserStruct;
    struct PriceNumDen {
        uint256 numerator;
        uint256 denominator;
    }
    struct Observation {
        uint64 timestampLast;
        uint256 price0CumulativeLast;
        FixedPoint.uq112x112 price0Average;
    }
    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    address private constant deadAddress = 0x000000000000000000000000000000000000dEaD;
    address public immutable tradedToken;
    address public immutable reserveToken;
    uint256 public immutable priceDrop;
    PriceNumDen minClaimPrice;
    address public externalToken;
    PriceNumDen externalTokenExchangePrice;
    address public uniswapV2Pair;
    address internal uniswapRouter;
    address internal uniswapRouterFactory;
    bool internal immutable token01;
    bool internal alreadyRunStartupSync;
    uint64 internal constant averagePriceWindow = 5;
    uint64 internal constant FRACTION = 10000;
    uint64 internal constant LOCKUP_INTERVAL = 24 * 60 * 60; // day in seconds
    uint64 internal startupTimestamp;
    uint64 internal lockupIntervalAmount;
    uint256 public immutable buyTaxMax;
    uint256 public immutable sellTaxMax;
    uint256 public buyTax;
    uint256 public sellTax;
    uint256 public totalCumulativeClaimed;
    Liquidity internal internalLiquidity;
    Observation internal pairObservation;
    mapping(address => MinimumsLib.UserStruct) internal tokensLocked;
    mapping(address => uint64) internal managers;
    event AddedLiquidity(uint256 tradedTokenAmount, uint256 priceAverageData);
    modifier onlyManagers() {
        require(owner() == _msgSender() || managers[_msgSender()] != 0, "MANAGERS_ONLY");
        _;
    }
    constructor(string memory tokenName_, string memory tokenSymbol_, address reserveToken_, uint256 priceDrop_, uint64 lockupIntervalAmount_, PriceNumDen memory minClaimPrice_, address externalToken_, PriceNumDen memory externalTokenExchangePrice_, uint256 buyTaxMax_, uint256 sellTaxMax_)
    ERC777(tokenName_, tokenSymbol_, new address[](0)) {
        buyTaxMax = buyTaxMax_;
        sellTaxMax = sellTaxMax_;
        require(reserveToken_ != address(0), "reserveToken invalid");
        tradedToken = address(this);
        reserveToken = reserveToken_;
        priceDrop = priceDrop_;
        lockupIntervalAmount = lockupIntervalAmount_;
        minClaimPrice.numerator = minClaimPrice_.numerator;
        minClaimPrice.denominator = minClaimPrice_.denominator;
        externalToken = externalToken_;
        externalTokenExchangePrice.numerator = externalTokenExchangePrice_.numerator;
        externalTokenExchangePrice.denominator = externalTokenExchangePrice_.denominator;
        (uniswapRouter, uniswapRouterFactory) = SwapSettingsLib.netWorkSettings();
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_SENDER_INTERFACE_HASH, address(this));
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
        uniswapV2Pair = IUniswapV2Factory(uniswapRouterFactory).createPair(tradedToken, reserveToken);
        require(uniswapV2Pair != address(0), "can't create pair");
        startupTimestamp = currentBlockTimestamp();
        pairObservation.timestampLast = currentBlockTimestamp();
        token01 = (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) ? true : false;
        internalLiquidity = new Liquidity(tradedToken, reserveToken, uniswapRouter);
    }

    function tokensReceived(address operator, address from, address to, uint256 amount, bytes calldata userData, bytes calldata operatorData) external {}
    function tokensToSend(address operator, address from, address to, uint256 amount, bytes calldata userData, bytes calldata operatorData) external {}
    function addManagers(address manager) public onlyManagers {
        managers[manager] = currentBlockTimestamp(); }
    function setBuyTax(uint256 fraction) public onlyOwner {
        require(fraction <= buyTaxMax, "FRACTION_INVALID");
        buyTax = fraction; }
    function setSellTax(uint256 fraction) public onlyOwner {
        require(fraction <= sellTaxMax, "FRACTION_INVALID");
        sellTax = fraction; }
    function addInitialLiquidity(uint256 amountTradedToken, uint256 amountReserveToken) public onlyOwner runOnlyOnce {
        require(amountReserveToken <= ERC777(reserveToken).balanceOf(address(this)), "INSUFFICIENT_RESERVE");
        _claim(amountTradedToken, address(this));
        ERC777(tradedToken).transfer(address(internalLiquidity), amountTradedToken);
        ERC777(reserveToken).transfer(address(internalLiquidity), amountReserveToken);
        internalLiquidity.addLiquidity(); }
    function claim(uint256 tradedTokenAmount) public onlyManagers {
        _validateClaim(tradedTokenAmount);
        _claim(tradedTokenAmount, msg.sender); }
    function claim(uint256 tradedTokenAmount, address account) public onlyManagers {
        _validateClaim(tradedTokenAmount);
        _claim(tradedTokenAmount, account); }
    function claimViaExternal(uint256 externalTokenAmount, address account) public {
        require(externalToken != address(0), "EMPTY_EXTERNALTOKEN");
        require(externalTokenAmount <= ERC777(externalToken).allowance(msg.sender, address(this)), "INSUFFICIENT_AMOUNT");
        ERC777(externalToken).transferFrom(msg.sender, deadAddress, externalTokenAmount);
        uint256 tradedTokenAmount = (externalTokenAmount * externalTokenExchangePrice.numerator) / externalTokenExchangePrice.denominator;
        _validateClaim(tradedTokenAmount);
        _claim(tradedTokenAmount, account); }
    function addLiquidity(uint256 tradedTokenAmount) public onlyManagers {
        singlePairSync();
        uint256 tradedReserve1, tradedReserve2, uint256 priceAverageData, rTraded, rReserved, traded2Swap, traded2Liq, reserved2Liq;
        FixedPoint.uq112x112 memory averageWithPriceDrop;
        (tradedReserve1, tradedReserve2, priceAverageData) = _maxAddLiquidity();
        bool err;
        if (tradedReserve1 < tradedReserve2 && tradedTokenAmount <= (tradedReserve2 - tradedReserve1)) {
            err = false;
        } else {
            err = true;
        }
        if (err == false) {
            if (tradedTokenAmount == 0) {
                tradedTokenAmount = tradedReserve2 - tradedReserve1;
            }
            (rTraded, rReserved, traded2Swap, traded2Liq, reserved2Liq) = _calculateSellTradedAndLiquidity(tradedTokenAmount);
            averageWithPriceDrop = (
                FixedPoint
                    .uq112x112(uint224(priceAverageData))
                    .muluq(FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop)))
                    .muluq(FixedPoint.fraction(1, FRACTION))
            );
            if (FixedPoint.fraction(rReserved, rTraded + traded2Swap + traded2Liq)._x <= averageWithPriceDrop._x) {
                err = true;
            }
        }
        require(err == false, "PRICE_DROP_TOO_BIG");
        _doSellTradedAndLiquidity(traded2Swap, traded2Liq);
        emit AddedLiquidity(tradedTokenAmount, priceAverageData);
        update(); }
    function transferFrom(address holder, address recipient, uint256 amount) public virtual override returns (bool) {
        if (uniswapV2Pair == recipient) {
            uint256 taxAmount = (amount * sellTax) / FRACTION;
            if (taxAmount != 0) {
                amount -= taxAmount;
                _burn(holder, taxAmount, "", "");
            }
        }
        return super.transferFrom(holder, recipient, amount); }
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        if (uniswapV2Pair == _msgSender()) {
            uint256 taxAmount = (amount * buyTax) / FRACTION;

            if (taxAmount != 0) {
                amount -= taxAmount;
                _burn(_msgSender(), taxAmount, "", "");
            }
        }
        return super.transfer(recipient, amount); }
    function singlePairSync() internal {
        if (alreadyRunStartupSync == false) {
            alreadyRunStartupSync = true;
            IUniswapV2Pair(uniswapV2Pair).sync();
        } }
    function _beforeTokenTransfer(address, /*operator*/ address from, address to, uint256 amount) internal virtual override {
        if ((from == address(0)) || (from == address(this) && to == address(0))) {
            //skip validation
        } else {
            uint256 balance = balanceOf(from);
            uint256 locked = tokensLocked[from]._getMinimum();
            require(balance - locked >= amount, "INSUFFICIENT_AMOUNT");
        } }
    function currentBlockTimestamp() internal view returns (uint64) {
        return uint64(block.timestamp % 2**64);
    }
    function _uniswapReserves() internal view returns (uint112, uint112, uint32) {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(uniswapV2Pair).getReserves();
        require(reserve0 != 0 && reserve1 != 0, "RESERVES_EMPTY");

        if (token01) {
            return (reserve0, reserve1, blockTimestampLast);
        } else {
            return (reserve1, reserve0, blockTimestampLast);
        }
    }
    function _validateClaim(uint256 tradedTokenAmount) internal view {
        (uint112 _reserve0, uint112 _reserve1, ) = IUniswapV2Pair(uniswapV2Pair).getReserves();
        uint256 currentIterationTotalCumulativeClaimed = totalCumulativeClaimed + tradedTokenAmount;
        // amountin reservein reserveout
        uint256 amountOut = IUniswapV2Router02(uniswapRouter).getAmountOut(
            currentIterationTotalCumulativeClaimed,
            _reserve0,
            _reserve1
        );
        require(amountOut > 0, "CLAIM_VALIDATION_ERROR");
        require(FixedPoint.fraction(_reserve1 - amountOut, _reserve0 + currentIterationTotalCumulativeClaimed)._x >
                FixedPoint.fraction(minClaimPrice.numerator, minClaimPrice.denominator)._x,
                "PRICE_HAS_BECOME_A_LOWER_THAN_MINCLAIMPRICE"); }
    function _claim(uint256 tradedTokenAmount, address account) internal {
        totalCumulativeClaimed += tradedTokenAmount;
        _mint(account, tradedTokenAmount, "", "");
        if (_msgSender() != owner() && _msgSender() != address(this)) {
            tokensLocked[account]._minimumsAdd(tradedTokenAmount, lockupIntervalAmount, LOCKUP_INTERVAL, true);
        } }
    function doSwapOnUniswap(address tokenIn, address tokenOut, uint256 amountIn, address beneficiary) internal returns (uint256 amountOut) {
        require(ERC777(tokenIn).approve(address(uniswapRouter), amountIn), "APPROVE_FAILED");
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);
        uint256[] memory outputAmounts = IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(amountIn, 0, path, beneficiary, block.timestamp);
        amountOut = outputAmounts[1]; }
    function tradedAveragePrice() internal view returns (FixedPoint.uq112x112 memory) {
        uint64 blockTimestamp = currentBlockTimestamp();
        uint256 price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
        uint64 timeElapsed = blockTimestamp - pairObservation.timestampLast;
        uint64 windowSize = ((blockTimestamp - startupTimestamp) * averagePriceWindow) / FRACTION;
        if (timeElapsed > windowSize && timeElapsed > 0 && price0Cumulative > pairObservation.price0CumulativeLast) {
            return FixedPoint.uq112x112(uint224(price0Cumulative - pairObservation.price0CumulativeLast) / uint224(timeElapsed));
        } else {
            return pairObservation.price0Average;
        } }
    function update() internal {
        uint64 blockTimestamp = currentBlockTimestamp();
        uint64 timeElapsed = blockTimestamp - pairObservation.timestampLast;
        uint64 windowSize = ((blockTimestamp - startupTimestamp) * averagePriceWindow) / FRACTION;
        if (timeElapsed > windowSize && timeElapsed > 0) {
            uint256 price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
            pairObservation.price0Average = FixedPoint.uq112x112(uint224(price0Cumulative - pairObservation.price0CumulativeLast)).divuq(FixedPoint.encode(timeElapsed));
            pairObservation.price0CumulativeLast = price0Cumulative;
            pairObservation.timestampLast = blockTimestamp;
        }}
    function _calculateSellTradedAndLiquidity(uint256 incomingTradedToken) internal view returns (uint256 rTraded, uint256 rReserved, uint256 traded2Swap, uint256 traded2Liq, uint256 reserved2Liq) {
        (rTraded, rReserved, /*uint256 priceTraded*/) = _uniswapReserves();
        traded2Swap = sqrt((rTraded + incomingTradedToken) * (rTraded)) - rTraded; //
        require(traded2Swap > 0 && incomingTradedToken > traded2Swap, "BAD_AMOUNT");
        reserved2Liq = IUniswapV2Router02(uniswapRouter).getAmountOut(traded2Swap, rTraded, rReserved);
        traded2Liq = incomingTradedToken - traded2Swap; }
    function _doSellTradedAndLiquidity(uint256 traded2Swap, uint256 traded2Liq) internal {
        _mint(address(this), traded2Swap, "", "");
        doSwapOnUniswap(tradedToken, reserveToken, traded2Swap, address(internalLiquidity));
        _mint(address(internalLiquidity), traded2Liq, "", "");
        internalLiquidity.addLiquidity(); }
    function _maxAddLiquidity() internal view returns (uint256, uint256, uint256) {
        uint112 reserve0, reserve1;
        uint32 blockTimestampLast;
        (reserve0, reserve1, blockTimestampLast) = _uniswapReserves();
        FixedPoint.uq112x112 memory priceAverageData = tradedAveragePrice();
        FixedPoint.uq112x112 memory q1 = FixedPoint.encode(uint112(sqrt(reserve0)));
        FixedPoint.uq112x112 memory q2 = FixedPoint.encode(uint112(sqrt(reserve1)));
        FixedPoint.uq112x112 memory q3 = (priceAverageData.muluq(FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop))).muluq(FixedPoint.fraction(1, FRACTION))).sqrt();
        uint256 reserve0New = (q1.muluq(q2).muluq(FixedPoint.encode(uint112(sqrt(FRACTION)))).muluq(FixedPoint.encode(uint112(1)).divuq(q3))).decode();
        return (reserve0, reserve0New, priceAverageData._x); }
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) {
            return 0;
        }
        uint256 xAux = uint256(x);
        result = 1;
        if (xAux >= 0x100000000000000000000000000000000) {
            xAux >>= 128;
            result <<= 64;
        }
        if (xAux >= 0x10000000000000000) {
            xAux >>= 64;
            result <<= 32;
        }
        if (xAux >= 0x100000000) {
            xAux >>= 32;
            result <<= 16;
        }
        if (xAux >= 0x10000) {
            xAux >>= 16;
            result <<= 8;
        }
        if (xAux >= 0x100) {
            xAux >>= 8;
            result <<= 4;
        }
        if (xAux >= 0x10) {
            xAux >>= 4;
            result <<= 2;
        }
        if (xAux >= 0x8) {
            result <<= 1;
        }
        // The operations can never overflow because the result is
        // max 2^127 when it enters this block.
        unchecked {
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1; // Seven iterations should be enough
            uint256 roundedDownResult = x / result;
            return result >= roundedDownResult ? roundedDownResult : result;
        }
    }
}
