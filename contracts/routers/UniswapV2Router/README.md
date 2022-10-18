# Инструкция по вызову send через UniswapV2Router
## Разварачивание контраков в сети отправителя(в данном случае в сети BSC(FROM))
  ### 1. Задеплоить ERC20 токен с параметрами TOKEN, TKN и 100000000000000000000000000000000000000. [Контракт токена](./contracts/Token.sol)
  ### 2. Задеплоить [UniswapV2Factory](./Uniswap-v2-core/UniswapV2Factory.sol)
  ### 3. Создать пару из нашего токена из пункта 1 и [USDT](https://testnet.bscscan.com/token/0x7ef95a0fee0dd31b22626fa2e10ee6a223f8a684)
  ### 4. Вызвать approve у TOKEN и USDT на адрес получившейся пары и размером 100000000000000000000000000000000000000
  ### 5. Вызвать transfer У TOKEN и USDT указав адрес пары и число 5000000000000000000000000000000000
  ### 6. Вызвать mint у контракта пары указав ваш адрес
  ### 7. Задеплоить [UniswapV2Router](./contracts/UniswapV2Router.sol) с параметрами: 
  + _factry - адрес фабрики из пункта 2
  + _weth - 0x0000000000000000000000000000000000000000, ETH 
  + _eth - 0x0000000000000000000000000000000000000000
  + _initcode - для того, чтобы получить _initcode, нам необходимо:
    - Найти наш контракт в сети 
    - Верифицировать контракт
    - Скопировать Contract Creation Code во вкладке contract
    - Перейти на [сайт](https://emn178.github.io/online-tools/keccak_256.html)
    - Вставить Contract Creation Code и указать Input type: Hex
    - Скопировать полученный результат и вставить его в поле _initcode
  + _fee - 1
  + _feeFactor - 1
  ### 8. Задеплоить контракт [AugustusSwapper](./contracts/AugustusSwapper.sol) с адресом вашего кошелька
  ### 9. Вызвать у AugustusSwapper метод *grantRole* с параметрами ROUTER_ROLE, который можно получить вызвав метод ROUTER_ROLE, и адресом роутера
  ### 10. Вызвать у AugustusSwapper метод *setImplementation* с параметрами 0xc4d66de8 и адресом Router. После этого сделать вызов fallback с параметром 0xc4d66de800000000000000000000000068d936cb4723bdd38c488fd50514803f96789d2d
  ### 11. Вызвать у AugustusSwapper метод *setImplementation* с параметрами 0xf89f5d94 и адресом Router
  ### 12. ВЫзвать метод *getTokenTransferProxy* у AugustusSwapper и вызвать метод approve у токена, который вы меняете
   
___
## Разворачивание контрактов в сети KOVAN(TO)
### 1. Задеплоить ERC20 токен с параметрами TOKEN, TKN и 100000000000000000000000000000000000000. [Контракт токена](./contracts/Token.sol)
  ### 2. Задеплоить [UniswapV2Factory](./Uniswap-v2-core/UniswapV2Factory.sol)
  ### 3. Создать пару из нашего токена из пункта 1 и deUsdt
  ### 4. Вызвать approve у TOKEN и deUsdt на адрес получившейся пары и размером 100000000000000000000000000000000000000
  ### 5. Вызвать transfer У TOKEN и deUsdt указав адрес пары и число 5000000000000000000000000000000000
  ### 6. Вызвать mint у контракта пары указав ваш адрес
  ### 7. Задеплоить [UniswapV2Router](./contracts/UniswapV2Router.sol) с параметрами: 
  + _factry - адрес фабрики из пункта 2
  + _weth - 0x0000000000000000000000000000000000000000
  + _eth - 0x0000000000000000000000000000000000000000
  + _initcode - для того, чтобы получить _initcode, нам необходимо:
    - Найти наш контракт в сети 
    - Верифицировать контракт
    - Скопировать Contract Creation Code во вкладке contract
    - Перейти на [сайт](https://emn178.github.io/online-tools/keccak_256.html)
    - Вставить Contract Creation Code и указать Input type: Hex
    - Скопировать полученный результат и вставить его в поле _initcode
  + _fee - 1
  + _feeFactor - 1
   ### 8. Задеплоить контракт [AugustusSwapper](./contracts/AugustusSwapper.sol) с адресом вашего кошелька
  ### 9. Вызвать у AugustusSwapper метод *grantRole* с параметрами ROUTER_ROLE, который можно получить вызвав метод ROUTER_ROLE, и адресом роутера
  ### 10. Вызвать у AugustusSwapper метод *setImplementation* с параметрами 0xc4d66de8 и адресом Router. После этого сделать вызов fallback с параметром 0xc4d66de800000000000000000000000068d936cb4723bdd38c488fd50514803f96789d2d
  ### 11. Вызвать у AugustusSwapper метод *setImplementation* с параметрами 0xd41030aa и адресом Router
___
## Инициализация сети отправителя(FROM) 
Вызвать у AugustusSwapper метод *setImplementation* с параметрами 0x6586f26b и адресом роутера. После этого сделать вызов fallback с параметром 
  ~~~ javascript
  web3.eth.abi.encodeFunctionCall({
    name: 'setContractAddressOnChainId',
    type: 'function',
    inputs: [{
        type: 'address',
        name: '_address'
    },{
        type: 'uint256',
        name: '_chainIdTo'
    }]
    }, ['TO_AdminUpgradeabilityProxy', 'TO_chainIdTo']);
~~~
+ TO_AdminUpgradeabilityProxy - адрес Proxy в сети получателя
+ TO_chainIdTo - Цепочка получателя
___
## Инициализация сети получателя(TO)
Вызвать у AugustusSwapper метод *setImplementation* с параметрами 0x2c13e57c и адресом роутера. После этого сделать вызов fallback с параметром 
  ~~~ javascript
  web3.eth.abi.encodeFunctionCall({
    name: 'addControllingAddress',
    type: 'function',
    inputs: [{
        type: 'bytes',
        name: 'from'
    },{
        type: 'uint256',
        name: 'chainId'
    }]
}, ['FROM', 'chainIdFrom']);
~~~
+ FROM - адрес Proxy в сети отправителя
+ chainIdFrom - Цепочка отправителя
___
## Вызов swapOnUniswap_deBridge
Задеплоить контракт [IParaswap](./contracts/IParaswap.sol) по адресу AugustusSwapper и вызвать метод swapDeBridge
~~~
function swapDeBridge(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata pathBeforeSend,
        address[] calldata pathAfterSend,
        address _receiver,
        uint256 _executionFee
        uint256 _chainIdTo,
    )  
~~~
+ amountIn - Это сумма которую вы хотите отправить
+ amountOutMin - 0
+ pathBeforeSend - Адрес токенов которые мы деплоили в BSC [TOKEN, USDT]
+ pathAfterSend - Адрес токенов которые мы деплоили в Kovan[TOKEN, DeUSDt]
+ _chainIdTo - Chain id сети, в которую мы отправляем наши токены. В данном случае 42
+ _receiver - адрес получателя
+ _executionFee - сумма, которая отправится киперам за выполнение транзакции на стороне получателя. Должно быть 50000000000000000
+ Также нам надо отправить 10000000000000000 BNB, чтобы msg.value = 0.01 ether, иначе транзакция не пройдет.
___
+ Инструкция по пользованию методом swapDeBridge [ссылка](https://docs.google.com/document/d/1czKNoZGNrHOBgCQh_u3pdKN-DLiMNBmzBFeQjSy-Aew/edit?usp=sharing)
