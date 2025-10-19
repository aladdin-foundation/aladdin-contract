import "dotenv/config";
import hre from "hardhat";

const { ethers, network } = hre;

const PRESET_USDT = {
  sepolia: "0x7169D38820dfd117C3FA1f22a697dBA58d90BA06",
};

async function deployAladdinToken(label, owner) {
  const factory = await ethers.getContractFactory("AladdinToken");
  const token = await factory.deploy(owner);
  await token.waitForDeployment();
  const address = await token.getAddress();
  console.log(`${label} 已部署: ${address}`);
  return address;
}

async function resolveUsdtAddress(deployer) {
  const preset = PRESET_USDT[network.name];
  if (preset && ethers.isAddress(preset)) {
    console.log(`使用预设 ${network.name} USDT 地址: ${preset}`);
    return preset;
  }

  console.log(
    `网络 ${network.name} 未配置预设 USDT，将部署测试代币用作支付代币...`
  );
  return deployAladdinToken("MockUSDT", deployer.address);
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`部署账户: ${deployer.address}`);

  const usdtAddress = await resolveUsdtAddress(deployer);

  const AgentMarket = await ethers.getContractFactory("AgentMarket");
  const agentMarket = await AgentMarket.deploy(usdtAddress, ethers.ZeroAddress);
  await agentMarket.waitForDeployment();
  const agentMarketAddress = await agentMarket.getAddress();
  console.log(`AgentMarket 部署成功: ${agentMarketAddress}`);

  const rewardTokenAddress = await deployAladdinToken(
    "AladdinToken (Reward)",
    deployer.address
  );

  const RewardManager = await ethers.getContractFactory("RewardManager");
  const rewardManager = await RewardManager.deploy(
    rewardTokenAddress,
    agentMarketAddress
  );
  await rewardManager.waitForDeployment();
  const rewardManagerAddress = await rewardManager.getAddress();
  console.log(`RewardManager 部署成功: ${rewardManagerAddress}`);

  const setTx = await agentMarket.setRewardManager(rewardManagerAddress);
  await setTx.wait();
  console.log("AgentMarket 已成功绑定 RewardManager。");

  console.log("\n部署完成，关键地址：");
  console.log(`USDT Token:      ${usdtAddress}`);
  console.log(`AgentMarket:     ${agentMarketAddress}`);
  console.log(`Reward Token:    ${rewardTokenAddress}`);
  console.log(`RewardManager:   ${rewardManagerAddress}`);
  console.log(
    "\n提示：RewardManager 奖励池初始余额为 0，可按需手动调用奖励代币合约 transfer() 转入额度。"
  );
}

main().catch((error) => {
  console.error("部署失败:", error);
  process.exitCode = 1;
});
