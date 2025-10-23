// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title DecentralizedStableCoin
 * @author Patrick Collins
 * Collateral: Exogenous
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 *
 * This is the contract meant to be owned by DSCEngine. It is an ERC20 token that can be minted and burned by the DSCEngine smart contract.
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStablecoin_InsufficientBalance();
    error DecentralizedStablecoin_MustBeMoreThanZero();
    error DecentralizedStablecoin_NotZeroAddress();

    constructor() 
        ERC20("DecentralizedStableCoin", "DSC")
        Ownable(msg.sender)
    {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (balance < _amount) {
            revert DecentralizedStablecoin_InsufficientBalance();
        }
        if (_amount == 0) {
            revert DecentralizedStablecoin_MustBeMoreThanZero();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_amount <= 0) {
            revert DecentralizedStablecoin_MustBeMoreThanZero();
        }
        if (_to == address(0)) {
            revert DecentralizedStablecoin_NotZeroAddress();
        }
        _mint(_to, _amount);

        return true;
    }
 }