// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/YieldProxy.sol";
import "../contracts/strategies/AaveYieldStrategy.sol";
import "../contracts/AladdinToken.sol";

contract MockAaveLendingPool {
    IERC20 public asset;
    IERC20 public aToken;
    uint256 public constant APR = 300; // 3%

    mapping(address => uint256) public deposits;

    constructor(address _asset, address _aToken) {
        asset = IERC20(_asset);
        aToken = IERC20(_aToken);
    }

    function deposit(address assetAddress, uint256 amount, address onBehalfOf, uint16) external {
        require(assetAddress == address(asset), "Invalid asset");
        asset.transferFrom(msg.sender, address(this), amount);
        deposits[onBehalfOf] += amount;
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address assetAddress, uint256 amount, address to) external returns (uint256) {
        require(assetAddress == address(asset), "Invalid asset");
        uint256 userDeposit = deposits[to];
        uint256 withdrawAmount = amount > userDeposit ? userDeposit : amount;

        deposits[to] -= withdrawAmount;
        aToken.burn(msg.sender, withdrawAmount);
        asset.transfer(to, withdrawAmount);

        return withdrawAmount;
    }

    function getUserAccountData(address) external pure returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return (0, 0, 0, 0, 0, 0);
    }
}

contract MockAToken is AladdinToken {
    address public immutable UNDERLYING_ASSET_ADDRESS;
    address public incentivesController;

    constructor(address _underlying, address _incentivesController) AladdinToken("aToken", "aToken") {
        UNDERLYING_ASSET_ADDRESS = _underlying;
        incentivesController = _incentivesController;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function getIncentivesController() external view returns (address) {
        return incentivesController;
    }
}

contract MockIncentivesController {
    mapping(address => uint256) public rewards;

    function setRewards(address user, uint256 amount) external {
        rewards[user] = amount;
    }

    function getRewardsBalance(address[] calldata, address user) external view returns (uint256) {
        return rewards[user];
    }

    function claimRewards(address[] calldata, uint256 amount, address to) external returns (uint256) {
        uint256 userRewards = rewards[to];
        uint256 claimAmount = amount > userRewards ? userRewards : amount;
        rewards[to] -= claimAmount;
        return claimAmount;
    }
}

contract YieldProxyTest is Test {
    YieldProxy public yieldProxy;
    AaveYieldStrategy public aaveStrategy;
    MockAaveLendingPool public mockLendingPool;
    MockAToken public mockAToken;
    MockIncentivesController public mockIncentivesController;
    AladdinToken public usdtToken;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    uint256 public constant DEPOSIT_AMOUNT = 1000 * 10**6; // 1000 USDT
    uint256 public constant YIELD_AMOUNT = 10 * 10**6; // 10 USDT yield

    function setUp() public {
        // Start prank as owner
        vm.startPrank(owner);

        // Deploy tokens
        usdtToken = new AladdinToken();
        usdtToken.mint(owner, 1000000 * 10**6);
        usdtToken.mint(user1, 100000 * 10**6);
        usdtToken.mint(user2, 100000 * 10**6);

        // Deploy mock contracts
        mockAToken = new MockAToken(address(usdtToken), address(0));
        mockIncentivesController = new MockIncentivesController();
        mockLendingPool = new MockAaveLendingPool(address(usdtToken), address(mockAToken));

        // Deploy strategy
        aaveStrategy = new AaveYieldStrategy(
            address(usdtToken),
            address(mockAToken),
            address(mockLendingPool)
        );

        // Deploy YieldProxy
        yieldProxy = new YieldProxy(address(usdtToken));

        // Authorize strategy
        yieldProxy.authorizeStrategy(address(aaveStrategy));

        // Switch to the strategy
        yieldProxy.switchStrategy(address(aaveStrategy));

        vm.stopPrank();
    }

    function testDeposit() public {
        vm.startPrank(user1);

        uint256 balanceBefore = usdtToken.balanceOf(user1);
        usdtToken.approve(address(yieldProxy), DEPOSIT_AMOUNT);

        yieldProxy.deposit(DEPOSIT_AMOUNT);

        uint256 balanceAfter = usdtToken.balanceOf(user1);
        assertEq(balanceBefore - balanceAfter, DEPOSIT_AMOUNT, unicode"用户余额应该减少");
        assertEq(yieldProxy.userDeposits(user1), DEPOSIT_AMOUNT, unicode"用户存款应该正确记录");
        assertEq(yieldProxy.userPrincipal(user1), DEPOSIT_AMOUNT, unicode"用户本金应该正确记录");
        assertEq(yieldProxy.totalDeposits(), DEPOSIT_AMOUNT, unicode"总存款应该正确记录");

        vm.stopPrank();
    }

    function testDepositZeroAmount() public {
        vm.startPrank(user1);
        usdtToken.approve(address(yieldProxy), 100);

        vm.expectRevert();
        yieldProxy.deposit(0);

        vm.stopPrank();
    }

    function testWithdraw() public {
        // First deposit
        vm.startPrank(user1);
        usdtToken.approve(address(yieldProxy), DEPOSIT_AMOUNT);
        yieldProxy.deposit(DEPOSIT_AMOUNT);

        // Add some yield by minting extra aTokens
        mockAToken.mint(address(yieldProxy), YIELD_AMOUNT);

        uint256 balanceBefore = usdtToken.balanceOf(user1);
        yieldProxy.withdraw(DEPOSIT_AMOUNT / 2);

        uint256 balanceAfter = usdtToken.balanceOf(user1);
        assertEq(yieldProxy.userDeposits(user1), DEPOSIT_AMOUNT / 2, unicode"用户存款应该减少");
        assertEq(yieldProxy.userPrincipal(user1), DEPOSIT_AMOUNT / 2, unicode"用户本金应该减少");

        vm.stopPrank();
    }

    function testWithdrawAll() public {
        // First deposit
        vm.startPrank(user1);
        usdtToken.approve(address(yieldProxy), DEPOSIT_AMOUNT);
        yieldProxy.deposit(DEPOSIT_AMOUNT);

        // Add some yield
        mockAToken.mint(address(yieldProxy), YIELD_AMOUNT);

        uint256 balanceBefore = usdtToken.balanceOf(user1);
        yieldProxy.withdrawAll();

        uint256 balanceAfter = usdtToken.balanceOf(user1);
        assertEq(yieldProxy.userDeposits(user1), 0, unicode"用户存款应该为0");
        assertEq(yieldProxy.userPrincipal(user1), 0, unicode"用户本金应该为0");

        vm.stopPrank();
    }

    function testClaimYield() public {
        // Deposit first
        vm.startPrank(user1);
        usdtToken.approve(address(yieldProxy), DEPOSIT_AMOUNT);
        yieldProxy.deposit(DEPOSIT_AMOUNT);

        // Add yield
        mockAToken.mint(address(yieldProxy), YIELD_AMOUNT);

        uint256 balanceBefore = usdtToken.balanceOf(user1);
        uint256 yieldBefore = yieldProxy.getUserEstimatedYield(user1);
        yieldProxy.claimYield();

        uint256 balanceAfter = usdtToken.balanceOf(user1);
        uint256 expectedYield = (yieldBefore * 9900) / 10000; // After 1% fee

        assertEq(balanceAfter - balanceBefore, expectedYield, unicode"用户应该收到收益");

        vm.stopPrank();
    }

    function testStrategySwitch() public {
        vm.startPrank(owner);

        // Deploy new strategy
        AaveYieldStrategy newStrategy = new AaveYieldStrategy(
            address(usdtToken),
            address(mockAToken),
            address(mockLendingPool)
        );

        // Authorize new strategy
        yieldProxy.authorizeStrategy(address(newStrategy));

        // Switch strategy
        address oldStrategy = address(yieldProxy.currentStrategy());
        yieldProxy.switchStrategy(address(newStrategy));

        assertEq(address(yieldProxy.currentStrategy()), address(newStrategy), unicode"策略应该切换");

        vm.stopPrank();
    }

    function testUnauthorizedStrategy() public {
        vm.startPrank(owner);

        // Deploy unauthorized strategy
        AaveYieldStrategy unauthorizedStrategy = new AaveYieldStrategy(
            address(usdtToken),
            address(mockAToken),
            address(mockLendingPool)
        );

        // Try to switch without authorization
        vm.expectRevert();
        yieldProxy.switchStrategy(address(unauthorizedStrategy));

        vm.stopPrank();
    }

    function testMultipleUsers() public {
        // User 1 deposits
        vm.startPrank(user1);
        usdtToken.approve(address(yieldProxy), DEPOSIT_AMOUNT);
        yieldProxy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        usdtToken.approve(address(yieldProxy), DEPOSIT_AMOUNT * 2);
        yieldProxy.deposit(DEPOSIT_AMOUNT * 2);
        vm.stopPrank();

        // Add yield
        mockAToken.mint(address(yieldProxy), YIELD_AMOUNT);

        // Check estimated yields
        uint256 user1Yield = yieldProxy.getUserEstimatedYield(user1);
        uint256 user2Yield = yieldProxy.getUserEstimatedYield(user2);

        // User 2 should get approximately 2x yield of user 1
        assertEq(user2Yield, user1Yield * 2, unicode"收益应该按比例分配");
    }

    function testGetBalance() public {
        vm.startPrank(user1);
        usdtToken.approve(address(yieldProxy), DEPOSIT_AMOUNT);
        yieldProxy.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 balance = yieldProxy.getTotalBalance();
        assertEq(balance, DEPOSIT_AMOUNT, unicode"总余额应该等于存款金额");
    }

    function testGetCurrentAPR() public {
        uint256 apr = yieldProxy.getCurrentAPR();
        assertEq(apr, 300, unicode"APR应该为300基点(3%)");
    }
}