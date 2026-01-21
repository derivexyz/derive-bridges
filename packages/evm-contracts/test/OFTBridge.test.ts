import { expect } from 'chai';
import { ethers } from 'hardhat';
import { OFTSource, OFTDestination, MockLayerZeroEndpoint } from '../typechain-types';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

describe('OFT Bridge - Many to One', function () {
  let sourceOFT1: OFTSource;
  let sourceOFT2: OFTSource;
  let destinationOFT: OFTDestination;
  let mockEndpointSource1: MockLayerZeroEndpoint;
  let mockEndpointSource2: MockLayerZeroEndpoint;
  let mockEndpointDest: MockLayerZeroEndpoint;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  const DESTINATION_CHAIN_ID = 1;
  const SOURCE_CHAIN_ID_1 = 101;
  const SOURCE_CHAIN_ID_2 = 102;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy mock endpoints
    const MockEndpoint = await ethers.getContractFactory('MockLayerZeroEndpoint');
    mockEndpointSource1 = await MockEndpoint.deploy();
    mockEndpointSource2 = await MockEndpoint.deploy();
    mockEndpointDest = await MockEndpoint.deploy();

    // Deploy destination OFT
    const OFTDestFactory = await ethers.getContractFactory('OFTDestination');
    destinationOFT = await OFTDestFactory.deploy(
      'Canonical Token',
      'CTKN',
      await mockEndpointDest.getAddress(),
      0 // No supply cap
    );

    // Deploy source OFTs
    const OFTSourceFactory = await ethers.getContractFactory('OFTSource');
    sourceOFT1 = await OFTSourceFactory.deploy(
      'Source Token 1',
      'STKN1',
      await mockEndpointSource1.getAddress(),
      DESTINATION_CHAIN_ID
    );

    sourceOFT2 = await OFTSourceFactory.deploy(
      'Source Token 2',
      'STKN2',
      await mockEndpointSource2.getAddress(),
      DESTINATION_CHAIN_ID
    );

    // Setup trusted remotes
    const destAddress = await destinationOFT.getAddress();
    const source1Address = await sourceOFT1.getAddress();
    const source2Address = await sourceOFT2.getAddress();

    await sourceOFT1.setDestinationAddress(
      ethers.solidityPacked(['address'], [destAddress])
    );
    await sourceOFT2.setDestinationAddress(
      ethers.solidityPacked(['address'], [destAddress])
    );

    await destinationOFT.setTrustedRemote(
      SOURCE_CHAIN_ID_1,
      ethers.solidityPacked(['address'], [source1Address])
    );
    await destinationOFT.setTrustedRemote(
      SOURCE_CHAIN_ID_2,
      ethers.solidityPacked(['address'], [source2Address])
    );

    // Mint initial supply on source chains
    await sourceOFT1.mint(user1.address, ethers.parseEther('1000'));
    await sourceOFT2.mint(user2.address, ethers.parseEther('1000'));
  });

  describe('Deployment', function () {
    it('Should set the correct name and symbol for destination OFT', async function () {
      expect(await destinationOFT.name()).to.equal('Canonical Token');
      expect(await destinationOFT.symbol()).to.equal('CTKN');
    });

    it('Should set the correct name and symbol for source OFTs', async function () {
      expect(await sourceOFT1.name()).to.equal('Source Token 1');
      expect(await sourceOFT1.symbol()).to.equal('STKN1');
      expect(await sourceOFT2.name()).to.equal('Source Token 2');
      expect(await sourceOFT2.symbol()).to.equal('STKN2');
    });

    it('Should set the correct destination chain ID', async function () {
      expect(await sourceOFT1.destinationChainId()).to.equal(DESTINATION_CHAIN_ID);
      expect(await sourceOFT2.destinationChainId()).to.equal(DESTINATION_CHAIN_ID);
    });
  });

  describe('Bridge Tokens from Source to Destination', function () {
    it('Should burn tokens on source chain and mint on destination', async function () {
      const amount = ethers.parseEther('100');
      const fee = await mockEndpointSource1.mockNativeFee();

      // Check initial balances
      expect(await sourceOFT1.balanceOf(user1.address)).to.equal(ethers.parseEther('1000'));
      expect(await destinationOFT.balanceOf(user1.address)).to.equal(0);

      // Send tokens from source to destination
      await sourceOFT1
        .connect(user1)
        .sendToChain(
          DESTINATION_CHAIN_ID,
          ethers.solidityPacked(['address'], [user1.address]),
          amount,
          { value: fee }
        );

      // Check source balance decreased
      expect(await sourceOFT1.balanceOf(user1.address)).to.equal(ethers.parseEther('900'));

      // Simulate LayerZero delivery
      const payload = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes', 'uint256'],
        [ethers.solidityPacked(['address'], [user1.address]), amount]
      );

      await mockEndpointDest.deliverMessage(
        SOURCE_CHAIN_ID_1,
        ethers.solidityPacked(['address'], [await sourceOFT1.getAddress()]),
        await destinationOFT.getAddress(),
        1,
        payload
      );

      // Check destination balance increased
      expect(await destinationOFT.balanceOf(user1.address)).to.equal(amount);
    });

    it('Should support multiple source chains bridging to one destination', async function () {
      const amount1 = ethers.parseEther('100');
      const amount2 = ethers.parseEther('200');
      const fee = await mockEndpointSource1.mockNativeFee();

      // Send from source 1
      await sourceOFT1
        .connect(user1)
        .sendToChain(
          DESTINATION_CHAIN_ID,
          ethers.solidityPacked(['address'], [user1.address]),
          amount1,
          { value: fee }
        );

      // Send from source 2
      await sourceOFT2
        .connect(user2)
        .sendToChain(
          DESTINATION_CHAIN_ID,
          ethers.solidityPacked(['address'], [user2.address]),
          amount2,
          { value: fee }
        );

      // Simulate LayerZero delivery from source 1
      const payload1 = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes', 'uint256'],
        [ethers.solidityPacked(['address'], [user1.address]), amount1]
      );

      await mockEndpointDest.deliverMessage(
        SOURCE_CHAIN_ID_1,
        ethers.solidityPacked(['address'], [await sourceOFT1.getAddress()]),
        await destinationOFT.getAddress(),
        1,
        payload1
      );

      // Simulate LayerZero delivery from source 2
      const payload2 = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes', 'uint256'],
        [ethers.solidityPacked(['address'], [user2.address]), amount2]
      );

      await mockEndpointDest.deliverMessage(
        SOURCE_CHAIN_ID_2,
        ethers.solidityPacked(['address'], [await sourceOFT2.getAddress()]),
        await destinationOFT.getAddress(),
        1,
        payload2
      );

      // Check destination balances
      expect(await destinationOFT.balanceOf(user1.address)).to.equal(amount1);
      expect(await destinationOFT.balanceOf(user2.address)).to.equal(amount2);
    });

    it('Should revert if insufficient fee is provided', async function () {
      const amount = ethers.parseEther('100');

      await expect(
        sourceOFT1
          .connect(user1)
          .sendToChain(
            DESTINATION_CHAIN_ID,
            ethers.solidityPacked(['address'], [user1.address]),
            amount,
            { value: 0 }
          )
      ).to.be.reverted;
    });

    it('Should revert if trying to send to wrong destination chain', async function () {
      const amount = ethers.parseEther('100');
      const fee = await mockEndpointSource1.mockNativeFee();

      await expect(
        sourceOFT1
          .connect(user1)
          .sendToChain(
            999, // Wrong chain ID
            ethers.solidityPacked(['address'], [user1.address]),
            amount,
            { value: fee }
          )
      ).to.be.revertedWithCustomError(sourceOFT1, 'InvalidDestinationChain');
    });
  });

  describe('Bridge Tokens from Destination to Source', function () {
    beforeEach(async function () {
      // First bridge some tokens to destination
      const amount = ethers.parseEther('100');
      const fee = await mockEndpointSource1.mockNativeFee();

      await sourceOFT1
        .connect(user1)
        .sendToChain(
          DESTINATION_CHAIN_ID,
          ethers.solidityPacked(['address'], [user1.address]),
          amount,
          { value: fee }
        );

      const payload = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes', 'uint256'],
        [ethers.solidityPacked(['address'], [user1.address]), amount]
      );

      await mockEndpointDest.deliverMessage(
        SOURCE_CHAIN_ID_1,
        ethers.solidityPacked(['address'], [await sourceOFT1.getAddress()]),
        await destinationOFT.getAddress(),
        1,
        payload
      );
    });

    it('Should burn tokens on destination and mint on source', async function () {
      const amount = ethers.parseEther('50');
      const fee = await mockEndpointDest.mockNativeFee();

      // Check initial balances
      expect(await destinationOFT.balanceOf(user1.address)).to.equal(ethers.parseEther('100'));

      // Send back to source
      await destinationOFT
        .connect(user1)
        .sendToChain(
          SOURCE_CHAIN_ID_1,
          ethers.solidityPacked(['address'], [user1.address]),
          amount,
          { value: fee }
        );

      // Check destination balance decreased
      expect(await destinationOFT.balanceOf(user1.address)).to.equal(ethers.parseEther('50'));

      // Simulate LayerZero delivery back to source
      const payload = ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'uint256'],
        [user1.address, amount]
      );

      await mockEndpointSource1.deliverMessage(
        DESTINATION_CHAIN_ID,
        ethers.solidityPacked(['address'], [await destinationOFT.getAddress()]),
        await sourceOFT1.getAddress(),
        1,
        payload
      );

      // Check source balance (original 900 + returned 50 = 950)
      expect(await sourceOFT1.balanceOf(user1.address)).to.equal(ethers.parseEther('950'));
    });
  });

  describe('Security and Access Control', function () {
    it('Should only allow owner to set trusted remotes', async function () {
      await expect(
        destinationOFT
          .connect(user1)
          .setTrustedRemote(999, ethers.solidityPacked(['address'], [user1.address]))
      ).to.be.revertedWithCustomError(destinationOFT, 'OwnableUnauthorizedAccount');
    });

    it('Should only allow owner to pause', async function () {
      await expect(
        sourceOFT1.connect(user1).setPaused(true)
      ).to.be.revertedWithCustomError(sourceOFT1, 'OwnableUnauthorizedAccount');
    });

    it('Should revert when paused', async function () {
      await sourceOFT1.setPaused(true);

      const amount = ethers.parseEther('100');
      const fee = await mockEndpointSource1.mockNativeFee();

      await expect(
        sourceOFT1
          .connect(user1)
          .sendToChain(
            DESTINATION_CHAIN_ID,
            ethers.solidityPacked(['address'], [user1.address]),
            amount,
            { value: fee }
          )
      ).to.be.revertedWithCustomError(sourceOFT1, 'ContractPaused');
    });

    it('Should reject messages from untrusted remotes', async function () {
      const amount = ethers.parseEther('100');
      const payload = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes', 'uint256'],
        [ethers.solidityPacked(['address'], [user1.address]), amount]
      );

      // Try to deliver from an untrusted source
      await expect(
        mockEndpointDest.deliverMessage(
          999, // Untrusted chain ID
          ethers.solidityPacked(['address'], [user2.address]),
          await destinationOFT.getAddress(),
          1,
          payload
        )
      ).to.be.revertedWithCustomError(destinationOFT, 'UntrustedRemote');
    });
  });

  describe('Fee Estimation', function () {
    it('Should estimate fees correctly', async function () {
      const amount = ethers.parseEther('100');
      const expectedFee = await mockEndpointSource1.mockNativeFee();

      const estimatedFee = await sourceOFT1.estimateSendFee(DESTINATION_CHAIN_ID, amount);

      expect(estimatedFee).to.equal(expectedFee);
    });
  });
});
