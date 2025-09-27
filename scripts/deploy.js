import hre from "hardhat";
import fs from "fs";

console.log("🚀 Deploying Enhanced Agent Market with NFT Rating System...");

// Sepolia Testnet USDT Contract Address
const USDT_ADDRESS = "0x7169D38820dfd117C3FA1f22a697dBA58d90BA06";

async function main() {
  console.log("📋 Step 1: Deploying AgentMarketFactory...");

  // Deploy AgentMarketFactory which will deploy both contracts
  const AgentMarketFactory = await hre.ethers.getContractFactory("AgentMarketFactory");

  const marketConfig = {
    usdtToken: USDT_ADDRESS,
    feePercentage: 200 // 2%
  };

  const factory = await AgentMarketFactory.deploy(marketConfig);

  await factory.waitForDeployment();

  console.log(`✅ AgentMarketFactory deployed to: ${factory.target}`);

  // Get the deployed contracts
  const agentMarket = await factory.agentMarket();
  const ratingNFT = await factory.ratingNFT();

  console.log(`🏪 AgentMarket deployed to: ${agentMarket}`);
  console.log(`⭐ RatingNFT deployed to: ${ratingNFT}`);

  // Deploy DisputeResolution contract
  console.log("⚖️  Step 2: Deploying DisputeResolution contract...");

  const DisputeResolution = await hre.ethers.getContractFactory("DisputeResolution");
  const disputeResolution = await DisputeResolution.deploy(agentMarket);

  await disputeResolution.waitForDeployment();

  console.log(`✅ DisputeResolution deployed to: ${disputeResolution.target}`);

  // Verify contracts on Etherscan (optional)
  console.log("⏳ Waiting for block confirmations...");

  // Wait for 6 block confirmations for more reliable verification
  await factory.deploymentTransaction().wait(6);
  await disputeResolution.deploymentTransaction().wait(6);

  console.log("🎉 Deployment completed successfully!");
  console.log("📊 Contract Addresses:");
  console.log(`   AgentMarketFactory: ${factory.target}`);
  console.log(`   AgentMarket: ${agentMarket}`);
  console.log(`   RatingNFT: ${ratingNFT}`);
  console.log(`   DisputeResolution: ${disputeResolution.target}`);
  console.log(`   USDT: ${USDT_ADDRESS}`);

  // Save deployment info to a file
  const deploymentInfo = {
    network: hre.network.name,
    AgentMarketFactory: factory.target,
    AgentMarket: agentMarket,
    RatingNFT: ratingNFT,
    DisputeResolution: disputeResolution.target,
    USDT: USDT_ADDRESS,
    deploymentTime: new Date().toISOString(),
    features: [
      "✅ Fixed fee calculation bugs",
      "✅ 3-day payment delay mechanism",
      "✅ Enhanced security controls",
      "✅ Mutual rating NFT system",
      "✅ AI-powered matching algorithm",
      "✅ Reputation scoring system"
    ]
  };

  fs.writeFileSync(
    'deployment-info.json',
    JSON.stringify(deploymentInfo, null, 2)
  );

  console.log("📄 Deployment info saved to deployment-info.json");

  console.log("\n🔮 Next Steps:");
  console.log("1. Verify contracts on Etherscan");
  console.log("2. Set up frontend integration");
  console.log("3. Configure IPFS for NFT metadata");
  console.log("4. Test the mutual rating system");
}

main().catch((error) => {
  console.error("❌ Deployment failed:", error);
  process.exitCode = 1;
});