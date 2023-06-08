import { expect } from 'chai';
import { ethers } from 'hardhat';

describe('OptimisticISM', function () {
  const FRAUD_WINDOW_DURATION = 3600; // 1 hour
  let optimisticISM: any;
  let signers: any[] = [];
  let customIsm: { address: any };

  beforeEach(async function () {
    const OptimisticISMFactory = await ethers.getContractFactory(
      'OptimisticIsm',
    );
    signers = await ethers.getSigners();
    optimisticISM = await OptimisticISMFactory.deploy(FRAUD_WINDOW_DURATION);
    await optimisticISM.deployed();

    const CustomIsm = await ethers.getContractFactory('MockCustomIsm');
    customIsm = await CustomIsm.deploy();
  });

  describe('SubModule', function () {
    it('should set and get custom submodule', async function () {
      const SubModule = await ethers.getContractFactory('MockCustomIsm');
      const subModule = await SubModule.deploy();
      await subModule.deployed();

      await optimisticISM.setSubModule(subModule.address);
      expect(await optimisticISM.customIsm()).to.eq(subModule.address);
    });
  });

  describe('Watcher', function () {
    it('should add and remove a watcher', async function () {
      await optimisticISM.addWatcher(signers[1].address);
      expect(await optimisticISM.watcher(signers[1].address)).to.equal(true);

      await optimisticISM.removeWatcher(signers[1].address);
      expect(await optimisticISM.watcher(signers[1].address)).to.equal(false);
    });
  });

  describe('markFraudulent', function () {
    it('should mark an ISM as fraudulent', async function () {
      await optimisticISM.addWatcher(signers[1].address);
      await optimisticISM.connect(signers[1]).markFraudulent(customIsm.address);
      expect(
        await optimisticISM.ismFlaggedTime(customIsm.address),
      ).to.not.equal(0);
    });
  });

  describe('switchIsm', function () {
    it('should switch ISM after marking it as fraudulent', async function () {
      const NewIsm = await ethers.getContractFactory('MockCustomIsm');
      const newIsm = await NewIsm.deploy();

      await optimisticISM.setSubModule(customIsm.address);

      await optimisticISM.addWatcher(signers[0].address);
      await optimisticISM.connect(signers[0]).markFraudulent(customIsm.address);

      await optimisticISM.switchIsm(newIsm.address);
      expect(await optimisticISM.customIsm()).to.equal(newIsm.address);
      expect(await optimisticISM.customIsm()).to.eq(newIsm.address);
    });
  });

  describe('verify & preVerify', () => {
    it('should pre-verify the message and verify', async function () {
      const message = ethers.utils.toUtf8Bytes('message1');
      const metadata = ethers.utils.toUtf8Bytes('metadata1');

      await optimisticISM.preVerify(metadata, message);

      const messageId = ethers.utils.keccak256(message);
      const verification = await optimisticISM.verifiedMessages(messageId);

      expect(verification.ism).to.equal(ethers.constants.AddressZero);
      expect(verification.time).to.not.equal(0);

      await ethers.provider.send('evm_increaseTime', [3600 + 10]);
      await ethers.provider.send('evm_mine', []);

      const verified = await optimisticISM.verify(metadata, message);
      expect(verified).to.be.true;
    });

    it('should pre-verify the message and verify with custom ism', async function () {
      const DefaultIsmModule = await ethers.getContractFactory('MockCustomIsm');
      const defaultIsmModule = await DefaultIsmModule.deploy();

      // Set the submodule as the verifier
      await optimisticISM.setSubModule(defaultIsmModule.address);

      const message = ethers.utils.toUtf8Bytes('message');
      const metadata = ethers.utils.toUtf8Bytes('metadata');

      await optimisticISM.preVerify(metadata, message);

      const messageId = ethers.utils.keccak256(message);
      const verification = await optimisticISM.verifiedMessages(messageId);

      expect(verification.ism).to.equal(defaultIsmModule.address);
      expect(verification.time).to.not.equal(0);

      await ethers.provider.send('evm_increaseTime', [3600 + 10]);
      await ethers.provider.send('evm_mine', []);

      // Try pre-verifying the same message again, should fail
      await expect(
        optimisticISM.preVerify(metadata, message),
      ).to.be.revertedWith(
        'Message has already been proposed for verification',
      );

      const verified = await optimisticISM.verify(metadata, message);
      expect(verified).to.be.true;
    });

    it('should not verify the message if fraud window has elapsed', async function () {
      const message = ethers.utils.toUtf8Bytes('message');
      const metadata = ethers.utils.toUtf8Bytes('metadata');
      await optimisticISM.preVerify(metadata, message);

      // Simulate passage of time beyond fraud window
      await ethers.provider.send('evm_increaseTime', [1500]); // Increase time
      await ethers.provider.send('evm_mine'); // Mine the next block

      const verified = await optimisticISM.verify(metadata, message);
      expect(verified).to.be.false;
    });
  });
});
