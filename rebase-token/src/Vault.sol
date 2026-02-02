// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    error Vault_RedeemFailed();

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(address _rebaseToken) {
        i_rebaseToken = IRebaseToken(_rebaseToken);
    }

    receive() external payable {}

    /**
     * @notice Deposits ETH into the vault and mints corresponding tokens for the user.
     * @dev This function is payable and can be called with ETH.
     */
    function deposit() external payable {
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeems tokens for ETH.
     * @param _amount The amount of tokens to redeem.
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");

        if (!success) {
            revert Vault_RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice Returns the address of the rebase token.
     * @return The address of the rebase token.
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
