#!/usr/bin/env node

import "dotenv/config";
import fs from "fs";
import path from "path";
import { exec } from "child_process";
import { promisify } from "util";

const execAsync = promisify(exec);

// 网络配置映射 - 定义不同链的区块浏览器地址
// 扩展性强，可根据需要添加更多网络
const LEGACY_NETWORKS: Record<string, string> = {
  "chain-11155111": "sepolia", // Sepolia 测试网
  "chain-31337": "localhost", // 本地网络
  "chain-1": "mainnet", // 以太坊主网
  "chain-10143": "monadTestnet", // Monad 测试网
  "chain-8453": "base", // Base 主网
  "chain-84532": "baseSepolia", // Base Sepolia 测试网
  "chain-137": "polygon", // Polygon 主网
  "chain-80002": "polygonAmoy", // Polygon Amoy 测试网
  "chain-42161": "arbitrum", // Arbitrum One
  "chain-421614": "arbitrumSepolia", // Arbitrum Sepolia 测试网
  "chain-10": "optimism", // Optimism 主网
  "chain-11155420": "optimismSepolia", // Optimism Sepolia 测试网
};

// 类型定义
interface ContractInfo {
  contractName: string;
  address: string;
}

interface DeploymentInfo {
  addresses: Record<string, string>;
  networkName: string;
  latestDeployment: string;
}

interface VerifyCommand {
  contractName: string;
  address: string;
  command: string;
  args: string[];
  blockscoutCommand?: string;
}

// 辅助函数：从已部署地址文件中提取地址
function loadDeployedAddresses(): DeploymentInfo {
  const deploymentsDir = path.join(process.cwd(), "ignition/deployments");

  if (!fs.existsSync(deploymentsDir)) {
    throw new Error("未找到部署目录！请先运行部署。");
  }

  // 查找最新的部署目录
  const deployments = fs
    .readdirSync(deploymentsDir, { withFileTypes: true })
    .filter((dirent) => dirent.isDirectory())
    .map((dirent) => dirent.name)
    .sort((a, b) => b.localeCompare(a)); // 最新在前

  if (deployments.length === 0) {
    throw new Error("未找到任何部署记录！");
  }

  const latestDeployment = deployments[0];
  const addressesFile = path.join(
    deploymentsDir,
    latestDeployment,
    "deployed_addresses.json",
  );

  if (!fs.existsSync(addressesFile)) {
    throw new Error(`未找到部署地址文件：${addressesFile}`);
  }

  const addresses = JSON.parse(fs.readFileSync(addressesFile, "utf-8"));
  const networkName = LEGACY_NETWORKS[latestDeployment] || "unknown";

  return { addresses, networkName, latestDeployment };
}

// 获取部署者地址
function getDeployerAddress(): string {
  // 优先从环境变量获取
  if (process.env.DEPLOYER_ADDRESS) {
    return process.env.DEPLOYER_ADDRESS;
  }

  // 其次从 .env 文件中的私钥解析（需要 ethers）
  // 这里简化处理，使用已知的部署者地址
  const knownDeployer = "0x849fbd15f60b89ec8ae25d074addf95273cbed45";

  try {
    const deploymentsDir = path.join(process.cwd(), "ignition/deployments");
    const deployments = fs
      .readdirSync(deploymentsDir, { withFileTypes: true })
      .filter((dirent) => dirent.isDirectory())
      .map((dirent) => dirent.name)
      .sort((a, b) => b.localeCompare(a));

    if (deployments.length === 0) {
      console.warn("⚠️  未找到部署记录，使用默认部署者地址");
      return knownDeployer;
    }

    const latestDeployment = deployments[0];
    const journalFile = path.join(
      deploymentsDir,
      latestDeployment,
      "journal.jsonl",
    );

    if (!fs.existsSync(journalFile)) {
      console.warn("⚠️  未找到部署日志文件，使用默认部署者地址");
      return knownDeployer;
    }

    const journalData = fs.readFileSync(journalFile, "utf-8");
    const lines = journalData.split("\n");

    // 查找包含 "from" 字段的第一行
    for (const line of lines) {
      if (line.trim() === "") continue;
      try {
        const parsed = JSON.parse(line);
        if (
          parsed.from &&
          parsed.from !== "0x0000000000000000000000000000000000000000"
        ) {
          return parsed.from;
        }
      } catch (e) {
        // 忽略解析错误
      }
    }

    return knownDeployer;
  } catch (error) {
    console.warn("⚠️  获取部署者地址失败，使用默认地址");
    return knownDeployer;
  }
}

