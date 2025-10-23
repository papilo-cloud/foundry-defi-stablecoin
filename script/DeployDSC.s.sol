// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStablecoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() public returns(DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (address wEthUsdPriceFeed,
        address wBtcUsdPriceFeed,
        address wBtc,
        address wEth,
        ) = helperConfig.activeNetworkConfig();

        tokenAddresses = [wEth, wBtc];
        priceFeedAddresses = [wEthUsdPriceFeed, wBtcUsdPriceFeed];

        vm.startBroadcast();
        dsc = new DecentralizedStableCoin();
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dsc, dscEngine, helperConfig);
    }
}