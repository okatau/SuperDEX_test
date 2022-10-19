pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/ITokenTransferProxy.sol";
import "../../interfaces/IRouter.sol";
import "../../interfaces/IERC20PermitLegacy.sol";
import "../../libraries/Utils.sol";
import "../../DeBridgeContracts/BridgeAppBase.sol";
import "../../FeeModel.sol";
import "../../AugustusStorage.sol";

contract SimpleSwap is FeeModel, IRouter, BridgeAppBase {
    using SafeMath for uint256;
    using Flags for uint256;
    address public immutable augustusRFQ;

    struct SwapData{
        bool currentChain;
        address[] path;
        uint256 fromAmount;
        address beneficiary;
        bytes exchangeData;
        uint256[] startIndexes;
        uint256[] values;
    }

    event LastBalance(address _token, uint256 balance);

    /*solhint-disable no-empty-blocks*/
    constructor(
        uint256 _partnerSharePercent,
        uint256 _maxFeePercent,
        IFeeClaimer _feeClaimer,
        address _augustusRFQ
    ) public FeeModel(_partnerSharePercent, _maxFeePercent, _feeClaimer) {
        augustusRFQ = _augustusRFQ;
    }

    /*solhint-enable no-empty-blocks*/

    function initialize(bytes calldata) external override {
        revert("METHOD NOT IMPLEMENTED");
    }

    function getKey() external pure override returns (bytes32) {
        return keccak256(abi.encodePacked("SIMPLE_SWAP_ROUTER", "1.0.0"));
    }

    function simpleSwap(Utils.SimpleData memory data)
        public
        payable
        returns (uint256 receivedAmount)
    {
        require(data.deadline >= block.timestamp, "Deadline breached");
        address payable beneficiary = data.beneficiary == address(0)
            ? payable(msg.sender)
            : data.beneficiary;
        receivedAmount = performSimpleSwap(
            data.callees,
            data.exchangeData,
            data.startIndexes,
            data.values,
            data.fromToken,
            data.toToken,
            data.fromAmount,
            data.toAmount,
            data.expectedAmount,
            data.partner,
            data.feePercent,
            data.permit,
            beneficiary
        );

        emit SwappedV3(
            data.uuid,
            data.partner,
            data.feePercent,
            msg.sender,
            beneficiary,
            data.fromToken,
            data.toToken,
            data.fromAmount,
            receivedAmount,
            data.expectedAmount
        );

        return receivedAmount;
    }

    /// @notice The function using to swap tokens between chains
    /// @dev This function using only for swap beofre Debridge
    /// @param data All data required to swap. See ../../libraires/Utils.sol
    /// @return receivedAmount Amount of tokens that user will receive after swap
    function simpleSwapDeBridge(Utils.SimpleDataDeBridge memory data)
        public
        payable
        returns (uint256 receivedAmount)
    {
        require(data.deadline >= block.timestamp, "Deadline breached");
        require(data.beneficiary != address(0), "Beneficiary can't be zero address");
        SwapData memory tempData = getDataToSwap(data);
        (receivedAmount) = performSimpleSwapDeBridge(
            data.callees,
            tempData.exchangeData,
            tempData.startIndexes,
            tempData.values,
            tempData.path,
            tempData.fromAmount,
            data.toAmount,
            data.expectedAmount,
            data.partner,
            data.feePercent,
            data.permit,
            payable(tempData.beneficiary),
            data.calleesBeforeSend,
            tempData.currentChain
        );

        // _send(data, receivedAmount);
        emit LastBalance(tempData.path[tempData.path.length - 1], IERC20(tempData.path[tempData.path.length - 1]).balanceOf(address(this)));
        emit SwappedV3(
            data.uuid,
            data.partner,
            data.feePercent,
            msg.sender,
            payable(address(this)),
            data.pathBeforeSend[0],
            data.pathBeforeSend[1],
            data.fromAmount,
            receivedAmount,
            data.expectedAmount
        );

        return (receivedAmount);
    }

    /// @dev This function using for swap after DeBridge
    function simpleSwapAfterDeBridge(Utils.SimpleDataDeBridge memory data)
        public
        payable
        returns (uint256 receivedAmount)
    {
        require(data.deadline >= block.timestamp, "Deadline breached");

        
        data.fromAmount = IERC20(data.pathAfterSend[0]).allowance(msg.sender, address(this));
        IERC20(data.pathAfterSend[0]).transferFrom(msg.sender, address(this), data.fromAmount);

        if (data.pathAfterSend.length == 1) {
            Utils.transferTokens(data.pathAfterSend[0], data.beneficiary, receivedAmount);
        } else {
            (data.exchangeData, data.startIndexes[data.callees.length]) = encodeFunctionCall(
                data.fromAmount,
                data.pathAfterSend,
                data.exchangeData
            );

            if (data.pathAfterSend[0] == address(0)) {
                data.values[data.callees.length - 1] = data.fromAmount;
            }

            (receivedAmount) = performSimpleSwapDeBridge(
                data.callees,
                data.exchangeData,
                data.startIndexes,
                data.values,
                data.pathAfterSend,
                data.fromAmount,
                data.toAmount,
                data.expectedAmount,
                data.partner,
                data.feePercent,
                data.permit,
                data.beneficiary,
                data.calleesBeforeSend,
                true
            );

            emit SwappedV3(
                data.uuid,
                data.partner,
                data.feePercent,
                msg.sender,
                payable(address(this)),
                data.pathAfterSend[0],
                data.pathAfterSend[1],
                data.fromAmount,
                receivedAmount,
                data.expectedAmount
            );
        }

        return (receivedAmount);
    }

    function simpleBuy(Utils.SimpleData calldata data) external payable {
        require(data.deadline >= block.timestamp, "Deadline breached");
        address payable beneficiary = data.beneficiary == address(0)
            ? payable(msg.sender)
            : data.beneficiary;
        (uint256 receivedAmount, uint256 remainingAmount) = performSimpleBuy(
            data.callees,
            data.exchangeData,
            data.startIndexes,
            data.values,
            data.fromToken,
            data.toToken,
            data.fromAmount,
            data.toAmount,
            data.expectedAmount,
            data.partner,
            data.feePercent,
            data.permit,
            beneficiary
        );

        emit BoughtV3(
            data.uuid,
            data.partner,
            data.feePercent,
            msg.sender,
            beneficiary,
            data.fromToken,
            data.toToken,
            data.fromAmount.sub(remainingAmount),
            receivedAmount,
            data.expectedAmount
        );
    }

    function performSimpleSwap(
        address[] memory callees,
        bytes memory exchangeData,
        uint256[] memory startIndexes,
        uint256[] memory values,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount,
        uint256 expectedAmount,
        address payable partner,
        uint256 feePercent,
        bytes memory permit,
        address payable beneficiary
    ) private returns (uint256 receivedAmount) {
        require(
            msg.value == (fromToken == address(0) ? fromAmount : 0),
            "Incorrect msg.value"
        );
        require(toAmount > 0, "toAmount is too low");
        require(
            callees.length + 1 == startIndexes.length,
            "Start indexes must be 1 greater then number of callees"
        );
        require(
            callees.length == values.length,
            "callees and values must have same length"
        );

        //If source token is not ETH than transfer required amount of tokens
        //from sender to this contract
        transferTokensFromProxy(fromToken, fromAmount, permit);

        performCalls(callees, exchangeData, startIndexes, values);

        receivedAmount = Utils.tokenBalance(toToken, address(this));

        require(
            receivedAmount >= toAmount,
            "Received amount of tokens are less then expected"
        );

        if (!_isTakeFeeFromSrcToken(feePercent)) {
            // take fee from dest token
            takeToTokenFeeSlippageAndTransfer(
                toToken,
                expectedAmount,
                receivedAmount,
                beneficiary,
                partner,
                feePercent
            );
        } else {
            // Transfer toToken to beneficiary
            Utils.transferTokens(toToken, beneficiary, receivedAmount);

            // take fee from source token
            takeFromTokenFee(fromToken, fromAmount, partner, feePercent);
        }

        return receivedAmount;
    }

    function performSimpleSwapDeBridge(
        address[] memory callees,
        bytes memory exchangeData,
        uint256[] memory startIndexes,
        uint256[] memory values,
        address[] memory path,
        uint256 fromAmount,
        uint256 toAmount,
        uint256 expectedAmount,
        address payable partner,
        uint256 feePercent,
        bytes memory permit,
        address payable beneficiary,
        uint256 calleesBeforeSend,
        bool currentChainId
    ) private returns (uint256) {
        require(toAmount > 0, "toAmount is too low");
        require(
            callees.length + 1 == startIndexes.length,
            "Start indexes must be 1 greater then number of callees"
        );
        require(
            callees.length == values.length,
            "callees and values must have same length"
        );

        //If source token is not ETH than transfer required amount of tokens
        //from sender to this contract
        if (!currentChainId) {
            transferTokensFromProxy(path[0], fromAmount, permit);
        } else {
            IERC20(path[0]).transferFrom(msg.sender, address(this), fromAmount);
        }

        performCallsDeBridge(
            callees,
            exchangeData,
            startIndexes,
            values,
            calleesBeforeSend,
            currentChainId
        );

        uint256 receivedAmount = Utils.tokenBalance(path[1], address(this));

        require(
            receivedAmount >= toAmount,
            "Received amount of tokens are less then expected"
        );
        if (!currentChainId) {
            if (!_isTakeFeeFromSrcToken(feePercent)) {
                // take fee from dest token
                receivedAmount = takeToTokenFeeSlippageAndTransfer(
                    path[1],
                    expectedAmount,
                    receivedAmount,
                    beneficiary,
                    partner,
                    feePercent
                );
            } else {
                // take fee from source token
                receivedAmount = takeFromTokenFee(
                    path[0],
                    fromAmount,
                    partner,
                    feePercent
                );
            }
        }
        Utils.transferTokens(path[1], beneficiary, receivedAmount);
        return (receivedAmount);
    }

    function performSimpleBuy(
        address[] memory callees,
        bytes memory exchangeData,
        uint256[] memory startIndexes,
        uint256[] memory values,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount,
        uint256 expectedAmount,
        address payable partner,
        uint256 feePercent,
        bytes memory permit,
        address payable beneficiary
    ) private returns (uint256 receivedAmount, uint256 remainingAmount) {
        require(
            msg.value == (fromToken == Utils.ethAddress() ? fromAmount : 0),
            "Incorrect msg.value"
        );
        require(toAmount > 0, "toAmount is too low");
        require(
            callees.length + 1 == startIndexes.length,
            "Start indexes must be 1 greater then number of callees"
        );
        require(
            callees.length == values.length,
            "callees and values must have same length"
        );

        //If source token is not ETH than transfer required amount of tokens
        //from sender to this contract
        transferTokensFromProxy(fromToken, fromAmount, permit);

        performCalls(callees, exchangeData, startIndexes, values);

        receivedAmount = Utils.tokenBalance(toToken, address(this));

        require(
            receivedAmount >= toAmount,
            "Received amount of tokens are less then expected"
        );

        if (!_isTakeFeeFromSrcToken(feePercent)) {
            // take fee from dest token
            takeToTokenFeeAndTransfer(
                toToken,
                receivedAmount,
                beneficiary,
                partner,
                feePercent
            );

            // Transfer remaining token back to msg.sender
            remainingAmount = Utils.tokenBalance(fromToken, address(this));
            Utils.transferTokens(
                fromToken,
                payable(msg.sender),
                remainingAmount
            );
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
                partner,
                feePercent
            );
        }

        return (receivedAmount, remainingAmount);
    }

    function transferTokensFromProxy(
        address token,
        uint256 amount,
        bytes memory permit
    ) private {
        if (token != Utils.ethAddress()) {
            Utils.permit(token, permit);
            tokenTransferProxy.transferFrom(
                token,
                msg.sender,
                address(this),
                amount
            );
        }
    }

    function performCalls(
        address[] memory callees,
        bytes memory exchangeData,
        uint256[] memory startIndexes,
        uint256[] memory values
    ) private {
        for (uint256 i = 0; i < callees.length; i++) {
            require(
                callees[i] != address(tokenTransferProxy),
                "Can not call TokenTransferProxy Contract"
            );

            if (callees[i] == augustusRFQ) {
                verifyAugustusRFQParams(startIndexes[i], exchangeData);
            } else {
                uint256 dataOffset = startIndexes[i];
                bytes32 selector;
                assembly {
                    selector := mload(add(exchangeData, add(dataOffset, 32)))
                }
                require(
                    bytes4(selector) != IERC20.transferFrom.selector,
                    "transferFrom not allowed for externalCall"
                );
            }

            bool result = externalCall(
                callees[i], //destination
                values[i], //value to send
                startIndexes[i], // start index of call data
                startIndexes[i + 1].sub(startIndexes[i]), // length of calldata
                exchangeData // total calldata
            );
            require(result, "External call failed");
        }
    }

    function performCallsDeBridge(
        address[] memory callees,
        bytes memory exchangeData,
        uint256[] memory startIndexes,
        uint256[] memory values,
        uint256 calleesBeforeSend,
        bool currentChainId
    ) private {
        uint256 _itterFrom = currentChainId ? calleesBeforeSend : 0;
        uint256 _itterTo = currentChainId ? callees.length : calleesBeforeSend;
        for (uint256 i = _itterFrom; i < _itterTo; i++) {
            require(
                callees[i] != address(tokenTransferProxy),
                "Can not call TokenTransferProxy Contract"
            );

            if (callees[i] == augustusRFQ) {
                verifyAugustusRFQParams(startIndexes[i], exchangeData);
            } else {
                uint256 dataOffset = startIndexes[i];
                bytes32 selector;
                assembly {
                    selector := mload(add(exchangeData, add(dataOffset, 32)))
                }
                require(
                    bytes4(selector) != IERC20.transferFrom.selector,
                    "transferFrom not allowed for externalCall"
                );
            }

            bool result = externalCall(
                callees[i], //destination
                values[i], //value to send
                startIndexes[i], // start index of call data
                startIndexes[i + 1].sub(startIndexes[i]), // length of calldata
                exchangeData // total calldata
            );
            require(result, "External call failed");
        }
    }

    function verifyAugustusRFQParams(
        uint256 startIndex,
        bytes memory exchangeData
    ) private view {
        // Load the 4 byte function signature in the lower 32 bits
        // Also load the memory address of the calldata params which follow
        uint256 sig;
        uint256 paramsStart;
        assembly {
            let tmp := add(exchangeData, startIndex)
            // Note that all bytes variables start with 32 bytes length field
            sig := shr(224, mload(add(tmp, 32)))
            paramsStart := add(tmp, 36)
        }
        if (
            sig == 0x98f9b46b || // fillOrder
            sig == 0xbbbc2372 || // fillOrderNFT
            sig == 0x00154008 || // fillOrderWithTarget
            sig == 0x3c3694ab || // fillOrderWithTargetNFT
            sig == 0xc88ae6dc || // partialFillOrder
            sig == 0xb28ace5f || // partialFillOrderNFT
            sig == 0x24abf828 || // partialFillOrderWithTarget
            sig == 0x30201ad3 || // partialFillOrderWithTargetNFT
            sig == 0xda6b84af || // partialFillOrderWithTargetPermit
            sig == 0xf6c1b371 // partialFillOrderWithTargetPermitNFT
        ) {
            // First parameter is fixed size (encoded in place) order struct
            // with nonceAndMeta being the first field, therefore:
            // nonceAndMeta is the first 32 bytes of the ABI encoding
            uint256 nonceAndMeta;
            assembly {
                nonceAndMeta := mload(paramsStart)
            }
            address userAddress = address(uint160(nonceAndMeta));
            require(
                userAddress == address(0) || userAddress == msg.sender,
                "unauthorized user"
            );
        } else if (
            sig == 0x077822bd || // batchFillOrderWithTarget
            sig == 0xc8b81d63 || // batchFillOrderWithTargetNFT
            sig == 0x1c64b820 || // tryBatchFillOrderTakerAmount
            sig == 0x01fb36ba // tryBatchFillOrderMakerAmount
        ) {
            // First parameter is variable length array of variable size order
            // infos where first field of order info is the actual order struct
            // (fixed size so encoded in place) which starts with nonceAndMeta.
            // Therefore, the nonceAndMeta is the first 32 bytes of order info.
            // But we need to find where the order infos start!
            // Firstly, we load the offset of the array, and its length
            uint256 arrayPtr;
            uint256 arrayLength;
            uint256 arrayStart;
            assembly {
                arrayPtr := add(paramsStart, mload(paramsStart))
                arrayLength := mload(arrayPtr)
                arrayStart := add(arrayPtr, 32)
            }
            // Each of the words after the array length is an offset from the
            // start of the array data, loading this gives us nonceAndMeta
            for (uint256 i = 0; i < arrayLength; ++i) {
                uint256 nonceAndMeta;
                assembly {
                    arrayPtr := add(arrayPtr, 32)
                    nonceAndMeta := mload(add(arrayStart, mload(arrayPtr)))
                }
                address userAddress = address(uint160(nonceAndMeta));
                require(
                    userAddress == address(0) || userAddress == msg.sender,
                    "unauthorized user"
                );
            }
        } else {
            revert("unrecognized AugustusRFQ method selector");
        }
    }

    /*solhint-disable no-inline-assembly*/
    /**
     * @dev Source take from GNOSIS MultiSigWallet
     * @dev https://github.com/gnosis/MultiSigWallet/blob/master/contracts/MultiSigWallet.sol
     */
    function externalCall(
        address destination,
        uint256 value,
        uint256 dataOffset,
        uint256 dataLength,
        bytes memory data
    ) private returns (bool) {
        bool result = false;

        assembly {
            let x := mload(0x40) // "Allocate" memory for output
            // (0x40 is where "free memory" pointer is stored by convention)

            let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
                gas(),
                destination,
                value,
                add(d, dataOffset),
                dataLength, // Size of the input (in bytes) - this is what fixes the padding problem
                x,
                0 // Output is ignored, therefore the output size is zero
            )
            // let ptr := mload(0x40)
            // let size := returndatasize()
            // returndatacopy(ptr, 0, size)
            // revert(ptr, size)
        }
        return result;
    }

    ///NEW FUNCTIONS

    /// @dev Function using for send tokens and data through DeBridge
    /// @param tokensBought Amount of tokens that contract receive after swap
    function _send(Utils.SimpleDataDeBridge memory data, uint256 tokensBought)
        public
        payable
    {
        require(msg.value >= 0.01 ether, "msg.value too low");
        address _bridgeAddress = 0x68D936Cb4723BdD38C488FD50514803f96789d2D;
        uint256 lastInThePath = data.pathBeforeSend.length - 1;
        if (data.pathBeforeSend[lastInThePath] != Utils.ethAddress()){
            IERC20(data.pathBeforeSend[lastInThePath]).approve(_bridgeAddress, tokensBought);
        }
        require(
            tokensBought.div(2) >= data.executionFee,
            "insufficient token amount line 642"
        );
        address contractAddressTo = chainIdToContractAddress[data.chainId];
        require(
            contractAddressTo != address(0),
            "Incremetor: ChainId is not supported"
        );
        IDeBridgeGate.SubmissionAutoParamsTo memory autoParams;
        autoParams.flags = autoParams.flags.setFlag(
            Flags.REVERT_IF_EXTERNAL_FAIL,
            true
        );
        autoParams.flags = autoParams.flags.setFlag(
            Flags.PROXY_WITH_SENDER,
            true
        );
        autoParams.executionFee = data.executionFee;
        autoParams.fallbackAddress = abi.encodePacked(data.beneficiary);
        autoParams.data = abi.encodeWithSignature(
            "simpleSwapAfterDeBridge((address[],address[],uint256,uint256,uint256,address[],bytes,uint256[],uint256[],uint256,address,address,uint256,bytes,uint256,bytes16,uint256,uint256))",
            data
        );
        emit LastBalance(data.pathBeforeSend[lastInThePath], IERC20(data.pathBeforeSend[lastInThePath]).balanceOf(address(this)));
        uint256 deBridgeFee = getChainId() == 80001
            ? 0.1 ether
            : 0.01 ether;
        if (data.pathBeforeSend[lastInThePath] != Utils.ethAddress()){
            Utils.transferTokens(Utils.ethAddress(), payable(contractAddressTo), deBridgeFee);
        }
        Utils.transferTokens(data.pathBeforeSend[lastInThePath], data.beneficiary, tokensBought);

        // if (data.pathBeforeSend[1] == address(0)) {
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
        //         data.pathBeforeSend[1],
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

    function _approve(
        address _token,
        address _to,
        uint256 _amount
    ) public {
        IERC20(_token).approve(_to, _amount);
    }

    function initialize(address _bridgeAddr) public {
        __BridgeAppBase_init(IDeBridgeGate(_bridgeAddr));
    }

    function encodeFunctionCall(
        uint256 amountIn,
        address[] memory path,
        bytes memory data
    ) public pure returns (bytes memory, uint256) {
        bytes memory encodeCall = abi.encodeWithSignature(
            "swapOnUniswap(uint256,uint256,address[])",
            amountIn,
            0,
            path
        );
        data = bytes.concat(data, encodeCall);
        return (data, data.length);
    }

    function getDataToSwap(Utils.SimpleDataDeBridge memory data) 
        private 
        view 
        returns(SwapData memory)
        {
        SwapData memory returnData;
        returnData.currentChain = data.chainId == getChainId();
        uint256 deBridgeFee = getChainId() == 80001 ? 0.1 ether : 0.01 ether;
        (returnData.fromAmount, returnData.beneficiary, returnData.path) = returnData.currentChain ?
        (IERC20(data.pathAfterSend[0]).allowance(msg.sender, address(this)), data.beneficiary, data.pathAfterSend) :
        (data.pathBeforeSend[0] == Utils.ethAddress() ? (data.fromAmount - deBridgeFee) : data.fromAmount, address(this), data.pathBeforeSend);
        returnData.exchangeData = data.exchangeData;
        returnData.startIndexes = data.startIndexes;
        returnData.values = data.values;
        
        if(returnData.currentChain && (data.pathAfterSend.length >= 2)){
            (returnData.exchangeData, returnData.startIndexes[data.callees.length]) = encodeFunctionCall(
                returnData.fromAmount,
                data.pathAfterSend,
                data.exchangeData
            );

            if (data.pathAfterSend[0] == address(0)) {
                returnData.values[data.callees.length - 1] = returnData.fromAmount;
            }
        }
        return(returnData);
    }

    /*solhint-enable no-inline-assembly*/
}