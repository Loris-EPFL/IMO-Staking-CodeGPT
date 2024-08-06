// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

library Errors {
    // Generic errors
    error ZeroAddress();
    error NullAmount();

    // Token management
    error TokenNotAllowed();
    error TokenAlreadyAllowed();

    // Mint ratios
    error InvalidRatio();
}