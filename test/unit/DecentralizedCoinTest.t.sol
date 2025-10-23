// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStablecoin.sol";

contract DecentralizedCoinTest is Test {
    DecentralizedStableCoin dsc;

    error DecentralizedStablecoin_MustBeMoreThanZero();
    error DecentralizedStablecoin_NotZeroAddress();

    address public USER = makeAddr("user");
    address public OTHER_USER = makeAddr("other user");
    address public owner;

    uint256 public constant MINT_AMOUNT = 1000e18; // 1000 DSC
    uint256 public constant BURN_AMOUNT = 500e18; // 500 DSC

    function setUp() public {
        dsc = new DecentralizedStableCoin();
        owner = dsc.owner();
    }

    function testConstructorSetsOwner() public view {
        assertEq(owner, address(this));
    }

    function testConstructorSetsCorrectNameAndSymbol() public view {
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
    }

    function testConstructorSetsCorrectDecimals() public view {
        assertEq(dsc.decimals(), 18);
    }

    /////////////////// MINT TESTS ///////////////////
    function testOnlyOwnerCanMint() public {
        vm.prank(USER);
        vm.expectRevert();
        dsc.mint(USER, MINT_AMOUNT);
    }

    function testOwnerCanMint() public {
        dsc.mint(USER, MINT_AMOUNT);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, MINT_AMOUNT);
    }

    function testMintRevertWithZeroAmount() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStablecoin_MustBeMoreThanZero.selector);
        dsc.mint(USER, 0);
    }

    function testRevertIfAddressIsInvalid() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStablecoin_NotZeroAddress.selector);
        dsc.mint(address(0), MINT_AMOUNT);
    }

    /////////////////// BURN TEST /////////////////////
    function testBurnSuccess() public {
        dsc.mint(owner, MINT_AMOUNT);
        uint256 initialBalance = dsc.balanceOf(owner);
        uint256 initialSupply = dsc.totalSupply();

        dsc.burn(BURN_AMOUNT);

        uint256 finalBalance = dsc.balanceOf(owner);
        uint256 finalSupply = dsc.totalSupply();

        assertEq(finalBalance, initialBalance - BURN_AMOUNT);
        assertEq(finalSupply, initialSupply - BURN_AMOUNT);
    }

    function testBurnAllBalances() public {
        dsc.mint(owner, MINT_AMOUNT);
        dsc.burn(MINT_AMOUNT);

        assertEq(dsc.balanceOf(owner), 0);
        assertEq(dsc.totalSupply(), 0);
    }

    function testOnlyOwnerCanBurn() public {
        dsc.mint(USER, MINT_AMOUNT);
        vm.prank(USER);
        vm.expectRevert();
        dsc.burn(BURN_AMOUNT);
    }

    function testRevertIfAmountIsLessThanBalance() public {
        dsc.mint(owner, BURN_AMOUNT);
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStablecoin_InsufficientBalance.selector);
        dsc.burn(MINT_AMOUNT);
    }
}