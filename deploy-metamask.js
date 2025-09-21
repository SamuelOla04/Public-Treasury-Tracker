const { ethers } = require("hardhat");

async function main() {
    console.log("🦊 METAMASK TREASURY VAULT DEPLOYMENT");
    console.log("=====================================");
    
    // Connect to MetaMask (will prompt user)
    const [deployer] = await ethers.getSigners();
    console.log(`📝 Deploying with MetaMask account: ${deployer.address}`);
    
    // Get network info
    const network = await ethers.provider.getNetwork();
    console.log(`🌐 Network: ${network.name} (Chain ID: ${network.chainId})`);
    
    // Check balance
    const balance = await deployer.getBalance();
    console.log(`💰 Account balance: ${ethers.utils.formatEther(balance)} ETH`);
    
    // Verify sufficient balance for deployment
    if (balance.lt(ethers.utils.parseEther("0.01"))) {
        console.log("⚠️  WARNING: Low balance! You may need more ETH for gas fees.");
        if (network.name === "sepolia") {
            console.log("🔗 Get test ETH: https://faucets.chain.link/sepolia");
        }
    }
    
    // ============ DEPLOYMENT CONFIGURATION ============
    console.log("\n⚙️ DEPLOYMENT CONFIGURATION:");
    
    // Define initial treasury managers (using valid local test addresses)
    const initialManagers = [
        deployer.address,                                    // Deployer as first manager
        "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",        // Account #1 from local node
        "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"         // Account #2 from local node
    ];
    
    // Security configuration
    const requiredConfirmations = 2;                        // Need 2 out of 3 approvals
    const dailyWithdrawalLimit = ethers.utils.parseEther("5"); // 5 ETH daily limit (lower for testing)
    
    console.log(`👥 Initial Managers: ${initialManagers.length}`);
    console.log(`✅ Required Confirmations: ${requiredConfirmations}`);
    console.log(`💵 Daily Withdrawal Limit: ${ethers.utils.formatEther(dailyWithdrawalLimit)} ETH`);
    
    // Ask user to confirm before proceeding
    console.log("\n🔍 PLEASE CONFIRM IN METAMASK:");
    console.log("- Check the network (should be Sepolia for testing)");
    console.log("- Review gas fees");
    console.log("- Approve the transaction");
    
    // ============ CONTRACT DEPLOYMENT ============
    console.log("\n🏗️ DEPLOYING CONTRACT...");
    console.log("(This will open MetaMask for confirmation)");
    
    try {
        // Get the contract factory
        const TreasuryVault = await ethers.getContractFactory("TreasuryVault");
        
        // Deploy the contract (MetaMask will prompt for approval)
        const treasuryVault = await TreasuryVault.deploy(
            initialManagers,
            requiredConfirmations,
            dailyWithdrawalLimit
        );
        
        console.log("⏳ Waiting for deployment confirmation...");
        
        // Wait for deployment to complete
        await treasuryVault.deployed();
        
        console.log("✅ TreasuryVault deployed successfully!");
        console.log(`📍 Contract Address: ${treasuryVault.address}`);
        
        // ============ DEPLOYMENT VERIFICATION ============
        console.log("\n🔍 VERIFYING DEPLOYMENT...");
        
        // Get deployment transaction
        const deployTx = treasuryVault.deployTransaction;
        console.log(`📄 Transaction Hash: ${deployTx.hash}`);
        console.log(`⛽ Gas Used: ${deployTx.gasLimit.toString()}`);
        
        // Verify initial configuration
        const actualRequiredConfirmations = await treasuryVault.requiredConfirmations();
        const actualDailyLimit = await treasuryVault.dailyWithdrawalLimit();
        const firstManager = await treasuryVault.treasuryManagers(0);
        
        console.log("\n📊 VERIFICATION RESULTS:");
        console.log(`✅ Required Confirmations: ${actualRequiredConfirmations}`);
        console.log(`✅ Daily Limit: ${ethers.utils.formatEther(actualDailyLimit)} ETH`);
        console.log(`✅ First Manager: ${firstManager}`);
        
        // ============ NEXT STEPS ============
        console.log("\n📋 DEPLOYMENT SUMMARY:");
        console.log("======================");
        console.log(`🏦 Treasury Contract: ${treasuryVault.address}`);
        console.log(`🌐 Network: ${network.name}`);
        console.log(`🔗 Etherscan: https://${network.name === 'sepolia' ? 'sepolia.' : ''}etherscan.io/address/${treasuryVault.address}`);
        
        console.log("\n🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!");
        console.log("Your Treasury Vault is now live! 🛡️");
        
        if (network.name === "sepolia") {
            console.log("\n🧪 TESTING PHASE:");
            console.log("- This is on testnet with fake ETH");
            console.log("- Test all functions before mainnet");
            console.log("- Verify on Sepolia Etherscan");
        }
        
        return treasuryVault.address;
        
    } catch (error) {
        if (error.code === 4001) {
            console.log("❌ User rejected transaction in MetaMask");
        } else {
            console.log("❌ Deployment failed:", error.message);
        }
        throw error;
    }
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
