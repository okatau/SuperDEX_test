## Пример данных для метода swapOnUniswapV2ForkDeBridge
~~~
[["Первый токен в пути обменов на стороне отправителя",
"Первый токен в пути обменов на стороне получателя"],
"amountIn",
"amountOutMin",
"weth(Если не покупаем ефир, то указывать нулевой адрес)",
"poolsBeforeSend(См. ниже)",
"poolsAfterSend(См. нижу)",
"executionFee",
"chainIdTo",
"beneficiary(получатель)"
]
~~~
### Получение данных для poolsBeforeSend и PoolsAfterSend

Необходимо перейти по [ссылке](https://testnet.bscscan.com/address/0xf78bFB108200B6514EEB907b5E6c6c61d63DBe73#readContract) и заполнить поля:
+ feePercent - 9970
+ pair - адрес пары, в которой будет происходить обмен
+ direction -  true если токен который мы отправляем это token0 в паре, иначе false