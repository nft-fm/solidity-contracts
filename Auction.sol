// SPDX-License-Identifier: MIT

import "./lib/ReentrancyGuard.sol";
import "./lib/Context.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";
import "./lib/IERC1155.sol";
import "./lib/ERC1155Holder.sol";
import "./INFTSale.sol";

pragma solidity 0.8.4;

struct AuctionLot {
    uint256 startTime;
    uint256 endTime;
    uint256 nftID;
    uint256 bidIncrementPercent;
    address payable currentBidder;
    uint256 currentBid;
    bool firstBid;
}

contract Auction is Context, Ownable, ReentrancyGuard, ERC1155Holder, INFTSale {
    using SafeMath for uint256;

    constructor(address nftToken) {
        NFT_TOKEN = IERC1155(nftToken);
        nftAddress = nftToken;
    }

    address public nftAddress;
    IERC1155 private NFT_TOKEN;

    mapping(uint256 => AuctionLot) public lots;
    uint256 public totalLots;

    event NewLot(
        uint256 indexed lotID,
        address creator,
        uint256 startTime,
        uint256 endTime,
        uint256 nftID,
        uint256 startPrice,
        uint256 bidIncrementPercent
    );
    event Bid();

    function stake(
        uint256 nftID,
        address payable artist,
        uint32 quantity,
        uint256 price,
        uint256 startTime,
        bytes calldata data
    ) override public nonReentrant {
        require(
            _msgSender() == nftAddress,
            "Can only stake via NFT_FM contract."
        );
        require(quantity == 1, "Cannot put more than 1 NFT up for auction.");
        uint256 endTime;
        uint256 bidIncrementPercent;
        (endTime, bidIncrementPercent) = abi.decode(data, (uint256, uint256));
        require(endTime > startTime, "Bad timestamps.");
        require(endTime > block.timestamp, "Bad timestamps.");
        totalLots++;
        lots[totalLots] = AuctionLot(startTime, endTime, nftID, bidIncrementPercent, artist, price, true);
        emit NewLot(totalLots, artist, startTime, endTime, nftID, price, bidIncrementPercent);
    }

    function bid(uint256 lotID) payable public nonReentrant {
        AuctionLot memory lot = lots[lotID];
        require(lot.nftID != 0, "No lot exists with that ID.");
        require(block.timestamp > lot.startTime, "Auction has not started yet.");
        require(block.timestamp < lot.endTime, "Auction has completed.");
        if (lot.firstBid) {
            require(msg.value > lot.currentBid, "Must bid at least the minimum starting bid.");
        } else {
            uint256 increment = lot.currentBid.mul(lot.bidIncrementPercent).div(100);
            require(msg.value > lot.currentBid.add(increment), "Must bid more than current highest bid + increment.");
            lot.currentBidder.transfer(lot.currentBid); // refund previous bidder
        }
        lot.currentBidder = payable(_msgSender());
        lot.currentBid = msg.value;
    }

    function getCurrentMinBid(uint256 lotID) public view returns (uint256) {
        AuctionLot memory lot = lots[lotID];
        uint256 increment = lot.currentBid.mul(lot.bidIncrementPercent).div(100);
        return lot.currentBid.add(increment);
    }

    // TODO how to get a function to run at a specific time? (auction endTime)
    function payout(uint256 lotID) public nonReentrant {
        AuctionLot memory lot = lots[lotID];
        //require(lot.rewardID != 0, "No lot exists with that ID.");
        require(block.timestamp > lot.endTime, "Auction has not completed yet.");
        require(lot.currentBidder != address(0), "Reward has already been paid.");
        NFT_TOKEN.safeTransferFrom(address(this), lot.currentBidder, lot.nftID, 1, "");
        lots[lotID].currentBidder = payable(address(0));
    }
}