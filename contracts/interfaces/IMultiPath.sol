pragma solidity ^0.8.0;

import "../libraries/Utils.sol";

interface IMultiPath {
    function multiSwapDeBridge(Utils.SellDataDeBridge memory data)
        external
        payable
        returns (uint256);

    function multiSwapAfterDeBridge(Utils.SellDataDeBridge memory data)
        external
        payable
        returns (uint256);
}
