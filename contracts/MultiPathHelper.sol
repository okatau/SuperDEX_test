/**
 *Submitted for verification at BscScan.com on 2022-09-10
*/

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MultiPathHelper{
    
    struct Order {
        IERC20 makerToken;
        IERC20 takerToken;
        uint128 makerAmount;
        uint128 takerAmount;
        address maker;
        address taker;
        address txOrigin;
        bytes32 pool;
        uint64 expiry;
        uint256 salt;
    }

    enum SignatureType {
        ILLEGAL,
        INVALID,
        EIP712,
        ETHSIGN
    }

    struct Signature {
        // How to validate the signature.
        SignatureType signatureType;
        // EC Signature data.
        uint8 v;
        // EC Signature data.
        bytes32 r;
        // EC Signature data.
        bytes32 s;
    }

    struct ZeroxV4Data {
        Order order;
        Signature signature;
    }

    function getPools(uint256 fee, address pair, bool direction ) public pure returns (uint256) {
        // return (direction ? fee << 161 + uint256(uint160(pair)) : fee << 161 + uint256(uint160(pair)) - 1461501637330902918203684832716283019655932542976);
        if (direction) {
            return ((fee << 161) + uint256(uint160(pair)));
        } else {
            return (((fee << 161) + uint256(uint160(pair)) - 1461501637330902918203684832716283019655932542976));
        }
    }

    function encodeSwap(
        uint amountIn, 
        uint amountOut, 
        address[] calldata path
        ) public view returns (bytes memory data, uint256 length){
        data = abi.encodeWithSignature("swapOnUniswap(uint256,uint256,address[])", amountIn, amountOut, path);
        length = data.length;
    }

    function encodePayload(ZeroxV4Data memory data) public pure returns (bytes memory){
        return abi.encode(data);
    }
}