// 生成验证命令和参数
function generateVerifyCommands(
  contracts: ContractInfo[],
  networkName: string,
  deployerAddress: string,
): VerifyCommand[] {
  const commands: VerifyCommand[] = [];

  contracts.forEach(({ contractName, address }) => {
    const constructorArgs: string[] = [];

    // 根据合约类型添加构造函数参数
    if (contractName === "AladdinToken") {
      // 需要部署者地址
      constructorArgs.push(deployerAddress);
    } else if (contractName === "AgentMarket") {
      // 需要 USDT 地址和 zero address
      const usdtContract = contracts.find((c) => c.contractName === "MockUSDT");
      if (usdtContract) {
        constructorArgs.push(
          usdtContract.address,
          "0x0000000000000000000000000000000000000000",
        );
      }
    } else if (contractName === "YieldProxy") {
      // 只需要 USDT 地址
      const usdtContract = contracts.find((c) => c.contractName === "MockUSDT");
      if (usdtContract) {
        constructorArgs.push(usdtContract.address);
      }
    } else if (contractName === "RewardManager") {
      // 需要 AladdinToken 和 AgentMarket 地址
      const aladdinTokenContract = contracts.find(
        (c) => c.contractName === "AladdinToken",
      );
      const agentMarketContract = contracts.find(
        (c) => c.contractName === "AgentMarket",
      );
      if (aladdinTokenContract && agentMarketContract) {
        constructorArgs.push(
          aladdinTokenContract.address,
          agentMarketContract.address,
        );
      }
    }

    // 生成 Etherscan 和 Blockscout 两个命令
    const etherscanCmd = `npx hardhat verify --network ${networkName} ${address} ${constructorArgs.join(" ")}`;
    const blockscoutCmd = `npx hardhat verify blockscout --network ${networkName} ${address} ${constructorArgs.join(" ")}`;

    commands.push({
      contractName,
      address,
      command: etherscanCmd,
      args: constructorArgs,
      blockscoutCommand: blockscoutCmd,
    } as VerifyCommand & { blockscoutCommand: string });
  });

  return commands;
}

// 执行单个验证命令
async function executeVerifyCommand(command: VerifyCommand, networkName: string): Promise<boolean> {
  console.log(`\n🔄 正在验证 ${command.contractName}...`);
  console.log(`   地址: ${command.address}`);

  // 首先尝试 Etherscan
  try {
    const { stdout, stderr } = await execAsync(command.command, {
      env: process.env,
    });

    const output = stdout.toLowerCase();

    if (stdout.includes("Successfully verified")) {
      console.log(`✅ ${command.contractName} 验证成功！`);
      console.log(`🔗 Etherscan: https://${networkName}.etherscan.io/address/${command.address}`);
      return true;
    } else if (output.includes("already been verified") || output.includes("already verified")) {
      console.log(`✅ ${command.contractName} 已经验证过了！`);
      console.log(`🔗 Etherscan: https://${networkName}.etherscan.io/address/${command.address}`);
      return true;
    } else {
      // 验证失败但无特殊状态，尝试 Blockscout
      if (command.blockscoutCommand) {
        return await executeBlockscoutVerify(command, networkName);
      }
      return false;
    }
  } catch (error: any) {
    // 检查错误消息中是否包含已验证信息
    const errorMsg = error.message?.toLowerCase() || "";

    if (errorMsg.includes("already been verified") || errorMsg.includes("already verified")) {
      console.log(`✅ ${command.contractName} 已经验证过了！`);
      console.log(`🔗 Etherscan: https://${networkName}.etherscan.io/address/${command.address}`);
      return true;
    }

    // 如果是 API key 错误且有 Blockscout 命令，则尝试 Blockscout
    if (errorMsg.includes("etherscan api key is empty") && command.blockscoutCommand) {
      return await executeBlockscoutVerify(command, networkName);
    }

    console.error(`❌ ${command.contractName} 验证失败:`, error.message);
    return false;
  }
}

