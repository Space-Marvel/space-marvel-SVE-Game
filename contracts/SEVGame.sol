// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface ISEVCore {
    function exists(uint256 _id) external view returns (bool);

    function ownerOf(uint256 tokenId) external view returns (address);

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function evolve(uint256[] memory _nftIds, uint256 _newGene) external  returns (uint256); 

    function breed(
        address _toAddress,
        uint256 _nftId1,
        uint256 _nftId2,
        uint256 _gene
    ) external returns (uint256);
}

contract SEVGame is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserActive {
        address user;
        uint256 time;
        bool isLockEvolve;
    }

    struct UserRequest {
        address user;
        bool isEvolve;
        address nft;
        uint256[] nftIds;
    }

    struct Fee {
        IERC20 currency;
        uint256 amount;
        bool active;
    }

    /*
        active hero: 0
        active spaceship: 1
        breed: 2
        evolve: 3
    */

    mapping(uint8 => Fee) fees;

    mapping(uint256 => UserRequest) idToRequests;
    uint256 public currentRequestId;

    ISEVCore public nftHero;
    ISEVCore public nftSpaceShip;

    mapping(uint256 => UserActive) idToHeros;
    // mapping (address=>mapping (uint256=>UserActive)) idToNfts;
    mapping(uint256 => UserActive) idToSpaceShips;
    uint256 public durationActiveHero;
    uint256 public durationActiveSpaceShip;

    mapping(address => bool) whilelists;

    address public vault;

    event Active(
        address nftAddeess,
        uint256 nftId,
        address user,
        address feeContract,
        uint256 feeAmount,
        uint256 time
    );
    event Deactive(
        address nftAddeess,
        uint256 nftId,
        address user,
        uint256 time
    );

    constructor(
        ISEVCore _nftHero,
        ISEVCore _nftSpaceShip,
        uint256 _durationActiveHero,
        uint256 _durationActiveSpaceShip,
        address _vault
    ) {
        require(address(_nftHero) != address(0), "Error: NFT hero invalid");
        require(
            address(_nftSpaceShip) != address(0),
            "Error: NFT SpaceShip invalid"
        );

        require(_vault != address(0), "Error: Vault invalid");

        nftHero = _nftHero;
        nftSpaceShip = _nftSpaceShip;
        durationActiveHero = _durationActiveHero;
        durationActiveSpaceShip = _durationActiveSpaceShip;
        vault = _vault;
    }

    modifier onlyWhilelist() {
        require(whilelists[_msgSender()], "Error: only whilelist");
        _;
    }

    function setWhilelists(
        address[] memory _whilelists,
        bool[] memory _isWhilelists
    ) external onlyOwner {
        require(
            _whilelists.length == _isWhilelists.length,
            "Error: invalid input"
        );
        for (uint8 i = 0; i < _whilelists.length; i++) {
            whilelists[_whilelists[i]] = _isWhilelists[i];
        }
    }

    function setSEVHeroCore(ISEVCore _nftHero) external onlyOwner {
        require(address(_nftHero) != address(0), "Error: NFT Hero address(0)");
        nftHero = _nftHero;
    }

    function setSEVSpaceShipCore(ISEVCore _nftSpaceShip) external onlyOwner {
        require(
            address(_nftSpaceShip) != address(0),
            "Error: NFT SpaceShip address(0)"
        );
        nftSpaceShip = _nftSpaceShip;
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Error: Vault address(0)");
        vault = _vault;
    }

    function setFees(
        uint8 _id,
        IERC20 _currency,
        uint256 _amount,
        bool _active
    ) external onlyOwner {
        fees[_id] = Fee(_currency, _amount, _active);
    }

    function setDurationActiveHero(uint256 _durationActiveHero)
        external
        onlyOwner
    {
        durationActiveHero = _durationActiveHero;
    }

    function setDurationActiveSpaceShip(uint256 _durationActiveSpaceShip)
        external
        onlyOwner
    {
        durationActiveSpaceShip = _durationActiveSpaceShip;
    }

    function active(address _nftAddeess, uint256 _nftId)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        require(
            _nftAddeess == address(nftHero) ||
                _nftAddeess == address(nftSpaceShip),
            "Error: NFT contract invalid"
        );

        if (_nftAddeess == address(nftHero)) {
            require(nftHero.exists(_nftId), "Error: wrong nftId");
            require(
                nftHero.ownerOf(_nftId) == _msgSender(),
                "Error: you are not the owner"
            );

            //check active duration
            if (idToHeros[_nftId].user != address(0)) {
                require(
                    idToHeros[_nftId].time - block.timestamp >=
                        durationActiveHero,
                    "Error: wait to active"
                );
            }

            //transfer NFT for market contract
            nftHero.transferFrom(_msgSender(), address(this), _nftId);
            idToHeros[_nftId].user = _msgSender();
            idToHeros[_nftId].time = block.timestamp;

            //charge fee
            if (fees[0].active) {
                if (address(fees[0].currency) == address(0)) {
                    payable(vault).transfer(fees[0].amount);
                    //transfer BNB back to user if amount > fee
                    if (msg.value > fees[0].amount) {
                        payable(_msgSender()).transfer(
                            msg.value - fees[0].amount
                        );
                    }
                } else {
                    fees[0].currency.safeTransferFrom(
                        _msgSender(),
                        vault,
                        fees[0].amount
                    );
                    //transfer BNB back to user if currency is not address(0)
                    if (msg.value != 0) {
                        payable(_msgSender()).transfer(msg.value);
                    }
                }
            }

            emit Active(
                _nftAddeess,
                _nftId,
                _msgSender(),
                address(fees[0].currency),
                fees[0].amount,
                block.timestamp
            );
        } else {
            require(nftSpaceShip.exists(_nftId), "Error: wrong nftId");
            require(
                nftSpaceShip.ownerOf(_nftId) == _msgSender(),
                "Error: you are not the owner"
            );

            //check active duration
            if (idToSpaceShips[_nftId].user != address(0)) {
                require(
                    idToSpaceShips[_nftId].time - block.timestamp >=
                        durationActiveSpaceShip,
                    "Error: wait to active"
                );
            }

            //transfer NFT for market contract
            nftSpaceShip.transferFrom(_msgSender(), address(this), _nftId);
            idToSpaceShips[_nftId].user = _msgSender();
            idToSpaceShips[_nftId].time = block.timestamp;

            //charge fee
            if (fees[1].active) {
                if (address(fees[1].currency) == address(0)) {
                    payable(vault).transfer(fees[1].amount);
                    //transfer BNB back to user if amount > fee
                    if (msg.value > fees[1].amount) {
                        payable(_msgSender()).transfer(
                            msg.value - fees[1].amount
                        );
                    }
                } else {
                    fees[1].currency.safeTransferFrom(
                        _msgSender(),
                        vault,
                        fees[1].amount
                    );
                    //transfer BNB back to user if currency is not address(0)
                    if (msg.value != 0) {
                        payable(_msgSender()).transfer(msg.value);
                    }
                }
            }

            emit Active(
                _nftAddeess,
                _nftId,
                _msgSender(),
                address(fees[1].currency),
                fees[1].amount,
                block.timestamp
            );
        }
    }

    function deactive(address _nftAddeess, uint256 _nftId)
        external
        payable
        nonReentrant
    {
        require(
            _nftAddeess == address(nftHero) ||
                _nftAddeess == address(nftSpaceShip),
            "Error: NFT contract invalid"
        );

        if (_nftAddeess == address(nftHero)) {
            // require(nftHero.exists(_nftId), "Error: wrong nftId");

            require(
                idToHeros[_nftId].user == _msgSender(),
                "Error: you are not the owner"
            );
            require(!idToHeros[_nftId].isLockEvolve, "Error: lock for evolve");

            //transfer NFT for market contract
            nftHero.transferFrom(address(this), _msgSender(), _nftId);
            delete idToHeros[_nftId];
        } else {
            // require(nftSpaceShip.exists(_nftId), "Error: wrong nftId");

            require(
                idToSpaceShips[_nftId].user == _msgSender(),
                "Error: you are not the owner"
            );

            require(!idToHeros[_nftId].isLockEvolve, "Error: lock for evolve");

            //transfer NFT for market contract
            nftSpaceShip.transferFrom(address(this), _msgSender(), _nftId);
        }

        emit Deactive(_nftAddeess, _nftId, _msgSender(), block.timestamp);
    }

    event EvolveRequest(
        address user,
        uint256 requestId,
        address nft,
        uint256[] nftIds,
        uint256 time
    );

    function evolveRequest(address _nftAddeess, uint256[] memory _nftIds)
        external
        nonReentrant
    {
        require(_nftAddeess == address(nftHero), "Error: NFT contract invalid");

        for (uint256 i = 0; i < _nftIds.length; i++) {
            require(
                idToHeros[_nftIds[i]].user == _msgSender(),
                "Error: you are not the owner"
            );
            require(
                !idToHeros[_nftIds[i]].isLockEvolve,
                "Error: lock for evolve already"
            );
        }

        for (uint256 i = 0; i < _nftIds.length; i++) {
            idToHeros[_nftIds[i]].isLockEvolve = true;
        }

        idToRequests[currentRequestId] = UserRequest(
            _msgSender(),
            true,
            _nftAddeess,
            _nftIds
        );

        emit EvolveRequest(
            _msgSender(),
            currentRequestId,
            _nftAddeess,
            _nftIds,
            block.timestamp
        );

        currentRequestId += 1;
    }

    event EvolveProcess(
        uint256 requestId,
        address user,
        address nft,
        uint256[] nftIds,
        uint256 newNftId,
        uint256 time
    );

    function evolve(uint256 _requestId, uint256 _newGene)
        external
        onlyWhilelist
    {
        require(
            idToRequests[_requestId].user != address(0),
            "Error: request invalid"
        );

        require(idToRequests[_requestId].isEvolve, "Error: request invalid");

        uint256 newId = ISEVCore(idToRequests[_requestId].nft).evolve(
            idToRequests[_requestId].nftIds,
            _newGene
        );

        emit EvolveProcess(
            _requestId,
            idToRequests[_requestId].user,
            idToRequests[_requestId].nft,
            idToRequests[_requestId].nftIds,
            newId,
            block.timestamp
        );

        delete idToRequests[_requestId];
    }

    event BreedRequest(
        address user,
        uint256 id,
        address nft,
        uint256[] nftIds,
        uint256 time
    );

    function breedRequest(
        address _nftAddeess,
        uint256 _nftId1,
        uint256 _nftId2
    ) external payable nonReentrant {
        require(
            _nftAddeess == address(nftHero) ||
                _nftAddeess == address(nftSpaceShip),
            "Error: NFT contract invalid"
        );

        require(
            ISEVCore(_nftAddeess).ownerOf(_nftId1) == _msgSender(),
            "Error: you are not the owner"
        );

        require(
            ISEVCore(_nftAddeess).ownerOf(_nftId2) == _msgSender(),
            "Error: you are not the owner"
        );

        ISEVCore(_nftAddeess).transferFrom(
            _msgSender(),
            address(this),
            _nftId1
        );
        ISEVCore(_nftAddeess).transferFrom(
            _msgSender(),
            address(this),
            _nftId2
        );

        uint256[] memory ids = new uint256[](2);
        ids[0] = _nftId1;
        ids[1] = _nftId2;

        idToRequests[currentRequestId] = UserRequest(
            _msgSender(),
            false,
            _nftAddeess,
            ids
        );

        //charge fee
        if (fees[3].active) {
            if (address(fees[3].currency) == address(0)) {
                payable(vault).transfer(fees[3].amount);
                //transfer BNB back to user if amount > fee
                if (msg.value > fees[3].amount) {
                    payable(_msgSender()).transfer(msg.value - fees[3].amount);
                }
            } else {
                fees[3].currency.safeTransferFrom(
                    _msgSender(),
                    vault,
                    fees[3].amount
                );
                //transfer BNB back to user if currency is not address(0)
                if (msg.value != 0) {
                    payable(_msgSender()).transfer(msg.value);
                }
            }
        }
        emit BreedRequest(
            _msgSender(),
            currentRequestId,
            _nftAddeess,
            ids,
            block.timestamp
        );

        currentRequestId += 1;
    }

    event BreedProcess(
        uint256 requestId,
        address user,
        address nft,
        uint256[] nftIds,
        uint256 newNftId,
        uint256 time
    );

    function breedProcess(uint256 _requestId, uint256 _newGene)
        external
        onlyWhilelist
    {
        require(
            idToRequests[_requestId].user != address(0),
            "Error: request invalid"
        );

        require(!idToRequests[_requestId].isEvolve, "Error: request invalid");

        uint256 newNftId = ISEVCore(idToRequests[_requestId].nft).breed(
            idToRequests[_requestId].user,
            idToRequests[_requestId].nftIds[0],
            idToRequests[_requestId].nftIds[1],
            _newGene
        );

        ISEVCore(idToRequests[_requestId].nft).transferFrom(
            address(this),
            idToRequests[_requestId].user,
            idToRequests[_requestId].nftIds[0]
        );
        ISEVCore(idToRequests[_requestId].nft).transferFrom(
            address(this),
            idToRequests[_requestId].user,
            idToRequests[_requestId].nftIds[1]
        );

        emit BreedProcess(
            _requestId,
            idToRequests[_requestId].user,
            idToRequests[_requestId].nft,
            idToRequests[_requestId].nftIds,
            newNftId,
            block.timestamp
        );

        delete idToRequests[_requestId];
    }
}
