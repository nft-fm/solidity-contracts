// SPDX-License-Identifier: MIT

import "./lib/Context.sol";
import "./lib/SafeMath.sol";
import "./lib/Ownable.sol";
import "./lib/ReentrancyGuard.sol";
import "./lib/ERC1155Holder.sol";
import "./NFTToken.sol";

pragma solidity 0.8.4;

contract Trade is Context, Ownable, ReentrancyGuard, ERC1155Holder {
	using SafeMath for uint256;

	constructor(address nftToken, address payable _ownerWallet) {
		NFT_TOKEN = NFT_FM(nftToken);
		ownerWallet = _ownerWallet;
		ownerRoyaltyPercent = 2;
	}

    NFT_FM private NFT_TOKEN;
	address payable ownerWallet;

	struct Item {
		address payable seller;
		uint256 nftID;
		uint256 price;
		bool sold;
	}

	mapping(uint256 => bool) public royaltySet;
	mapping(uint256 => uint8) private royaltyPercents;
	uint8 public ownerRoyaltyPercent;
	mapping(uint256 => Item) public items;
	uint256 public totalItems;

	// TODO other events that need emitting?
	// TODO what fields should be indexed?
	event NewItem(address seller, uint256 nftID, uint256 price);
	event Purchase(uint256 itemID, address seller, address buyer, uint256 nftID, uint256 price, uint256 royalties);

	function setOwnerWallet(address payable newOwner) public onlyOwner {
		ownerWallet = newOwner;
	}

	function setArtistRoyalties(uint256 nftID, uint8 percent) public {
		require(NFT_TOKEN.owners(nftID) == _msgSender(), "You do not own that NFT.");
		require(percent <= 50, "Royalties cannot be above 50%");
		royaltyPercents[nftID] = percent;
		royaltySet[nftID] = true;
	}

	function getArtistRoyalties(uint256 nftID) public view returns (uint8) {
		if (royaltySet[nftID])
			return royaltyPercents[nftID];
		else
			return 2;
	}

	function setOwnerRoyalties(uint8 percent) public onlyOwner {
		require(percent <= 50, "Royalties cannot be above 50%");
		ownerRoyaltyPercent = percent;
	}

	function sell(uint256 nftID, uint256 price) public nonReentrant {
		require(price > 0, "Price must be non-zero.");
		try NFT_TOKEN.safeTransferFrom(_msgSender(), address(this), nftID, 1, "") {
		} catch {
			revert("Seller must approve transfer of NFTs.");
		}
		items[totalItems] = Item(
			payable(_msgSender()),
			nftID,
			price,
			false
		);
		totalItems++;
		emit NewItem(_msgSender(), nftID, price);
	}

	// TODO function to un-stake nfts?
	// could that be abusable by the seller somehow?

	function buy(uint256 itemID) public payable nonReentrant {
		Item memory item = items[itemID];
		require(!item.sold, "That item has already been sold.");
		uint256 royaltyPercent = getArtistRoyalties(item.nftID);
		uint256 artistRoyalty = item.price.mul(royaltyPercent);
		uint256 cost = item.price.add(artistRoyalty);
		uint256 ownerRoyalty = cost.mul(ownerRoyaltyPercent);
		cost = cost.add(ownerRoyalty);
		require(msg.value == cost, "Exact change required.");
		item.seller.transfer(item.price);
		if (artistRoyalty != 0)
			payable(NFT_TOKEN.owners(item.nftID)).transfer(artistRoyalty);
		if (ownerRoyalty != 0)
			ownerWallet.transfer(ownerRoyalty);
		item.sold = true;
		emit Purchase(itemID, item.seller, _msgSender(), item.nftID, item.price, artistRoyalty);
	}
}