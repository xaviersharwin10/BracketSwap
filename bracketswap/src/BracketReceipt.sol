// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @notice ERC-721 receipt representing a winning LP position awaiting redemption into the next pool.
/// Escrow is keyed by receiptId — entitlement travels with the NFT when transferred.
contract BracketReceipt is ERC721 {
    struct ReceiptData {
        bytes32 matchId;
        address winningTeam;
        uint256 usdcEntitlement; // USDC held in escrow for this receipt
        uint8 tournamentRound;
        bool redeemed;
    }

    address public admin;
    address public router; // set once via setRouter after deploy

    mapping(uint256 => ReceiptData) public receipts;
    uint256 public nextReceiptId;

    error NotRouter();
    error AlreadyRedeemed();

    modifier onlyRouter() {
        if (msg.sender != router) revert NotRouter();
        _;
    }

    constructor() ERC721("BracketSwap Receipt", "BSR") {
        admin = msg.sender;
    }

    function setRouter(address _router) external {
        require(msg.sender == admin && router == address(0), "BracketReceipt: already set");
        router = _router;
    }

    /// @notice Mint a receipt for a winner who chose the receipt path (deferred redemption).
    function mint(address to, bytes32 matchId, address winningTeam, uint256 usdcEntitlement, uint8 tournamentRound)
        external
        onlyRouter
        returns (uint256 receiptId)
    {
        receiptId = nextReceiptId++;
        receipts[receiptId] = ReceiptData({
            matchId: matchId,
            winningTeam: winningTeam,
            usdcEntitlement: usdcEntitlement,
            tournamentRound: tournamentRound,
            redeemed: false
        });
        _mint(to, receiptId);
    }

    /// @notice Mark a receipt as redeemed (router calls this after processing redemption).
    function markRedeemed(uint256 receiptId) external onlyRouter {
        if (receipts[receiptId].redeemed) revert AlreadyRedeemed();
        receipts[receiptId].redeemed = true;
        _burn(receiptId);
    }

    function getReceipt(uint256 receiptId) external view returns (ReceiptData memory) {
        return receipts[receiptId];
    }
}
