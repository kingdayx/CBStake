// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CBmod.sol";
import "./CBBPP.sol";
import "./CBNPP.sol";

contract CBNFTStakingVault is Ownable, CBNFTBurnTrackingPlugin {
    struct Vault {
        address nftContract;
        uint256 stakingPeriod;
        uint256 burnPeriod;
        uint256 rewardAmount;
        IERC20 rewardToken;
    }

    struct StakeInfo {
        uint256 claimCount;
        uint256 tokenId;
    }

    struct Stake {
        uint256 vaultId;
        StakeInfo stakeInfo;
        uint256 stakedAt;
        bool claimed;
    }

    Vault[] public vaults;
    mapping(uint256 => Stake) public stakes;
    uint256 public totalStakes;
    CBBPP public cbbpp; // Declare the CBBPP contract instance
    CBNPP public cbnpp; // Declare the CBNPP contract instance

    event NFTStaked(address indexed user, uint256 indexed vaultId, uint256 indexed tokenId);
    event RewardClaimed(address indexed user, uint256 indexed vaultId, uint256 amount);
    event NFTBurned(uint256 indexed vaultId, uint256 indexed tokenId);

    constructor(address cbbppAddress, address cbnppAddress) Ownable(msg.sender) {
        // Create default vaults
        createDefaultVaults();
        cbbpp = CBBPP(cbbppAddress); // Initialize the CBBPP contract instance
        cbnpp = CBNPP(cbnppAddress); // Initialize the CBNPP contract instance
    }

    function createDefaultVaults() internal {
        // Create BPP vault
        vaults.push(
            Vault(address(cbbpp), 30 days, 60 days, 100 ether, IERC20(0x0987654321098765432109876543210987654321))
        );

        // Create NPP vault
        vaults.push(
            Vault(address(cbnpp), 45 days, 90 days, 150 ether, IERC20(0x1098765432109876543210987654321098765432))
        );

        // Create DRILL vault (replace with the actual DRILL contract address)
        vaults.push(
            Vault(
                0x3456789012345678901234567890123456789012,
                60 days,
                120 days,
                200 ether,
                IERC20(0x2109876543210987654321098765432109876543)
            )
        );
    }

    function createVault(
        address nftContract,
        uint256 stakingPeriod,
        uint256 burnPeriod,
        uint256 rewardAmount,
        IERC20 rewardToken
    ) external onlyOwner {
        require(stakingPeriod <= burnPeriod, "Invalid staking and burn periods");
        vaults.push(Vault(nftContract, stakingPeriod, burnPeriod, rewardAmount, rewardToken));
    }

    function stakeNFT(address erc6900Account, uint256 vaultId, uint256 tokenId) external {
        require(vaultId < vaults.length, "Invalid vault ID");
        Vault storage vault = vaults[vaultId];
        IERC721(vault.nftContract).transferFrom(msg.sender, address(this), tokenId);
        IERC721(vault.nftContract).transferFrom(address(this), erc6900Account, tokenId);
        stakes[totalStakes] = Stake(vaultId, StakeInfo(0, tokenId), block.timestamp, false);
        totalStakes++;
        emit NFTStaked(msg.sender, vaultId, tokenId);
    }

    function claimReward(uint256 stakeId) external {
        require(stakeId < totalStakes, "Invalid stake ID");
        Stake storage stake = stakes[stakeId];
        stake.stakeInfo.claimCount++;

        Vault storage vault = vaults[stake.vaultId];
        if (stake.stakeInfo.claimCount == 6) {
            if (vault.nftContract == address(cbbpp)) {
                CBBPP.Stage currentStage = cbbpp.getStage(stake.stakeInfo.tokenId);
                CBBPP.Stage nextStage = getNextStageCBBPP(currentStage);

                // Mint a new CBBPP NFT to the user's address with the next stage
                uint256 newTokenId = cbbpp.mint(msg.sender, nextStage);

                // Update the staked NFT to the newly minted CBBPP NFT
                stake.stakeInfo.tokenId = newTokenId;
                stake.stakeInfo.claimCount = 0;
            } else if (vault.nftContract == address(cbnpp)) {
                CBNPP.Stage currentStage = cbnpp.getStage(stake.stakeInfo.tokenId);
                CBNPP.Stage nextStage = getNextStageCBNPP(currentStage);

                // Mint a new CBNPP NFT to the user's address with the next stage
                uint256 newTokenId = cbnpp.mint(msg.sender, nextStage);

                // Update the staked NFT to the newly minted CBNPP NFT
                stake.stakeInfo.tokenId = newTokenId;
                stake.stakeInfo.claimCount = 0;
            }
        }

        require(!stake.claimed, "Reward already claimed");
        require(block.timestamp >= stake.stakedAt + vault.stakingPeriod, "Staking period not completed");

        stake.claimed = true;
        uint256 rewardAmount = vault.rewardAmount;
        uint256 burnAmount = (rewardAmount * 10) / 100; // 10% of reward amount
        vault.rewardToken.transfer(msg.sender, rewardAmount - burnAmount);
        emit RewardClaimed(msg.sender, stake.vaultId, rewardAmount - burnAmount);

        // Burn tokens on every claim
        vault.rewardToken.transfer(address(0), burnAmount);
    }

    function getNextStageCBBPP(CBBPP.Stage currentStage) internal pure returns (CBBPP.Stage) {
        if (currentStage == CBBPP.Stage.Initiate) {
            return CBBPP.Stage.Molding;
        } else if (currentStage == CBBPP.Stage.Molding) {
            return CBBPP.Stage.Enlightened;
        } else {
            return CBBPP.Stage.Enlightened;
        }
    }

    function getNextStageCBNPP(CBNPP.Stage currentStage) internal pure returns (CBNPP.Stage) {
        if (currentStage == CBNPP.Stage.Initiate) {
            return CBNPP.Stage.Molding;
        } else if (currentStage == CBNPP.Stage.Molding) {
            return CBNPP.Stage.Enlightened;
        } else {
            return CBNPP.Stage.Enlightened;
        }
    }

    function burnExpiredNFTs(address erc6900Account) external {
        for (uint256 i = 0; i < totalStakes; i++) {
            Stake storage stake = stakes[i];
            if (!stake.claimed) {
                Vault storage vault = vaults[stake.vaultId];
                if (block.timestamp >= stake.stakedAt + vault.burnPeriod) {
                    executeAutoBurn(erc6900Account, vault.nftContract, stake.stakeInfo.tokenId, stake.vaultId);
                    stake.claimed = true;
                }
            }
        }
    }
}
