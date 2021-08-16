// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

/**
@title Dividend-Paying Token Interface
@author Roger Wu (https://github.com/roger-wu)
@dev An interface for a dividend-paying token contract.
*/
interface IDividendPayingToken {
    /// @notice View the amount of dividend in wei that an address can withdraw.
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` can withdraw.
    function dividendOf(address _owner) external view returns (uint256);

    /// @notice Distributes bnb to token holders as dividends.
    /// @dev SHOULD distribute the paid bnb to token holders as dividends.
    ///  SHOULD NOT directly transfer bnb to token holders in this function.
    ///  MUST emit a `DividendsDistributed` event when the amount of distributed bnb is greater than 0.
    function distributeDividends() external payable;

    /// @notice Withdraws the bnb distributed to the sender.
    /// @dev SHOULD transfer `dividendOf(msg.sender)` wei to `msg.sender`, and `dividendOf(msg.sender)` SHOULD be 0 after the transfer.
    ///  MUST emit a `DividendWithdrawn` event if the amount of bnb transferred is greater than 0.
    function withdrawDividend() external;

    /// @dev This event MUST emit when bnb is distributed to token holders.
    /// @param from The address which sends bnb to this contract.
    /// @param weiAmount The amount of distributed bnb in wei.
    event DividendsDistributed(address indexed from, uint256 weiAmount);

    /// @dev This event MUST emit when an address withdraws their dividend.
    /// @param to The address which withdraws bnb from this contract.
    /// @param weiAmount The amount of withdrawn bnb in wei.
    event DividendWithdrawn(address indexed to, uint256 weiAmount);
}
