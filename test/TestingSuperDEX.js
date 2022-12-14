const { expect } = require("chai");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { ethers } = require('hardhat');

const provider = ethers.provider;

describe("Deploying and testing SuperDEX", function(){
    async function deploySuperDEX() {
        const accounts = await ethers.getSigners();
        const owner = accounts[0];
        const zeroAddress = ethers.constants.AddressZero;

        //deploying first test token
        let token1 = await ethers.getContractFactory("Token");
        let TestToken1 = await token1.deploy("TestToken1", "TT", ethers.utils.parseEther("100000000000000000000000.0"));
        await TestToken1.deployed();
        // deploying second test token
        const TestToken2 = await token1.deploy("TestToken2", "TT", ethers.utils.parseEther("100000000000000000000000.0"));
        await TestToken2.deployed();
        //deploying WETH
        let weth = await ethers.getContractFactory("WETH9");
        const WETH = await weth.deploy();
        for(let i = 1; i < 15; i++){
            await accounts[i].sendTransaction({to: owner.address, value: ethers.utils.parseEther("9999")});
        }
        await WETH.deposit({value: ethers.utils.parseEther("50000")});
        //deploying uniswap factory and creating token 1 and token 2 pair
        const uniswapFactory = await ethers.getContractFactory("UniswapV2Factory");
        const UniswapFactory = await uniswapFactory.deploy(owner.address);
        await UniswapFactory.deployed();
        let tx = await UniswapFactory.createPair(TestToken1.address, TestToken2.address);
        let result = await tx.wait();
        let pairAddress = result.events[0].args.pair;
        const UniswapV2Pair = await ethers.getContractAt("UniswapV2Pair", pairAddress, provider.getSigner());
        //create pair TT2 and weth
        tx = await UniswapFactory.createPair(TestToken2.address, WETH.address);
        result = await tx.wait();
        pairAddress = result.events[0].args.pair;
        const UniswapV2PairETH = await ethers.getContractAt("UniswapV2Pair", pairAddress, provider.getSigner());
        //add balance to UniswapV2Pair
        await TestToken1.transfer(UniswapV2Pair.address, ethers.utils.parseEther("50000000000000.0"));
        await TestToken2.transfer(UniswapV2Pair.address, ethers.utils.parseEther("50000000000000.0"));
        await UniswapV2Pair.mint(owner.address);
        //add blance to UniswapV2PairETH
        await TestToken2.transfer(UniswapV2PairETH.address, ethers.utils.parseEther("40000"));
        await WETH.transfer(UniswapV2PairETH.address, ethers.utils.parseEther("40000"));
        await UniswapV2PairETH.mint(owner.address);
        //deploying AugustusSwapper
        let augustus = await ethers.getContractFactory("AugustusSwapper");
        const AugustusSwapper = await augustus.deploy(owner.address);
        const TokenTransferProxy = await AugustusSwapper.getTokenTransferProxy();
        //deploying MultiPath and Adapter01
        let feeClaimer = await ethers.getContractFactory("FeeClaimer");
        const FeeClaimer = await feeClaimer.deploy(AugustusSwapper.address);
        let multiPath = await ethers.getContractFactory("MultiPath");
        const MultiPath = await multiPath.deploy(ethers.BigNumber.from(8500), ethers.BigNumber.from(500), FeeClaimer.address);
        let adapter = await ethers.getContractFactory("Adapter01");        
        const Adapter01 = await adapter.deploy(zeroAddress, 0, zeroAddress, zeroAddress, WETH.address);
        //deploying NewUniswapV2ExchangeRouter
        let newUniswapV2Lib = await ethers.getContractFactory("contracts/libraries/NewUniswapV2Lib.sol:NewUniswapV2Lib");
        const NewUniswapV2Lib = await newUniswapV2Lib.deploy();
        let nuv2er = await ethers.getContractFactory("NewUniswapV2Router", {
            libraries: {
                NewUniswapV2Lib: NewUniswapV2Lib.address,
            }
        });
        // let nuv2er = await ethers.getContractFactory("NewUniswapV2Router");
        const NewUniswapV2Router = await nuv2er.deploy();
        //deploying SimpleSwap
        let augustusRFQ = await ethers.getContractFactory("AugustusRFQ");
        const AugustusRFQ = await augustusRFQ.deploy();
        let simpleSwap = await ethers.getContractFactory("SimpleSwap");
        const SimpleSwap = await simpleSwap.deploy(ethers.BigNumber.from(8500), ethers.BigNumber.from(500), FeeClaimer.address, AugustusRFQ.address);
        //deploying UniswapV2Router
        let temp = await ethers.getContractFactory("UniswapV2Pair");
        let initCode = ethers.utils.keccak256(temp.bytecode);
        let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
        let uniswapV2Router = await ethers.getContractFactory("contracts/routers/UniswapV2Router/UniswapV2Router.sol:UniswapV2Router");
        const UniswapV2Router = await uniswapV2Router.deploy(
            UniswapFactory.address, 
            WETH.address, 
            ethAddress, 
            initCode, 
            ethers.BigNumber.from(997),
            ethers.BigNumber.from(1000));
        //deploying ZeroxV4Router
        let staking = await ethers.getContractFactory("Staking");
        const Staking = await staking.deploy();
        let fcc = await ethers.getContractFactory("FeeCollectorController");
        const FeeCollectorController = await fcc.deploy(WETH.address, Staking.address);
        let initialMigration = await ethers.getContractFactory("InitialMigration");
        const InitialMigration = await initialMigration.deploy(owner.address);
        let zeroEx = await ethers.getContractFactory("ZeroEx");
        const ZeroEx = await zeroEx.deploy(InitialMigration.address);
        let SFRF = await ethers.getContractFactory("SimpleFunctionRegistryFeature");
        const SimpleFunctionRegistryFeature = await SFRF.deploy();
        let ownableFeature = await ethers.getContractFactory("OwnableFeature");
        const OwnableFeature = await ownableFeature.deploy();
        let noswos = await ethers.getContractFactory(
            "contracts/routers/ZeroxV4/ZeroexExchangeProxy/features/NativeOrdersFeatureWOS.sol:NativeOrdersFeature");
        const NativeOrdersFeatureWOS = await noswos.deploy(
            ZeroEx.address,
            WETH.address,
            Staking.address,
            FeeCollectorController.address,
            ethers.BigNumber.from(0)
        );
        await InitialMigration.initializeZeroEx(
            owner.address, 
            ZeroEx.address, 
            [
                SimpleFunctionRegistryFeature.address, 
                OwnableFeature.address
            ]
        );
        let migrateCall = [
            "function migrate(address target, bytes data, address newOwner)"
        ];
        let iface = new ethers.utils.Interface(migrateCall);
        let calldata = iface.encodeFunctionData("migrate", [ NativeOrdersFeatureWOS.address, '0x8fd3ab80', owner.address ])
        tx = {
            to: ZeroEx.address,
            data: calldata 
        }
        await owner.sendTransaction(tx);
        let zeroXV4Router = await ethers.getContractFactory("ZeroxV4Router");
        const ZeroxV4Router = await zeroXV4Router.deploy(WETH.address);
        
        //setImplementation
        let megaSwap = "0x0afb3a65";
        let multiSwap = "0x6c149d98";
        let swapOnUniswapDeBridge = "0x808c01c7";
        let swapOnUniswap = "0x54840d1a";
        let swapOnUniswapV2ForkDeBridge = "0xa2a14470";
        let simpleSwapDeBridge = "0x99461a51";
        let simpleswapAfterDeBridge = "0x4bdac611";
        let swapSimpleSwap = "0x54e3f31b";
        let swapOnZeroXv4DeBridge = "0x77dd05b9";
        let routerRole = await AugustusSwapper.ROUTER_ROLE();
        let encodeCall = [
            "function setContractAddressOnChainId(address _address, uint256 _chainIdTo)"
        ];
        iface = new ethers.utils.Interface(encodeCall);
        calldata = iface.encodeFunctionData("setContractAddressOnChainId", [accounts[15].address, 1]);
        let setAddressSig = calldata.substring(0, 10);
        await AugustusSwapper.grantRole(routerRole, MultiPath.address);
        await AugustusSwapper.setImplementation(setAddressSig, MultiPath.address);
        tx = {
            to: AugustusSwapper.address,
            data: calldata
        };
        await owner.sendTransaction(tx);
        await AugustusSwapper.setImplementation(megaSwap, MultiPath.address);
        await AugustusSwapper.setImplementation(multiSwap, MultiPath.address);

        await AugustusSwapper.grantRole(routerRole, NewUniswapV2Router.address);
        await AugustusSwapper.setImplementation(setAddressSig, NewUniswapV2Router.address);
        await owner.sendTransaction(tx);
        await AugustusSwapper.setImplementation(swapOnUniswapV2ForkDeBridge, NewUniswapV2Router.address);

        await AugustusSwapper.grantRole(routerRole, SimpleSwap.address);
        await AugustusSwapper.setImplementation(setAddressSig, SimpleSwap.address);
        await owner.sendTransaction(tx);
        await AugustusSwapper.setImplementation(simpleSwapDeBridge, SimpleSwap.address);
        await AugustusSwapper.setImplementation(simpleswapAfterDeBridge, SimpleSwap.address);
        await AugustusSwapper.setImplementation(swapSimpleSwap, SimpleSwap.address);

        await AugustusSwapper.grantRole(routerRole, UniswapV2Router.address);
        await AugustusSwapper.setImplementation(setAddressSig, UniswapV2Router.address);
        await owner.sendTransaction(tx);
        await AugustusSwapper.setImplementation(swapOnUniswap, UniswapV2Router.address);
        await AugustusSwapper.setImplementation(swapOnUniswapDeBridge, UniswapV2Router.address);

        await AugustusSwapper.grantRole(routerRole, ZeroxV4Router.address);
        await AugustusSwapper.setImplementation(setAddressSig, ZeroxV4Router.address);
        await owner.sendTransaction(tx);
        await AugustusSwapper.setImplementation(swapOnZeroXv4DeBridge, ZeroxV4Router.address);
        // console.log(MultiPath.interface);
        return { 
            TestToken1, 
            TestToken2,
            WETH, 
            AugustusSwapper, 
            TokenTransferProxy, 
            Adapter01, 
            UniswapV2Pair, 
            UniswapV2PairETH, 
            SimpleSwap,
            ZeroEx,
            accounts, 
            owner };
    }

    describe("Testing MultiPath", function(){
        it("Testing multiSwapDeBridge. Swap token to token", async function(){            
            const { TestToken1, 
                TestToken2,  
                AugustusSwapper, 
                TokenTransferProxy, 
                Adapter01, 
                UniswapV2Pair,
                accounts, 
                owner } = await loadFixture(deploySuperDEX);
            // Get data to swap before and after bridge
            receiver = accounts[16];
            let payload;
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let direction = await UniswapV2Pair.token0() == TestToken1.address;
            payload = await MultiPathHelper.getPools(ethers.BigNumber.from(9970), UniswapV2Pair.address, direction);
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let encoder = new ethers.utils.AbiCoder();
            let calldata = encoder.encode([ "tuple(address, uint256[])" ], [[ethers.constants.AddressZero, [payload]]]);
            let data = [[
                [TestToken1.address, TestToken1.address],
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther("3"),
                ethers.utils.parseEther("3.5"),
                receiver.address,
                [[
                    TestToken2.address,
                    0,
                    [[
                        Adapter01.address,
                        10000,
                        0,
                        [[
                            4,
                            ethers.constants.AddressZero,
                            10000,
                            calldata,
                            0
                        ]]
                    ]]
                ]],
                [[
                    TestToken2.address,
                    0,
                    [[
                        Adapter01.address,
                        10000,
                        0,
                        [[
                            4,
                            ethers.constants.AddressZero,
                            10000,
                            calldata,
                            0
                        ]]
                    ]]
                ]],
                ethers.constants.AddressZero,
                ethers.BigNumber.from("452312848583266388373324160190187140051835877600158453279131187530910679040"),
                "0x00",
                1686061732,
                "0x48726217fca940b892b3b899843c8a57",
                ethers.utils.parseEther("0.05"),
                1
            ]];
            let ABI = [
                "function multiSwapDeBridge((address[],uint256,uint256,uint256,address,(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[],(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[],address,uint256,bytes,uint256,bytes16,uint256,uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("multiSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            }
            // Swap before bridge
            await TestToken1.approve(TokenTransferProxy, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
            // Get data
            balanceBefore = await TestToken2.balanceOf(receiver.address);            
            data[0][13] = 31337;
            functionCall = iface.encodeFunctionData("multiSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
            }
            //Swap after bridge
            await TestToken1.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
        })

        it("Testint multiSwapDeBridge. Swap token to ETH", async function(){
            const {
                TestToken2, 
                WETH, 
                AugustusSwapper, 
                TokenTransferProxy, 
                Adapter01,
                UniswapV2PairETH,
                accounts, 
                owner 
            } = await loadFixture(deploySuperDEX);
            let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
            let receiver = accounts[16];
            let direction = await UniswapV2PairETH.token0() == TestToken2.address;
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let encodedPair = await MultiPathHelper.getPools(ethers.BigNumber.from(9970), UniswapV2PairETH.address, direction);
            let balanceBefore = await receiver.getBalance();
            let encoder = new ethers.utils.AbiCoder();
            payload = encoder.encode([ "tuple(address, uint256[])" ], [[WETH.address, [encodedPair]]]);
            let data = [[
                [TestToken2.address, TestToken2.address],
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther("1"),
                ethers.utils.parseEther("1.5"),
                receiver.address,
                [[
                    ethAddress,
                    0,
                    [[
                        Adapter01.address,
                        10000,
                        0,
                        [[
                            4,
                            ethers.constants.AddressZero,
                            10000,
                            payload,
                            0
                        ]]
                    ]]
                ]],
                [[
                    ethAddress,
                    0,
                    [[
                        Adapter01.address,
                        10000,
                        0,
                        [[
                            4,
                            ethers.constants.AddressZero,
                            10000,
                            payload,
                            0
                        ]]
                    ]]
            ]],
            ethers.constants.AddressZero,
            ethers.BigNumber.from("452312848583266388373324160190187140051835877600158453279131187530910679040"),
            "0x00",
            1686061732,
            "0x48726217fca940b892b3b899843c8a57",
            ethers.utils.parseEther("0.05"),
            1
            ]];
            let ABI = [
                "function multiSwapDeBridge((address[],uint256,uint256,uint256,address,(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[],(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[],address,uint256,bytes,uint256,bytes16,uint256,uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("multiSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            }
            // Swap before Bridge
            await TestToken2.approve(TokenTransferProxy, ethers.utils.parseEther("100"));
            await owner.sendTransaction(tx);
            expect(await receiver.getBalance()).greaterThan(balanceBefore);
                        
            balanceBefore = await receiver.getBalance();
            data[0][13] = 31337;
            functionCall = iface.encodeFunctionData("multiSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
            }
            // Swap after bridge
            await TestToken2.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await receiver.getBalance()).greaterThan(balanceBefore);
        })

        it("Testing multiSwapDeBridge. Swap ETH to token", async function(){
            const {
                TestToken2, 
                WETH, 
                AugustusSwapper, 
                Adapter01,
                UniswapV2PairETH,
                accounts, 
                owner } = await loadFixture(deploySuperDEX);
            let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
            let receiver = accounts[16];
            let encodedPair;
            let direction = await UniswapV2PairETH.token0() == WETH.address;
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            encodedPair = await MultiPathHelper.getPools(ethers.BigNumber.from(9970), UniswapV2PairETH.address, direction);
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let encoder = new ethers.utils.AbiCoder();
            payload = encoder.encode([ "tuple(address, uint256[])" ], [[WETH.address, [encodedPair]]]);
            let data = [[
                [ethAddress, ethAddress],
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther("1"),
                ethers.utils.parseEther("1.5"),
                receiver.address,
                [[
                    TestToken2.address,
                    0,
                    [[
                        Adapter01.address,
                        10000,
                        0,
                        [[
                            4,
                            ethers.constants.AddressZero,
                            10000,
                            payload,
                            0
                        ]]
                    ]]
                ]],
                [[
                    TestToken2.address,
                    0,
                    [[
                        Adapter01.address,
                        10000,
                        0,
                        [[
                            4,
                            ethers.constants.AddressZero,
                            10000,
                            payload,
                            0
                        ]]
                    ]]
                ]],
                ethers.constants.AddressZero,
                ethers.BigNumber.from("452312848583266388373324160190187140051835877600158453279131187530910679040"),
                "0x00",
                1686061732,
                "0x48726217fca940b892b3b899843c8a57",
                ethers.utils.parseEther("0.05"),
                1
            ]];
            let ABI = [
                "function multiSwapDeBridge((address[],uint256,uint256,uint256,address,(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[],(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[],address,uint256,bytes,uint256,bytes16,uint256,uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("multiSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
            value: ethers.utils.parseEther("5")
            }
            // Swap before bridge
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
        })
        
        it("Testing megaSwapDeBridge. Swap token to token", async function(){
            const { 
                TestToken1, 
                TestToken2,  
                AugustusSwapper, 
                TokenTransferProxy, 
                Adapter01, 
                UniswapV2Pair,
                accounts, 
                owner } = await loadFixture(deploySuperDEX);
            let receiver = accounts[16];
            let payload;
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let direction = await UniswapV2Pair.token0() == TestToken1.address;
            payload = await MultiPathHelper.getPools(ethers.BigNumber.from(9970), UniswapV2Pair.address, direction);
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let encoder = new ethers.utils.AbiCoder();
            calldata = encoder.encode([ "tuple(address, uint256[])" ], [[ethers.constants.AddressZero, [payload]]]);            
            let data = [[
                [TestToken1.address, TestToken1.address], 
                ethers.utils.parseEther("5"), 
                ethers.utils.parseEther("1"), 
                ethers.utils.parseEther("1.5"), 
                receiver.address, 
                [[
                    10000, 
                    [[
                        TestToken2.address,
                        0,
                        [[
                            Adapter01.address,
                            10000,
                            0,
                            [[
                                4,
                                ethers.constants.AddressZero,
                                10000,
                                calldata,
                                0
                            ]]
                        ]]
                    ]]
                ]],
                [[
                    10000, 
                    [[
                        TestToken2.address,
                        0,
                        [[
                            Adapter01.address,
                            10000,
                            0,
                            [[
                                4,
                                ethers.constants.AddressZero,
                                10000,
                                calldata,
                                0
                            ]]
                        ]]
                    ]]
                ]],
                ethers.constants.AddressZero,
                ethers.BigNumber.from("452312848583266388373324160190187140051835877600158453279131187530910679040"),
                "0x00",
                1686061732,
                "0x48726217fca940b892b3b899843c8a57",
                ethers.utils.parseEther("0.05"),
                1
            ]];
            let ABI = [
                "function megaSwapDeBridge((address[],uint256,uint256,uint256,address,(uint256,(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[])[],(uint256,(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[])[],address,uint256,bytes,uint256,bytes16,uint256,uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("megaSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            };
            // Swap before bridge
            await TestToken1.approve(TokenTransferProxy, ethers.utils.parseEther("100"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);

            balanceBefore = await TestToken2.balanceOf(receiver.address);
            data[0][13] = 31337;
            functionCall = iface.encodeFunctionData("megaSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
            }
            // Swap after bridge
            await TestToken1.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
        })

        it("Testing megaSwapDeBridge. Swap token to ETH", async function(){
            const {
                TestToken2, 
                WETH, 
                AugustusSwapper, 
                TokenTransferProxy, 
                Adapter01,
                UniswapV2PairETH,
                accounts, 
                owner 
            } = await loadFixture(deploySuperDEX);
            let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
            let receiver = accounts[16];
            let payload;
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let direction = await UniswapV2PairETH.token0() == TestToken2.address;
            payload = await MultiPathHelper.getPools(ethers.BigNumber.from(9970), UniswapV2PairETH.address, direction)
            let balanceBefore = await receiver.getBalance();
            let encoder = new ethers.utils.AbiCoder();
            calldata = encoder.encode([ "tuple(address, uint256[])" ], [[WETH.address, [payload]]]);
            let data = [[
                [TestToken2.address, TestToken2.address], 
                ethers.utils.parseEther("5"), 
                ethers.utils.parseEther("1"), 
                ethers.utils.parseEther("1.5"), 
                receiver.address, 
                [[
                    10000, 
                    [[
                        ethAddress,
                        0,
                        [[
                            Adapter01.address,
                            10000,
                            0,
                            [[
                                4,
                                ethers.constants.AddressZero,
                                10000,
                                calldata,
                                0
                            ]]
                        ]]
                    ]]
                ]],
                [[
                    10000, 
                    [[
                        ethAddress,
                        0,
                        [[
                            Adapter01.address,
                            10000,
                            0,
                            [[
                                4,
                                ethers.constants.AddressZero,
                                10000,
                                calldata,
                                0
                            ]]
                        ]]
                    ]]
                ]],
                ethers.constants.AddressZero,
                ethers.BigNumber.from("452312848583266388373324160190187140051835877600158453279131187530910679040"),
                "0x00",
                1686061732,
                "0x48726217fca940b892b3b899843c8a57",
                ethers.utils.parseEther("0.05"),
                1
            ]];
            let ABI = [
                "function megaSwapDeBridge((address[],uint256,uint256,uint256,address,(uint256,(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[])[],(uint256,(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[])[],address,uint256,bytes,uint256,bytes16,uint256,uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("megaSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            };
            // Swap before bridge
            await TestToken2.approve(TokenTransferProxy, ethers.utils.parseEther("100"));
            await owner.sendTransaction(tx);
            expect(await receiver.getBalance()).greaterThan(balanceBefore);

            balanceBefore = await receiver.getBalance();
            data[0][13] = 31337;
            functionCall = iface.encodeFunctionData("megaSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
            }
            // Swap after bridge
            await TestToken2.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await receiver.getBalance()).greaterThan(balanceBefore);
        })

        it("Testing megaSwapDeBridge. Swap ETH to token", async function(){
            const {
                TestToken2, 
                WETH, 
                AugustusSwapper,  
                Adapter01,
                UniswapV2PairETH,
                accounts, 
                owner 
            } = await loadFixture(deploySuperDEX);
            let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
            let receiver = accounts[16];
            let payload;
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let direction = await UniswapV2PairETH.token0() == WETH.address;
            payload = await MultiPathHelper.getPools(ethers.BigNumber.from(9970), UniswapV2PairETH.address, direction);
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let encoder = new ethers.utils.AbiCoder();
            calldata = encoder.encode([ "tuple(address, uint256[])" ], [[WETH.address, [payload]]]);
            let data = [[
                [ethAddress, ethAddress], 
                ethers.utils.parseEther("5"), 
                ethers.utils.parseEther("1"), 
                ethers.utils.parseEther("1.5"), 
                receiver.address, 
                [[
                    10000, 
                    [[
                        TestToken2.address,
                        0,
                        [[
                            Adapter01.address,
                            10000,
                            0,
                            [[
                                4,
                                ethers.constants.AddressZero,
                                10000,
                                calldata,
                                0
                            ]]
                        ]]
                    ]]
                ]],
                [[
                    10000, 
                    [[
                        TestToken2.address,
                        0,
                        [[
                            Adapter01.address,
                            10000,
                            0,
                            [[
                                4,
                                ethers.constants.AddressZero,
                                10000,
                                calldata,
                                0
                            ]]
                        ]]
                    ]]
                ]],
                ethers.constants.AddressZero,
                ethers.BigNumber.from("452312848583266388373324160190187140051835877600158453279131187530910679040"),
                "0x00",
                1686061732,
                "0x48726217fca940b892b3b899843c8a57",
                ethers.utils.parseEther("0.05"),
                1
            ]];
            let ABI = [
                "function megaSwapDeBridge((address[],uint256,uint256,uint256,address,(uint256,(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[])[],(uint256,(address,uint256,(address,uint256,uint256,(uint256,address,uint256,bytes,uint256)[])[])[])[],address,uint256,bytes,uint256,bytes16,uint256,uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("megaSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("5")
            };
            // Swap before bridge
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
        })
    })

    describe("Tesing NewUniswapV2Router", function(){
        it("Swap token to token", async function(){
            const { TestToken1, 
                TestToken2,  
                AugustusSwapper, 
                TokenTransferProxy, 
                UniswapV2Pair,
                accounts, 
                owner } = await loadFixture(deploySuperDEX);
            let receiver = accounts[16];
            let payload;
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let direction = await UniswapV2Pair.token0() == TestToken1.address;
            payload = await MultiPathHelper.getPools(ethers.BigNumber.from(9970), UniswapV2Pair.address, direction);
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let data = [[
                [TestToken1.address, TestToken1.address],
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther("1.5"),
                ethers.constants.AddressZero,
                [payload],
                [payload],
                ethers.utils.parseEther("0.05"),
                1,
                receiver.address
            ]];
            let ABI = [
                "function swapOnUniswapV2ForkDeBridge((address[],uint256,uint256,address,uint256[],uint256[],uint256,uint256,address))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("swapOnUniswapV2ForkDeBridge", data);
            let tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            };
            // Swap before bridge
            await TestToken1.approve(TokenTransferProxy, ethers.utils.parseEther("100"));
            await owner.sendTransaction(tx);                
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);

            balanceBefore = await TestToken2.balanceOf(receiver.address);
            data[0][7] = 31337;
            functionCall = iface.encodeFunctionData("swapOnUniswapV2ForkDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
            }
            // Swap after bridge
            await TestToken1.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
        })

        it("Swap token to ETH", async function(){
            const {
                TestToken2, 
                WETH, 
                AugustusSwapper, 
                TokenTransferProxy,
                UniswapV2PairETH,
                accounts, 
                owner 
            } = await loadFixture(deploySuperDEX);
            let receiver = accounts[16];
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let direction = await UniswapV2PairETH.token0() == TestToken2.address;
            payload = await MultiPathHelper.getPools(ethers.BigNumber.from(9970), UniswapV2PairETH.address, direction);
            let balanceBefore = await receiver.getBalance();
            let data = [[
                [TestToken2.address, TestToken2.address],
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther("1.5"),
                WETH.address,
                [payload],
                [payload],
                ethers.utils.parseEther("0.05"),
                1,
                receiver.address
            ]];
            let ABI = [
                "function swapOnUniswapV2ForkDeBridge((address[],uint256,uint256,address,uint256[],uint256[],uint256,uint256,address))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("swapOnUniswapV2ForkDeBridge", data);
            let tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            };
            // Swap before bridge
            await TestToken2.approve(TokenTransferProxy, ethers.utils.parseEther("100"));
            await owner.sendTransaction(tx);                
            expect(await receiver.getBalance()).greaterThan(balanceBefore);

            balanceBefore = await receiver.getBalance();
            data[0][7] = 31337;
            functionCall = iface.encodeFunctionData("swapOnUniswapV2ForkDeBridge", data);
            tx = {
            to: AugustusSwapper.address,
               data: functionCall,
            }
            // Swap after bridge
            await TestToken2.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await receiver.getBalance()).greaterThan(balanceBefore);
        })

        it("Swap ETH to token", async function(){
            const {
                TestToken2, 
                WETH, 
                AugustusSwapper, 
                UniswapV2PairETH,
                accounts, 
                owner 
            } = await loadFixture(deploySuperDEX);
            let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
            let receiver = accounts[16];
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let direction = await UniswapV2PairETH.token0() == WETH.address;
            let payload = await MultiPathHelper.getPools(ethers.BigNumber.from(9970), UniswapV2PairETH.address, direction);
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let data = [[
                [ethAddress, ethAddress],
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther("1.5"),
                WETH.address,
                [payload],
                [payload],
                ethers.utils.parseEther("0.05"),
                1,
                receiver.address
            ]];
            let ABI = [
                "function swapOnUniswapV2ForkDeBridge((address[],uint256,uint256,address,uint256[],uint256[],uint256,uint256,address))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("swapOnUniswapV2ForkDeBridge", data);
            let tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("5.01")
            };
            // Swap before debridge
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
        })
    })

    describe("Testing UniswapV2Router", function(){
        it("Swap token to token", async function(){
            const { TestToken1, 
            TestToken2,  
            AugustusSwapper, 
            TokenTransferProxy, 
            accounts, 
            owner 
            } = await loadFixture(deploySuperDEX);
            let receiver = accounts[16];
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let data = [[
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther("0"),
                [TestToken1.address, TestToken2.address],
                [TestToken1.address, TestToken2.address],
                receiver.address,
                ethers.utils.parseEther("0.05"),
                1
            ]];
            let ABI = [
                "function swapOnUniswapDeBridge((uint256, uint256, address[], address[], address, uint256, uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("swapOnUniswapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            }
            // Swap before bridge
            await TestToken1.approve(TokenTransferProxy, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);

            balanceBefore = await TestToken2.balanceOf(receiver.address);
            data[0][6] = 31337;
            functionCall = iface.encodeFunctionData("swapOnUniswapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall
            }
            // Swap after bridge
            await TestToken1.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
        })

        it("Swap token to ETH", async function(){
            const {  
            TestToken2,  
            AugustusSwapper, 
            TokenTransferProxy, 
            accounts, 
            owner } = await loadFixture(deploySuperDEX);
            let receiver = accounts[16];
            let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
            let balanceBefore = await receiver.getBalance();
            let data = [[
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther("0"),
                [TestToken2.address, ethAddress],
                [TestToken2.address, ethAddress],
                receiver.address,
                ethers.utils.parseEther("0.05"),
                1
            ]];
            let ABI = [
                "function swapOnUniswapDeBridge((uint256, uint256, address[], address[], address, uint256, uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("swapOnUniswapDeBridge", data);
            let tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            }
            // Swap before bridge
            await TestToken2.approve(TokenTransferProxy, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await receiver.getBalance()).greaterThan(balanceBefore);

            balanceBefore = await receiver.getBalance();
            data[0][6] = 31337;
            functionCall = iface.encodeFunctionData("swapOnUniswapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall
            }
            // Swap after bridge
            await TestToken2.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await receiver.getBalance()).greaterThan(balanceBefore);
        })

        it("Swap ETH to token", async function(){
            const {  
                TestToken2,  
                AugustusSwapper, 
                accounts, 
                owner } = await loadFixture(deploySuperDEX);
            let receiver = accounts[16];
            let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let data = [[
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther("0"),
                [ethAddress, TestToken2.address],
                [ethAddress, TestToken2.address],
                receiver.address,
                ethers.utils.parseEther("0.05"),
                1
            ]];
            let ABI = [
                "function swapOnUniswapDeBridge((uint256, uint256, address[], address[], address, uint256, uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("swapOnUniswapDeBridge", data);       
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("5.01")
            }
            // Swap before bridge
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
        })
    })

    describe("Testing SimpleSwap", function(){
        it("Swap token to token", async function(){
            const { 
                TestToken1, 
                TestToken2,  
                AugustusSwapper, 
                TokenTransferProxy, 
                accounts, 
                owner } = await loadFixture(deploySuperDEX);
            let receiver = accounts[16];
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let payload = await MultiPathHelper.encodeSwap(
                ethers.utils.parseEther("5"), 
                ethers.utils.parseEther("0"), 
                [TestToken1.address, TestToken2.address]
            );
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let data = [[
                [TestToken1.address, TestToken2.address],
                [TestToken1.address, TestToken2.address],
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther('1'),
                ethers.utils.parseEther("1.5"),
                [AugustusSwapper.address, AugustusSwapper.address],
                payload[0],
                [0, 196, 0],
                [0, 0],
                1,
                receiver.address,
                ethers.constants.AddressZero,
                ethers.BigNumber.from("452312848583266388373324160190187140051835877600158453279131187530910679040"),
                "0x00",
                1686061732,
                "0x48726217fca940b892b3b899843c8a57",
                ethers.utils.parseEther("0.05"),
                1,
                TokenTransferProxy
            ]];
            let ABI = [
                "function simpleSwapDeBridge((address[],address[],uint256,uint256,uint256,address[],bytes,uint256[],uint256[],uint256,address,address,uint256,bytes,uint256,bytes16,uint256,uint256,address))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("simpleSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            };
            // Swap before bridge
            await TestToken1.approve(TokenTransferProxy, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);

            balanceBefore = await TestToken2.balanceOf(receiver.address);
            data[0][17] = 31337;
            functionCall = iface.encodeFunctionData("simpleSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall
            };
            // Swap after bridge
            await TestToken1.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
        })

        it("Swap token to ETH", async function(){
            const { 
                TestToken2,  
                AugustusSwapper, 
                TokenTransferProxy, 
                accounts, 
                owner } = await loadFixture(deploySuperDEX);
            let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
            let receiver = accounts[16];
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let payload = await MultiPathHelper.encodeSwap(
                ethers.utils.parseEther("5"), 
                ethers.utils.parseEther("0"), 
                [TestToken2.address, ethAddress]
            );
            let balanceBefore = await receiver.getBalance();
            let data = [[
                [TestToken2.address, ethAddress],
                [TestToken2.address, ethAddress],
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther('1'),
                ethers.utils.parseEther("1.5"),
                [AugustusSwapper.address, AugustusSwapper.address],
                payload[0],
                [0, 196, 0],
                [0, 0],
                1,
                receiver.address,
                ethers.constants.AddressZero,
                ethers.BigNumber.from("452312848583266388373324160190187140051835877600158453279131187530910679040"),
                "0x00",
                1686061732,
                "0x48726217fca940b892b3b899843c8a57",
                ethers.utils.parseEther("0.05"),
                1,
                TokenTransferProxy
            ]];
            let ABI = [
                "function simpleSwapDeBridge((address[],address[],uint256,uint256,uint256,address[],bytes,uint256[],uint256[],uint256,address,address,uint256,bytes,uint256,bytes16,uint256,uint256,address))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("simpleSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            };
            // Swap before bridge
            await TestToken2.approve(TokenTransferProxy, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await receiver.getBalance()).greaterThan(balanceBefore); 

            balanceBefore = await receiver.getBalance();
            data[0][17] = 31337;
            functionCall = iface.encodeFunctionData("simpleSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall
            };
            // Swap after bridge
            await TestToken2.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await receiver.getBalance()).greaterThan(balanceBefore);
        })

        it("Swap ETH to token", async function(){
            const { 
                TestToken2,  
                AugustusSwapper, 
                TokenTransferProxy, 
                accounts, 
                owner } = await loadFixture(deploySuperDEX);
            let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
            let receiver = accounts[16];
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let payload = await MultiPathHelper.encodeSwap(
                ethers.utils.parseEther("4.99"), 
                ethers.utils.parseEther("0"), 
                [ethAddress, TestToken2.address]
            );
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let data = [[
                [ethAddress, TestToken2.address],
                [ethAddress, TestToken2.address],
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther('1'),
                ethers.utils.parseEther("1.5"),
                [AugustusSwapper.address, AugustusSwapper.address],
                payload[0],
                [0, 196, 0],
                [ethers.utils.parseEther("4.99"), 0],
                1,
                receiver.address,
                ethers.constants.AddressZero,
                ethers.BigNumber.from("452312848583266388373324160190187140051835877600158453279131187530910679040"),
                "0x00",
                1686061732,
                "0x48726217fca940b892b3b899843c8a57",
                ethers.utils.parseEther("0.05"),
                1,
                TokenTransferProxy
            ]];
            let ABI = [
                "function simpleSwapDeBridge((address[],address[],uint256,uint256,uint256,address[],bytes,uint256[],uint256[],uint256,address,address,uint256,bytes,uint256,bytes16,uint256,uint256,address))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("simpleSwapDeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("5")
            };
            // Swap before bridge
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore); 
        })
    })

    describe("Testing ZeroExRouter", function(){
        it("Swap token to token", async function(){
            const { 
                TestToken1, 
                TestToken2,  
                AugustusSwapper, 
                TokenTransferProxy, 
                ZeroEx,
                accounts, 
                owner } = await loadFixture(deploySuperDEX);
            let receiver = accounts[16];
            let taker = accounts[17];
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let payload1 = await MultiPathHelper.encodePayload(
                [[
                    TestToken2.address,
                    TestToken1.address,
                    ethers.utils.parseEther("5"),
                    ethers.utils.parseEther("5"),
                    taker.address,
                    AugustusSwapper.address,
                    owner.address,
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                    ethers.BigNumber.from(1755520021),
                    ethers.BigNumber.from(1659700605000)
                ],
                [
                    "3",
                    "28",
                    "0xf29ce1b13dc01ca4f4391d4f8774d002b294924142841655f21c70cc533544e6",
                    "0x4d5c48a4d0ce035d6b78354c3942c1f824c7068be7ae54988ddc02fbb55acb62"
                ]]

            )
            let payload2 = await MultiPathHelper.encodePayload(
                [[
                    TestToken2.address,
                    TestToken1.address,
                    ethers.utils.parseEther("3"),
                    ethers.utils.parseEther("3"),
                    taker.address,
                    AugustusSwapper.address,
                    owner.address,
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                    ethers.BigNumber.from(1755520021),
                    ethers.BigNumber.from(1659700605000)
                ],
                [
                    "3",
                    "28",
                    "0xf29ce1b13dc01ca4f4391d4f8774d002b294924142841655f21c70cc533544e6",
                    "0x4d5c48a4d0ce035d6b78354c3942c1f824c7068be7ae54988ddc02fbb55acb62"
                ]]

            )
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let data = [[
                [TestToken1.address, TestToken2.address],
                [TestToken1.address, TestToken2.address],
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther("1"),
                ZeroEx.address,
                ZeroEx.address,
                payload1,
                payload2,
                receiver.address,
                ethers.utils.parseEther("0.05"),
                1
            ]];
            let ABI = [
                "function swapOnZeroXv4DeBridge((address[],address[],uint256,uint256,address,address,bytes,bytes,address,uint256,uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("swapOnZeroXv4DeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            };
            // Swap before bridge
            await TestToken2.transfer(taker.address, ethers.utils.parseEther("10"));
            await TestToken2.connect(taker).approve(ZeroEx.address, ethers.utils.parseEther("10"));
            await TestToken1.approve(TokenTransferProxy, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);

            balanceBefore = await TestToken2.balanceOf(receiver.address);
            balanceBefore = await TestToken2.balanceOf(receiver.address);
            data[0][10] = 31337;
            functionCall = iface.encodeFunctionData("swapOnZeroXv4DeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall
            };
            // Swap after bridge
            await TestToken2.transfer(taker.address, ethers.utils.parseEther("3"));
            await TestToken2.connect(taker).approve(ZeroEx.address, ethers.utils.parseEther("3"));
            await TestToken1.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
        });

        it("Swap token to ETH", async function(){
            const { 
                TestToken2, 
                WETH,
                AugustusSwapper, 
                TokenTransferProxy, 
                ZeroEx,
                accounts, 
                owner } = await loadFixture(deploySuperDEX);
            let receiver = accounts[16];
            let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
            let taker = accounts[17];
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let payload1 = await MultiPathHelper.encodePayload(
                [[
                    WETH.address,
                    TestToken2.address,
                    ethers.utils.parseEther("5"),
                    ethers.utils.parseEther("5"),
                    taker.address,
                    AugustusSwapper.address,
                    owner.address,
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                    ethers.BigNumber.from(1755520021),
                    ethers.BigNumber.from(1659700605000)
                ],
                [
                    "3",
                    "28",
                    "0xf29ce1b13dc01ca4f4391d4f8774d002b294924142841655f21c70cc533544e6",
                    "0x4d5c48a4d0ce035d6b78354c3942c1f824c7068be7ae54988ddc02fbb55acb62"
                ]]

            )
            let payload2 = await MultiPathHelper.encodePayload(
                [[
                    WETH.address,
                    TestToken2.address,
                    ethers.utils.parseEther("3"),
                    ethers.utils.parseEther("3"),
                    taker.address,
                    AugustusSwapper.address,
                    owner.address,
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                    ethers.BigNumber.from(1755520021),
                    ethers.BigNumber.from(1659700605000)
                ],
                [
                    "3",
                    "28",
                    "0xf29ce1b13dc01ca4f4391d4f8774d002b294924142841655f21c70cc533544e6",
                    "0x4d5c48a4d0ce035d6b78354c3942c1f824c7068be7ae54988ddc02fbb55acb62"
                ]]

            )
            let balanceBefore = await receiver.getBalance();
            let data = [[
                [TestToken2.address, ethAddress],
                [TestToken2.address, ethAddress],
                ethers.utils.parseEther("5"),
                ethers.utils.parseEther("1"),
                ZeroEx.address,
                ZeroEx.address,
                payload1,
                payload2,
                receiver.address,
                ethers.utils.parseEther("0.05"),
                1
            ]];
            let ABI = [
                "function swapOnZeroXv4DeBridge((address[],address[],uint256,uint256,address,address,bytes,bytes,address,uint256,uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("swapOnZeroXv4DeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("0.01")
            };
            // Swap before bridge
            await WETH.transfer(taker.address, ethers.utils.parseEther("8"));
            await WETH.connect(taker).approve(ZeroEx.address, ethers.utils.parseEther("5"));
            await TestToken2.approve(TokenTransferProxy, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx); 
            expect(await receiver.getBalance()).greaterThan(balanceBefore);

            balanceBefore = await receiver.getBalance();
            data[0][10] = 31337;
            functionCall = iface.encodeFunctionData("swapOnZeroXv4DeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall
            };
            // Swap after bridge
            await WETH.connect(taker).approve(ZeroEx.address, ethers.utils.parseEther("3"));
            await TestToken2.approve(AugustusSwapper.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await receiver.getBalance()).greaterThan(balanceBefore);
        })

        it("Swap ETH to token", async function(){
            const { 
                TestToken2, 
                WETH,
                AugustusSwapper, 
                ZeroEx,
                accounts, 
                owner } = await loadFixture(deploySuperDEX);
            let receiver = accounts[16];
            let ethAddress = ethers.utils.getAddress("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
            let taker = accounts[17];
            let helper = await ethers.getContractFactory("MultiPathHelper");
            let MultiPathHelper = await helper.deploy();
            let payload = await MultiPathHelper.encodePayload(
                [[
                    TestToken2.address,
                    WETH.address,
                    ethers.utils.parseEther("4.99"),
                    ethers.utils.parseEther("4.99"),
                    taker.address,
                    AugustusSwapper.address,
                    owner.address,
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                    ethers.BigNumber.from(1755520021),
                    ethers.BigNumber.from(1659700605000)
                ],
                [
                    "3",
                    "28",
                    "0xf29ce1b13dc01ca4f4391d4f8774d002b294924142841655f21c70cc533544e6",
                    "0x4d5c48a4d0ce035d6b78354c3942c1f824c7068be7ae54988ddc02fbb55acb62"
                ]]

            )            
            let balanceBefore = await TestToken2.balanceOf(receiver.address);
            let data = [[
                [ethAddress, TestToken2.address],
                [TestToken2.address, ethAddress],
                ethers.utils.parseEther("4.99"),
                ethers.utils.parseEther("1"),
                ZeroEx.address,
                ZeroEx.address,
                payload,
                payload,
                receiver.address,
                ethers.utils.parseEther("0.05"),
                1
            ]];
            let ABI = [
                "function swapOnZeroXv4DeBridge((address[],address[],uint256,uint256,address,address,bytes,bytes,address,uint256,uint256))"
            ];
            let iface = new ethers.utils.Interface(ABI);
            let functionCall = iface.encodeFunctionData("swapOnZeroXv4DeBridge", data);
            tx = {
                to: AugustusSwapper.address,
                data: functionCall,
                value: ethers.utils.parseEther("5")
            };
            // Swap before bridge
            await TestToken2.transfer(taker.address, ethers.utils.parseEther("8"));
            await TestToken2.connect(taker).approve(ZeroEx.address, ethers.utils.parseEther("5"));
            await owner.sendTransaction(tx);
            expect(await TestToken2.balanceOf(receiver.address)).greaterThan(balanceBefore);
        })
    })
})

