pragma solidity ^0.8.26;

import "@openzeppelin/utils/math/Math.sol";


contract RawYieldCalculator {
    // Constants
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant PRECISION = 1e18;

    function calculateRawYield(
        uint256 _principal,
        uint256 _apy,
        uint256 _from,
        uint256 _to
    ) public pure returns (uint256) {
        require(_to > _from, "Invalid time range");
        
        uint256 timeDelta = _to - _from;
        
        // Convert APY to a yearly rate (assuming _apy is in basis points)
        uint256 yearlyRate = (_apy * PRECISION) / 10000;
        
        // Calculate raw yield: principal * rate * (time / year)
        uint256 rawYield = Math.mulDiv(
            Math.mulDiv(_principal, yearlyRate, PRECISION),
            timeDelta,
            SECONDS_PER_YEAR
        );
        
        return rawYield;
    }
}
