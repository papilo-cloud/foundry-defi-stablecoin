// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address wEth;
    address ethUsdPriceFeed;

    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokenAddressesAndPriceFeedAddressNotMatching();

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10e18; // 10 ETH
    uint256 public constant STARTING_BALANCE = 100e18; // 100 ETH

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, , , wEth, ) = helperConfig.activeNetworkConfig();
        ERC20Mock(wEth).mint(USER, STARTING_BALANCE);
    }

    ///////////// CONSTRUCTOR TESTS /////////////
    address[] priceFeedsAddresses;
    address[] tokenAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeedLength() public {
        tokenAddresses.push(wEth);
        priceFeedsAddresses.push(ethUsdPriceFeed);
        priceFeedsAddresses.push(ethUsdPriceFeed);

        vm.expectRevert(DSCEngine__TokenAddressesAndPriceFeedAddressNotMatching.selector);
        new DSCEngine(
            tokenAddresses,
            priceFeedsAddresses,
            address(dsc)
        );
    }

    ///////////// PRICE TESTS /////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18; // 15 ETH
        uint256 expectedUsd = 30000e18; // 15 ETH * $2000/ETH
        uint256 actualUsd = dscEngine.getUsdPrice(wEth, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100e18; // $100
        uint256 expectedWeth = 0.05 ether; // $100 / $2000 per ETH = 0.05 ETH
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(wEth, usdAmount);

        assertEq(expectedWeth, actualWeth);
    }

    ///////////////////// DEPOSIT COLLATERAL TESTS ///////////////
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(address(wEth), 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        ranToken.mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier isDepositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(address(wEth), AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateral() public isDepositCollateral {

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(wEth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    /////////////////// REEDEM COLLATERAL TESTS /////////////////
    function testRevertsIfRedeemAmountZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.redeemCollateral(address(wEth), 0);
        vm.stopPrank();
    }

    function testReedemCollateralSuccess() public {
        uint256 reedemAmount = 5e18; // 5 ETH
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(address(wEth), AMOUNT_COLLATERAL);

        uint256 userBalanceBefore = ERC20Mock(wEth).balanceOf(USER);
        dscEngine.redeemCollateral(address(wEth), reedemAmount);

        uint256 userBalanceAfter = ERC20Mock(wEth).balanceOf(USER);
        assertEq(userBalanceAfter, userBalanceBefore + reedemAmount);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);

        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(wEth, collateralValueInUsd);
        assertEq(expectedDepositAmount, AMOUNT_COLLATERAL - reedemAmount);
        vm.stopPrank();
    }

    function testRedeemAllCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(address(wEth), AMOUNT_COLLATERAL);

        dscEngine.redeemCollateral(address(wEth), AMOUNT_COLLATERAL);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
        assertEq(ERC20Mock(wEth).balanceOf(USER), STARTING_BALANCE);
    }

    // function testRevertIfMintedDscBreaksHealthFactor() public isDepositCollateral {
    //     (, int256 ethPrice,,,) = dscEngine.getPriceFeed(ethUsdPriceFeed).latestRoundData();
    //     uint256 amountToMInt = (AMOUNT_COLLATERAL * uint256(ethPrice)) / 2e18; // trying to mint 50% of collateral value

    //     vm.startPrank(USER);
    //     ERC20Mock(wEth).approve(address(dscEngine), AMOUNT_COLLATERAL);

    //     uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(
    //         dscEngine.getUsdPrice(wEth, AMOUNT_COLLATERAL),
    //         amountToMInt
    //     );
    //     dscEngine.depositCollateralAndMintDSC(wEth, AMOUNT_COLLATERAL, amountToMInt);

    //     (, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
    // }
}