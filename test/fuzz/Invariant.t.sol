// Prpperties of teh DSC system should alwys hold true
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "../fuzz/Handler.t.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


// What are invariants?
// 1. Total supply of DSC should always be less than the total value of collateral in the system
// 2. Getter view functions should never revert
// 3. Health factor of any user should always be above the minimum health factor (1e18)
// 4. Liquidation should always improve the health factor of a user

contract Invariant is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    DeployDSC deployer;
    HelperConfig helperConfig;
    Handler handler;
    address wEth;
    address wBtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (,,wEth, wBtc,) = helperConfig.activeNetworkConfig();
        // targetContract(address(dscEngine));
        handler = new Handler(dsc, dscEngine);
        targetContract(address(handler));
    }

    function invariant_protocolMusthaveMorevalueThanTotalSupply() public view {
        uint256 totalDscSupply = dsc.totalSupply();
        uint256 totalWethDeposited = ERC20Mock(wEth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = ERC20Mock(wBtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdPrice(address(wEth), totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdPrice(address(wBtc), totalWbtcDeposited);

        console.log("WETH VALUE: ", wethValue);
        console.log("WBTC VALUE: ", wbtcValue);
        console.log("TOTAL DSC SUPPLY: ", totalDscSupply);
        console.log("TIMES MINT CALLED: ", handler.timesMintCalled());

        assert(wethValue + wbtcValue >= totalDscSupply);
    }

    function invariant_getterFunctionsShouldNotRevert() public view {
        // address[] memory users = handler.usersWithCollateralDeposited();
        // for (uint256 i = 0; i < users.length; i++) {
        //     dscEngine.getAccountInformation(users[i]);
        //     dscEngine.getHealthFactor(users[i]);
        // }
        dscEngine.getCollateralTokens();
        dscEngine.getLiquidationThreshold();
        dscEngine.getPrecision();
    }
}