const { ethers } = require("hardhat");

async function main() {
    console.log("🚀 STARTING TREASURY VAULT DEPLOYMENT");
    console.log("=====================================");
    
    // Get the deployer account
    const [deployer] = await ethers.getSigners();
    console.log(`📝 Deploying with account: ${deployer.address}`);
    console.log(`💰 Account balance: ${ethers.utils.formatEther(await deployer.getBalance())} ETH`);
    
    // ============ DEPLOYMENT CONFIGURATION ============
    console.log("\n⚙️ DEPLOYMENT CONFIGURATION:");
    
    // Define initial treasury managers (replace with real addresses)
    const initialManagers = [
        deployer.address,                                    // Deployer as first manager
        "0x1234567890123456789012345678901234567890",        // Manager 2 (REPLACE)
        "0x2345678901234567890123456789012345678901"         // Manager 3 (REPLACE)
    ];
    
    // Security configuration
    const requiredConfirmations = 2;                        // Need 2 out of 3 approvals
    const dailyWithdrawalLimit = ethers.utils.parseEther("10"); // 10 ETH daily limit
    
    console.log(`👥 Initial Managers: ${initialManagers.length}`);
    console.log(`✅ Required Confirmations: ${requiredConfirmations}`);
    console.log(`💵 Daily Withdrawal Limit: ${ethers.utils.formatEther(dailyWithdrawalLimit)} ETH`);
    
    // ============ CONTRACT DEPLOYMENT ============
    console.log("\n🏗️ DEPLOYING CONTRACT...");
    
    // Get the contract factory
    const TreasuryVault = await ethers.getContractFactory("TreasuryVault");
    
    // Deploy the contract with initialization parameters
    const treasuryVault = await TreasuryVault.deploy(
        initialManagers,
        requiredConfirmations,
        dailyWithdrawalLimit
    );
    
    // Wait for deployment to complete
    await treasuryVault.deployed();
    
    console.log("✅ TreasuryVault deployed successfully!");
    console.log(`📍 Contract Address: ${treasuryVault.address}`);
    
    // ============ DEPLOYMENT VERIFICATION ============
    console.log("\n🔍 VERIFYING DEPLOYMENT...");
    
    // Check if contract is deployed correctly
    const deployedCode = await ethers.provider.getCode(treasuryVault.address);
    if (deployedCode === "0x") {
        throw new Error("❌ Contract deployment failed - no code at address");
    }
    
    // Verify initial configuration
    const actualRequiredConfirmations = await treasuryVault.requiredConfirmations();
    const actualDailyLimit = await treasuryVault.dailyWithdrawalLimit();
    const managerCount = await treasuryVault.treasuryManagers(0); // Check first manager
    
    console.log("📊 VERIFICATION RESULTS:");
    console.log(`✅ Required Confirmations: ${actualRequiredConfirmations}`);
    console.log(`✅ Daily Limit: ${ethers.utils.formatEther(actualDailyLimit)} ETH`);
    console.log(`✅ First Manager: ${managerCount}`);
    
    // ============ POST-DEPLOYMENT INFO ============
    console.log("\n📋 DEPLOYMENT SUMMARY:");
    console.log("======================");
    console.log(`🏦 Treasury Contract: ${treasuryVault.address}`);
    console.log(`🌐 Network: ${(await ethers.provider.getNetwork()).name}`);
    console.log(`⛽ Gas Used: Will be shown in transaction receipt`);
    console.log(`🔐 Security: Enterprise-grade multi-signature treasury`);
    
    console.log("\n🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!");
    console.log("Your Treasury Vault is now live and ready to secure funds! 🛡️");
    
    return treasuryVault.address;
}

// Execute deployment
main()
    .then((address) => {
        console.log(`\n🚀 Final Contract Address: ${address}`);
        process.exit(0);
    })
    .catch((error) => {
        console.error("❌ Deployment failed:", error);
        process.exit(1);
    });
