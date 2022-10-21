pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HelperWithTokens {

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

    function withdrawTokens(address _token) public {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        (bool success) = IERC20(_token).transfer(msg.sender, amount);
        require(success, "error");
    }

    function giveApprove(address _to, uint256 _amount, address _token) public {
        (bool success) = IERC20(_token).approve(_to, _amount);
    }

    function decodePayload(bytes memory payload) public pure returns(ZeroxV4Data memory)
    {
        return (abi.decode(payload, (ZeroxV4Data)));
    }

}