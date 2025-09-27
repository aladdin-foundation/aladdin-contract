// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AgentMarket is Ownable, ReentrancyGuard {
    IERC20 public usdtToken;

    uint256 public feePercentage = 200; // 2% fee (200 basis points)
    uint256 public constant FEE_PRECISION = 10000;

    struct Job {
        uint256 id; // 任务ID
        address client; // 发布者
        uint256 reward; // 报酬
        uint256 deadline; // 截止时间
        uint256 createdAt; // 创建时间
        JobStatus status; // 状态
        address[] applicants; // 申请人列表
        address selectedAgent; // 被选中代理人
        string contentURI; // 存储 title/description 的 IPFS/Arweave 链接
        bool isDisputed; // 是否有争议
        uint256 completionTime; // 完成时间
        bool clientRated; // 客户是否已评价
        bool agentRated; // 代理人是否已评价
    }

    struct Agent {
        bool isRegistered; // 是否注册
        string profileURI; // off-chain profile（名字、技能、简介都放 IPFS/Arweave）
        uint256 rating; // 评分
        uint256 completedJobs; // 完成的任务数量
    }

    enum JobStatus {
        Open,
        InProgress,
        Completed,
        Cancelled,
        Expired
    }

    mapping(uint256 => Job) public jobs;
    mapping(address => Agent) public agents;
    mapping(address => uint256[]) public agentJobIds;
    mapping(address => uint256[]) public clientJobIds;
    mapping(uint256 => bool) public feeWithdrawn;

    uint256 public jobCounter;
    uint256 public totalFeesEarned;
    bool public paused;

    uint256 public constant MIN_REWARD = 1 * 1e6; // 1 USDT (6 decimals)
    uint256 public constant MAX_REWARD = 10000 * 1e6; // 10,000 USDT
    uint256 public constant PAYMENT_DELAY = 3 days;

    event JobCreated(
        uint256 indexed jobId,
        address indexed client,
        string contentURI,
        uint256 reward,
        uint256 deadline
    );

    event JobApplied(uint256 indexed jobId, address indexed agent);

    event AgentSelected(uint256 indexed jobId, address indexed agent);

    event JobCompleted(
        uint256 indexed jobId,
        address indexed agent,
        uint256 reward,
        uint256 feeAmount
    );

    event RatingNFTMinted(
        uint256 indexed jobId,
        address indexed reviewer,
        address indexed reviewee,
        uint256 tokenId,
        uint8 rating
    );

    event PaymentClaimed(
        uint256 indexed jobId,
        address indexed agent,
        uint256 amount
    );

    event ContractPaused(address indexed by);

    event ContractUnpaused(address indexed by);

    event JobCancelled(uint256 indexed jobId);

    event JobExpired(uint256 indexed jobId, address[] agents);

    event AgentRegistered(address indexed wallet, string name);

    event FeeUpdated(uint256 newFeePercentage);

    event FundsWithdrawn(address indexed to, uint256 amount);

    modifier onlyRegisteredAgent() {
        require(agents[msg.sender].isRegistered, "Agent not registered");
        _;
    }

    modifier jobExists(uint256 jobId) {
        require(jobs[jobId].id != 0, "Job does not exist");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor(address _usdtAddress) Ownable(msg.sender) {
        usdtToken = IERC20(_usdtAddress);
    }

    function registerAgent(string memory profileURI) external {
        require(!agents[msg.sender].isRegistered, "Agent already registered");
        require(bytes(profileURI).length > 0, "Profile URI cannot be empty");

        agents[msg.sender] = Agent({
            isRegistered: true,
            profileURI: profileURI,
            rating: 0,
            completedJobs: 0
        });

        emit AgentRegistered(msg.sender, profileURI);
    }

    function createJob(
        string memory contentURI,
        uint256 reward,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        require(bytes(contentURI).length > 0, "Content URI cannot be empty");
        require(
            reward >= MIN_REWARD && reward <= MAX_REWARD,
            "Reward amount out of range"
        );
        require(
            deadline > block.timestamp + 1 hours,
            "Deadline must be at least 1 hour in the future"
        );
        require(
            deadline <= block.timestamp + 365 days,
            "Deadline cannot be more than 1 year in the future"
        );

        uint256 feeAmount = (reward * feePercentage) / FEE_PRECISION;
        uint256 totalAmount = reward + feeAmount;

        require(
            usdtToken.balanceOf(msg.sender) >= totalAmount,
            "Insufficient USDT balance"
        );

        require(
            usdtToken.allowance(msg.sender, address(this)) >= totalAmount,
            "Insufficient USDT allowance"
        );

        bool success = usdtToken.transferFrom(
            msg.sender,
            address(this),
            totalAmount
        );
        require(success, "USDT transfer failed");

        jobCounter++;
        uint256 jobId = jobCounter;

        jobs[jobId] = Job({
            id: jobId,
            client: msg.sender,
            reward: reward,
            deadline: deadline,
            createdAt: block.timestamp,
            status: JobStatus.Open,
            applicants: new address[](0),
            selectedAgent: address(0),
            contentURI: contentURI,
            isDisputed: false,
            completionTime: 0,
            clientRated: false,
            agentRated: false
        });

        clientJobIds[msg.sender].push(jobId);

        emit JobCreated(jobId, msg.sender, contentURI, reward, deadline);
    }

    function applyForJob(
        uint256 jobId
    ) external onlyRegisteredAgent jobExists(jobId) whenNotPaused {
        Job storage job = jobs[jobId];

        require(job.status == JobStatus.Open, "Job is not open");
        require(block.timestamp < job.deadline, "Job deadline passed");
        require(
            job.applicants.length < 50,
            "Maximum number of applicants reached"
        );

        for (uint i = 0; i < job.applicants.length; i++) {
            require(job.applicants[i] != msg.sender, "Already applied");
        }

        job.applicants.push(msg.sender);
        agentJobIds[msg.sender].push(jobId);

        emit JobApplied(jobId, msg.sender);
    }

    function selectAgent(
        uint256 jobId,
        address agent
    ) external jobExists(jobId) nonReentrant whenNotPaused {
        Job storage job = jobs[jobId];

        require(job.client == msg.sender, "Only client can select agent");
        require(job.status == JobStatus.Open, "Job is not open");
        require(agents[agent].isRegistered, "Agent not registered");
        require(agent != address(0), "Invalid agent address");

        bool isApplicant = false;
        for (uint i = 0; i < job.applicants.length; i++) {
            if (job.applicants[i] == agent) {
                isApplicant = true;
                break;
            }
        }
        require(isApplicant, "Agent must be an applicant");

        job.selectedAgent = agent;
        job.status = JobStatus.InProgress;

        emit AgentSelected(jobId, agent);
    }

    function completeJob(
        uint256 jobId
    ) external jobExists(jobId) nonReentrant whenNotPaused {
        Job storage job = jobs[jobId];

        require(
            msg.sender == job.client || msg.sender == job.selectedAgent,
            "Only client or selected agent can complete job"
        );
        require(job.status == JobStatus.InProgress, "Job not in progress");
        require(!job.isDisputed, "Job is disputed");

        job.status = JobStatus.Completed;
        job.completionTime = block.timestamp;

        emit JobCompleted(
            jobId,
            job.selectedAgent,
            job.reward,
            (job.reward * feePercentage) / FEE_PRECISION
        );
    }

    function claimPayment(
        uint256 jobId
    ) external jobExists(jobId) nonReentrant whenNotPaused {
        Job storage job = jobs[jobId];

        require(job.status == JobStatus.Completed, "Job not completed");
        require(
            msg.sender == job.selectedAgent,
            "Only selected agent can claim payment"
        );
        require(
            block.timestamp >= job.completionTime + PAYMENT_DELAY,
            "Payment not yet available"
        );
        require(!job.isDisputed, "Job is disputed");

        uint256 feeAmount = (job.reward * feePercentage) / FEE_PRECISION;
        uint256 agentPayment = job.reward - feeAmount;

        job.status = JobStatus.Completed; // Ensure status remains completed

        bool success = usdtToken.transfer(msg.sender, agentPayment);
        require(success, "USDT transfer to agent failed");

        totalFeesEarned += feeAmount;

        emit PaymentClaimed(jobId, msg.sender, agentPayment);
    }

    function cancelJob(
        uint256 jobId
    ) external jobExists(jobId) nonReentrant whenNotPaused {
        Job storage job = jobs[jobId];

        require(job.client == msg.sender, "Only client can cancel job");
        require(
            job.status == JobStatus.Open,
            "Only open jobs can be cancelled"
        );

        job.status = JobStatus.Cancelled;

        uint256 feeAmount = (job.reward * feePercentage) / FEE_PRECISION;
        uint256 totalAmount = job.reward + feeAmount;
        bool success = usdtToken.transfer(job.client, totalAmount);
        require(success, "USDT refund failed");

        emit JobCancelled(jobId);
    }

    function checkJobExpiration(
        uint256 jobId
    ) external jobExists(jobId) whenNotPaused {
        Job storage job = jobs[jobId];

        require(job.status == JobStatus.Open, "Job not open");
        require(block.timestamp >= job.deadline, "Job not expired");

        job.status = JobStatus.Expired;

        if (job.applicants.length > 0) {
            uint256 feeAmount = (job.reward * feePercentage) / FEE_PRECISION;
            uint256 totalRewardAfterFee = job.reward - feeAmount;
            uint256 agentShare = totalRewardAfterFee / job.applicants.length;

            for (uint i = 0; i < job.applicants.length; i++) {
                bool success = usdtToken.transfer(
                    job.applicants[i],
                    agentShare
                );
                require(success, "USDT transfer to agent failed");
            }

            totalFeesEarned += feeAmount;
        } else {
            uint256 totalAmount = job.reward +
                (job.reward * feePercentage) /
                FEE_PRECISION;
            bool success = usdtToken.transfer(job.client, totalAmount);
            require(success, "USDT refund failed");
        }

        emit JobExpired(jobId, job.applicants);
    }

    function mintRatingNFT(
        uint256 jobId,
        address reviewee,
        uint8 rating,
        string memory,
        string memory
    ) external jobExists(jobId) whenNotPaused {
        Job storage job = jobs[jobId];

        require(job.status == JobStatus.Completed, "Job must be completed");
        require(
            (msg.sender == job.client && reviewee == job.selectedAgent) ||
                (msg.sender == job.selectedAgent && reviewee == job.client),
            "Only job participants can rate each other"
        );
        require(rating >= 1 && rating <= 5, "Rating must be between 1 and 5");

        // Check if user has already rated this counterparty for this job
        if (msg.sender == job.client) {
            require(!job.clientRated, "Client already rated for this job");
            job.clientRated = true;
        } else {
            require(!job.agentRated, "Agent already rated for this job");
            job.agentRated = true;
        }

        // Update completed jobs count when agent is rated
        if (reviewee == job.selectedAgent) {
            agents[reviewee].completedJobs++;
        }

        // In production, you would call the RatingNFT contract here
        // For now, we'll emit an event to be handled by the frontend
        emit RatingNFTMinted(jobId, msg.sender, reviewee, 0, rating);
    }

    function getAgentRating(address agent) public view returns (uint256) {
        // This would typically query the RatingNFT contract
        // For now, return a placeholder
        return agents[agent].rating;
    }

    function getClientRating(address) public pure returns (uint256) {
        // This would typically query the RatingNFT contract
        // For now, return a placeholder
        return 0; // Implement client rating logic if needed
    }

    function getJobRatingStatus(
        uint256 jobId
    )
        external
        view
        jobExists(jobId)
        returns (bool clientHasRated, bool agentHasRated)
    {
        Job storage job = jobs[jobId];
        return (job.clientRated, job.agentRated);
    }

    function setFeePercentage(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= 1000, "Fee cannot exceed 10%"); // Max 10%
        feePercentage = newFeePercentage;
        emit FeeUpdated(newFeePercentage);
    }

    function withdrawFees() external onlyOwner {
        require(totalFeesEarned > 0, "No fees to withdraw");

        uint256 contractBalance = usdtToken.balanceOf(address(this));
        require(
            contractBalance >= totalFeesEarned,
            "Insufficient contract balance for fee withdrawal"
        );

        uint256 withdrawAmount = totalFeesEarned;
        totalFeesEarned = 0;

        bool success = usdtToken.transfer(owner(), withdrawAmount);
        require(success, "USDT transfer failed");

        emit FundsWithdrawn(owner(), withdrawAmount);
    }

    function getJob(
        uint256 jobId
    ) external view jobExists(jobId) returns (Job memory) {
        return jobs[jobId];
    }

    function getAgentJobs(
        address agent
    ) external view returns (uint256[] memory) {
        return agentJobIds[agent];
    }

    function getClientJobs(
        address client
    ) external view returns (uint256[] memory) {
        return clientJobIds[client];
    }

    function getJobApplicants(
        uint256 jobId
    ) external view jobExists(jobId) returns (address[] memory) {
        return jobs[jobId].applicants;
    }

    function pause() external onlyOwner {
        require(!paused, "Contract is already paused");
        paused = true;
        emit ContractPaused(msg.sender);
    }

    function unpause() external onlyOwner {
        require(paused, "Contract is not paused");
        paused = false;
        emit ContractUnpaused(msg.sender);
    }

    function emergencyWithdraw() external onlyOwner {
        require(paused, "Contract must be paused to emergency withdraw");

        uint256 balance = usdtToken.balanceOf(address(this));
        require(balance > 0, "No funds to withdraw");

        bool success = usdtToken.transfer(owner(), balance);
        require(success, "Emergency withdrawal failed");

        emit FundsWithdrawn(owner(), balance);
        totalFeesEarned = 0; // Reset fees earned counter
    }
}
