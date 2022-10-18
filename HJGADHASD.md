 
 ~~~
// Data required for cross chain swap in SimpleSwap
struct SimpleDataDeBridge {
    // Path of the tokens addresses to swap before DeBridge
    address[] pathBeforeSend;
    // Path of the tokens addresses to swap after DeBridge
    address[] pathAfterSend;
    // Amount that user give to swap
    uint256 fromAmount;
    // Minimal amount that user will reicive after swap
    uint256 toAmount;
    // Expected amount that user will receive after swap
    uint256 expectedAmount;
    // Addresses of exchanges that will perform swap
    address[] callees;
    // Encoded data to call exchanges
    bytes exchangeData;
    // Start and end indexes of the exchangeData 
    uint256[] startIndexes;
    // Amount of the ether that user send
    uint256[] values;
    // The number of callees used for swap before DeBridge
    uint256 calleesBeforeSend;
    // Address of the wallet that receive tokens
    address payable beneficiary;
    address payable partner;
    uint256 feePercent;
    bytes permit;
    uint256 deadline;
    bytes16 uuid;
    // Fee paid to keepers to execute swap in second chain
    uint256 executionFee;
    // Chain id to which tokens are sent
    uint256 chainId;
}
~~~
~~~
[
["pathbeforeSend"],
["pathAfterSend"],
"fromAmount",
"toAmount",
"expectedAmount",
["адрес контракта, в котором будет проходить обмен в сети отправителя", "адрес контракта, в котором будет проходить обмен в сети получателя"],
"закодированый вызов функции(в примере вызова ниже используется вызов в swapOnUniswap)",
["0", "196", "0"](индексы, которые указывают на границы даных(предыдущий параметр), последний 0, т.к. контракт сам собирает вызов на стороне получателя),
["0", "0"](количество эфира, котторый мы отправляем для обмена),
"1"(сколько обмеников идет до deBridg'a),
"0x687FA78988BCfDBB8C3FECB9cE66672F7651EDe1"(адрес получателя),
"0x0000000000000000000000000000000000000000"(адрес partner'a),
"452312848583266388373324160190187140051835877600158453279131187530910679040",
"0x00",
"1686061732",
"0x48726217fca940b892b3b899843c8a57",
"50000000000000000"(executionFee),
"80001"(ChainIdTo)
]

~~~
[
["0x8475318Ee39567128ab81D6b857e7621b9dC3442","0x3f951798464b47e037fAF6eBAb337CB07F5e16c9"],
["0xC75E8e8E14F370bF25ffD81148Fd16305b6aFba6", "0x7bcE539216d7E2cB1270DAA564537E0C1bA3F356"],
"5000000000000000000",
"3000000000000000000",
"3500000000000000000",
["0x38582841f43D41e71C9b3A46B61aD79D765432AF", "0xe0073335C740eD1589aA20B1360C673F9196985b"],
"0x54840d1a0000000000000000000000000000000000000000000000004563918244f400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000020000000000000000000000008475318ee39567128ab81d6b857e7621b9dc34420000000000000000000000003f951798464b47e037faf6ebab337cb07f5e16c9",
["0", "196", "0"],
["0", "0"],
"1",
"0x687FA78988BCfDBB8C3FECB9cE66672F7651EDe1",
"0x0000000000000000000000000000000000000000",
"452312848583266388373324160190187140051835877600158453279131187530910679040",
"0x00",
"1686061732",
"0x48726217fca940b892b3b899843c8a57",
"50000000000000000",
"80001"
]