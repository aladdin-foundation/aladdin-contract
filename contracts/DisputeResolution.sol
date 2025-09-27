// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./AgentMarket.sol";

contract DisputeResolution is Ownable, ReentrancyGuard {
    AgentMarket public agentMarket;

    struct Dispute {
        uint256 id;
        uint256 jobId;
        address initiator;
        address defendant;
        string reason;
        DisputeStatus status;
        uint256 createdAt;
        uint256 votingDeadline;
        mapping(address => bool) hasVoted;
        mapping(address => bool) votes;
        uint256 forVotes;
        uint256 againstVotes;
    }

    enum DisputeStatus {
        Open,
        Resolved,
        Rejected,
        Cancelled
    }

    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => bool) public disputedJobs;
    uint256 public disputeCounter;

    event DisputeCreated(
        uint256 indexed disputeId,
        uint256 indexed jobId,
        address indexed initiator,
        address defendant
    );

    event VoteCast(
        uint256 indexed disputeId,
        address indexed voter,
        bool vote
    );

    event DisputeResolved(
        uint256 indexed disputeId,
        uint256 indexed jobId,
        bool resolution
    );

    modifier onlyJobParticipants(uint256 jobId) {
        AgentMarket.Job memory job = agentMarket.getJob(jobId);
        require(
            msg.sender == job.client || msg.sender == job.selectedAgent,
            "Only job participants can initiate dispute"
        );
        _;
    }

    constructor(address _agentMarketAddress) Ownable(msg.sender) {
        agentMarket = AgentMarket(_agentMarketAddress);
    }

    function initiateDispute(
        uint256 jobId,
        string memory reason,
        uint256 votingDuration
    ) external onlyJobParticipants(jobId) nonReentrant {
        require(!disputedJobs[jobId], "Job already disputed");

        AgentMarket.Job memory job = agentMarket.getJob(jobId);
        require(job.status == AgentMarket.JobStatus.InProgress || job.status == AgentMarket.JobStatus.Completed, "Job not in progress or completed");

        uint256 votingDeadline = block.timestamp + votingDuration;
        require(votingDuration > 0, "Voting duration must be positive");

        disputeCounter++;
        uint256 disputeId = disputeCounter;

        Dispute storage dispute = disputes[disputeId];
        dispute.id = disputeId;
        dispute.jobId = jobId;
        dispute.initiator = msg.sender;
        dispute.defendant = msg.sender == job.client ? job.selectedAgent : job.client;
        dispute.reason = reason;
        dispute.status = DisputeStatus.Open;
        dispute.createdAt = block.timestamp;
        dispute.votingDeadline = votingDeadline;

        disputedJobs[jobId] = true;

        emit DisputeCreated(disputeId, jobId, msg.sender, dispute.defendant);
    }

    function vote(uint256 disputeId, bool inFavor) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];

        require(dispute.id != 0, "Dispute does not exist");
        require(dispute.status == DisputeStatus.Open, "Dispute not open");
        require(block.timestamp < dispute.votingDeadline, "Voting period ended");
        require(!dispute.hasVoted[msg.sender], "Already voted");

        dispute.hasVoted[msg.sender] = true;
        dispute.votes[msg.sender] = inFavor;

        if (inFavor) {
            dispute.forVotes++;
        } else {
            dispute.againstVotes++;
        }

        emit VoteCast(disputeId, msg.sender, inFavor);
    }

    function resolveDispute(uint256 disputeId) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];

        require(dispute.id != 0, "Dispute does not exist");
        require(dispute.status == DisputeStatus.Open, "Dispute not open");
        require(block.timestamp >= dispute.votingDeadline, "Voting period not ended");

        bool resolution = dispute.forVotes > dispute.againstVotes;
        dispute.status = resolution ? DisputeStatus.Resolved : DisputeStatus.Rejected;

        disputedJobs[dispute.jobId] = false;

        emit DisputeResolved(disputeId, dispute.jobId, resolution);
    }

    function getDispute(uint256 disputeId) external view returns (
        uint256 id,
        uint256 jobId,
        address initiator,
        address defendant,
        string memory reason,
        DisputeStatus status,
        uint256 createdAt,
        uint256 votingDeadline,
        uint256 forVotes,
        uint256 againstVotes
    ) {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.id != 0, "Dispute does not exist");

        return (
            dispute.id,
            dispute.jobId,
            dispute.initiator,
            dispute.defendant,
            dispute.reason,
            dispute.status,
            dispute.createdAt,
            dispute.votingDeadline,
            dispute.forVotes,
            dispute.againstVotes
        );
    }

    function hasVoted(uint256 disputeId, address voter) external view returns (bool) {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.id != 0, "Dispute does not exist");
        return dispute.hasVoted[voter];
    }
}