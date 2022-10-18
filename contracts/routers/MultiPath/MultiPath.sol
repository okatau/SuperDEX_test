pragma solidity ^0.8.1;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../../interfaces/IFeeClaimer.sol";
import "../../interfaces/ITokenTransferProxy.sol";
import "../../interfaces/IRouter.sol";
import "../../interfaces/IRouter.sol";
import "../../interfaces/IWETH.sol";
import "../../adapters/IAdapter.sol";
import "../../adapters/IBuyAdapter.sol";
import "../../libraries/Utils.sol";
import "../../DeBridgeContracts/BridgeAppBase.sol";
import "../../AugustusStorage.sol";
import "../../interfaces/IAugustusSwapperV5.sol";
import "../../FeeModel.sol";


// Arg [0] : _partnerSharePercent (uint256): 8500
// Arg [1] : _maxFeePercent (uint256): 500
// Arg [2] : _feeClaimer (address): 0xef13101c5bbd737cfb2bf00bbd38c626ad6952f7

contract MultiPath is FeeModel, IRouter, BridgeAppBase {
    using SafeMath for uint256;
    using Flags for uint256;

    // uint256 CURRENT_CHAINID;
    // uint256 DEBRIDGE_FEE;

    event TokensBought(address token, uint256 amount);
    event CurrentETHBalance(uint256 balance);

    /*solhint-disable no-empty-blocks*/
    constructor(
        uint256 _partnerSharePercent,
        uint256 _maxFeePercent,
        IFeeClaimer _feeClaimer
    ) public FeeModel(_partnerSharePercent, _maxFeePercent, _feeClaimer) {}

    /*solhint-enable no-empty-blocks*/

    function initialize(bytes calldata) external override {
        revert("METHOD NOT IMPLEMENTED");
    }

    function getKey() external pure override returns (bytes32) {
        return keccak256(abi.encodePacked("MULTIPATH_ROUTER", "1.0.0"));
    }

    /**
     * @dev The function which performs the multi path swap.
     * @param data Data required to perform swap.
     */
    function multiSwap(Utils.SellData memory data) public payable returns (uint256) {
        require(data.deadline >= block.timestamp, "Deadline breached");

        address fromToken = data.fromToken;
        uint256 fromAmount = data.fromAmount;
        require(msg.value == (fromToken == Utils.ethAddress() ? fromAmount : 0), "Incorrect msg.value");
        uint256 toAmount = data.toAmount;
        uint256 expectedAmount = data.expectedAmount;
        address payable beneficiary = data.beneficiary == address(0) ? payable(msg.sender) : data.beneficiary;
        Utils.Path[] memory path = data.path;
        address toToken = path[path.length - 1].to;

        require(toAmount > 0, "To amount can not be 0");

        //If source token is not ETH than transfer required amount of tokens
        //from sender to this contract
        transferTokensFromProxy(fromToken, fromAmount, data.permit);
        if (_isTakeFeeFromSrcToken(data.feePercent)) {
            // take fee from source token
            fromAmount = takeFromTokenFee(fromToken, fromAmount, data.partner, data.feePercent);
        }

        performSwap(fromToken, fromAmount, path);

        uint256 receivedAmount = Utils.tokenBalance(toToken, address(this));

        require(receivedAmount >= toAmount, "Received amount of tokens are less then expected");

        if (!_isTakeFeeFromSrcToken(data.feePercent)) {
            // take fee from dest token
            takeToTokenFeeSlippageAndTransfer(
                toToken,
                expectedAmount,
                receivedAmount,
                beneficiary,
                data.partner,
                data.feePercent
            );
        } else {
            // Fee is already taken from fromToken
            // Transfer toToken to beneficiary
            Utils.transferTokens(toToken, beneficiary, receivedAmount);
        }

        emit SwappedV3(
            data.uuid,
            data.partner,
            data.feePercent,
            msg.sender,
            beneficiary,
            fromToken,
            toToken,
            fromAmount,
            receivedAmount,
            expectedAmount
        );

        return receivedAmount;
    }
    

    /// @notice The function using to swap tokens between chains
    /// @dev This function using only for swap beofre Debridge
    /// @param data All data required to swap. See ../../libraires/Utils.sol
    /// @return receivedAmount Amount of tokens that user will receive after swap
    function multiSwapDeBridge(Utils.SellDataDeBridge memory data) public payable returns (uint256) {
        require(data.deadline >= block.timestamp, "Deadline breached");
        require(data.beneficiary != address(0), "U cant send tx wo receiver address");

        bool currentChainId = data.chainId == getChainId();
        uint256 deBridgeFee = getChainId() == 80001 ? 0.1 ether : 0.01 ether;

        (Utils.Path[] memory path, address fromToken) = currentChainId ? 
            (data.pathAfterSend, data.fromToken[1]) : 
            (data.pathBeforeSend, data.fromToken[0]);

        uint256 fromAmount = currentChainId ? 
            IERC20(fromToken).allowance(msg.sender, address(this)) : 
            (fromToken == Utils.ethAddress() ? (data.fromAmount - deBridgeFee) : data.fromAmount);

        require(msg.value == (currentChainId ? 
            0 : 
            (fromToken == Utils.ethAddress() ? data.fromAmount : deBridgeFee)), "Incorrect msg.value");

        address toToken = path[path.length - 1].to;

        require(data.toAmount > 0, "To amount can not be 0");

        //If source token is not ETH than transfer required amount of tokens
        //from sender to this contract
        if (currentChainId) {
            transferTokensDeBridge(fromToken, fromAmount, data.beneficiary, path.length, data.permit);
        } 
        else {
            transferTokensFromProxy(fromToken, fromAmount, data.permit);

            if (_isTakeFeeFromSrcToken(data.feePercent)) {
                // take fee from source token
                fromAmount = takeFromTokenFee(fromToken, fromAmount, data.partner, data.feePercent);
            }
        }


        uint256 receivedAmount;

        if (path.length > 0) {    
            performSwap(fromToken, fromAmount, path);
        
            receivedAmount = Utils.tokenBalance(toToken, address(this));
        
            require(receivedAmount >= data.toAmount, "Received amount of tokens are less then expected");

            if (!currentChainId){
                if (!_isTakeFeeFromSrcToken(data.feePercent)) {
                    // take fee from dest token
                    receivedAmount = takeToTokenFeeSlippageAndTransfer(
                    toToken,
                    data.expectedAmount,
                    receivedAmount,
                    payable(address(this)),
                    data.partner,
                    data.feePercent
                    );
                }

                _send(data, receivedAmount);
                
            } else {
                Utils.transferTokens(toToken, data.beneficiary, receivedAmount);
            }
        }

        return receivedAmount;
    }

    /**
     * @dev The function which performs the single path buy.
     * @param data Data required to perform swap.
     */
    function buy(Utils.BuyData memory data) public payable returns (uint256) {
        require(data.deadline >= block.timestamp, "Deadline breached");

        address fromToken = data.fromToken;
        uint256 fromAmount = data.fromAmount;
        require(msg.value == (fromToken == Utils.ethAddress() ? fromAmount : 0), "Incorrect msg.value");
        uint256 toAmount = data.toAmount;
        address payable beneficiary = data.beneficiary == address(0) ? payable(msg.sender) : data.beneficiary;
        address toToken = data.toToken;
        uint256 expectedAmount = data.expectedAmount;

        require(toAmount > 0, "To amount can not be 0");

        //If source token is not ETH than transfer required amount of tokens
        //from sender to this contract
        transferTokensFromProxy(fromToken, fromAmount, data.permit);

        uint256 receivedAmount = performBuy(data.adapter, fromToken, toToken, fromAmount, toAmount, data.route);

        uint256 remainingAmount;

        if (!_isTakeFeeFromSrcToken(data.feePercent)) {
            // take fee from dest token
            takeToTokenFeeAndTransfer(toToken, receivedAmount, beneficiary, data.partner, data.feePercent);

            // Transfer fromToken back to sender
            remainingAmount = Utils.tokenBalance(fromToken, address(this));
            Utils.transferTokens(fromToken, payable(msg.sender), remainingAmount);
        } else {
            // Transfer toToken to beneficiary
            Utils.transferTokens(toToken, beneficiary, receivedAmount);

            // take slippage from src token
            remainingAmount = Utils.tokenBalance(fromToken, address(this));
            takeFromTokenFeeSlippageAndTransfer(
                fromToken,
                fromAmount,
                expectedAmount,
                remainingAmount,
                data.partner,
                data.feePercent
            );
        }

        fromAmount = fromAmount.sub(remainingAmount);
        emit BoughtV3(
            data.uuid,
            data.partner,
            data.feePercent,
            msg.sender,
            beneficiary,
            fromToken,
            toToken,
            fromAmount,
            receivedAmount,
            expectedAmount
        );

        return receivedAmount;
    }

    /**
     * @dev The function which performs the mega path swap.
     * @param data Data required to perform swap.
     */
    function megaSwap(Utils.MegaSwapSellData memory data) public payable returns (uint256) {
        require(data.deadline >= block.timestamp, "Deadline breached");
        address fromToken = data.fromToken;
        uint256 fromAmount = data.fromAmount;
        require(msg.value == (fromToken == Utils.ethAddress() ? fromAmount : 0), "Incorrect msg.value");
        uint256 toAmount = data.toAmount;
        uint256 expectedAmount = data.expectedAmount;
        address payable beneficiary = data.beneficiary == address(0) ? payable(msg.sender) : data.beneficiary;
        Utils.MegaSwapPath[] memory path = data.path;
        address toToken = path[0].path[path[0].path.length - 1].to;

        require(toAmount > 0, "To amount can not be 0");

        //if fromToken is not ETH then transfer tokens from user to this contract
        transferTokensFromProxy(fromToken, fromAmount, data.permit);
        if (_isTakeFeeFromSrcToken(data.feePercent)) {
            // take fee from source token
            fromAmount = takeFromTokenFee(fromToken, fromAmount, data.partner, data.feePercent);
        }

        for (uint8 i = 0; i < uint8(path.length); i++) {
            uint256 _fromAmount = fromAmount.mul(path[i].fromAmountPercent).div(10000);
            if (i == path.length - 1) {
                _fromAmount = Utils.tokenBalance(address(fromToken), address(this));
            }
            performSwap(fromToken, _fromAmount, path[i].path);
        }

        uint256 receivedAmount = Utils.tokenBalance(toToken, address(this));

        require(receivedAmount >= toAmount, "Received amount of tokens are less then expected");

        if (!_isTakeFeeFromSrcToken(data.feePercent)) {
            // take fee from dest token
            takeToTokenFeeSlippageAndTransfer(
                toToken,
                expectedAmount,
                receivedAmount,
                beneficiary,
                data.partner,
                data.feePercent
            );
        } else {
            // Fee is already taken from fromToken
            // Transfer toToken to beneficiary
            Utils.transferTokens(toToken, beneficiary, receivedAmount);
        }

        emit SwappedV3(
            data.uuid,
            data.partner,
            data.feePercent,
            msg.sender,
            beneficiary,
            fromToken,
            toToken,
            fromAmount,
            receivedAmount,
            expectedAmount
        );

        return receivedAmount;
    }

    function megaSwapDeBridge(Utils.MegaSwapSellDataDeBridge memory data) public payable returns (uint256) {
        require(data.deadline >= block.timestamp, "Deadline breached");
        require(data.beneficiary != address(0), "U cant send tx wo receiver address");
        bool currentChainId = getChainId() == data.chainId;
        uint256 deBridgeFee = getChainId() == 80001 ? 0.1 ether : 0.01 ether;
        (address fromToken, Utils.MegaSwapPath[] memory path) = currentChainId ? 
            (data.fromToken[1], data.pathAfterSend) :
            (data.fromToken[0], data.pathBeforeSend);
        uint256 fromAmount = currentChainId ? 
            IERC20(fromToken).allowance(msg.sender, address(this)) : 
            (fromToken == Utils.ethAddress() ? (data.fromAmount - deBridgeFee) : data.fromAmount);
       require(msg.value == (currentChainId ? 
            0 : 
            (fromToken == Utils.ethAddress() ? data.fromAmount : deBridgeFee)), "Incorrect msg.value");
        address payable beneficiary = data.beneficiary;
        address toToken = path[0].path[path[0].path.length - 1].to;

        require(data.toAmount > 0, "To amount can not be 0");

        //if fromToken is not ETH then transfer tokens from user to this contract
        if (currentChainId) {
            transferTokensDeBridge(fromToken, fromAmount, data.beneficiary, path.length, data.permit);
        } 
        else {
            transferTokensFromProxy(fromToken, fromAmount, data.permit);

            if (_isTakeFeeFromSrcToken(data.feePercent)) {
                // take fee from source token
                fromAmount = takeFromTokenFee(fromToken, fromAmount, data.partner, data.feePercent);
            }
        }

        uint256 receivedAmount;

        if (path.length > 0) {
            for (uint8 i = 0; i < uint8(path.length); i++) {
                uint256 _fromAmount = fromAmount.mul(path[i].fromAmountPercent).div(10000);
                if (i == path.length - 1) {
                    _fromAmount = Utils.tokenBalance(address(fromToken), address(this));
                    if (fromToken == Utils.ethAddress()){
                        _fromAmount -= deBridgeFee;
                    }
                }
                performSwap(fromToken, _fromAmount, path[i].path);
            }

            receivedAmount = Utils.tokenBalance(toToken, address(this));

            require(receivedAmount >= data.toAmount, "Received amount of tokens are less then expected");
            if (!currentChainId){
                if (!_isTakeFeeFromSrcToken(data.feePercent)) {
                    // take fee from dest token
                    receivedAmount = takeToTokenFeeSlippageAndTransfer(
                        toToken,
                        data.expectedAmount,
                        receivedAmount,
                        payable(address(this)),
                        data.partner,
                        data.feePercent
                    );
                }
                _send(data, receivedAmount);
            } else {
                Utils.transferTokens(toToken, data.beneficiary, receivedAmount);
            }
        }

        return receivedAmount;
    }

    //Helper function to perform swap
    function performSwap(
        address fromToken,
        uint256 fromAmount,
        Utils.Path[] memory path
    ) private {
        require(path.length > 0, "Path not provided for swap");

        //Assuming path will not be too long to reach out of gas exception
        for (uint256 i = 0; i < path.length; i++) {
            //_fromToken will be either fromToken or toToken of the previous path
            address _fromToken = i > 0 ? path[i - 1].to : fromToken;
            address _toToken = path[i].to;

            uint256 _fromAmount = i > 0 ? Utils.tokenBalance(_fromToken, address(this)) : fromAmount;

            for (uint256 j = 0; j < path[i].adapters.length; j++) {
                Utils.Adapter memory adapter = path[i].adapters[j];

                //Check if exchange is supported
                // require(
                //     IAugustusSwapperV5(address(this)).hasRole(WHITELISTED_ROLE, adapter.adapter),
                //     "Exchange not whitelisted"
                // );

                //Calculating tokens to be passed to the relevant exchange
                //percentage should be 200 for 2%
                uint256 fromAmountSlice = i > 0 && j == path[i].adapters.length.sub(1)
                    ? Utils.tokenBalance(address(_fromToken), address(this))
                    : _fromAmount.mul(adapter.percent).div(10000);

                //DELEGATING CALL TO THE ADAPTER
                (bool success, ) = adapter.adapter.delegatecall(
                    abi.encodeWithSelector(
                        IAdapter.swap.selector,
                        _fromToken,
                        _toToken,
                        fromAmountSlice,
                        uint256(0), //adapter.networkFee,
                        adapter.route
                    )
                );

                require(success, "Call to adapter failed");
            }
        }
    }

    //Helper function to perform swap
    function performBuy(
        address adapter,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount,
        Utils.Route[] memory routes
    ) private returns (uint256) {
        //Check if exchange is supported
        require(IAugustusSwapperV5(address(this)).hasRole(WHITELISTED_ROLE, adapter), "Exchange not whitelisted");

        for (uint256 j = 0; j < routes.length; j++) {
            Utils.Route memory route = routes[j];

            uint256 fromAmountSlice;
            uint256 toAmountSlice;

            //last route
            if (j == routes.length.sub(1)) {
                toAmountSlice = toAmount.sub(Utils.tokenBalance(address(toToken), address(this)));

                fromAmountSlice = Utils.tokenBalance(address(fromToken), address(this));
            } else {
                fromAmountSlice = fromAmount.mul(route.percent).div(10000);
                toAmountSlice = toAmount.mul(route.percent).div(10000);
            }

            //delegate Call to the exchange
            (bool success, ) = adapter.delegatecall(
                abi.encodeWithSelector(
                    IBuyAdapter.buy.selector,
                    route.index,
                    fromToken,
                    toToken,
                    fromAmountSlice,
                    toAmountSlice,
                    route.targetExchange,
                    route.payload
                )
            );
            require(success, "Call to adapter failed");
        }

        uint256 receivedAmount = Utils.tokenBalance(toToken, address(this));
        require(receivedAmount >= toAmount, "Received amount of tokens are less then expected tokens");

        return receivedAmount;
    }

    function transferTokensFromProxy(
        address token,
        uint256 amount,
        bytes memory permit
    ) private {
        if (token != Utils.ethAddress()) {
            Utils.permit(token, permit);
            tokenTransferProxy.transferFrom(token, msg.sender, address(this), amount);
            // IERC20(token).transferFrom(msg.sender, address(this), amount);
        }
    }

    function _approve(address _token, address _to, uint256 amount) public {
        IERC20(_token).approve(_to, amount);
    }
    
    function _send(Utils.SellDataDeBridge memory data, uint256 tokensBought)
        public
        payable
    {
        require(msg.value >= 0.01 ether, "msg.value too low");
        address _bridgeAddress = 0x68D936Cb4723BdD38C488FD50514803f96789d2D;
        address _token = data.pathBeforeSend[data.pathBeforeSend.length - 1].to;
        if (_token != Utils.ethAddress()){
            IERC20(_token).approve(_bridgeAddress, tokensBought);
        }
        require(tokensBought.div(2) >= data.executionFee, "insufficient token amount line 484");
        address contractAddressTo = chainIdToContractAddress[data.chainId];
        require(
            contractAddressTo != address(0),
            "Incremetor: ChainId is not supported"
        );
        IDeBridgeGate.SubmissionAutoParamsTo memory autoParams;
        autoParams.flags = autoParams.flags.setFlag(Flags.REVERT_IF_EXTERNAL_FAIL, true);
        autoParams.flags = autoParams.flags.setFlag(Flags.PROXY_WITH_SENDER, true);
        autoParams.executionFee = data.executionFee;
        autoParams.fallbackAddress = abi.encodePacked(data.beneficiary);
        autoParams.data = abi.encodeWithSelector(
            this.multiSwapDeBridge.selector,
            data
        );
        uint256 deBridgeFee = getChainId() == 80001
            ? 0.1 ether
            : 0.01 ether;
        emit TokensBought(_token, tokensBought);
        emit CurrentETHBalance(address(this).balance);
        if (_token != Utils.ethAddress()){
            Utils.transferTokens(Utils.ethAddress(), payable(contractAddressTo), deBridgeFee);
        }
        Utils.transferTokens(_token, data.beneficiary, tokensBought);
        // if (_token == Utils.ethAddress()) {
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
        //     deBridgeGate.send{value: msg.value}(
        //         _token,
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

    function _send(Utils.MegaSwapSellDataDeBridge memory data, uint256 tokensBought)
        public
        payable
    {
        require(msg.value >= 0.01 ether, "msg.value too low");
        address _bridgeAddress = 0x68D936Cb4723BdD38C488FD50514803f96789d2D;
        address _token = data.pathBeforeSend[data.pathBeforeSend.length - 1].path[data.pathBeforeSend[data.pathBeforeSend.length - 1].path.length - 1].to;
        if (_token != Utils.ethAddress()){
            IERC20(_token).approve(_bridgeAddress, tokensBought);
        }
        require(tokensBought.div(2) >= data.executionFee, "insufficient token amount line 484");
        address contractAddressTo = chainIdToContractAddress[data.chainId];
        require(
            contractAddressTo != address(0),
            "Incremetor: ChainId is not supported"
        );
        IDeBridgeGate.SubmissionAutoParamsTo memory autoParams;
        autoParams.flags = autoParams.flags.setFlag(Flags.REVERT_IF_EXTERNAL_FAIL, true);
        autoParams.flags = autoParams.flags.setFlag(Flags.PROXY_WITH_SENDER, true);
        autoParams.executionFee = data.executionFee;
        autoParams.fallbackAddress = abi.encodePacked(data.beneficiary);
        autoParams.data = abi.encodeWithSelector(
            this.megaSwapDeBridge.selector,
            data
        );

        uint256 deBridgeFee = getChainId() == 80001
            ? 0.1 ether
            : 0.01 ether;
        emit TokensBought(_token, tokensBought);
        emit CurrentETHBalance(address(this).balance);
        if (_token != Utils.ethAddress()){
            Utils.transferTokens(Utils.ethAddress(), payable(contractAddressTo), deBridgeFee);
        }
        Utils.transferTokens(_token, data.beneficiary, tokensBought);
        // if (_token == Utils.ethAddress()) {
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
        //         _token,
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

    function transferTokensDeBridge(address token, uint256 amount, address payable receiver, uint256 pathLength, bytes memory permit) public payable {
        // transferTokensFromProxy(token, amount, permit);
        IERC20(token).transferFrom(msg.sender, address(this), amount);
            if(pathLength == 0){
                Utils.transferTokens(token, receiver, amount);
            }
    }

}