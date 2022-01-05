// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./CoffinBandOracle.sol";
import './ICollateralReserveV2Calc.sol';

contract CollateralReserveV2CalcFTM is CoffinBandOracle, ICollateralReserveV2Calc {
    using SafeMath for uint256;
    string public name = "CollateralReserveV2CalcFTM";

    uint256 internal constant PRICE_PRECISION18 = 1e18;

    function getPrice() public view override returns (uint256, uint8) {
        return (super.getBandRate("FTM","USD"), 18);
    }
    function valuation( uint amount_ ) external view override returns ( uint _value ) {
        ( uint256 price, uint8 d ) = getPrice();
        uint256 price2 = price.mul(PRICE_PRECISION18).div(10**d);
        _value = amount_.mul(price2).div(1e18);
    }
}

