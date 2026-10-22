// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface IOwnable {
    function owner() external view returns (address);
}
contract Store is Ownable {
    struct Series {
        uint256 id;
        address contractAddress;
        string name;
        address creator;
        uint256 seriesId;
        uint256 version;
        bool isLatest;
        string releaseMetadata;
    }
    error SeriesNotFound(uint256 id);
    error InvalidContractAddress();
    error MismatchedSeries(uint256 oldId, uint256 newId);
    error NotAContract(address account);
    error DuplicateVersion(uint256 seriesId, uint256 version);
    event ContractURIUpdated(); // ERC7572
    event SeriesRegistered(
        uint256 indexed id,
        address indexed contractAddress,
        bool indexed isLatest
    );

    event SeriesRemoved(
        uint256 indexed seriesId,
        address indexed contractAddress
    );

    event SeriesLatestStatusUpdated(
        uint256 indexed id,
        uint256 indexed seriesId,
        bool indexed isLatest
    );

    uint256 private _nextId;
    mapping(uint256 => Series) private _series;
    mapping(uint256 => bool) private _exists;

    uint256[] private _ids;
    mapping(uint256 => uint256) private _indices;

    uint256[] private _latestIds;
    mapping(uint256 => uint256) private _latestIndices;

    mapping(uint256 => uint256[]) private _seriesBySeriesId;

    // seriesId => version => 登録済みか
    mapping(uint256 => mapping(uint256 => bool)) private _versionTaken;

    constructor() Ownable(msg.sender) {}

    string private _contractURI; // ERC7572

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function setContractURI(string memory newURI) external onlyOwner {
        _contractURI = newURI;
        emit ContractURIUpdated();
    }

    function registerSeries(
        address contractAddress,
        uint256 seriesId,
        uint256 version,
        bool isLatest,
        string memory releaseMetadata
    ) external onlyOwner returns (uint256 id) {
        if (contractAddress == address(0)) revert InvalidContractAddress();
        // EOA だと下の name() / owner() が理由なしで revert するので、先にわかるエラーで止める
        if (contractAddress.code.length == 0) revert NotAContract(contractAddress);
        if (_versionTaken[seriesId][version]) revert DuplicateVersion(seriesId, version);
        _versionTaken[seriesId][version] = true;

        id = _nextId++;
        string memory name = IERC721Metadata(contractAddress).name();
        address creator = IOwnable(contractAddress).owner();

        _series[id] = Series({
            id: id,
            contractAddress: contractAddress,
            name: name,
            creator: creator,
            seriesId: seriesId,
            version: version,
            isLatest: isLatest,
            releaseMetadata: releaseMetadata
        });

        _exists[id] = true;
        _seriesBySeriesId[seriesId].push(id);
        _indices[id] = _ids.length;
        _ids.push(id);
        if (isLatest) {
            _addLatest(id);
        }
        emit SeriesRegistered(id, contractAddress, isLatest);
    }

    function setLatestStatus(uint256 id, bool isLatest) external onlyOwner {
        Series storage series = _getExistingSeriesStorage(id);
        if (series.isLatest == isLatest) {
            return;
        }
        series.isLatest = isLatest;
        if (isLatest) {
            _addLatest(id);
        } else {
            _removeLatest(id);
        }

        emit SeriesLatestStatusUpdated(id, series.seriesId, isLatest);
    }
    function getSeries() external view returns (Series[] memory series) {
        uint256 length = _ids.length;
        series = new Series[](length);

        for (uint256 i = 0; i < length; i++) {
            series[i] = _series[_ids[i]];
        }
    }

    function getLatestSeries() external view returns (Series[] memory series) {
        uint256 length = _latestIds.length;
        series = new Series[](length);
        for (uint256 i = 0; i < length; i++) {
            series[i] = _series[_latestIds[i]];
        }
    }

    function getSeriesById(uint256 id) external view returns (Series memory) {
        return _getExistingSeries(id);
    }

    function getSeriesBySeriesId(
        uint256 seriesId
    ) external view returns (Series[] memory series) {
        // 要修正
        uint256[] storage selectedSeries = _seriesBySeriesId[seriesId];
        uint256 length = selectedSeries.length;
        series = new Series[](length);

        for (uint256 i = 0; i < length; i++) {
            series[i] = _series[selectedSeries[i]];
        }
    }

    function SeriesCount() external view returns (uint256) {
        return _ids.length;
    }

    function exists(uint256 id) external view returns (bool) {
        return _exists[id];
    }
    function _addLatest(uint256 id) internal {
        _latestIndices[id] = _latestIds.length;
        _latestIds.push(id);
    }

    function _removeLatest(uint256 id) internal {
        uint256 index = _latestIndices[id];
        uint256 lastIndex = _latestIds.length - 1;

        if (index != lastIndex) {
            uint256 lastSeriesId = _latestIds[lastIndex];

            _latestIds[index] = lastSeriesId;
            _latestIndices[lastSeriesId] = index;
        }
        _latestIds.pop();
        delete _latestIndices[id];
    }

    function _versionUp(uint256 oldId, uint256 newId) internal onlyOwner {
        if (oldId == newId) {
            return;
        }

        Series storage oldSeries = _getExistingSeriesStorage(oldId);
        Series storage newSeries = _getExistingSeriesStorage(newId);

        if (oldSeries.seriesId != newSeries.seriesId) {
            revert MismatchedSeries(oldId, newId);
        }

        _removeLatest(oldId);
        _addLatest(newId);

        newSeries.isLatest = true;
        oldSeries.isLatest = false;
    }

    function _getExistingSeries(
        uint256 id
    ) internal view returns (Series memory) {
        if (!_exists[id]) {
            revert SeriesNotFound(id);
        }
        return _series[id];
    }

    function _getExistingSeriesStorage(
        uint256 id
    ) internal view returns (Series storage series) {
        if (!_exists[id]) {
            revert SeriesNotFound(id);
        }
        return _series[id];
    }

    function _requireExistingSeries(uint256 id) internal view {
        if (!_exists[id]) {
            revert SeriesNotFound(id);
        }
    }
}
