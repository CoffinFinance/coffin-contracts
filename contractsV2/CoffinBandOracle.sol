// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "@openzeppelin/contracts/access/Ownable.sol";



interface IBandStdReference {
    /// A structure returned whenever someone requests for standard reference data.
    struct ReferenceData {
        uint256 rate; // base/quote exchange rate, multiplied by 1e18.
        uint256 lastUpdatedBase; // UNIX epoch of the last time when base price gets updated.
        uint256 lastUpdatedQuote; // UNIX epoch of the last time when quote price gets updated.
    }

    /// Returns the price data for the given base/quote pair. Revert if not available.
    function getReferenceData(string memory _base, string memory _quote)
        external
        view
        returns (ReferenceData memory);

    /// Similar to getReferenceData, but with multiple base/quote pairs at once.
    function getReferenceDataBulk(
        string[] memory _bases,
        string[] memory _quotes
    ) external view returns (ReferenceData[] memory);
}


contract CoffinBandOracle is Ownable {

    IBandStdReference bandRef;

    constructor(
    ) {
        //ref: https://docs.fantom.foundation/tutorials/band-protocol-standard-dataset
        address fantomBandProtocol = 0x56E2898E0ceFF0D1222827759B56B28Ad812f92F;
        setBandOracle(fantomBandProtocol);

    }

    function getBandRate(string memory token0, string memory token1)
        public
        view
        returns (uint256)
    {
        IBandStdReference.ReferenceData memory data = bandRef.getReferenceData(
            token0,
            token1
        );
        return data.rate;
    }

    function setBandOracle(address _bandOracleAddress) public onlyOwner {
        bandRef = IBandStdReference(_bandOracleAddress);
    }

}

