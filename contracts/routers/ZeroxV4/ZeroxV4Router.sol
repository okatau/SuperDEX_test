pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../libraries/Utils.sol";
import "../../libraries/LibOrderV4.sol";
import "../../interfaces/IZeroxV4.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/IRouter.sol";
import "../../interfaces/ITokenTransferProxy.sol";
import "../../AugustusStorage.sol";
import "../../DeBridgeContracts/BridgeAppBase.sol";

contract ZeroxV4Router is AugustusStorage, IRouter, BridgeAppBase {
    using Flags for uint256;
    using SafeMath for uint256;
    address public immutable weth;
    // uint256 CURRENT_CHAINID;

    struct ZeroxV4Data {
        LibOrderV4.Order order;
        LibOrderV4.Signature signature;
    }

    event LogReceivedAmount(uint256 amount);

    constructor(address _weth) public {
        weth = _weth;
        // CURRENT_CHAINID = getChainId();
    }

    function initialize(bytes calldata data) override external {
        revert("METHOD NOT IMPLEMENTED");
    }

    function getKey() override external pure returns(bytes32) {
        return keccak256(abi.encodePacked("ZEROX_V4_ROUTER", "1.0.0"));
    }

    function swapOnZeroXv4(
        IERC20 fromToken,
        IERC20 toToken,
        uint256 fromAmount,
        uint256 amountOutMin,
        address exchange,
        bytes calldata payload
    )
        external
        payable
    {
        address _fromToken = address(fromToken);
        address _toToken = address(toToken);

        if (address(fromToken) == Utils.ethAddress()) {
            require(fromAmount == msg.value, "Incorrect msg.value");
            IWETH(weth).deposit{value: fromAmount}();
            _fromToken = weth;
        } else {
            require(msg.value == 0, "Incorrect msg.value");
            transferTokensFromProxy(_fromToken, fromAmount);
        } 

        if (address(toToken) == Utils.ethAddress()) {
            _toToken = weth;
        }

        ZeroxV4Data memory data = abi.decode(payload, (ZeroxV4Data));
        require(address(data.order.takerToken) == address(_fromToken), "Invalid from token!!");
        require(address(data.order.makerToken) == address(_toToken), "Invalid to token!!");


        Utils.approve(exchange, address(_fromToken), fromAmount);
        IZeroxV4(exchange).fillRfqOrder(
            data.order,
            data.signature,
            uint128(fromAmount)
        );

        uint256 receivedAmount = Utils.tokenBalance(address(_toToken), address(this));
        require(receivedAmount >= amountOutMin, "Slippage check failed");

        if (address(toToken) == Utils.ethAddress()) {
            IWETH(weth).withdraw(receivedAmount);
        }

        Utils.transferTokens(address(toToken), payable(msg.sender), receivedAmount);
    }

    function swapOnZeroXv4DeBridge(
        Utils.ZeroxV4DataDeBridge memory data
    )
        external
        payable
    {
        bool currentChainId = getChainId() == data.chainIdTo;
        uint256 deBridgeFee = getChainId() == 80001 ? 0.1 ether : 0.01 ether;
        bool instaTransfer = false;
        uint256 amountIn = data.fromAmount;
        (IERC20[] memory path, bytes memory payload, address exchange) = currentChainId ? 
            (data.pathAfterSend, data.payloadAfterSend, data.exchangeAfterSend) : 
            (data.pathBeforeSend, data.payloadBeforeSend, data.exchangeBeforeSend);
        address _fromToken = address(path[0]);
        address _toToken = address(path[1]);

        if (currentChainId) {
            amountIn = IERC20(path[0]).allowance(msg.sender, address(this));
            // IERC20(path[0]).approve(address(tokenTransferProxy), amountIn);
            IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
            if (path.length == 0) {
                IERC20(path[0]).transfer(data.beneficiary, amountIn);
                instaTransfer = true;
            }
        }
        else {
            if (address(path[0]) == Utils.ethAddress()) {
                require(amountIn == msg.value - deBridgeFee, "Incorrect msg.value");
                IWETH(weth).deposit{value: amountIn}();
                _fromToken = weth;
            } else {
                require(msg.value == deBridgeFee, "Incorrect msg.value");
                transferTokensFromProxy(_fromToken, amountIn);
            } 
        }

        if (address(path[1]) == Utils.ethAddress()) {
            _toToken = weth;
        }

        ZeroxV4Data memory zeroxData = abi.decode(payload, (ZeroxV4Data));
        require(address(zeroxData.order.takerToken) == address(_fromToken), "Invalid from token!!");
        require(address(zeroxData.order.makerToken) == address(_toToken), "Invalid to token!!");
        uint256 receivedAmount;

        if (!instaTransfer) {
            Utils.approve(exchange, address(_fromToken), amountIn);
            IZeroxV4(exchange).fillRfqOrder(
                zeroxData.order,
                zeroxData.signature,
                uint128(amountIn)
            );
            receivedAmount = Utils.tokenBalance(address(_toToken), address(this));
            emit LogReceivedAmount(receivedAmount);
            require(receivedAmount >= data.amountOutMin, "Slippage check failed");
            if (!currentChainId){
                _send(data, receivedAmount, deBridgeFee);
            } else {
                if (address(path[1]) == Utils.ethAddress()) {
                    IWETH(weth).withdraw(receivedAmount);
                }
                Utils.transferTokens(address(path[1]), data.beneficiary, receivedAmount);
            }
        }
    }

    function swapOnZeroXv4WithPermit(
        IERC20 fromToken,
        IERC20 toToken,
        uint256 fromAmount,
        uint256 amountOutMin,
        address exchange,
        bytes calldata payload,
        bytes calldata permit
    )
        external
        payable
    {
        address _fromToken = address(fromToken);
        address _toToken = address(toToken);

        if (address(fromToken) == Utils.ethAddress()) {
            require(fromAmount == msg.value, "Incorrect msg.value");
            IWETH(weth).deposit{value: fromAmount}();
            _fromToken = weth;
        } else {
            require(msg.value == 0, "Incorrect msg.value");
            Utils.permit(_fromToken, permit);
            transferTokensFromProxy(_fromToken, fromAmount);
        } 

        if (address(toToken) == Utils.ethAddress()) {
            _toToken = weth;
        }

        ZeroxV4Data memory data = abi.decode(payload, (ZeroxV4Data));
        require(address(data.order.takerToken) == address(_fromToken), "Invalid from token!!");
        require(address(data.order.makerToken) == address(_toToken), "Invalid to token!!");


        Utils.approve(exchange, address(_fromToken), fromAmount);
        IZeroxV4(exchange).fillRfqOrder(
            data.order,
            data.signature,
            uint128(fromAmount)
        );

        uint256 receivedAmount = Utils.tokenBalance(address(_toToken), address(this));
        require(receivedAmount >= amountOutMin, "Slippage check failed");

        if (address(toToken) == Utils.ethAddress()) {
            IWETH(weth).withdraw(receivedAmount);
        }

        Utils.transferTokens(address(toToken), payable(msg.sender), receivedAmount);
    }

    function transferTokensFromProxy(
        address token,
        uint256 amount
    )
      private
    {
        if (token != Utils.ethAddress()) {
            tokenTransferProxy.transferFrom(
                token,
                msg.sender,
                address(this),
                amount
            );
        }
    }

    function _send(
        Utils.ZeroxV4DataDeBridge memory data,
        uint256 tokensBought,
        uint256 deBridgeFee
        ) public payable {
        address _bridgeAddress = 0x68D936Cb4723BdD38C488FD50514803f96789d2D;

        address contractAddressTo = chainIdToContractAddress[data.chainIdTo];
        require(contractAddressTo != address(0), "Incremetor: ChainId is not supported");
        require(tokensBought.div(2) >= data.executionFee, "UNISWAPV2ROuter: #1");
        if (Utils.ethAddress() != address(data.pathBeforeSend[1])){
            IERC20(data.pathBeforeSend[1]).approve(_bridgeAddress, tokensBought);
        }
        IDeBridgeGate.SubmissionAutoParamsTo memory autoParams;
        autoParams.flags = autoParams.flags.setFlag(Flags.REVERT_IF_EXTERNAL_FAIL, true);
        autoParams.flags = autoParams.flags.setFlag(Flags.PROXY_WITH_SENDER, true);
        autoParams.executionFee = data.executionFee;
        autoParams.fallbackAddress = abi.encodePacked(data.beneficiary);
        autoParams.data = abi.encodeWithSelector(this.swapOnZeroXv4DeBridge.selector, data);

        if (address(data.pathBeforeSend[1]) != Utils.ethAddress()){
            Utils.transferTokens(Utils.ethAddress(), payable(contractAddressTo), deBridgeFee);
        }
        Utils.transferTokens(address(data.pathBeforeSend[1]), payable(data.beneficiary), tokensBought);
        // if (address(data.pathBeforeSend[1]) == weth){
        //     deBridgeGate.send{value: tokensBought}(
        //         address(0),
        //         tokensBought,
        //         data.chainIdTo,
        //         abi.encodePacked(contractAddressTo),
        //         "",
        //         false,
        //         0,
        //         abi.encode(autoParams)
        //     );
        // }
        // else{
        //     deBridgeGate.send{value: deBridgeFee}(
        //         address(data.pathBeforeSend[1]),
        //         tokensBought,
        //         data.chainIdTo,
        //         abi.encodePacked(contractAddressTo),
        //         "",
        //         false,
        //         0,
        //         abi.encode(autoParams)
        //     );
        // }
    }


    function initialize(address _bridgeAddr)public{
        __BridgeAppBase_init(IDeBridgeGate(_bridgeAddr));
    }
}