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

import {DecentralizedStableCoin} from "./DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "../script/libraries/OracleLib.sol";

/**
 * @title DecentralizedStableCoin Engine
 * @author Abdul Badamasi
 *
 * The system is designed to be as minimal as possible to allow, and allow the tokens maintan
    a $1 == 1 token peg.
 * This stablecoin has the following properties:
 * - Exogenous
 * - Decentralized (Algorithmic)
 * - Pegged to USD
 * - Crypto Collateralized 
 *
 * It is similar ot DAI if DAI had no governance, no fees, and no interest rates.
    and was only backed by wBTC and WETH.
 *
 * Our DSC system should always be overcollateralized to ensure the peg stability.
    at no point should the value of all collateral <= the backed value of all DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and
    burning DSC, as well as depositing and withdrawing collateral.
* @notice This contract is very loosely based on the MakerDAO DSS (DAI Stablecoin System) architecture.
 */

contract DSCEngine is ReentrancyGuard {
    //////////////// ERRORS ////////////////
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokenAddressesAndPriceFeedAddressNotMatching();
    error DSCEngine__InsufficientCollateral();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__TransferFailed();
    error DSCEngine__NotEnoughDSCToBurn();
    error DSCEngine__NotAllowedToLiquidate();

    //////////////////////////// TYPES ////////////////////////////
    using OracleLib for AggregatorV3Interface;

    //////////////// STATE VARIABLES ////////////////
    mapping(address tokenAddress => address priceFeedAddress) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    uint256 private constant PRECISION = 1e8; // 8 decimals
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; // 10 decimals to make price feed return 18 decimals
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 50%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant liquidationBonus = 10; // 10%
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1.
    uint256 private constant LIQUIDATION_BONUS = 10; // this means

    DecentralizedStableCoin private immutable i_dsc;

    //////////////// EVENTS ////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event CollateralRedeemed(
        address indexed from,
        address indexed to,
        address indexed token,
        uint256 amount
    );

    //////////////// MODIFIERS ////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isTokenAllowed(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ///////////////// FUNCTIONS /////////////////
    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses,
        address _dscAddress
    ) {
        // USD Price Feeds
        if(_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressNotMatching();
        }
        // For example ETH / USD, BTC / USD, MKR / USD price feed
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(_dscAddress);
    }

    /////////////// EXTERNAL FUNCTIONS /////////////////

    /**
     * @notice follows CEI pattern
     * @param _tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral The amount of the token to deposit as collateral
     * @param _amountDscToMint The amount of DSC to mint
     */
    function depositCollateralAndMintDSC(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountDscToMint
    ) 
        external
    {
        depositCollateral(_tokenCollateralAddress, _amountCollateral);
        mintDSC(_amountDscToMint);
    }

    /**
     * @notice follows CEI pattern
     * @param _tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amount The amount of the token to deposit as collateral
     */
    function depositCollateral(
        address _tokenCollateralAddress,
        uint256 _amount
    ) 
        public
        moreThanZero(_amount)
        isTokenAllowed(_tokenCollateralAddress)
        nonReentrant
    {
        // 1. Deposit Collateral
        // 2. Mint DSC
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amount;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amount);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        s_collateralTokens.push(_tokenCollateralAddress);
    }

    function redeemCollateralForDsc(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        uint256 _amountDscToBurn
    ) external {
        burnDSC(_amountDscToBurn);
        redeemCollateral(_tokenCollateralAddress, _amountCollateral);
    }

    // In order to withdraw collateral, you have to burn DSC
    // 1. health factor must be over 1 after collatwral pulled
    function redeemCollateral(
        address _tokenCollateralAddress,
        uint256 _amountCollateral
    )
        public
        moreThanZero(_amountCollateral)
        nonReentrant
    {
        
        _redeemCollateral(
            _tokenCollateralAddress,
            _amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI pattern
     * @param _amountDscToMint The amount of DSC to mint
     * @notice they must have more collateral deposited than the minimum threshold
     */
    function mintDSC(uint256 _amountDscToMint)
        public
        moreThanZero(_amountDscToMint)
        nonReentrant
    {
        s_dscMinted[msg.sender] += _amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, _amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 _amount) public moreThanZero(_amount) {
        _burnDsc(_amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // if someone is almost undercollateralized, we will pay you to liquidate them

    /**
     * @param _user The user who has broken the health factor. Their health factor
        should be below MIN-HEALTH_FACTOR
     * @param _collateralTokenAddress The erc20 collateral address to liquuidate from the user
     * @param _debtToCover the amount of DSC you want to burn to improve the users health factor
     * @notice 
     */
    function liquidate(
        address _user,
        address _collateralTokenAddress,
        uint256 _debtToCover
    )
        external moreThanZero(_debtToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(_user);

        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__NotAllowedToLiquidate();
        }
        uint256 tokenAmountFromDEbtCovered = getTokenAmountFromUsd(_collateralTokenAddress, _debtToCover);
        uint256 bunusCollateral = (tokenAmountFromDEbtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDEbtCovered + bunusCollateral;
        _redeemCollateral(
            _collateralTokenAddress,
            totalCollateralToRedeem,
            _user,
            msg.sender
        );
        _burnDsc(_debtToCover, _user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(_user);
        if (endingUserHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorOk();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function calculateHealthFactor(
        uint256 _totalDscMinted,
        uint256 _collateralValueInUsd
    ) 
        external 
        pure 
        returns (uint256) 
    {
        return _calculateHealthFactor(_totalDscMinted, _collateralValueInUsd);
    }

    function getHealthFactor(address _user) external view returns (uint256) {
        return _healthFactor(_user);
    }

    ///////////////// PRIVATE & INTERNAL VIEW FUNCTIONS /////////////////
    /**
     * @notice Returns the health factor of a user, if it is below the minimum threshold, they can be liquidated
     * If a user's health factor drops below 1, they are eligible for liquidation
    */
    function _getAccountInformation(address _user) 
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[_user]; // Total borrowed value
        collateralValueInUsd = getAccountCollateralValue(_user); 
    }

    /**
     * @dev low-level internal function, do not call unless the function calling it checking
     *  for health factor being broken
     */
    function _burnDsc(
        uint256 _amountToBurn,
        address _onBehalfOf,
        address _dscFrom
    )
        internal
    {
        s_dscMinted[_onBehalfOf] -= _amountToBurn;
        bool success = i_dsc.transferFrom(_dscFrom, address(this), _amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(_amountToBurn);
    }

    function _redeemCollateral(
        address _tokenCollateralAddress,
        uint256 _amountCollateral,
        address _from,
        address _to
    )
        internal
    {
        s_collateralDeposited[_from][_tokenCollateralAddress] -= _amountCollateral;
        emit CollateralRedeemed(_from, _to, _tokenCollateralAddress, _amountCollateral);

        bool success = IERC20(_tokenCollateralAddress).transfer(
            _to,
            _amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _healthFactor(address _user) private view returns (uint256) {
        // get total dsc minted
        // get collateral value
        // calculate health factor
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = 
            _getAccountInformation(_user);
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collatoralAdjustedForThreshold = 
            (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collatoralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(
        uint256 _totalDscMinted,
        uint256 _collateralValueInUsd
    ) 
        internal 
        pure 
        returns (uint256) 
    {
        if (_totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collatoralAdjustedForThreshold = 
            (_collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collatoralAdjustedForThreshold * PRECISION) / _totalDscMinted;
    }

    function _getUsdValue(address _token, uint256 _amount) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount) / PRECISION; 
    }

    /////////////// PUBLIC & EXTERNAL VIEW FUNCTIONS /////////////////
    function getAccountCollateralValue(address _user) public view returns (uint256 totalValue) {
        // loop through each collateral token, get the amount deposited, and the price, to calculate the total value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_user][token];
            uint256 price = getUsdPrice(token, amount);
            totalValue += price;
        }
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getUsdPrice(address _tokenAddress, uint256 _amount) public view returns (uint256) {
        return _getUsdValue(_tokenAddress, _amount);
    }

    function getTokenAmountFromUsd(address _token, uint256 _usdAmountInWei)
        public
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (_usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);    
    }

    function getAccountInformation(address _user) 
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(_user);
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getMinHealthfactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralBalanceOfUser(address _user, address _token) external view returns (uint256) {
        return s_collateralDeposited[_user][_token];
    }

    function getCollateralTokenPriceFeed(address _token) external view returns (address) {
        return s_priceFeeds[_token];
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }
}