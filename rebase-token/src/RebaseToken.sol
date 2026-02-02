// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author baditu
 * @notice This is a cross-chain rebase token that incentivizes users to deposit into a vault and gain interest in rewards
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositing
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 interestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    mapping(address => uint256) private s_userInterestRates;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints new tokens for a user
     * @param _to The address of the user
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burns tokens from a user
     * @param _from The address of the user
     * @param _amount The amount of tokens to burn
     * @dev This function does not update the user's interest rate or last updated timestamp
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Sets a new interest rate
     * @param _newInterestRate The new interest rate to be set
     * @dev The interest rate can only be decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the balance of a user including accrued interest
     * @param _user The address of the user
     * @return The balance of the user including accrued interest
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principle balance of the user (the number of tokens that have actually been minted to the user)
        // multiply the principle balance by interest rate that has accumulated since the last update
        uint256 currentPrincipalBalance = super.balanceOf(_user);
        if (currentPrincipalBalance == 0) {
            return 0;
        }
        return currentPrincipalBalance * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfers tokens from one user to another
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     * @dev This function updates the interest rates and last updated timestamps for both the sender and recipient
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[msg.sender];
        }

        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfers tokens from one user to another
     * @param _from The address of the sender
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     * @dev This function updates the interest rates and last updated timestamps for both the sender and recipient
     */
    function transferFrom(address _from, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_from);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[_from];
        }

        return super.transferFrom(_from, _recipient, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints accrued interest to a user
     * @param _user The address of the user
     * @dev This function calculates the interest that has accumulated since the last update and mints the tokens to the user
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens that have been minted to the user -> principle balance
        uint256 principleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user (2) - (1)
        uint256 tokensToMint = currentBalance - principleBalance;
        //set the users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // call _mint to mint the tokens to the user
        _mint(_user, tokensToMint);
    }

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                INTERNAL & PRIVATE VIEW & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate the interest that has accumulated since the last update
     * @param _user The address of the user
     * @return linearInterest The amount of interest that has accumulated
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        /*
         * @note: We need to calculate the interest that has accumulated since the last update
         * and this is going to be linear growth with time
         * @note: Example
         *     -> deposit = 10 tokens
         *     -> interest rate = 5%
         *     -> time elapsed = 2 seconds
         *     -> calculation: 10 + (10 * 5% * 2) => 10 * (1 + 5% + 2)
         */
        uint256 lastUpdatedTimestamp = s_userLastUpdatedTimestamp[_user];
        if (lastUpdatedTimestamp == 0) {
            return 0;
        }
        uint256 timeElapsed = block.timestamp - lastUpdatedTimestamp;
        linearInterest = PRECISION_FACTOR + (s_userInterestRates[_user] * timeElapsed);
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL & PUBLIC VIEW & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the current interest rate in the smart contract
     * @return The current interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Gets the interest rate for a specific user
     * @param _user The address of the user
     * @return The interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }

    /**
     * @notice Get the principle balance of user. This is the number of tokens that have currently been minted to the user, not including any interest
     * @param _user The address of the user
     * @return The principal balance of the user
     */
    function getPrincipleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }
}
