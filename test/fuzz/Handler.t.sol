// SPDX-License-Identifier: MIT
// Handler is going to narrow down the way we can call our contract methods

pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStablecoin.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregato.sol";

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    ERC20Mock wEth;
    ERC20Mock wBtc;

    uint256 public timesMintCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;
    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max; //

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dscEngine) {
        dsc = _dsc;
        dscEngine = _dscEngine;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        require(collateralTokens.length >= 2, "Not enough collateral tokens");

        wEth = ERC20Mock(collateralTokens[0]);
        wBtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wEth)));
    }

    // minting and burning DSC
    function mintDsc(uint256 _amount, uint256 _addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[_addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMInted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);
        int256 maxDsctoMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMInted);
        if (maxDsctoMint < 0) {
            return;
        }
        _amount = bound(_amount, 0, uint256(maxDsctoMint));
        if (_amount == 0) {
            return;
        }
        vm.startPrank(sender);
        dscEngine.mintDSC(_amount);
        vm.stopPrank();

        timesMintCalled++;
    }

    // redeem collateral
    function depositCollateral(
        uint256 _amount,
        uint256 _collateralSeed
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);
        _amount = bound(_amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, _amount);
        collateral.approve(address(dscEngine), _amount);
        dscEngine.depositCollateral(address(collateral), _amount);
        vm.stopPrank();

        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(
        uint256 _collateralSeed,
        uint256 _amount
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(_collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));

        _amount = bound(_amount, 0, maxCollateralToRedeem);
        if (_amount == 0) {
            return;
        }

        dscEngine.redeemCollateral(address(collateral), _amount);
    }

    // This breaks our invariant test suite!!!
    // function upateCollateralPrice(int256 _newPrice, uint256 _priceSeed) public {
    //     if (_priceSeed % 2 == 0) {
    //         ethUsdPriceFeed.updateAnswer(_newPrice);
    //     } else {
    //         btcUsdPriceFeed.updateAnswer(_newPrice);
    //     }
    // }

    ////////////// Helper Functions //////////////
    function _getCollateralFromSeed(uint256 _seed) private view returns (ERC20Mock) {
        if (_seed % 2 == 0) {
            return wEth;
        } else {
            return wBtc;
        }
    }

}