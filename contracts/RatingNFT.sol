// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./AgentMarket.sol";

contract RatingNFT is ERC721, ERC721URIStorage, Ownable {
    uint256 private _tokenIdCounter;

    AgentMarket public agentMarket;

    struct RatingData {
        uint256 jobId;
        address reviewer;
        address reviewee;
        uint8 rating; // 1-5 stars
        string reviewText;
        uint256 timestamp;
        RatingType ratingType;
        bool exists;
    }

    enum RatingType {
        ClientToAgent,
        AgentToClient
    }

    mapping(uint256 => RatingData) public ratingData;
    mapping(address => uint256[]) public userRatings;
    mapping(uint256 => bool) public jobRated; // jobId => bool
    mapping(address => uint256) public userRatingCount;

    event RatingMinted(
        uint256 indexed tokenId,
        uint256 indexed jobId,
        address indexed reviewer,
        address reviewee,
        uint8 rating,
        RatingType ratingType
    );

    event RatingUpdated(
        uint256 indexed tokenId,
        uint8 newRating,
        string newReviewText
    );

    modifier onlyJobParticipants(uint256 jobId, address reviewer, address reviewee) {
        AgentMarket.Job memory job = agentMarket.getJob(jobId);
        require(
            (reviewer == job.client && reviewee == job.selectedAgent) ||
            (reviewer == job.selectedAgent && reviewee == job.client),
            "Only job participants can rate each other"
        );
        require(job.status == AgentMarket.JobStatus.Completed, "Job must be completed");
        _;
    }

    modifier validRating(uint8 rating) {
        require(rating >= 1 && rating <= 5, "Rating must be between 1 and 5");
        _;
    }

    constructor(address _agentMarketAddress)
        ERC721("Agent Rating", "ARATING")
        Ownable(msg.sender)
    {
        agentMarket = AgentMarket(_agentMarketAddress);
    }

    function mintRating(
        uint256 jobId,
        address reviewee,
        uint8 rating,
        string memory reviewText,
        string memory metadataURI
    ) external validRating(rating) {
        require(!jobRated[jobId], "Job already rated by this user");

        address reviewer = msg.sender;

        // Check if reviewer is a participant in the job
        AgentMarket.Job memory job = agentMarket.getJob(jobId);
        require(
            (reviewer == job.client && reviewee == job.selectedAgent) ||
            (reviewer == job.selectedAgent && reviewee == job.client),
            "Only job participants can rate each other"
        );
        require(job.status == AgentMarket.JobStatus.Completed, "Job must be completed");

        // Check if user has already rated this counterparty for this job
        require(!hasUserRatedJob(jobId, reviewer), "User already rated for this job");

        // Determine rating type
        RatingType ratingType = (reviewer == job.client) ?
            RatingType.ClientToAgent : RatingType.AgentToClient;

        // Mint NFT
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        _safeMint(reviewer, tokenId);
        _setTokenURI(tokenId, metadataURI);

        // Store rating data
        ratingData[tokenId] = RatingData({
            jobId: jobId,
            reviewer: reviewer,
            reviewee: reviewee,
            rating: rating,
            reviewText: reviewText,
            timestamp: block.timestamp,
            ratingType: ratingType,
            exists: true
        });

        // Update user ratings
        userRatings[reviewer].push(tokenId);
        userRatingCount[reviewee]++;

        // Mark job as rated by this user
        _markJobRated(jobId, reviewer);

        emit RatingMinted(tokenId, jobId, reviewer, reviewee, rating, ratingType);
    }

    function updateRating(
        uint256 tokenId,
        uint8 newRating,
        string memory newReviewText,
        string memory updatedTokenURI
    ) external validRating(newRating) {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender, "Only rating owner can update");
        require(block.timestamp < ratingData[tokenId].timestamp + 7 days, "Rating can only be updated within 7 days");

        ratingData[tokenId].rating = newRating;
        ratingData[tokenId].reviewText = newReviewText;
        ratingData[tokenId].timestamp = block.timestamp;

        _setTokenURI(tokenId, updatedTokenURI);

        emit RatingUpdated(tokenId, newRating, newReviewText);
    }

    function getUserAverageRating(address user) public view returns (uint256) {
        uint256[] memory tokens = getUserRatingsForUser(user);
        if (tokens.length == 0) return 0;

        uint256 totalRating = 0;
        uint256 validRatings = 0;

        for (uint i = 0; i < tokens.length; i++) {
            RatingData memory data = ratingData[tokens[i]];
            if (data.exists && data.reviewee == user) {
                totalRating += data.rating;
                validRatings++;
            }
        }

        return validRatings > 0 ? (totalRating * 100) / validRatings : 0; // Return scaled by 100
    }

    function getUserRatingCount(address user) public view returns (uint256) {
        return userRatingCount[user];
    }

    function getUserRatingsForUser(address user) public view returns (uint256[] memory) {
        // Get all rating tokens where this user is the reviewee
        uint256[] memory allTokens = new uint256[](_tokenIdCounter);
        uint256 count = 0;

        for (uint i = 1; i <= _tokenIdCounter; i++) {
            if (ratingData[i].exists && ratingData[i].reviewee == user) {
                allTokens[count] = i;
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        for (uint i = 0; i < count; i++) {
            result[i] = allTokens[i];
        }

        return result;
    }

    function getJobRatings(uint256 jobId) public view returns (uint256[] memory) {
        uint256[] memory allTokens = new uint256[](_tokenIdCounter);
        uint256 count = 0;

        for (uint i = 1; i <= _tokenIdCounter; i++) {
            if (ratingData[i].exists && ratingData[i].jobId == jobId) {
                allTokens[count] = i;
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        for (uint i = 0; i < count; i++) {
            result[i] = allTokens[i];
        }

        return result;
    }

    function getMatchingScore(address user) public view returns (uint256) {
        // Calculate matching score based on:
        // 1. Average rating (60% weight)
        // 2. Number of ratings (20% weight)
        // 3. Recency of ratings (20% weight)

        uint256 avgRating = getUserAverageRating(user);
        uint256 ratingCount = getUserRatingCount(user);

        if (ratingCount == 0) return 0;

        // Calculate recency score (newer ratings weigh more)
        uint256 recencyScore = _calculateRecencyScore(user);

        // Weighted score calculation
        uint256 weightedScore = (avgRating * 60) + (ratingCount * 20 * 100) + recencyScore;

        // Normalize to 0-1000 scale
        return weightedScore / 100;
    }

    function _calculateRecencyScore(address user) internal view returns (uint256) {
        uint256[] memory tokens = getUserRatingsForUser(user);
        if (tokens.length == 0) return 0;

        uint256 totalRecency = 0;

        for (uint i = 0; i < tokens.length && i < 10; i++) { // Consider last 10 ratings
            RatingData memory data = ratingData[tokens[tokens.length - 1 - i]];
            uint256 daysSinceRating = (block.timestamp - data.timestamp) / 86400;

            // Weight decreases with age (max 1 year)
            if (daysSinceRating > 365) daysSinceRating = 365;
            uint256 weight = (365 - daysSinceRating) * 100 / 365;

            totalRecency += weight;
        }

        return totalRecency * 20; // 20% weight
    }

    function hasUserRatedJob(uint256 jobId, address user) internal view returns (bool) {
        // Check if user has rated anyone for this specific job
        uint256[] memory jobRatings = getJobRatings(jobId);
        for (uint i = 0; i < jobRatings.length; i++) {
            if (ratingData[jobRatings[i]].reviewer == user) {
                return true;
            }
        }
        return false;
    }

    function _markJobRated(uint256 jobId, address) internal {
        // Mark that this user has rated for this job
        // This is a simplified implementation - in production you'd want more sophisticated tracking
        jobRated[jobId] = true;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Emergency functions
    function pause() external onlyOwner {
        // Implement pause logic if needed
    }

    function unpause() external onlyOwner {
        // Implement unpause logic if needed
    }
}