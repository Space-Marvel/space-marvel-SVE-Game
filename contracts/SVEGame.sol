// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface ISVECore {
    function exists(uint256 _id) external view returns (bool);

    function ownerOf(uint256 tokenId) external view returns (address);

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function evolve(uint256[] memory _nftIds, uint256 _newGene) external;

    function breed(
        address _toAddress,
        uint256 _nftId1,
        uint256 _nftId2,
        uint256 _gene
    ) external returns (uint256);
}

contract SVEGame is Ownable, Pausable, ReentrancyGuard {
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

    mapping(uint256 => UserRequest) idToRequests;
    uint256 public currentRequestId;

    ISVECore public nftHero;
    ISVECore public nftSpaceShip;

    mapping(uint256 => UserActive) idToHeros;
    // mapping (address=>mapping (uint256=>UserActive)) idToNfts;
    mapping(uint256 => UserActive) idToSpaceShips;
    uint256 public feeActiveHero;
    uint256 public feeActiveSpaceShip;
    // uint256 public feeBreed;
    // uint256 public feeEvolve;
    uint256 public durationActiveHero;
    uint256 public durationActiveSpaceShip;

    IERC20 public feeContractHero;
    IERC20 public feeContractSpaceShip;
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
        ISVECore _nftHero,
        ISVECore _nftSpaceShip,
        IERC20 _feeContractHero,
        IERC20 _feeContractSpaceShip,
        uint256 _feeActiveHero,
        uint256 _feeActiveSpaceShip,
        // uint256 _feeBreed,
        // uint256 _feeEvolve,
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
        feeContractHero = _feeContractHero;
        feeContractSpaceShip = _feeContractSpaceShip;
        feeActiveHero = _feeActiveHero;
        feeActiveSpaceShip = _feeActiveSpaceShip;
        // feeBreed=_feeBreed;
        // feeEvolve= _feeEvolve;
        durationActiveHero = _durationActiveHero;
        durationActiveSpaceShip = _durationActiveSpaceShip;
        vault = _vault;
    }

    function setSVEHeroCore(ISVECore _nftHero) external onlyOwner {
        require(address(_nftHero) != address(0), "Error: NFT Hero address(0)");
        nftHero = _nftHero;
    }

    function setSVESpaceShipCore(ISVECore _nftSpaceShip) external onlyOwner {
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

    function setFeeContractHero(IERC20 _feeContractHero) external onlyOwner {
        feeContractHero = _feeContractHero;
    }

    function setFeeContractSpaceShip(IERC20 _feeContractSpaceShip)
        external
        onlyOwner
    {
        feeContractSpaceShip = _feeContractSpaceShip;
    }

    function setFeeActiveHero(uint256 _feeActiveHero) external onlyOwner {
        feeActiveHero = _feeActiveHero;
    }

    function setFeeActiveSpaceShip(uint256 _feeActiveSpaceShip)
        external
        onlyOwner
    {
        feeActiveSpaceShip = _feeActiveSpaceShip;
    }

    // function setFeeBreed(uint256 _feeBreed)
    //     external
    //     onlyOwner
    // {
    //     feeBreed = _feeBreed;
    // }

    // function setFeeEvolve(uint256 _feeEvolve)
    //     external
    //     onlyOwner
    // {
    //     feeEvolve = _feeEvolve;
    // }

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
            if (address(feeContractHero) == address(0)) {
                payable(vault).transfer(feeActiveHero);
                //transfer BNB back to user if amount > fee
                if (msg.value > feeActiveHero) {
                    payable(_msgSender()).transfer(msg.value - feeActiveHero);
                }
            } else {
                feeContractHero.safeTransferFrom(
                    _msgSender(),
                    vault,
                    feeActiveHero
                );
                //transfer BNB back to user if currency is not address(0)
                if (msg.value != 0) {
                    payable(_msgSender()).transfer(msg.value);
                }
            }
            emit Active(
                _nftAddeess,
                _nftId,
                _msgSender(),
                address(feeContractHero),
                feeActiveHero,
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
            if (address(feeContractSpaceShip) == address(0)) {
                payable(vault).transfer(feeActiveSpaceShip);
                //transfer BNB back to user if amount > fee
                if (msg.value > feeActiveSpaceShip) {
                    payable(_msgSender()).transfer(
                        msg.value - feeActiveSpaceShip
                    );
                }
            } else {
                feeContractSpaceShip.safeTransferFrom(
                    _msgSender(),
                    vault,
                    feeActiveHero
                );
                //transfer BNB back to user if currency is not address(0)
                if (msg.value != 0) {
                    payable(_msgSender()).transfer(msg.value);
                }
            }
            emit Active(
                _nftAddeess,
                _nftId,
                _msgSender(),
                address(feeContractSpaceShip),
                feeActiveSpaceShip,
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
        address nft,
        uint256[] nftIds,
        uint256 time
    );

    function evolveRequest(address _nftAddeess, uint256[] memory _nftIds)
        external
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
        currentRequestId += 1;

        emit EvolveRequest(_msgSender(), _nftAddeess, _nftIds, block.timestamp);
    }

    event EvolveProcess(
        uint256 requestId,
        address user,
        address nft,
        uint256[] nftIds,
        uint256 time
    );

    function evolve(uint256 _requestId, uint256 _newGene) external onlyOwner {
        require(
            idToRequests[_requestId].user != address(0),
            "Error: request invalid"
        );

        require(idToRequests[_requestId].isEvolve, "Error: request invalid");

        ISVECore(idToRequests[_requestId].nft).evolve(
            idToRequests[_requestId].nftIds,
            _newGene
        );

        emit EvolveProcess(
            _requestId,
            _msgSender(),
            idToRequests[_requestId].nft,
            idToRequests[_requestId].nftIds,
            block.timestamp
        );

        delete idToRequests[_requestId];
    }

    event BreedRequest(
        address user,
        address nft,
        uint256[] nftIds,
        uint256 time
    );

    function breedRequest(
        address _nftAddeess,
        uint256 _nftId1,
        uint256 _nftId2
    ) external {
        require(
            _nftAddeess == address(nftHero) ||
                _nftAddeess == address(nftSpaceShip),
            "Error: NFT contract invalid"
        );

        require(
            ISVECore(_nftAddeess).ownerOf(_nftId1) == _msgSender(),
            "Error: you are not the owner"
        );

        require(
            ISVECore(_nftAddeess).ownerOf(_nftId2) == _msgSender(),
            "Error: you are not the owner"
        );

        ISVECore(_nftAddeess).transferFrom(
            _msgSender(),
            address(this),
            _nftId1
        );
        ISVECore(_nftAddeess).transferFrom(
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

        currentRequestId += 1;
        emit BreedRequest(_msgSender(), _nftAddeess, ids, block.timestamp);
    }

    event BreedProcess(
        uint256 requestId,
        address user,
        address nft,
        uint256[] nftIds,
        uint256 time
    );

    function breedProcess(uint256 _requestId, uint256 _newGene)
        external
        onlyOwner
    {
        require(
            idToRequests[_requestId].user != address(0),
            "Error: request invalid"
        );

        require(!idToRequests[_requestId].isEvolve, "Error: request invalid");

        ISVECore(idToRequests[_requestId].nft).breed(
            idToRequests[_requestId].user,
            idToRequests[_requestId].nftIds[0],
            idToRequests[_requestId].nftIds[1],
            _newGene
        );

        ISVECore(idToRequests[_requestId].nft).transferFrom(
            address(this),
            idToRequests[_requestId].user,
            idToRequests[_requestId].nftIds[0]
        );
        ISVECore(idToRequests[_requestId].nft).transferFrom(
            address(this),
            idToRequests[_requestId].user,
            idToRequests[_requestId].nftIds[1]
        );

        emit BreedProcess(
            _requestId,
            idToRequests[_requestId].user,
            idToRequests[_requestId].nft,
            idToRequests[_requestId].nftIds,
            block.timestamp
        );

        delete idToRequests[_requestId];
    }
}
