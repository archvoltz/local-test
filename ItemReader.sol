// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IItemIdOf {
    function itemIdOf(uint256 tokenId) external view returns (uint256);
}

/// @notice 動作確認用: NFT を受け取ったとき(onERC721Received の中)に itemIdOf を読んで記録する
/// @dev safePurchase が _safeMint より先に _setTokenURI を呼んでいれば、正しい itemId が読める
contract ItemReader {
    uint256 public seenItemId = type(uint256).max;

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        seenItemId = IItemIdOf(msg.sender).itemIdOf(tokenId);
        return this.onERC721Received.selector;
    }
}
