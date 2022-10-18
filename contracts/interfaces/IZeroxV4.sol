pragma solidity ^0.8.0;

import "../libraries/LibOrderV4.sol";

interface IZeroxV4 {
    function fillRfqOrder(
        // The order
        LibOrderV4.Order calldata order,
        // The signature
        LibOrderV4.Signature calldata signature,
        // How much taker token to fill the order with
        uint128 takerTokenFillAmount
    )
        external
        payable
        returns (
            // How much maker token from the order the taker received.
            uint128,
            uint128
        );
}
