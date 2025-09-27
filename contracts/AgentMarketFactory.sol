// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AgentMarket.sol";
import "./RatingNFT.sol";

contract AgentMarketFactory is Ownable, ReentrancyGuard {
    AgentMarket public agentMarket;
    RatingNFT public ratingNFT;

    struct MarketConfig {
        address usdtToken;
        uint256 feePercentage;
    }

    event MarketDeployed(
        address indexed agentMarket,
        address indexed ratingNFT,
        address indexed usdtToken
    );

    event RatingNFTMintedIntegrated(
        uint256 indexed jobId,
        address indexed reviewer,
        address indexed reviewee,
        uint256 tokenId,
        uint8 rating
    );

    constructor(MarketConfig memory config) Ownable(msg.sender) {
        // Deploy AgentMarket
        agentMarket = new AgentMarket(config.usdtToken);

        // Deploy RatingNFT
        ratingNFT = new RatingNFT(address(agentMarket));

        emit MarketDeployed(
            address(agentMarket),
            address(ratingNFT),
            config.usdtToken
        );
    }

    function mintRatingWithValidation(
        uint256 jobId,
        address reviewee,
        uint8 rating,
        string memory reviewText,
        string memory tokenURI
    ) external nonReentrant {
        // Validate that job exists and is completed
        AgentMarket.Job memory job = agentMarket.getJob(jobId);
        require(job.status == AgentMarket.JobStatus.Completed, "Job must be completed");

        // Validate that caller is a job participant
        require(
            msg.sender == job.client || msg.sender == job.selectedAgent,
            "Only job participants can rate"
        );

        // Validate that reviewee is the other participant
        address expectedReviewee = msg.sender == job.client ? job.selectedAgent : job.client;
        require(reviewee == expectedReviewee, "Invalid reviewee address");

        // Check if user has already rated this job
        (bool clientHasRated, bool agentHasRated) = agentMarket.getJobRatingStatus(jobId);
        if (msg.sender == job.client) {
            require(!clientHasRated, "Client already rated for this job");
        } else {
            require(!agentHasRated, "Agent already rated for this job");
        }

        // Mark as rated in AgentMarket
        agentMarket.mintRatingNFT(jobId, reviewee, rating, reviewText, tokenURI);

        // Mint the actual NFT and get the tokenId (simplified for now)
        uint256 tokenId = 1; // In production, you'd get this from the NFT contract

        emit RatingNFTMintedIntegrated(jobId, msg.sender, reviewee, tokenId, rating);
    }

    function getTopAgentsForJob(uint256 jobId, uint256 limit) external view returns (address[] memory) {
        AgentMarket.Job memory job = agentMarket.getJob(jobId);
        address[] memory applicants = job.applicants;

        if (applicants.length == 0 || limit == 0) {
            return new address[](0);
        }

        // Calculate matching scores for all applicants
        uint256[] memory scores = new uint256[](applicants.length);
        for (uint i = 0; i < applicants.length; i++) {
            scores[i] = ratingNFT.getMatchingScore(applicants[i]);
        }

        // Sort applicants by score (simple bubble sort for demo)
        for (uint i = 0; i < applicants.length - 1; i++) {
            for (uint j = 0; j < applicants.length - i - 1; j++) {
                if (scores[j] < scores[j + 1]) {
                    // Swap scores
                    uint256 tempScore = scores[j];
                    scores[j] = scores[j + 1];
                    scores[j + 1] = tempScore;

                    // Swap addresses
                    address tempAddress = applicants[j];
                    applicants[j] = applicants[j + 1];
                    applicants[j + 1] = tempAddress;
                }
            }
        }

        // Return top N agents
        uint256 resultLength = applicants.length < limit ? applicants.length : limit;
        address[] memory topAgents = new address[](resultLength);
        for (uint i = 0; i < resultLength; i++) {
            topAgents[i] = applicants[i];
        }

        return topAgents;
    }

    function getAgentBasicInfo(address agentAddress) external view returns (
        string memory profileURI,
        uint256 rating,
        uint256 completedJobs,
        bool isRegistered
    ) {
        // Get agent data from AgentMarket through public mapping
        (
            bool agentIsRegistered,
            string memory agentProfileURI,
            uint256 agentRating,
            uint256 agentCompletedJobs
        ) = agentMarket.agents(agentAddress);

        return (
            agentProfileURI,
            agentRating,
            agentCompletedJobs,
            agentIsRegistered
        );
    }

    function getAgentReputation(address agentAddress) external view returns (
        uint256 averageRating,
        uint256 totalRatings,
        uint256 matchingScore
    ) {
        return (
            ratingNFT.getUserAverageRating(agentAddress),
            ratingNFT.getUserRatingCount(agentAddress),
            ratingNFT.getMatchingScore(agentAddress)
        );
    }

    function getJobRecommendations(address client, uint256 limit) external view returns (uint256[] memory) {
        uint256[] memory clientJobs = agentMarket.getClientJobs(client);
        if (clientJobs.length == 0) {
            return new uint256[](0);
        }

        // Get all open jobs
        uint256 openJobsCount = 0;
        for (uint i = 0; i < clientJobs.length; i++) {
            AgentMarket.Job memory job = agentMarket.getJob(clientJobs[i]);
            if (job.status == AgentMarket.JobStatus.Open) {
                openJobsCount++;
            }
        }

        if (openJobsCount == 0) {
            return new uint256[](0);
        }

        uint256[] memory openJobs = new uint256[](openJobsCount);
        uint256 index = 0;
        for (uint i = 0; i < clientJobs.length; i++) {
            AgentMarket.Job memory job = agentMarket.getJob(clientJobs[i]);
            if (job.status == AgentMarket.JobStatus.Open) {
                openJobs[index] = job.id;
                index++;
            }
        }

        // For now, return all open jobs (in production, add more sophisticated matching)
        uint256 resultLength = openJobs.length < limit ? openJobs.length : limit;
        uint256[] memory recommendations = new uint256[](resultLength);
        for (uint i = 0; i < resultLength; i++) {
            recommendations[i] = openJobs[i];
        }

        return recommendations;
    }

    function getReputationScore(address user) external view returns (uint256) {
        uint256 avgRating = ratingNFT.getUserAverageRating(user);
        uint256 ratingCount = ratingNFT.getUserRatingCount(user);
        uint256 matchingScore = ratingNFT.getMatchingScore(user);

        // Combined reputation score
        return (avgRating * 50 + ratingCount * 1000 + matchingScore * 10) / 100;
    }

    // Emergency functions
    function emergencyPauseMarkets() external onlyOwner {
        // Implement emergency pause logic
        // This would call pause functions on both contracts
    }

    function emergencyUnpauseMarkets() external onlyOwner {
        // Implement emergency unpause logic
    }

    // Upgrade functions
    function upgradeAgentMarket(address newAgentMarket) external onlyOwner {
        agentMarket = AgentMarket(newAgentMarket);
    }

    function upgradeRatingNFT(address newRatingNFT) external onlyOwner {
        ratingNFT = RatingNFT(newRatingNFT);
    }
}