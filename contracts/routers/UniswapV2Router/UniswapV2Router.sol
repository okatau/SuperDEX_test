pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../DeBridgeContracts/BridgeAppBase.sol";
import "../../interfaces/ITokenTransferProxy.sol";
import "../../interfaces/IRouter.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/IUniswapV2Pair.sol";
import "../../libraries/UniswapV2Lib.sol";
import "../../libraries/Utils.sol";
import "../../TransferHelper.sol";
import "../../AugustusStorage.sol";

contract UniswapV2Router is AugustusStorage, IRouter, BridgeAppBase, Ownable {
    using SafeMath for uint256;
    using Flags for uint256;

    address public immutable UNISWAP_FACTORY;
    address public immutable WETH;
    address public immutable ETH_IDENTIFIER;
    bytes32 public immutable UNISWAP_INIT_CODE;
    uint256 public immutable FEE;
    uint256 public immutable FEE_FACTOR;
    // uint256 public CURRENT_CHAINID;

    // 0x68D936Cb4723BdD38C488FD50514803f96789d2D адрес deBridgeGate в BSC и KOVAN
    // 0xEF3B092e84a2Dbdbaf507DeCF388f7f02eb43669 адрес прокси deBridge в KOVAN
    // 0xEF3B092e84a2Dbdbaf507DeCF388f7f02eb43669 адрес прокси deBridge в POLYGON

    mapping(address => bool) admins;

    event LogBalance(address _token, uint256 balance);
    event LogData(address token0, address tokenSold, uint256 amount0, uint256 amount1);

    constructor(
        address _factory,
        address _weth,
        address _eth,
        bytes32 _initCode,
        uint256 _fee,
        uint256 _feeFactor
    ) public {
        UNISWAP_FACTORY = _factory;
        WETH = _weth;
        ETH_IDENTIFIER = _eth;
        UNISWAP_INIT_CODE = _initCode;
        FEE = _fee;
        FEE_FACTOR = _feeFactor;
        // CURRENT_CHAINID = getChainId();
    }

    function initialize(bytes calldata data) external override {
        revert("METHOD NOT IMPLEMENTED");
    }

    function getKey() external pure override returns (bytes32) {
        return keccak256(abi.encodePacked("UNISWAP_DIRECT_ROUTER", "1.0.0"));
    }

    function swapOnUniswap(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) public payable {
        (uint256 tokensBought, ) = _swap(
            UNISWAP_FACTORY,
            UNISWAP_INIT_CODE,
            amountIn,
            path,
            ((0 << 161) + uint256(uint160(msg.sender)))
        );

        require(tokensBought >= amountOutMin, "Uniswap: INSUFFICIENT_OUTPUT_AMOUNT");
    }

    function swapOnUniswapFork(
        address factory,
        bytes32 initCode,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) external payable {
        (uint256 tokensBought, ) = _swap(
            factory,
            initCode,
            amountIn,
            path,
            ((0 << 161) + uint256(uint160(msg.sender)))
        );

        require(
            tokensBought >= amountOutMin,
            "Uniswap: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    /// @notice The function using to swap tokens between chains
    /** @dev variable crossChain using to understand which swap being performed. 
        Index 0 - usual swap in the same chain
        Index 1 - swap before DeBridge
        Index 2 - swap after Debrodge*/
    /// @param _data All data needed to cross chain swap. See ../../libraries/utils.sol
    function swapOnUniswapDeBridge(Utils.UniswapV2RouterData memory _data)
        external
        payable
    {
        bool currentChainId = _data.chainId == getChainId();
        uint256 tokensBought;
        address tokenBought;
        bool instaTransfer = false;
        address[] memory path = currentChainId ? _data.pathAfterSend : _data.pathBeforeSend;
        uint256 crossChain = (currentChainId ? (2 << 161) : (1 << 161)) + uint256(uint160(_data.beneficiary));
        uint256 amountIn = _data.amountIn;

        if (currentChainId) {
            amountIn = IERC20(path[0]).allowance(msg.sender, address(this));
            IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
            if (path.length == 1) {
                transferTokens(path[0], address(this), _data.beneficiary, amountIn);
                instaTransfer = true;
            }
        }
        if (!instaTransfer) {
                 
            (tokensBought, tokenBought) = _swap(
                UNISWAP_FACTORY,
                UNISWAP_INIT_CODE,
                amountIn,
                path,
                crossChain
            );

            if (!currentChainId) {
                send(_data, tokensBought, tokenBought);
            }
            require(
                tokensBought >= _data.amountOutMin,
                "Uniswap: INSUFFICIENT_OUTPUT_AMOUNT"
            );
        }
    }

    function buyOnUniswap(
        uint256 amountInMax,
        uint256 amountOut,
        address[] calldata path
    ) external payable {
        uint256 tokensSold = _buy(
            UNISWAP_FACTORY,
            UNISWAP_INIT_CODE,
            amountOut,
            path
        );

        require(
            tokensSold <= amountInMax,
            "Uniswap: INSUFFICIENT_INPUT_AMOUNT"
        );
    }

    function buyOnUniswapFork(
        address factory,
        bytes32 initCode,
        uint256 amountInMax,
        uint256 amountOut,
        address[] calldata path
    ) external payable {
        uint256 tokensSold = _buy(factory, initCode, amountOut, path);

        require(
            tokensSold <= amountInMax,
            "Uniswap: INSUFFICIENT_INPUT_AMOUNT"
        );
    }

    function transferTokens(
        address token,
        address from,
        address to,
        uint256 amount
    ) private {
        ITokenTransferProxy(tokenTransferProxy).transferFrom(token, from, to, amount);
        // IERC20(token).transferFrom(from, to,amount);
    }

    function _swap(
        address factory,
        bytes32 initCode,
        uint256 amountIn,
        address[] memory path,
        uint256 crossChainData
    ) private returns (uint256 tokensBought, address tokenBought) {
        require(path.length > 1, "More than 1 token required");
        uint256 pairs = uint256(path.length - 1);
        bool tokensBoughtEth;
        tokensBought = amountIn;
        address receiver;
        tokenBought;

        for (uint256 i = 0; i < pairs; i++) {
            address tokenSold = path[i];
            tokenBought = path[i + 1];

            address currentPair = receiver;

            if (i == pairs - 1) {
                if (tokenBought == ETH_IDENTIFIER) {
                    tokenBought = WETH;
                    tokensBoughtEth = true;
                }
            }
            if (i == 0) {
                if (tokenSold == ETH_IDENTIFIER) {
                    tokenSold = WETH;
                    currentPair = UniswapV2Lib.pairFor(factory, tokenSold, tokenBought, initCode);
                    uint256 amount = (crossChainData >> 161) == 1 ? 
                        msg.value - (getChainId() == 80001 ? 0.1 ether : 0.01 ether)
                        : 0;
                    require(amountIn == amount, "Incorrect amount of ETH sent");
                    IWETH(WETH).deposit{value: amount}();
                    assert(IWETH(WETH).transfer(currentPair, amount));
                } else {
                    currentPair = UniswapV2Lib.pairFor(factory, tokenSold, tokenBought, initCode);
                    if ((crossChainData >> 161) != 2) {
                        transferTokens(tokenSold, msg.sender, currentPair, amountIn);
                    } else {
                        IERC20(tokenSold).approve(address(getTokenTransferProxy()), amountIn);
                        transferTokens(tokenSold, address(this), currentPair, amountIn);
                    }
                }
            }
            //AmountIn for this hop is amountOut of previous hop
            tokensBought = UniswapV2Lib.getAmountOutByPair(
                tokensBought,
                currentPair,
                tokenSold,
                tokenBought,
                FEE,
                FEE_FACTOR
            );

            if ((i + 1) == pairs) {
                receiver = ((crossChainData >> 161) == 1) || tokensBoughtEth
                    ? address(this)
                    : address(uint160(crossChainData));
            } else {
                receiver = UniswapV2Lib.pairFor(
                    factory,
                    tokenBought,
                    path[i + 2] == ETH_IDENTIFIER ? WETH : path[i + 2],
                    initCode
                );
            }

            (address token0, ) = UniswapV2Lib.sortTokens(tokenSold, tokenBought);
            (uint256 amount0Out, uint256 amount1Out) = tokenSold == token0 ? 
                (uint256(0), tokensBought) : 
                (tokensBought, uint256(0));
            IUniswapV2Pair(currentPair).swap(amount0Out, amount1Out, receiver, new bytes(0));
        }
        if (tokensBoughtEth) {
            receiver = ((crossChainData >> 161) == 1) ? address(this) : address(uint160(crossChainData));
            IWETH(WETH).withdraw(tokensBought);
            TransferHelper.safeTransferETH(receiver, tokensBought);
            tokenBought = ETH_IDENTIFIER;
        }
    }

    function _buy(
        address factory,
        bytes32 initCode,
        uint256 amountOut,
        address[] calldata path
    ) private returns (uint256 tokensSold) {
        require(path.length > 1, "More than 1 token required");
        bool tokensBoughtEth;
        uint256 length = uint256(path.length);

        uint256[] memory amounts = new uint256[](length);
        address[] memory pairs = new address[](length - 1);

        amounts[length - 1] = amountOut;

        for (uint256 i = length - 1; i > 0; i--) {
            (amounts[i - 1], pairs[i - 1]) = UniswapV2Lib.getAmountInAndPair(
                factory,
                amounts[i],
                path[i - 1],
                path[i],
                initCode,
                FEE,
                FEE_FACTOR,
                WETH
            );
        }

        tokensSold = amounts[0];

        for (uint256 i = 0; i < length - 1; i++) {
            address tokenSold = path[i];
            address tokenBought = path[i + 1];

            if (i == length - 2) {
                if (tokenBought == ETH_IDENTIFIER) {
                    tokenBought = WETH;
                    tokensBoughtEth = true;
                }
            }
            if (i == 0) {
                if (tokenSold == ETH_IDENTIFIER) {
                    tokenSold = WETH;
                    TransferHelper.safeTransferETH(
                        msg.sender,
                        msg.value.sub(tokensSold)
                    );
                    IWETH(WETH).deposit{value: tokensSold}();
                    assert(IWETH(WETH).transfer(pairs[i], tokensSold));
                } else {
                    transferTokens(tokenSold, msg.sender, pairs[i], tokensSold);
                }
            }

            address receiver;

            if (i == length - 2) {
                if (tokensBoughtEth) {
                    receiver = address(this);
                } else {
                    receiver = msg.sender;
                }
            } else {
                receiver = pairs[i + 1];
            }

            (address token0, ) = UniswapV2Lib.sortTokens(
                tokenSold,
                tokenBought
            );
            (uint256 amount0Out, uint256 amount1Out) = tokenSold == token0
                ? (uint256(0), amounts[i + 1])
                : (amounts[i + 1], uint256(0));
            IUniswapV2Pair(pairs[i]).swap(
                amount0Out,
                amount1Out,
                receiver,
                new bytes(0)
            );
        }
        if (tokensBoughtEth) {
            IWETH(WETH).withdraw(amountOut);
            TransferHelper.safeTransferETH(msg.sender, amountOut);
        }
    }

    /// @dev Function using for send tokens and data through DeBridge
    /// @param data Data to execute swap in second chain
    /// @param tokensBought Amount of tokens that contract receive after swap
    /// @param tokenBought Address of token that was last in the path
    function send(
        Utils.UniswapV2RouterData memory data,
        uint256 tokensBought,
        address tokenBought
    ) public payable {
        address _bridgeAddress = 0x68D936Cb4723BdD38C488FD50514803f96789d2D;

        address contractAddressTo = chainIdToContractAddress[data.chainId];
        require(contractAddressTo != address(0), "Incremetor: ChainId is not supported");
        require(tokensBought.div(2) >= data.executionFee, "UNISWAPV2ROuter: #1");
        if (tokenBought != Utils.ethAddress()){
            IERC20(tokenBought).approve(_bridgeAddress, tokensBought);
        }
        IDeBridgeGate.SubmissionAutoParamsTo memory autoParams;
        autoParams.flags = autoParams.flags.setFlag(Flags.REVERT_IF_EXTERNAL_FAIL, true);
        autoParams.flags = autoParams.flags.setFlag(Flags.PROXY_WITH_SENDER, true);
        autoParams.executionFee = data.executionFee;
        autoParams.fallbackAddress = abi.encodePacked(data.beneficiary);
        autoParams.data = abi.encodeWithSelector(
            this.swapOnUniswapDeBridge.selector,
            data
        );

        uint256 deBridgeFee = getChainId() == 80001
            ? 0.1 ether
            : 0.01 ether;
        emit LogBalance(tokenBought, address(this).balance);
        if (tokenBought != Utils.ethAddress()){
            Utils.transferTokens(Utils.ethAddress(), payable(contractAddressTo), deBridgeFee);
        }
        Utils.transferTokens(tokenBought, payable(data.beneficiary), tokensBought);
        // emit LogBalance(tokenBought, IERC20(tokenBought).balanceOf(address(this)));
        
        // if (tokenBought == WETH) {
        //     deBridgeGate.send{value: tokensBought}(
        //         address(0),
        //         tokensBought,
        //         data.chainId,
        //         abi.encodePacked(contractAddressTo),
        //         "",
        //         false,
        //         0,
        //         abi.encode(autoParams)
        //     );
        // } else {
        //     deBridgeGate.send{value: deBridgeFee}(
        //         tokenBought,
        //         tokensBought,
        //         data.chainId,
        //         abi.encodePacked(contractAddressTo),
        //         "",
        //         false,
        //         0,
        //         abi.encode(autoParams)
        //     );
        // }
    }

    function initialize(address _bridgeAddr) public {
        __BridgeAppBase_init(IDeBridgeGate(_bridgeAddr));
    }

    function getTokenTransferProxy() public view returns (address) {
        return address(tokenTransferProxy);
    }
}
