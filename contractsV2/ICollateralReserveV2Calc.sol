// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;


interface ICollateralReserveV2Calc{
    function getPrice() external view returns (uint256, uint8);
    function valuation( uint amount_ ) external view returns ( uint _value );
}

