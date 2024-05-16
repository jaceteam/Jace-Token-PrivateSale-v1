// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title JaceTokenPrivateSaleV1
 * @dev $JACE TokenPrivateSale contract V1
 * @notice This contract facilitates the sale of $JACE tokens.
 * @author Jace.Team
 * @notice For more information, visit https://jace.team
 * @notice For support or inquiries, contact dev@jace.team
 */
contract JaceTokenPrivateSaleV1 is ReentrancyGuard {

    // SafeERC20 is a library from OpenZeppelin Contracts, ensuring safe ERC20 token transfers.
    using SafeERC20 for IERC20;

    // ChainLink BNB-USD price feed.
    AggregatorV3Interface internal priceFeed;

    // JACE token contract instance.
    IERC20 constant jaceToken = IERC20(0x0305ce989f3055a6Da8955fc52b615b0086A2157);

    // USDT token contract instance.
    IERC20 constant usdtToken = IERC20(0x55d398326f99059fF775485246999027B3197955); 

    // Jace company's fund wallet address.
    address constant jaceCompanyFundWallet = 0xF8c6D7E3fAcbd67C687eD6d1F9499E98eEed7e19;

    // Admin address.
    address constant admin = 0xC523bed68D08dbC411edE8ffBE4A9444eA19488C;
    
    // JACE token price in USD denominated in wei.
    uint constant jaceUSDPriceInWei = 120000000000000000; // $0.12

    // Tolerance percentage for BNB price fluctuations to buy JACE.
    uint constant bnbPriceTolerance = 5; // 5% 

    // Lockup period for JACE tokens before users can claim purchased tokens, measured in days.
    uint constant tokenLockupPeriodDays = 730; // 730 days

    // Timestamp indicating the start time of the token sale.
    uint immutable startTime;

    // Timestamp marking the end time of the token sale.
    uint immutable endTime;

    // This variable represents the total amount of Jace tokens deposited by the admin, denominated in wei.
    uint totalDepositedJaceToken;

    // Minimum amount of JACE tokens that a user can buy, denominated in wei.
    uint minBuyJaceInWei = 5000000000000000000000; // 5,000 JACE

    // Maximum amount of JACE tokens that a user can buy, denominated in wei.
    uint maxBuyJaceInWei = 500000000000000000000000; // 500,000 JACE

    // Total amount of JACE tokens bought by users, measured in wei.
    uint totalBoughtJaceInWei = 0;

    // Flag indicating whether the token sale is active.
    bool isTokenSaleActive = true;

    // Flag indicating whether buying tokens with BNB (Binance Coin) is enabled.
    bool enableBuyWithBNB = true;

    // Flag indicating whether buying tokens with USDT (Tether) is enabled.
    bool enableBuyWithUSDT = true;

    // Struct to represent vesting details for each user.
    struct Vesting {
        // Total amount of JACE tokens bought by the user, denominated in wei.
        uint totalBoughtJace;

        // Duration in days for which the tokens are locked up before they can be claimed.
        uint lockupPeriod;

        // Cumulative amount of JACE tokens claimed by the user up to the current point in time.
        uint totalClaimed;
    }

    // Mapping to associate each user's address with their Vesting details.
    mapping(address => Vesting) userVesting;

    // Represents a whitelist of addresses eligible to participate in the token sale.
    mapping(address => bool) private _tokenSaleWhitelist;

    // Event emitted when a new address is successfully added to the whitelist, indicating eligibility for participation in the token sale.
    event AddressAddedToWhitelist(address indexed newAddress);

    // Event emitted when the value of the minBuyJaceInWei is updated.
    event MinBuyJaceInWeiUpdated(uint indexed newMinBuyJaceInWei);

    // Event emitted when the value of the maxBuyJaceInWei is updated.
    event MaxBuyJaceInWeiUpdated(uint indexed newMaxBuyJaceInWei);

    // Event emitted when the status of the tokenSale is updated.
    event TokenSaleStatusUpdated(bool indexed newStatus);

    // Event emitted when a buyer purchases JACE tokens with BNB.
    event JaceBoughtWithBNB(address indexed buyer, uint amountBNB, uint amountJace);

    // Event emitted when a buyer purchases JACE tokens with USDT.
    event JaceBoughtWithUSDT(address indexed buyer, uint amountUSDT, uint amountJace);

    // Event emitted when a user successfully claims their JACE tokens after the lockup period.
    event JaceTokensClaimed(address indexed recipient, uint amountJace);

    // Event emitted when the admin withdraws the remaining JACE tokens after the tokenSale has ended.
    event RemainingJaceTokensWithdrawByAdmin(address indexed withdrawAddress, uint withdrawAmount);

    // Event emitted when the admin withdraws the contract's BNB balance.
    event ContractBalanceWithdrawnByAdmin(address indexed recipient, uint amount);

    // Event emitted when the option to buy tokens with BNB (Binance Coin) is enabled or disabled.
    event BuyWithBNBUpdated(bool isEnabled);

    // Event emitted when the option to buy tokens with USDT (Tether) is enabled or disabled.
    event BuyWithUSDTUpdated(bool isEnabled);

    // Event emitted when the admin deposits Jace tokens into the contract.
    event JaceTokensDepositedByAdmin(address indexed admin, uint JaceAmount);

    // Event emitted when the ChainLink price feed contract address is updated.
    event PriceFeedContractAddressUpdated(address indexed newAddress);

    constructor(uint _startTime, uint _endTime) {
        startTime = _startTime;
        endTime = _endTime;
        priceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);
    }

    // Modifier to restrict access exclusively to the admin.
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }

    // Modifier to restrict access to functions only to addresses present in the whitelist.
    modifier onlyWhitelisted() {
        require(isWhitelisted(msg.sender), "Address is not whitelisted");
        _;
    }

    // Allows the admin to deposit a specified amount of JACE tokens into the contract.
    function depositJaceTokensByAdmin(uint _jaceAmount) external onlyAdmin {
        uint contractAllowance = jaceToken.allowance(msg.sender, address(this));
        require(contractAllowance >= _jaceAmount, "Not enough allowance");

        jaceToken.safeTransferFrom(msg.sender, address(this), _jaceAmount);

        totalDepositedJaceToken = _jaceAmount;

        emit JaceTokensDepositedByAdmin(msg.sender, _jaceAmount);
    }

    // Function to purchase JACE tokens with Binance coin (BNB), necessitating that the sender is whitelisted.
    function buyJaceWithBNB() external payable nonReentrant onlyWhitelisted returns (bool) {
        require(enableBuyWithBNB, "Not allowed to buy with BNB");

        require(isTokenSaleActive, "TokenSale is not active");

        require(msg.value > 0, "Invalid BNB amount");

        require(startTime <= block.timestamp, "The token sale has not yet begun");
        require(endTime > block.timestamp, "The token sale has ended");

        uint jaceInWei = getJaceInWeiBasedOnBNBAmount(msg.value);
        require(jaceInWei >= minBuyJaceInWei - (minBuyJaceInWei * bnbPriceTolerance / 100), "JACE amount is below minimum");
        require(jaceInWei <= maxBuyJaceInWei + (minBuyJaceInWei * bnbPriceTolerance / 100), "JACE amount exceeds maximum");

        require(getRemainingJaceTokensToSell() >= jaceInWei, "Insufficient JACE tokens available for sale");

        require(userVesting[msg.sender].totalBoughtJace + jaceInWei <= maxBuyJaceInWei, "JACE amount exceeds maximum");

        (bool success, ) = payable(jaceCompanyFundWallet).call{value: msg.value}("");
        require(success, "BNB Payment failed");

        if (userVesting[msg.sender].totalBoughtJace > 0) {
            userVesting[msg.sender].totalBoughtJace += jaceInWei;
        } else {
            userVesting[msg.sender] = Vesting(
                jaceInWei,
                block.timestamp + (tokenLockupPeriodDays * 1 days),
                0
            );
        }

        totalBoughtJaceInWei += jaceInWei;

        emit JaceBoughtWithBNB(msg.sender, msg.value, jaceInWei); 

        return true;
    }

    // Function allowing the purchase of JACE tokens with Tether (USDT), with the condition that the sender is whitelisted.
    function buyJaceWithUSDT(uint _usdtAmountInWei) external nonReentrant onlyWhitelisted returns (bool) {
        require(enableBuyWithUSDT, "Not allowed to buy with USDT");

        require(isTokenSaleActive, "TokenSale is not active");

        require(_usdtAmountInWei > 0, "Invalid USDT amount");

        require(startTime <= block.timestamp, "The token sale has not yet begun");
        require(endTime > block.timestamp, "The token sale has ended");

        uint jaceInWei = getJaceInWeiBasedOnUSDTAmount(_usdtAmountInWei);
        require(jaceInWei >= minBuyJaceInWei, "JACE amount is below minimum");
        require(jaceInWei <= maxBuyJaceInWei, "JACE amount exceeds maximum");

        require(getRemainingJaceTokensToSell() >= jaceInWei, "Insufficient JACE tokens available for sale");

        require(userVesting[msg.sender].totalBoughtJace + jaceInWei <= maxBuyJaceInWei, "JACE amount exceeds maximum");

        uint contractAllowance = usdtToken.allowance(msg.sender, address(this));
        require(contractAllowance >= _usdtAmountInWei, "Make sure to add enough allowance");

        require(usdtToken.balanceOf(msg.sender) >= _usdtAmountInWei, "Insufficient USDT balance");

        usdtToken.safeTransferFrom(msg.sender, jaceCompanyFundWallet, _usdtAmountInWei);

        if (userVesting[msg.sender].totalBoughtJace > 0) {
            userVesting[msg.sender].totalBoughtJace += jaceInWei;
        } else {
            userVesting[msg.sender] = Vesting(
                jaceInWei,
                block.timestamp + (tokenLockupPeriodDays * 1 days),
                0
            );
        }

        totalBoughtJaceInWei += jaceInWei;

        emit JaceBoughtWithUSDT(msg.sender, _usdtAmountInWei, jaceInWei); 

        return true;
    }

    // Function permitting the claiming of JACE tokens once the lockup period has elapsed, with the prerequisite that the sender is whitelisted.
    function claimJaceTokens() external nonReentrant onlyWhitelisted {
        require(userVesting[msg.sender].totalBoughtJace > 0, "Nothing to claim");
        require(userVesting[msg.sender].totalClaimed == 0, "Already claimed");
        require(userVesting[msg.sender].lockupPeriod <= block.timestamp, "Lockup period has not ended yet");

        userVesting[msg.sender].totalClaimed = userVesting[msg.sender].totalBoughtJace;
           
        jaceToken.safeTransfer(msg.sender, userVesting[msg.sender].totalBoughtJace);

        emit JaceTokensClaimed(msg.sender, userVesting[msg.sender].totalBoughtJace);
    }

    // This function retrieves essential details about the token sale, providing a comprehensive overview of the token sale parameters and status.
    function getTokenSaleDetails() external view
    returns (
        uint _startTime,
        uint _endTime,
        bool _isTokenSaleActive,
        uint _jaceUSDPriceInWei,
        uint _minBuyJaceInWei,
        uint _maxBuyJaceInWei,
        uint _tokenLockupPeriodDays,
        uint _contractJaceBalance,
        uint _totalBoughtJaceInWei,
        uint _remainingJaceTokensToSell,
        bool _enableBuyWithBNB,
        bool _enableBuyWithUSDT
    ) {
        return (
            startTime,
            endTime,
            isTokenSaleActive,
            jaceUSDPriceInWei,
            minBuyJaceInWei,
            maxBuyJaceInWei,
            tokenLockupPeriodDays,
            jaceToken.balanceOf(address(this)),
            totalBoughtJaceInWei,
            getRemainingJaceTokensToSell(),
            enableBuyWithBNB,
            enableBuyWithUSDT
        );
    }

    // Function to get the remaining JACE tokens available for sale, represented in wei.
    function getRemainingJaceTokensToSell() internal view returns (uint) {
        if (totalBoughtJaceInWei > totalDepositedJaceToken) {
            return 0;
        } else {
            return totalDepositedJaceToken - totalBoughtJaceInWei;
        }
    }

    // Function to get the user vesting details.
    function getUserVetsingDetails(address userAddr) external view returns (uint _totalBoughtJace, uint _totalClaimed, uint _lockupPeriod) {
        Vesting memory vestingInfo = userVesting[userAddr];
        _totalBoughtJace = vestingInfo.totalBoughtJace;
        _totalClaimed = vestingInfo.totalClaimed;
        _lockupPeriod = vestingInfo.lockupPeriod;

        return (_totalBoughtJace, _totalClaimed, _lockupPeriod);
    }

    // Function to get the maximum amount of JACE tokens a user can purchase.
    // It subtracts the total amount of JACE tokens already bought by the user from the maximum allowed purchase limit.
    function getMaxJaceTokenCanUserBuy(address userAddr) external view returns (uint) {
        uint maxJaceTokenCanUserBuy = maxBuyJaceInWei - userVesting[userAddr].totalBoughtJace;
        if (getRemainingJaceTokensToSell() < maxJaceTokenCanUserBuy) {
            maxJaceTokenCanUserBuy = getRemainingJaceTokensToSell();
        }

        return maxJaceTokenCanUserBuy;
    }

    // Function to get JACE in wei based on BNB amount in wei.
    // Converts a given amount of BNB in wei to an equivalent amount of JACE in wei.
    function getJaceInWeiBasedOnBNBAmount(uint _bnbAmountInWei) public view returns (uint) {
        uint jaceInWei = (_bnbAmountInWei * getBNBPrice()) / jaceUSDPriceInWei;

        return jaceInWei;
    }

    // Function to get JACE in wei based on USDT amount in wei.
    // Converts a given amount of USDT in wei to an equivalent amount of JACE in wei.
    function getJaceInWeiBasedOnUSDTAmount(uint _usdtAmountInWei) public pure returns (uint) {
        uint jaceInWei = _usdtAmountInWei * 10**18 / jaceUSDPriceInWei;

        return jaceInWei;
    }

    // Function to get BNB in wei based on JACE amount in wei.
    // Converts a given amount of JACE in wei to an equivalent amount of BNB in wei.
    function getBNBInWeiBasedOnJaceAmount(uint _jaceAmountInWei) public view returns (uint) {
        uint bnbInWei = getUSDTInWeiBasedOnJaceAmount(_jaceAmountInWei) * 10**18 / getBNBPrice();

        return bnbInWei;
    }

    // Function to get USDT in wei based on JACE amount in wei.
    // Converts a given amount of JACE in wei to an equivalent amount of USDT in wei.
    function getUSDTInWeiBasedOnJaceAmount(uint _jaceAmountInWei) public pure returns (uint) {
        uint usdtInWei = _jaceAmountInWei * jaceUSDPriceInWei / 10**18;

        return usdtInWei;
    }

    // Function to update the minimum buy amount of JACE in wei.
    // Allows only the admin to update the minimum buy amount of JACE, specified in wei.
    function updateMinBuyJaceInWei(uint _minBuyJaceInWei) external onlyAdmin {
        minBuyJaceInWei = _minBuyJaceInWei;
        emit MinBuyJaceInWeiUpdated(_minBuyJaceInWei);
    }

    // Function to update the maximum buy amount of JACE in wei.
    // Allows only the admin to update the maximum buy amount of JACE, specified in wei.
    function updateMaxBuyJaceInWei(uint _maxBuyJaceInWei) external onlyAdmin {
        maxBuyJaceInWei = _maxBuyJaceInWei;
        emit MaxBuyJaceInWeiUpdated(_maxBuyJaceInWei);
    }

    // Function to update the token sale status.
    // Allows only the admin to update the token sale status, setting it to either active or inactive.
    function updateTokenSaleStatus(bool _status) external onlyAdmin {
        isTokenSaleActive = _status;
        emit TokenSaleStatusUpdated(_status);
    }

    // Function to allow the admin to withdraw the remaining JACE tokens.
    // Requires that the token sale is not currently active.
    function withdrawRemainingTokens(address _to) external onlyAdmin {
        require (!isTokenSaleActive, "The token sale is currently activated");

        require(_to != address(0), "Invalid recipient address");

        uint withdrawAmount = getRemainingJaceTokensToSell();
        require(withdrawAmount > 0, "Nothing to transfer");

        jaceToken.safeTransfer(_to, withdrawAmount);

        emit RemainingJaceTokensWithdrawByAdmin(_to, withdrawAmount);
    }

    // Function to allow the admin to withdraw the entire BNB balance of the contract and transfer it to the Jace company's fund wallet address.
    function withdrawContractBalance() external onlyAdmin {
        uint withdrawAmount = address(this).balance;
        require(withdrawAmount > 0, "Nothing to withdraw");

        (bool success, ) = payable(jaceCompanyFundWallet).call{value: withdrawAmount}("");
        require(success, "BNB Payment failed");

        emit ContractBalanceWithdrawnByAdmin(admin, withdrawAmount);
    }

    // Function to check if an address is whitelisted.
    // Returns true if the address is whitelisted for the token sale, otherwise returns false.
    function isWhitelisted(address _address) public view returns (bool) {
        return _tokenSaleWhitelist[_address];
    }

    // Function to add an address to the whitelist for the token sale.
    // Requires that the address is not already whitelisted.
    function addToWhitelist(address _newAddress) external onlyAdmin {
        require(!_tokenSaleWhitelist[_newAddress], "Address is already whitelisted");
        
        _tokenSaleWhitelist[_newAddress] = true;
        emit AddressAddedToWhitelist(_newAddress);
    }

    // Function to enable or disable buying tokens with BNB (Binance Coin).
    // Allows only the admin to update the status.
    function buyWithBNBUpdateStatus(bool _isEnabled) external onlyAdmin {
        enableBuyWithBNB = _isEnabled;
        emit BuyWithBNBUpdated(_isEnabled);
    }

    // Function to enable or disable buying tokens with USDT (Tether).
    // Allows only the admin to update the status.
    function buyWithUSDTUpdateStatus(bool _isEnabled) external onlyAdmin {
        enableBuyWithUSDT = _isEnabled;
        emit BuyWithUSDTUpdated(_isEnabled);
    }

    // Allows the admin to update the address of the ChainLink price feed contract.
    function updatePriceFeedContractAddress(address _newPriceFeedAddress) external onlyAdmin {
        priceFeed = AggregatorV3Interface(_newPriceFeedAddress);
        emit PriceFeedContractAddressUpdated(_newPriceFeedAddress);
    }

    // Function to get the BNB price.
    function getBNBPrice() internal view returns (uint) {
        (, int256 price, , ,) = priceFeed.latestRoundData();
        price = (price * (10**10));

        return uint(price);
    }

    // Function to receive BNB. msg.data must be empty
    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}