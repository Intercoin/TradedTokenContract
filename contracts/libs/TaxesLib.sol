// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

library TaxesLib {
    struct TaxesInfo { 
        uint16 fromBuyTax;
        uint16 toBuyTax;
        uint16 fromSellTax;
        uint16 toSellTax;
        uint64 buyTaxTimestamp;
        uint64 sellTaxTimestamp;
        uint64 buyTaxDuration;
        uint64 sellTaxDuration;
        bool buyTaxGradual;
        bool sellTaxGradual;
    } 

    struct TaxesInfoInit { 
        uint16 buyTax;
        uint16 sellTax;
        uint64 buyTaxDuration;
        uint64 sellTaxDuration;
        bool buyTaxGradual;
        bool sellTaxGradual;
    }

    function init(TaxesInfo storage taxesInfo, TaxesInfoInit memory taxesInfoInit) external {
        _setTaxes(taxesInfo, taxesInfoInit.buyTax, taxesInfoInit.sellTax);

        taxesInfo.buyTaxDuration = taxesInfoInit.buyTaxDuration;
        taxesInfo.sellTaxDuration = taxesInfoInit.sellTaxDuration;
        taxesInfo.buyTaxGradual = taxesInfoInit.buyTaxGradual;
        taxesInfo.sellTaxGradual = taxesInfoInit.sellTaxGradual;
    }

    function setTaxes(TaxesInfo storage taxesInfo, uint16 newBuyTax, uint16 newSellTax) external {
        _setTaxes(taxesInfo, newBuyTax, newSellTax);
    }

    function buyTax(TaxesInfo storage taxesInfo) external view returns(uint16) {
        return _buyTax(taxesInfo);
    }

    function sellTax(TaxesInfo storage taxesInfo) external view returns(uint16) {
        return _sellTax(taxesInfo);
    }


    function _buyTax(
        TaxesInfo storage taxesInfo
    ) private view returns(uint16) {
        if (taxesInfo.buyTaxDuration == 0) {
            return taxesInfo.toBuyTax;
        }
        if (
            block.timestamp < (taxesInfo.buyTaxDuration + taxesInfo.buyTaxTimestamp) &&
            block.timestamp >= taxesInfo.buyTaxTimestamp
        ) {
            if (taxesInfo.buyTaxGradual) {
                if (taxesInfo.toBuyTax > taxesInfo.fromBuyTax) {
                    return taxesInfo.fromBuyTax + uint16(uint32(taxesInfo.toBuyTax - taxesInfo.fromBuyTax) * uint32(block.timestamp - taxesInfo.buyTaxTimestamp) / uint32(taxesInfo.buyTaxDuration));
                } else {
                    return taxesInfo.fromBuyTax - uint16(uint32(taxesInfo.fromBuyTax - taxesInfo.toBuyTax) * uint32(block.timestamp - taxesInfo.buyTaxTimestamp) / uint32(taxesInfo.buyTaxDuration));
                }
            } else {
                return taxesInfo.fromBuyTax;
            }
        } else {
            return taxesInfo.toBuyTax;
        }
        
    }

    function _sellTax(
        TaxesInfo storage taxesInfo
    ) private view returns(uint16) {
        if (taxesInfo.sellTaxDuration == 0) {
            return taxesInfo.toSellTax;
        }
        if (
            block.timestamp < (taxesInfo.sellTaxDuration + taxesInfo.sellTaxTimestamp) &&
            block.timestamp >= taxesInfo.sellTaxTimestamp
        ) {
            if (taxesInfo.sellTaxGradual) {
                if (taxesInfo.toSellTax > taxesInfo.fromSellTax) {
                    return taxesInfo.fromSellTax + uint16(uint64(taxesInfo.toSellTax - taxesInfo.fromSellTax) * uint64(block.timestamp - taxesInfo.sellTaxTimestamp) / uint64(taxesInfo.sellTaxDuration));
                } else {
                    return taxesInfo.fromSellTax - uint16(uint64(taxesInfo.fromSellTax - taxesInfo.toSellTax) * uint64(block.timestamp - taxesInfo.sellTaxTimestamp) / uint64(taxesInfo.sellTaxDuration));
                }
            } else {
                return taxesInfo.fromSellTax;
            }
                
        } else {
            return taxesInfo.toSellTax;
        }
        
    }

    function _setTaxes(TaxesInfo storage taxesInfo, uint16 newBuyTax, uint16 newSellTax) private {
        taxesInfo.fromSellTax = _sellTax(taxesInfo);
        taxesInfo.toSellTax = newSellTax;
        taxesInfo.sellTaxTimestamp = uint64(block.timestamp);

        taxesInfo.fromBuyTax = _buyTax(taxesInfo);
        taxesInfo.toBuyTax = newBuyTax;
        taxesInfo.buyTaxTimestamp = uint64(block.timestamp);
    }

}