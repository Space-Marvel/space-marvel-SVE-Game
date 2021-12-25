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
}

contract SVEGame is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserActive {
        address user;
        uint256 time;
    }

    ISVECore nftHero;
    mapping(uint256 => UserActive) idToHeros;
    uint256 public feeActiveHero;
    uint256 public durationActiveHero;

    IERC20 feeContractHero;
    address public vault;

    event Active(address nftAddeess, uint256 nftId, address user, uint256 time);
    event Deactive(
        address nftAddeess,
        uint256 nftId,
        address user,
        uint256 time
    );

    constructor(
        ISVECore _nftHero,
        IERC20 _feeContractHero,
        uint256 _feeActiveHero,
        uint256 _durationActiveHero
    ) public {
        require(address(_nftHero) != address(0), "Error: NFT hero invalid");

        nftHero = _nftHero;
        feeContractHero = _feeContractHero;
        feeActiveHero = _feeActiveHero;
        durationActiveHero = _durationActiveHero;
    }

    function setSVECore(ISVECore _nftHero) external onlyOwner {
        require(address(_nftHero) != address(0), "Error: NFT Hero address(0)");
        nftHero = _nftHero;
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Error: Vault address(0)");
        vault = _vault;
    }

    function setFeeContractHero(IERC20 _feeContractHero) external onlyOwner {
        feeContractHero = _feeContractHero;
    }

    function setFeeActivehero(uint256 _feeActiveHero) external onlyOwner {
        feeActiveHero = _feeActiveHero;
    }

    function setDurationActivehero(uint256 _durationActiveHero)
        external
        onlyOwner
    {
        durationActiveHero = _durationActiveHero;
    }

    function active(address _nftAddeess, uint256 _nftId)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        require(_nftAddeess == address(nftHero), "Error: NFT contract invalid");

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
        }

        emit Active(_nftAddeess, _nftId, _msgSender(), block.timestamp);
    }

    function deactive(address _nftAddeess, uint256 _nftId) external payable {
        require(_nftAddeess == address(nftHero), "Error: NFT contract invalid");

        if (_nftAddeess == address(nftHero)) {
            require(nftHero.exists(_nftId), "Error: wrong nftId");

            require(
                idToHeros[_nftId].user == _msgSender(),
                "Error: you are not the owner"
            );

            //transfer NFT for market contract
            nftHero.transferFrom(address(this), _msgSender(), _nftId);
            delete idToHeros[_nftId];
        }

        emit Deactive(_nftAddeess, _nftId, _msgSender(), block.timestamp);
    }
}
