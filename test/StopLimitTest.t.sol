// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;
import {console2, Test} from "forge-std/Test.sol";

import {
    IOrderBookV3,
    IO
} from "rain.orderbook.interface/interface/deprecated/v3/IOrderBookV3.sol";
import {
    IOrderBookV4,
    OrderV3,
    OrderConfigV3,
    TakeOrderConfigV3,
    TakeOrdersConfigV3,
    ActionV1
} from "rain.orderbook.interface/interface/IOrderBookV4.sol"; 

import {IParserV2} from "rain.interpreter.interface/interface/IParserV2.sol";
import {IOrderBookV4ArbOrderTaker} from "rain.orderbook.interface/interface/IOrderBookV4ArbOrderTaker.sol";

import {IExpressionDeployerV3} from "rain.interpreter.interface/interface/deprecated/IExpressionDeployerV3.sol";
import {IInterpreterV3} from "rain.interpreter.interface/interface/IInterpreterV3.sol";
import {IInterpreterStoreV2} from "rain.interpreter.interface/interface/IInterpreterStoreV2.sol";
import {StrategyTests, IRouteProcessor, LibStrategyDeployment, LibComposeOrders,IInterpreterV3} from "h20.test-std/StrategyTests.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "h20.test-std/lib/LibProcessStream.sol";

uint256 constant VAULT_ID = uint256(keccak256("vault"));


/// @dev https://basescan.org/address/0x99b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D
IERC20 constant BASE_WLTH= IERC20(0x99b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D); 

/// @dev https://basescan.org/address/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
IERC20 constant BASE_USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

function baseWlthIo() pure returns (IO memory) {
    return IO(address(BASE_WLTH), 18, VAULT_ID);
}

function baseUsdcIo() pure returns (IO memory) {
    return IO(address(BASE_USDC), 6, VAULT_ID);
} 

contract StopLimitTest is StrategyTests { 

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 18339410;
    
    function selectFork() internal {
        uint256 fork = vm.createFork(vm.envString("RPC_URL_BASE"));
        vm.selectFork(fork);
        vm.rollFork(FORK_BLOCK_NUMBER);
    }

    function setUp() public {
        selectFork();
        
        iParser = IParserV2(0x56394785a22b3BE25470a0e03eD9E0a939C47b9b);
        iStore = IInterpreterStoreV2(0x6E4b01603edBDa617002A077420E98C86595748E); 
        iInterpreter = IInterpreterV3(0x379b966DC6B117dD47b5Fc5308534256a4Ab1BCC); 
        iExpressionDeployer = IExpressionDeployerV3(0x56394785a22b3BE25470a0e03eD9E0a939C47b9b); 
        iOrderBook = IOrderBookV4(0xA2f56F8F74B7d04d61f281BE6576b6155581dcBA);
        iArbInstance = IOrderBookV4ArbOrderTaker(0xF97A86C2Cb3e42f89AC5f5AA020E5c3505015a88);
        iRouteProcessor = IRouteProcessor(address(0x0389879e0156033202C44BF784ac18fC02edeE4f)); 
        EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        ORDER_OWNER = address(0x5e01e44aE1969e16B9160d903B6F2aa991a37B21); 
    }

    function testEnsureStopLimitSell() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseWlthIo();

        LibStrategyDeployment.StrategyDeploymentV3 memory strategy = LibStrategyDeployment.StrategyDeploymentV3(
            getEncodedBuyWlthRoute(),
            getEncodedSellWlthRoute(),
            0,
            0,
            10000e6,
            10000e18,
            0,
            0,
            "strategies/stop-limit.rain",
            "stop-limit-order.sell.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults,
            new ActionV1[](0)
        );

        OrderV3 memory order = addOrderDepositOutputTokens(strategy);

        // Current Price is not below the market price.
        {
            vm.expectRevert("Stop price.");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }

        // When current price goes below the market price the order suceeds.
        {
            moveExternalPrice(
                strategy.outputVaults[strategy.outputTokenIndex].token,
                strategy.inputVaults[strategy.inputTokenIndex].token,
                200000e18,
                strategy.takerRoute
            );
            
            vm.recordLogs();
            // `arb()` called
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyRatio, 0.0245e18);
            assertEq(strategyAmount, 50e18);
        
            vm.expectRevert("Max order count");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
             
        }
    }

    function testEnsureStopLimitBuy() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        LibStrategyDeployment.StrategyDeploymentV3 memory strategy = LibStrategyDeployment.StrategyDeploymentV3(
            getEncodedSellWlthRoute(),
            getEncodedBuyWlthRoute(),
            0,
            0,
            1000000e18,
            10000e6,
            0,
            0,
            "strategies/stop-limit.rain",
            "stop-limit-order.buy.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults,
            new ActionV1[](0)
        );

        OrderV3 memory order = addOrderDepositOutputTokens(strategy);

        // Current Price is not above the market price.
        {
            vm.expectRevert("Stop price.");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }
        {
            moveExternalPrice(
                strategy.inputVaults[strategy.inputTokenIndex].token,
                strategy.outputVaults[strategy.outputTokenIndex].token,
                strategy.makerAmount,
                strategy.makerRoute
            );
        }

        {
            vm.recordLogs();
            // `arb()` called
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyRatio, 40.25e18);
            assertEq(strategyAmount, 1e18);
    
            vm.expectRevert("Max order count");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        } 
    }
    
    function getEncodedBuyWlthRoute() internal pure returns (bytes memory) {
        bytes memory BUY_WLTH_ROUTE =
            hex"02833589fCD6eDb6E08f4c7C32D4f71b54bdA0291301ffff011536EE1506e24e5A36Be99C73136cD82907A902E01F97A86C2Cb3e42f89AC5f5AA020E5c3505015a88";
            
        return abi.encode(BUY_WLTH_ROUTE);
    }

    function getEncodedSellWlthRoute() internal pure returns (bytes memory) {
        bytes memory SELL_WLTH_ROUTE =
            hex"0299b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D01ffff011536EE1506e24e5A36Be99C73136cD82907A902E00F97A86C2Cb3e42f89AC5f5AA020E5c3505015a88";
            
        return abi.encode(SELL_WLTH_ROUTE);
    }

}


