pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/ITokenTransferProxy.sol";
import "../../interfaces/IRouter.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/IUniswapV2Pair.sol";
import "../../libraries/NewUniswapV2Lib.sol";
import "../../libraries/Utils.sol";
import "../../AugustusStorage.sol";
import "../../TransferHelper.sol";
import "../../DeBridgeContracts/BridgeAppBase.sol";

contract NewUniswapV2Router is AugustusStorage, IRouter, BridgeAppBase {
    using SafeMath for uint256;
    using Flags for uint256;

    address constant ETH_IDENTIFIER =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    // Pool bits are 255-161: fee, 160: direction flag, 159-0: address
    uint256 constant FEE_OFFSET = 161;
    uint256 constant DIRECTION_FLAG = 0x0000000000000000000000010000000000000000000000000000000000000000;

    // uint256 CURRENT_CHAINID;
    // uint256 DEBRIDGE_FEE;

    constructor() public {
        // CURRENT_CHAINID = getChainId();
        // DEBRIDGE_FEE = CURRENT_CHAINID == 80001 ? 0.1 ether : 0.01 ether;
    }

    function initialize(bytes calldata data) external override {
        revert("METHOD NOT IMPLEMENTED");
    }

    function getKey() external pure override returns (bytes32) {
        return keccak256(abi.encodePacked("UNISWAP_DIRECT_ROUTER", "2.0.0"));
    }

    function swapOnUniswapV2Fork(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address weth,
        uint256[] calldata pools
    ) external payable {
        _swap(
            tokenIn,
            amountIn,
            amountOutMin,
            weth,
            pools,
            ((0 << FEE_OFFSET) + uint256(uint160(msg.sender)))
        );
    }

    /// @notice The function using to swap tokens between chains
    /** @dev variable crossChain using to understand which swap being performed. 
        Index 0 - usual swap in the same chain
        Index 1 - swap before DeBridge
        Index 2 - swap after Debrodge*/
    /// @param _data All data needed to cross chain swap. See ../../libraries/utils.sol
    function swapOnUniswapV2ForkDeBridge(
        Utils.UniswapV2ForkDeBridge memory _data
    ) external payable {
        bool currentChainId = _data.chainIdTo == getChainId();
        // uint256 deBridgeFee = getChainId() == 80001 ? 0.1 ether : 0.01 ether;
        bool instaTransfer = false;
        (uint256[] memory pools, address tokenIn) = currentChainId ? (_data.poolsAfterSend, _data.tokenIn[1]) : (_data.poolsBeforeSend, _data.tokenIn[0]);
        uint256 crossChainData = (currentChainId ? (2 << FEE_OFFSET) : (1 << FEE_OFFSET)) + uint256(uint160(_data.beneficiary));
        uint256 amountIn = _data.amountIn;

        if (currentChainId) {
            amountIn = IERC20(tokenIn).allowance(msg.sender, address(this));
            IERC20(tokenIn).approve(address(tokenTransferProxy), amountIn);
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
            if (pools.length == 0) {
                IERC20(tokenIn).transfer(_data.beneficiary, amountIn);
                instaTransfer = true;
            }
        }
        if (!instaTransfer) {
            (uint256 receivedAmount, address tokenBought) = _swap(
                tokenIn,
                amountIn,
                _data.amountOutMin,
                _data.weth,
                pools,
                crossChainData
            );

            if (!currentChainId) {
                send(_data, receivedAmount, tokenBought);
            }
        }
    }

    function buyOnUniswapV2Fork(
        address tokenIn,
        uint256 amountInMax,
        uint256 amountOut,
        address weth,
        uint256[] calldata pools
    ) external payable {
        _buy(tokenIn, amountInMax, amountOut, weth, pools);
    }

    function swapOnUniswapV2ForkWithPermit(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address weth,
        uint256[] calldata pools,
        bytes calldata permit
    ) external payable {
        _swapWithPermit(tokenIn, amountIn, amountOutMin, weth, pools, permit);
    }

    function buyOnUniswapV2ForkWithPermit(
        address tokenIn,
        uint256 amountInMax,
        uint256 amountOut,
        address weth,
        uint256[] calldata pools,
        bytes calldata permit
    ) external payable {
        _buyWithPermit(tokenIn, amountInMax, amountOut, weth, pools, permit);
    }

    function transferTokens(
        address token,
        address from,
        address to,
        uint256 amount
    ) private {
        ITokenTransferProxy(tokenTransferProxy).transferFrom(token, from, to, amount);
    }

    function transferTokensWithPermit(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes calldata permit
    ) private {
        Utils.permit(token, permit);
        ITokenTransferProxy(tokenTransferProxy).transferFrom(token, from, to, amount);
    }

    function _swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address weth,
        uint256[] memory pools,
        uint256 crossChainData
    ) private returns (uint256 tokensBought, address tokenBought) {
        uint256 pairs = pools.length;

        require(pairs != 0, "At least one pool required");
        // uint256 deBridgeFee = getChainId() == 80001 ? 0.1 ether : 0.01 ether;
        bool tokensBoughtEth;
        if (tokenIn == ETH_IDENTIFIER) {
            require(amountIn == ((crossChainData >> FEE_OFFSET) == 0 ? msg.value : msg.value - (getChainId() == 80001 ? 0.1 ether : 0.01 ether)),
                "Incorrect msg.value"
            );
            IWETH(weth).deposit{value: msg.value}();
            require(IWETH(weth).transfer(address(uint160(pools[0])), msg.value));
        } else {
            require(msg.value == ((crossChainData >> FEE_OFFSET) != 1 ? 0 : (getChainId() == 80001 ? 0.1 ether : 0.01 ether)), "Incorrect msg.value");
            if ((crossChainData >> FEE_OFFSET) == 2) {
                IERC20(tokenIn).approve(getTokenTransferProxy(), amountIn);
                transferTokens(tokenIn, address(this), address(uint160(pools[0])), amountIn);
            } else {
                transferTokens(tokenIn, address(uint160(crossChainData)), address(uint160(pools[0])), amountIn);
            }
            tokensBoughtEth = weth != address(0);
        }

        tokensBought = amountIn;

        for (uint256 i = 0; i < pairs; ++i) {
            uint256 p = pools[i];
            address pool = address(uint160(p));
            bool direction = p & DIRECTION_FLAG == 0;
            tokensBought = NewUniswapV2Lib.getAmountOut(
                tokensBought,
                pool,
                direction,
                p >> FEE_OFFSET
            );
            (uint256 amount0Out, uint256 amount1Out) = direction
                ? (uint256(0), tokensBought)
                : (tokensBought, uint256(0));
            IUniswapV2Pair(pool).swap(
                amount0Out,
                amount1Out,
                i + 1 == pairs ? ((crossChainData >> FEE_OFFSET) == 1 ? address(this) : (tokensBoughtEth ? address(this) : address(uint160(crossChainData)))) : address(uint160(pools[i + 1])),
                ""
            );
            tokenBought = NewUniswapV2Lib.getTokenOut(pool, direction);
        }

        if (tokensBoughtEth) {
            IWETH(weth).withdraw(tokensBought);
            TransferHelper.safeTransferETH(
                (crossChainData >> FEE_OFFSET) == 1
                    ? address(this)
                    : address(uint160(crossChainData)),
                tokensBought
            );
        }

        require(
            tokensBought >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function _buy(
        address tokenIn,
        uint256 amountInMax,
        uint256 amountOut,
        address weth,
        uint256[] memory pools
    ) private returns (uint256 tokensSold) {
        uint256 pairs = pools.length;

        require(pairs != 0, "At least one pool required");

        uint256[] memory amounts = new uint256[](pairs + 1);

        amounts[pairs] = amountOut;

        for (uint256 i = pairs; i != 0; --i) {
            uint256 p = pools[i - 1];
            amounts[i - 1] = NewUniswapV2Lib.getAmountIn(
                amounts[i],
                address(uint160(p)),
                p & DIRECTION_FLAG == 0,
                p >> FEE_OFFSET
            );
        }

        tokensSold = amounts[0];
        require(
            tokensSold <= amountInMax,
            "UniswapV2Router: INSUFFICIENT_INPUT_AMOUNT"
        );
        bool tokensBoughtEth;

        if (tokenIn == ETH_IDENTIFIER) {
            TransferHelper.safeTransferETH(
                msg.sender,
                msg.value.sub(tokensSold)
            );
            IWETH(weth).deposit{value: tokensSold}();
            require(
                IWETH(weth).transfer(address(uint160(pools[0])), tokensSold)
            );
        } else {
            require(msg.value == 0, "Incorrect msg.value");
            transferTokens(
                tokenIn,
                msg.sender,
                address(uint160(pools[0])),
                tokensSold
            );
            tokensBoughtEth = weth != address(0);
        }

        for (uint256 i = 0; i < pairs; ++i) {
            uint256 p = pools[i];
            (uint256 amount0Out, uint256 amount1Out) = p & DIRECTION_FLAG == 0
                ? (uint256(0), amounts[i + 1])
                : (amounts[i + 1], uint256(0));
            IUniswapV2Pair(address(uint160(p))).swap(
                amount0Out,
                amount1Out,
                i + 1 == pairs
                    ? (tokensBoughtEth ? address(this) : msg.sender)
                    : address(uint160(pools[i + 1])),
                ""
            );
        }

        if (tokensBoughtEth) {
            IWETH(weth).withdraw(amountOut);
            TransferHelper.safeTransferETH(msg.sender, amountOut);
        }
    }

    function _swapWithPermit(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address weth,
        uint256[] memory pools,
        bytes calldata permit
    ) private returns (uint256 tokensBought) {
        uint256 pairs = pools.length;

        require(pairs != 0, "At least one pool required");

        bool tokensBoughtEth;

        if (tokenIn == ETH_IDENTIFIER) {
            require(amountIn == msg.value, "Incorrect msg.value");
            IWETH(weth).deposit{value: msg.value}();
            require(
                IWETH(weth).transfer(address(uint160(pools[0])), msg.value)
            );
        } else {
            require(msg.value == 0, "Incorrect msg.value");
            transferTokensWithPermit(
                tokenIn,
                msg.sender,
                address(uint160(pools[0])),
                amountIn,
                permit
            );
            tokensBoughtEth = weth != address(0);
        }

        tokensBought = amountIn;

        for (uint256 i = 0; i < pairs; ++i) {
            uint256 p = pools[i];
            address pool = address(uint160(p));
            bool direction = p & DIRECTION_FLAG == 0;

            tokensBought = NewUniswapV2Lib.getAmountOut(
                tokensBought,
                pool,
                direction,
                p >> FEE_OFFSET
            );
            (uint256 amount0Out, uint256 amount1Out) = direction
                ? (uint256(0), tokensBought)
                : (tokensBought, uint256(0));
            IUniswapV2Pair(pool).swap(
                amount0Out,
                amount1Out,
                i + 1 == pairs
                    ? (tokensBoughtEth ? address(this) : msg.sender)
                    : address(uint160(pools[i + 1])),
                ""
            );
        }

        if (tokensBoughtEth) {
            IWETH(weth).withdraw(tokensBought);
            TransferHelper.safeTransferETH(msg.sender, tokensBought);
        }

        require(
            tokensBought >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function _buyWithPermit(
        address tokenIn,
        uint256 amountInMax,
        uint256 amountOut,
        address weth,
        uint256[] memory pools,
        bytes calldata permit
    ) private returns (uint256 tokensSold) {
        uint256 pairs = pools.length;

        require(pairs != 0, "At least one pool required");

        uint256[] memory amounts = new uint256[](pairs + 1);

        amounts[pairs] = amountOut;

        for (uint256 i = pairs; i != 0; --i) {
            uint256 p = pools[i - 1];
            amounts[i - 1] = NewUniswapV2Lib.getAmountIn(
                amounts[i],
                address(uint160(p)),
                p & DIRECTION_FLAG == 0,
                p >> FEE_OFFSET
            );
        }

        tokensSold = amounts[0];
        require(
            tokensSold <= amountInMax,
            "UniswapV2Router: INSUFFICIENT_INPUT_AMOUNT"
        );
        bool tokensBoughtEth;

        if (tokenIn == ETH_IDENTIFIER) {
            TransferHelper.safeTransferETH(
                msg.sender,
                msg.value.sub(tokensSold)
            );
            IWETH(weth).deposit{value: tokensSold}();
            require(
                IWETH(weth).transfer(address(uint160(pools[0])), tokensSold)
            );
        } else {
            require(msg.value == 0, "Incorrect msg.value");
            transferTokensWithPermit(
                tokenIn,
                msg.sender,
                address(uint160(pools[0])),
                tokensSold,
                permit
            );
            tokensBoughtEth = weth != address(0);
        }

        for (uint256 i = 0; i < pairs; ++i) {
            uint256 p = pools[i];
            (uint256 amount0Out, uint256 amount1Out) = p & DIRECTION_FLAG == 0
                ? (uint256(0), amounts[i + 1])
                : (amounts[i + 1], uint256(0));
            IUniswapV2Pair(address(uint160(p))).swap(
                amount0Out,
                amount1Out,
                i + 1 == pairs
                    ? (tokensBoughtEth ? address(this) : msg.sender)
                    : address(uint160(pools[i + 1])),
                ""
            );
        }

        if (tokensBoughtEth) {
            IWETH(weth).withdraw(amountOut);
            TransferHelper.safeTransferETH(msg.sender, amountOut);
        }
    }

    // NEW FUNCTIONS

    function initialize(address _bridgeAddr) public {
        __BridgeAppBase_init(IDeBridgeGate(_bridgeAddr));
    }

    /// @dev Function using for send tokens and data through DeBridge
    /// @param data Data to execute swap in second chain
    /// @param tokensBought Amount of tokens that contract receive after swap
    /// @param tokenBought Address of token that was last in the path
    function send(
        Utils.UniswapV2ForkDeBridge memory data,
        uint256 tokensBought,
        address tokenBought
    ) public payable {
        address _bridgeAddress = 0x68D936Cb4723BdD38C488FD50514803f96789d2D;

        address contractAddressTo = chainIdToContractAddress[data.chainIdTo];
        require(contractAddressTo != address(0), "Incremetor: ChainId is not supported");
        require(tokensBought.div(2) >= data.executionFee, "Insufficient token amount");

        IERC20(tokenBought).approve(_bridgeAddress, tokensBought);
        IDeBridgeGate.SubmissionAutoParamsTo memory autoParams;
        autoParams.flags = autoParams.flags.setFlag(Flags.REVERT_IF_EXTERNAL_FAIL, true);
        autoParams.flags = autoParams.flags.setFlag(Flags.PROXY_WITH_SENDER, true);
        autoParams.executionFee = data.executionFee;
        autoParams.fallbackAddress = abi.encodePacked(data.beneficiary);
        autoParams.data = abi.encodeWithSelector(
            this.swapOnUniswapV2ForkDeBridge.selector,
            data,
            tokensBought
        );

        uint256 deBridgeFee = getChainId() == 80001 ? 0.1 ether : 0.01 ether;

        if (tokenBought == data.weth) {
            deBridgeGate.send{value: tokensBought}(
                address(0),
                tokensBought,
                data.chainIdTo,
                abi.encodePacked(contractAddressTo),
                "",
                false,
                0,
                abi.encode(autoParams)
            );
        } else {
            deBridgeGate.send{value: deBridgeFee}(
                tokenBought,
                tokensBought,
                data.chainIdTo,
                abi.encodePacked(contractAddressTo),
                "",
                false,
                0,
                abi.encode(autoParams)
            );
        }
    }

    function getTokenTransferProxy() public view returns (address) {
        return address(tokenTransferProxy);
    }
}
