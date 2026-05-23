// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Team outcome token (e.g., BRA_WIN, GER_WIN) paired with USDC in a BracketSwap pool.
contract OutcomeToken is ERC20, Ownable {
    constructor(string memory name, string memory symbol, address minter) ERC20(name, symbol) Ownable(minter) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
