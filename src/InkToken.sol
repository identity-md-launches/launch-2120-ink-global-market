// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Ink Global Market (INK)
/// @notice A fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract InkToken is ERC20 {
    /// @notice One billion INK, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer.
    /// @dev When created by a factory, that factory receives the supply.
    constructor() ERC20("Ink Global Market", "INK") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
