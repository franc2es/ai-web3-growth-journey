// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTStakingLoan is Ownable, AutomationCompatibleInterface {
    struct StakeInfo {
        address owner;
        address nftAddress;
        uint256 tokenId;
        uint256 value;
        uint256 borrowedAmount;
        uint256 dueTime;
        bool repaid;
        bool liquidated;
    }

    mapping(uint256 => StakeInfo) public stakes;
    uint256 public stakeCounter;

    mapping(address => mapping(uint256 => uint256)) public nftPriceOracle;

    function setNFTValue(address nftAddress, uint256 tokenId, uint256 value) external onlyOwner {
        nftPriceOracle[nftAddress][tokenId] = value;
    }

    function stakeNFT(address nftAddress, uint256 tokenId) external {
        uint256 value = nftPriceOracle[nftAddress][tokenId];
        require(value > 0, "NFT has no valuation");

        IERC721(nftAddress).transferFrom(msg.sender, address(this), tokenId);

        stakes[stakeCounter] = StakeInfo({
            owner: msg.sender,
            nftAddress: nftAddress,
            tokenId: tokenId,
            value: value,
            borrowedAmount: 0,
            dueTime: 0,
            repaid: false,
            liquidated: false
        });

        stakeCounter++;
    }

    function borrow(uint256 stakeId) external {
        StakeInfo storage stake = stakes[stakeId];
        require(msg.sender == stake.owner, "Not your stake");
        require(stake.borrowedAmount == 0, "Already borrowed");

        uint256 loanAmount = stake.value / 2;
        stake.borrowedAmount = loanAmount;
        stake.dueTime = block.timestamp + 1 days;

        payable(stake.owner).transfer(loanAmount);
    }

    function repay(uint256 stakeId) external payable {
        StakeInfo storage stake = stakes[stakeId];
        require(msg.sender == stake.owner, "Not your stake");
        require(!stake.repaid && !stake.liquidated, "Already closed");
        require(msg.value >= stake.borrowedAmount, "Insufficient repay");

        stake.repaid = true;
        IERC721(stake.nftAddress).transferFrom(address(this), stake.owner, stake.tokenId);
    }

    // ✅ performUpkeep will call this automatically
    function liquidate(uint256 stakeId) public {
        StakeInfo storage stake = stakes[stakeId];
        require(!stake.repaid && !stake.liquidated, "Already settled");
        require(block.timestamp > stake.dueTime, "Not due yet");

        stake.liquidated = true;
        IERC721(stake.nftAddress).transferFrom(address(this), owner(), stake.tokenId);
    }

    /// 🔁 Chainlink Automation part

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        for (uint256 i = 0; i < stakeCounter; i++) {
            StakeInfo storage s = stakes[i];
            if (!s.repaid && !s.liquidated && s.dueTime > 0 && block.timestamp > s.dueTime) {
                return (true, abi.encode(i));
            }
        }
        return (false, bytes(""));
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 stakeId = abi.decode(performData, (uint256));
        liquidate(stakeId);
    }

    receive() external payable {}
}
