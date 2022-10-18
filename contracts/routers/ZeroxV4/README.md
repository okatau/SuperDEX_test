# Инструкция по развертыванию контрактов Zerox
1. Задеплоить контракт [Staking'a](./Staking/Staking.sol)
2. Задеплоить контракт [FeeCollectorController'a](./ZeroexExchangeProxy/external/FeeCollectorController.sol) с параметрами:
   + weth - адрес обернутой нативной валюты
   + staking - адрес стейкинга из пункта 1
3. Задеплоить контракт [InitialMigration](./ZeroexExchangeProxy/migrations/InitialMigration.sol) с параметрами:
   + initializeCaller_ - адрес вашего кошелька
4. Задеплоить контракт [Zeroex](./ZeroexExchangeProxy/ZeroEx.sol) с параметрами:
 + bootstrapper - адрес InitialMigration из пункта 3
5. Задеплоить контракт [SimpleFunctionRegistryFeature](./ZeroexExchangeProxy/features/SimpleFunctionRegistryFeature.sol)
6. Задеплоить контракт [OwnableFeature](./ZeroexExchangeProxy/features/OwnableFeature)
7. Задеплоить контракт [NativeOrdersFeatureWOS](./ZeroexExchangeProxy/features/NativeOrdersFeatureWOS.sol) с параметрами:
   + zeroExAddress - адрес Zeroex из пункта 4
   + weth - адрес обернутой нативной валюты
   + staking - адрес стейкинга из пункта 1
   + feeCollectorController - адрес FeeCollectorController из пункта 2
   + protocolFeeMultiplier - 0
8. В контракте InitialMigration вызвать метод initializeZeroEx с параметрами:
+ owner - ваш адрес
+ zeroEx - адрес Zeroex из пункта 4
+ features - {SimplefunctionRegistryFeature из пункта 5, OwnableFeature из пункта 6}
9. Вызвать у контракта Zeroex метод migrate через fallback с параметрами:
+ адрес NativeOrdersFeatureWos
+ 0x8fd3ab80
+ ваш адрес
+ ~~~ js 
    web3.eth.abi.encodeFunctionCall({
    name: 'migrate',
    type: 'function',
    inputs: [{
        type: 'address',
        name: 'target'
    },{
        type: 'bytes',
        name: 'data'
    },{
    	type: 'address',
    	name: 'newOwner'
    }] 
    }, ['nof', '0x8fd3ab80', 'ur_address']);
После этих действий вы сможете вызывать все метод контракта NativeOrdersFeatureWOS чере 0x: ExchangeProxy

# Пример данных для вызова метода swapOnZeroXv4DeBridge
~~~
[
    ["Массив адресов для обмена на стороне отправителя"],
    ["Массив адресов для обмена на стороне получателя"],
    "fromAmount",
    "amountOutMin",
    "Адрес 0x Proxy на стороне отправителя",
    "Адрес 0x Proxy на стороне получателя",
    "payloadBeforeSend(См. ниже)",
    "payloadAfterSend(См. ниже)",
    "beneficiary",
    "executionFee",
    "chainIdTo"
]
~~~

## Как получить payloadBeforeSend и payloadAfterSend

Необходимой перейти по [ссылке](https://testnet.bscscan.com/address/0x0C580D4ac2bA0484cAFE92921A4eea464E6501e8#readContract) и заполнить поле encodePayload
~~~
[["makerToken(токен, который мы получим после обмена)", 
"takerToken(токен, кторый мы отдаем для обмена)",
"количество токенов, которые мы получим",
"количество токенов, которые мы отдаем",
"адрес, который отдает токены(AugustusSwappper)",
"адрес, который получает токены",
"Адрес получателя токенов",
"0x0000000000000000000000000000000000000000000000000000000000000000",
"1755520021",
"1659700605000"],
["3",
"28",
"0xf29ce1b13dc01ca4f4391d4f8774d002b294924142841655f21c70cc533544e6",
"0x4d5c48a4d0ce035d6b78354c3942c1f824c7068be7ae54988ddc02fbb55acb62"]]
~~~
Пример данных для encodePayload
~~~
[["0xDb566C053a357F673F362b0dC336688049345Fcb",
  "0x35a9Cd07682cA2DB38F1a9EA858e6719C11E5673",
  "4500000000000000000",
  "5000000000000000000",
  "0xE411Fed5cEdF4eB46FeB073dc4301943CEf042Af",
  "0x3EFAfF6672A96F4c9A3D438f9cF1Ff506897A452",
  "0x687FA78988BCfDBB8C3FECB9cE66672F7651EDe1",
  "0x0000000000000000000000000000000000000000000000000000000000000000",
  "1755520021",
  "1659700605000"],[
  "3",
  "28",
  "0xf29ce1b13dc01ca4f4391d4f8774d002b294924142841655f21c70cc533544e6",
  "0x4d5c48a4d0ce035d6b78354c3942c1f824c7068be7ae54988ddc02fbb55acb62"]]
~~~

# Пример данных для swapOnZeroXv4DeBridge
~~~
[
    ["0x35a9Cd07682cA2DB38F1a9EA858e6719C11E5673", "0xDb566C053a357F673F362b0dC336688049345Fcb"],
    ["0xd6462Ba26C30c45Ca86470f3eED250D9Aeb7489F", "0xd6B54Fc45191C9aF8d6F3e888fc4B66eCb72ff7E"],
    "5000000000000000000",
    "3500000000000000000",
    "0xFbd7D1C3c06842955E90CF3D2F23117eF36e2B35",
    "0xB173770f03b0438aba3cb045b11e8505a11c6C88",
    "0x000000000000000000000000db566c053a357f673f362b0dc336688049345fcb00000000000000000000000035a9cd07682ca2db38f1a9ea858e6719c11e56730000000000000000000000000000000000000000000000003e733628714200000000000000000000000000000000000000000000000000004563918244f40000000000000000000000000000e411fed5cedf4eb46feb073dc4301943cef042af0000000000000000000000003efaff6672a96f4c9a3d438f9cf1ff506897a452000000000000000000000000687fa78988bcfdbb8c3fecb9ce66672f7651ede100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000068a31c15000000000000000000000000000000000000000000000000000001826ddd70480000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000001cf29ce1b13dc01ca4f4391d4f8774d002b294924142841655f21c70cc533544e64d5c48a4d0ce035d6b78354c3942c1f824c7068be7ae54988ddc02fbb55acb62",
    "0x000000000000000000000000d6b54fc45191c9af8d6f3e888fc4b66ecb72ff7e000000000000000000000000d6462ba26c30c45ca86470f3eed250d9aeb7489f00000000000000000000000000000000000000000000000030927f74c9de00000000000000000000000000000000000000000000000000003782dace9d900000000000000000000000000000e411fed5cedf4eb46feb073dc4301943cef042af0000000000000000000000009488eae71ab2a3705588108b53b767b1342e9310000000000000000000000000687fa78988bcfdbb8c3fecb9ce66672f7651ede100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000068a31c15000000000000000000000000000000000000000000000000000001826ddd70480000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000001cf29ce1b13dc01ca4f4391d4f8774d002b294924142841655f21c70cc533544e64d5c48a4d0ce035d6b78354c3942c1f824c7068be7ae54988ddc02fbb55acb62",
    "0x687FA78988BCfDBB8C3FECB9cE66672F7651EDe1",
    "50000000000000000",
    "42"
]

~~~