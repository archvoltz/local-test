// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

import "solady/src/utils/LibString.sol";

contract ERC721Extended is ERC721, ERC721Enumerable, Ownable {
    // Main
    error InsufficientBalance();
    error InvalidAssetId();
    error Unavailable();

    uint256 private _nextTokenId;
    uint256 private _price;
    uint256 private _totalItems;
    bool private _isActive;

    // ERC4906
    event MetadataUpdate(uint256 tokenId);

    //ERC7160Extended
    event BaseUriPinned(uint256 indexed index);
    event BaseUriUnpinned();

    error LockedForever();
    error BaseURINotExists();
    error BaseURINotFound();
    error BaseURINotPinned();

    string[] private _baseURIs;
    uint256 private _pinnedBaseURIIndex;
    bool _hasPinnedBaseURIIndex;
    bool public uriLocked;

    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) Ownable(msg.sender) {
        _nextTokenId = 0;
        _pinnedBaseURIIndex = 0;
    }

    mapping(uint256 => uint256) private _itemIds;
    mapping(uint256 => uint256) private _baseURIIndices;

    /**
     * ERC7160Extended
     */

    function baseURIs()
        external
        view
        returns (uint256 index, string[] memory, bool pinned)
    {
        return (_pinnedBaseURIIndex, _baseURIs, _hasPinnedBaseURIIndex);
    }

    function pinBaseURI(uint256 index) external onlyOwner {
        if (uriLocked) revert LockedForever();

        if (_baseURIs.length == 0 || _baseURIs.length <= index)
            revert BaseURINotExists();

        _pinnedBaseURIIndex = index;
        _hasPinnedBaseURIIndex = true;

        emit BaseUriPinned(index);
    }

    function unpinBaseURI() external onlyOwner {
        if (uriLocked) revert LockedForever();

        if (!_hasPinnedBaseURIIndex) revert BaseURINotPinned();

        _pinnedBaseURIIndex = 0;
        _hasPinnedBaseURIIndex = false;

        emit BaseUriUnpinned();
    }

    function addBaseURI(string memory uri, bool pinned) external onlyOwner {
        if (uriLocked) revert LockedForever();

        _baseURIs.push(uri);

        if (pinned) {
            _pinnedBaseURIIndex = _baseURIs.length - 1;
            _hasPinnedBaseURIIndex = true;
            emit BaseUriPinned(_baseURIs.length - 1);
        }
    }

    function _setTokenURI(uint256 tokenId, uint256 itemId) internal {
        _itemIds[tokenId] = itemId;
        _baseURIIndices[tokenId] = _pinnedBaseURIIndex;
        emit MetadataUpdate(tokenId);
    }

    /**
     * ERC7572
     */

    event ContractURIUpdated();

    string private _contractURI;

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function setContractURI(string memory newURI) external onlyOwner {
        _contractURI = newURI;
        emit ContractURIUpdated();
    }

    /**
     * Main
     */

    function price() public view returns (uint256) {
        return _price;
    }

    function totalItems() public view returns (uint256) {
        return _totalItems;
    }

    function isActive() public view returns (bool) {
        return _isActive;
    }

    function setIsActive(bool status) external onlyOwner {
        _isActive = status;
    }

    function balance() external view returns (uint256) {
        // Solidityでコントラクトの残高やアドレスそのものを扱うには、一度 address 型に変換する必要ある
        // balance(addressの標準プロパ): アドレスのイーサ残高
        return address(this).balance;
    }

  
    function safePurchase(address to, uint256 itemId) public payable {
        if (msg.value < _price) revert InsufficientBalance();

        if (itemId > _totalItems) revert InvalidAssetId();

        if (!_isActive) revert Unavailable();

        uint256 tokenId = _nextTokenId++;

        // 受け取り側の onERC721Received から itemIdOf などを読めるよう、先に記録する
        _setTokenURI(tokenId, itemId);
        // erc721
        _safeMint(to, tokenId);
    }

    function itemIdOf(uint256 tokenId) external view returns (uint256) {
        _requireOwned(tokenId);
        return _itemIds[tokenId];
    }

    function baseURIIndexOf(uint256 tokenId) external view returns (uint256) {
        _requireOwned(tokenId);
        return _baseURIIndices[tokenId];
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        _requireOwned(tokenId);

        uint256 itemId = _itemIds[tokenId];
        uint256 baseUriIndex = _baseURIIndices[tokenId];

        string memory baseUri = _baseURIs[baseUriIndex];

        return
            bytes(baseUri).length != 0
                ? string(abi.encodePacked(baseUri, LibString.toString(itemId)))
                : "";
    }

    function setTotalItems(uint256 number) external onlyOwner {
        _totalItems = number;
    }

    function setPrice(uint256 newPrice) external onlyOwner {
        _price = newPrice;
    }

    function withdraw() external onlyOwner {
        // 'transfer' is deprecated and scheduled for removal. Use 'call{value: <amount>}("")' instead.
        //  payable(owner()).transfer(address(this).balance);

        (bool success, ) = payable(owner()).call{value: address(this).balance}(
            ""
        );
        if (!success) revert WithdrawFailed(); // 送金が成功し
    }

    function lockURI() external onlyOwner {
        uriLocked = true;
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
