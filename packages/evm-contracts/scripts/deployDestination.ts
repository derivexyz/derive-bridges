import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying OFTDestination with account:', deployer.address);
  console.log('Account balance:', (await ethers.provider.getBalance(deployer.address)).toString());

  // Configuration
  const tokenName = process.env.TOKEN_NAME || 'Canonical Bridge Token';
  const tokenSymbol = process.env.TOKEN_SYMBOL || 'CBTKN';
  const lzEndpoint = process.env.LAYERZERO_ENDPOINT;
  const supplyCap = process.env.SUPPLY_CAP || '0'; // 0 = unlimited

  if (!lzEndpoint) {
    throw new Error('LAYERZERO_ENDPOINT not set');
  }

  console.log('Deployment parameters:');
  console.log('- Token Name:', tokenName);
  console.log('- Token Symbol:', tokenSymbol);
  console.log('- LayerZero Endpoint:', lzEndpoint);
  console.log('- Supply Cap:', supplyCap, '(0 = unlimited)');

  const OFTDestination = await ethers.getContractFactory('OFTDestination');
  const oftDestination = await OFTDestination.deploy(
    tokenName,
    tokenSymbol,
    lzEndpoint,
    ethers.parseEther(supplyCap)
  );

  await oftDestination.waitForDeployment();

  const address = await oftDestination.getAddress();
  console.log('OFTDestination deployed to:', address);

  // Save deployment info
  console.log('\nDeployment Info:');
  console.log(JSON.stringify({
    contract: 'OFTDestination',
    address: address,
    network: (await ethers.provider.getNetwork()).name,
    deployer: deployer.address,
    tokenName,
    tokenSymbol,
    lzEndpoint,
    supplyCap,
  }, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
