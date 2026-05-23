// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBracketSwapHook {
    function setMatchLive(bytes32 matchId) external;
    function settleMatch(bytes32 matchId, address winningTeam, uint256 totalWinnerLiquidity, uint256 totalPot)
        external;
}
