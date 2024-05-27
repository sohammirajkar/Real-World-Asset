// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OracleLib, AggregatorV3Interface} from "./libraries/OracleLib.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title dTSLA
 * @author Soham Mirajkar
 * @notice This is our contract to make requests to the Alpaca API to mint TSLA-backed dTSLA tokens
 */
contract dTSLA is ConfirmedOwner, FunctionsClient, ERC20 {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    error dTSLA__NotEnoughCollateral();
    error dTSLA__DoesntMeetMinimumWithdrawlAmount();
    error dTSLA__TransferFailed();
    error UnexpectedRequestID(bytes32 requestId);

    enum MintOrRedeem {
        mint,
        redeem
    }

    struct dTSLARequest {
        uint256 amountOfToken;
        address requester;
        MintOrRedeem mintOrRedeem;
    }

    /**
     * Math Constants
     */
    uint256 constant PRECISION = 1e18;

    address SEPOLIA_FUNCTIONS_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 constant DON_ID = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    address constant SEPOLIA_USDC = 0xc59E3633BAAC79493d908e63626716e204A45EdF; // This is actually the LINK/USD feed address
    address constant SEPOLIA_TSLA_PRICE_FEED = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c; // This is actually the LINK/USD feed address
    address constant SEPOLIA_USDC_PRICE_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E; // This is actually the LINK/USD feed address
    uint32 constant GAS_LIMIT = 100_000;
    uint256 constant COLLATERAL_RATIO = 200; // 200% collateral ratio
    uint256 constant COLLATERAL_PRECISION = 100;
    uint256 constant ADDITIONAL_FEE_PRECISION = 1e10;
    uint256 constant MINIMUM_WITHDRAWL_AMOUNT = 100e6; // USDC has 6 decimals
    uint64 immutable i_subId;
    uint64 private s_secretVersion;
    uint8 private s_secretSlot;
    bytes32 s_donId;
    uint256 private immutable i_redemptionCoinDecimals;

    string private s_mintSourceCode;
    string private s_redeemSourceCode;
    uint256 private s_portfolioBalance;

    mapping(bytes32 requestId => dTSLARequest request) private s_requestIdToRequest;
    mapping(address user => uint256 pendingWithdrawlAmount) private s_userToWithdrawlAmount;

    constructor(
        string memory mintSourceCode,
        uint64 subId,
        string memory redeemSourceCode,
        bytes32 donId,
        uint64 secretVersion,
        address redemptionCoin,
        uint8 secretSlot
    ) FunctionsClient(SEPOLIA_FUNCTIONS_ROUTER) ConfirmedOwner(msg.sender) ERC20("Backed TSLA", "bTSLA") {
        s_mintSourceCode = mintSourceCode;
        s_redeemSourceCode = redeemSourceCode;
        i_subId = subId;
        s_donId = donId;
        s_secretVersion = secretVersion;
        s_secretSlot = secretSlot;
        i_redemptionCoinDecimals = ERC20(redemptionCoin).decimals();
    }

    function setSecretVersion(uint64 secretVersion) external onlyOwner {
        s_secretVersion = secretVersion;
    }

    function setSecretSlot(uint8 secretSlot) external onlyOwner {
        s_secretSlot = secretSlot;
    }

    /**
     * @notice Sends an HTTP request for character information
     * @dev If you pass 0, that will act just as a way to get an updated portfolio balance
     * @return requestId The ID of the request
     */
    function sendMintRequest(uint256 amountOfTokensToMint) external onlyOwner returns (bytes32 requestId) {
        // they want to mint $100 and the portfolio has $200 - then that's cool
        if (__getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) > s_portfolioBalance) {
            revert dTSLA__NotEnoughCollateral();
        }
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_mintSourceCode); // Initialize the request with JS code
        req.addDONHostedSecrets(s_secretSlot, s_secretVersion);

        // Send the request and store the request ID
        requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, s_donId);
        s_requestIdToRequest[requestId] = dTSLARequest(amountOfTokensToMint, msg.sender, MintOrRedeem.mint);
        return requestId;
    }

    /// @notice Return the amount of TSLA value (In USD) stored in the Alpaca account
    /// If we have enough TSLA, mint the dTSLA tokens
    function _mintFulFillRequest(bytes32 requestId, bytes memory response) internal {
        uint256 amountOfTokensToMint = s_requestIdToRequest[requestId].amountOfToken;
        s_portfolioBalance = uint256(bytes32(response));

        //If TSLA collateral(how much TSLA is bought) > TSLA to mint -> mint
        //How much TSLA in $$$ do we have?
        //How much TSLA in $$$ are we minting?
        if (__getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) > s_portfolioBalance) {
            revert dTSLA__NotEnoughCollateral();
        }

        if (amountOfTokensToMint != 0) {
            _mint(s_requestIdToRequest[requestId].requester, amountOfTokensToMint);
        }
    }

    /// @notice User sends a request to sell TSLA for USDC (redemption token)
    /// This will, have the chainlink function call alpaca (bank) & do the:
    /// 1. Sell TSLA
    /// 2. Buy USDC on the Brokerage
    /// 3. Send USDC to this contract for the user to withdraw
    function sendRedeemrequest(uint256 amountdTsla) external returns (bytes32 requestId) {
        uint256 amountTslaInUsdc = getUsdcValueOfUsd(getUsdValueOfTsla(amountdTsla));
        if (amountTslaInUsdc < MINIMUM_WITHDRAWL_AMOUNT) {
            revert dTSLA__DoesntMeetMinimumWithdrawlAmount();
        }

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_redeemSourceCode);

        string[] memory args = new string[](2);
        args[0] = amountdTsla.toString();
        args[1] = amountTslaInUsdc.toString();
        req.setArgs(args);

        requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requestIdToRequest[requestId] = dTSLARequest(amountdTsla, msg.sender, MintOrRedeem.redeem);

        _burn(msg.sender, amountdTsla);
    }

    function _redeemFulFillRequest(bytes32 requestId, bytes memory response) internal {
        uint256 usdcAmount = uint256(bytes32(response));
        uint256 usdcAmountWad;
        if (i_redemptionCoinDecimals < 18) {
            usdcAmountWad = usdcAmount * (10 ** (18 - i_redemptionCoinDecimals));
        }
        if (usdcAmount == 0) {
            // revert dTSLA__RedemptionFailed();
            // Redemption failed, we need to give them a refund of dTSLA
            // This is a potential exploit, look at this line carefully!!
            uint256 amountOfdTSLABurned = s_requestIdToRequest[requestId].amountOfToken;
            _mint(s_requestIdToRequest[requestId].requester, amountOfdTSLABurned);
            return;
        }

        s_userToWithdrawlAmount[s_requestIdToRequest[requestId].requester] += usdcAmount;
    }

    function withdraw() external {
        uint256 amountToWithdraw = s_userToWithdrawlAmount[msg.sender];
        s_userToWithdrawlAmount[msg.sender] = 0;

        bool success = ERC20(SEPOLIA_USDC).transfer(msg.sender, amountToWithdraw);
        if (!success) {
            revert dTSLA__TransferFailed();
        }
    }

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory)
        /**
         * err
         */
        internal
        override
    {
        if (s_requestIdToRequest[requestId].mintOrRedeem == MintOrRedeem.mint) {
            _mintFulFillRequest(requestId, response);
        } else {
            _redeemFulFillRequest(requestId, response);
        }
    }

    function __getCollateralRatioAdjustedTotalBalance(uint256 amountOfTokensToMint) internal view returns (uint256) {
        uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(amountOfTokensToMint);
        return (calculatedNewTotalValue * COLLATERAL_RATIO) / COLLATERAL_PRECISION;
    }

    ///The new expected total value in USD of all the dTSLA tokens combined
    function getCalculatedNewTotalValue(uint256 amountOfTokensToMint) internal view returns (uint256) {
        // 10 dtsla tokens + 5 dtsla tokens = 15 dtsla tokens * ( 100 )price of tsla = 1500 expected balance in bank acc
        return ((totalSupply() + amountOfTokensToMint) * getTslaPrice()) / PRECISION;
    }

    function getUsdcValueOfUsd(uint256 usdAmount) public view returns (uint256) {
        return usdAmount * getUsdcPrice() / PRECISION;
    }

    function getUsdValueOfTsla(uint256 tslaAmount) public view returns (uint256) {
        return tslaAmount * getTslaPrice() / PRECISION;
    }

    function getTslaPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_TSLA_PRICE_FEED);
        (, int256 price,,,) = OracleLib.staleCheckLatestRoundData(priceFeed);
        return uint256(price) * ADDITIONAL_FEE_PRECISION;
    }

    function getUsdcPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_USDC_PRICE_FEED);
        (, int256 price,,,) = OracleLib.staleCheckLatestRoundData(priceFeed);
        return uint256(price) * ADDITIONAL_FEE_PRECISION;
    }

    // VIEW & PURE FUNCTIONS

    function getRequest(bytes32 requestId) public view returns (dTSLARequest memory) {
        return s_requestIdToRequest[requestId];
    }

    function getPendingWithdrawlAmount(address user) public view returns (uint256) {
        return s_userToWithdrawlAmount[user];
    }

    function getPortfolioBalance() public view returns (uint256) {
        return s_portfolioBalance;
    }

    function getSubId() public view returns (uint64) {
        return i_subId;
    }

    function getMintSourceCode() public view returns (string memory) {
        return s_mintSourceCode;
    }

    function getRedeemSourceCode() public view returns (string memory) {
        return s_redeemSourceCode;
    }

    function getCollateralRatio() public pure returns (uint256) {
        return COLLATERAL_RATIO;
    }

    function getCollateralPrecision() public pure returns (uint256) {
        return COLLATERAL_PRECISION;
    }
}
