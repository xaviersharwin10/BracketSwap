// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IBracketSwapHook} from "./interfaces/IBracketSwapHook.sol";

/// @notice Admin-controlled oracle for demo. In production, replace with Chainlink sports feed.
contract MockOracle {
    address public admin;
    IBracketSwapHook public hook;

    error NotAdmin();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor(address _hook) {
        admin = msg.sender;
        hook = IBracketSwapHook(_hook);
    }

    function setMatchLive(bytes32 matchId) external onlyAdmin {
        hook.setMatchLive(matchId);
    }

    function settleMatch(bytes32 matchId, address winningTeam, uint256 totalWinnerLiquidity, uint256 totalPot)
        external
        onlyAdmin
    {
        hook.settleMatch(matchId, winningTeam, totalWinnerLiquidity, totalPot);
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }
}
