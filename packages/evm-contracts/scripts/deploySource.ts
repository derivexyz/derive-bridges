import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying OFTSource with account:', deployer.address);
  console.log('Account balance:', (await ethers.provider.getBalance(deployer.address)).toString());

  // Configuration
  const tokenName = process.env.TOKEN_NAME || 'Bridge Token';
  const tokenSymbol = process.env.TOKEN_SYMBOL || 'BTKN';
  const lzEndpoint = process.env.LAYERZERO_ENDPOINT;
  const destinationChainId = process.env.DESTINATION_CHAIN_ID || '1';

  if (!lzEndpoint) {
    throw new Error('LAYERZERO_ENDPOINT not set');
  }

  console.log('Deployment parameters:');
  console.log('- Token Name:', tokenName);
  console.log('- Token Symbol:', tokenSymbol);
  console.log('- LayerZero Endpoint:', lzEndpoint);
  console.log('- Destination Chain ID:', destinationChainId);

  const OFTSource = await ethers.getContractFactory('OFTSource');
  const oftSource = await OFTSource.deploy(
    tokenName,
    tokenSymbol,
    lzEndpoint,
    parseInt(destinationChainId)
  );

  await oftSource.waitForDeployment();

  const address = await oftSource.getAddress();
  console.log('OFTSource deployed to:', address);

  // Save deployment info
  console.log('\nDeployment Info:');
  console.log(JSON.stringify({
    contract: 'OFTSource',
    address: address,
    network: (await ethers.provider.getNetwork()).name,
    deployer: deployer.address,
    tokenName,
    tokenSymbol,
    lzEndpoint,
    destinationChainId,
  }, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