// 执行 Blockscout 验证
async function executeBlockscoutVerify(command: VerifyCommand, networkName: string): Promise<boolean> {
  if (!command.blockscoutCommand) {
    return false;
  }

  try {
    const { stdout, stderr } = await execAsync(command.blockscoutCommand, {
      env: process.env,
    });

    const output = stdout.toLowerCase();

    if (stdout.includes("Successfully verified")) {
      console.log(`✅ ${command.contractName} 验证成功！`);
      console.log(`🔗 Blockscout: https://eth-${networkName}.blockscout.com/address/${command.address}?tab=contract`);
      return true;
    } else if (output.includes("already been verified") || output.includes("already verified")) {
      console.log(`✅ ${command.contractName} 已经验证过了！`);
      console.log(`🔗 Blockscout: https://eth-${networkName}.blockscout.com/address/${command.address}?tab=contract`);
      return true;
    } else {
      console.log(`❌ ${command.contractName} 验证失败`);
      if (stderr) {
        console.error(`   错误: ${stderr}`);
      }
      if (stdout) {
        console.error(`   输出: ${stdout}`);
      }
      return false;
    }
  } catch (error: any) {
    // 检查错误消息中是否包含已验证信息
    const errorMsg = error.message?.toLowerCase() || "";

    if (errorMsg.includes("already been verified") || errorMsg.includes("already verified")) {
      console.log(`✅ ${command.contractName} 已经验证过了！`);
      console.log(`🔗 Blockscout: https://eth-${networkName}.blockscout.com/address/${command.address}?tab=contract`);
      return true;
    }

    console.error(`❌ ${command.contractName} 验证失败:`, error.message);
    return false;
  }
}

// 主函数
async function main(): Promise<void> {
  console.log("🔍 自动验证合约\n");

  // 检查 API Key
  const apiKey = "E6T984HMGCVHRGRZV8ZT5RJ3EMTEQS3W6B";
  if (!apiKey) {
    console.error("❌ 错误：请在 .env 文件中设置真实的 ETHERSCAN_API_KEY");
    console.error("   获取 API Key: https://etherscan.io/apis");
    console.error("   当前 API Key:", apiKey || "未设置");
    process.exit(1);
  }

  try {
    // 加载已部署的地址
    const { addresses, networkName, latestDeployment } =
      loadDeployedAddresses();
    console.log(`📂 加载部署记录: ${latestDeployment}`);
    console.log(`🌐 网络: ${networkName}`);

    // 获取部署者地址
    const deployerAddress = getDeployerAddress();
    console.log(`👤 部署者地址: ${deployerAddress}\n`);

    // 获取所有合约地址（排除 aaveYieldStrategy，因为它是可选的）
    const contractsToVerify = Object.entries(addresses)
      .filter(([name]) => !name.includes("AaveYieldStrategy"))
      .map(([name, address]) => {
        // 提取合约名称（去除前缀）
        const contractName = name.split("#")[1] || name;
        return { contractName, address };
      });

    if (contractsToVerify.length === 0) {
      console.log("⚠️  未找到需要验证的合约！");
      return;
    }

    console.log(`📋 待验证的合约 (${contractsToVerify.length}):`);
    contractsToVerify.forEach(({ contractName, address }) => {
      console.log(`   - ${contractName}: ${address}`);
    });

    // 生成验证命令
    const commands = generateVerifyCommands(
      contractsToVerify,
      networkName,
      deployerAddress,
    );

    console.log("\n" + "=".repeat(80));
    console.log("🚀 开始验证所有合约:");
    console.log("=".repeat(80));

    let successCount = 0;
    let failCount = 0;

    // 顺序执行验证命令（避免并发冲突）
    for (const cmd of commands) {
      const success = await executeVerifyCommand(cmd, networkName);
      if (success) {
        successCount++;
      } else {
        failCount++;
      }
      // 添加延迟避免验证API限制
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }

    // 总结
    console.log("\n" + "=".repeat(80));
    console.log("📊 验证结果统计:");
    console.log("=".repeat(80));
    console.log(`✅ 成功: ${successCount}`);
    console.log(`❌ 失败: ${failCount}`);
    console.log(`📊 总计: ${contractsToVerify.length}`);

    if (failCount === 0) {
      console.log("\n🎉 所有合约验证完成！");
    } else {
      console.log("\n⚠️  部分合约验证失败，请检查错误信息");
    }
  } catch (error: any) {
    console.error("\n❌ 验证过程中出错:", error.message);
    process.exit(1);
  }
}

// 运行
main();
