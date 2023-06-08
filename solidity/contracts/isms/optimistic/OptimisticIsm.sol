// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import {Message} from "../../libs/Message.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOptimisticIsm} from "../../interfaces/isms/IOptimisticIsm.sol";
import {IInterchainSecurityModule} from "../../interfaces/IInterchainSecurityModule.sol";

// Implements Optimistic Interchain Security Module (ISM)
contract OptimisticIsm is IOptimisticIsm, Ownable {
    using Message for bytes;

    // Constants
    uint8 public constant moduleType =
        uint8(IInterchainSecurityModule.Types.OPTIMISTIC);

    // Time to wait before considering a message valid (in seconds)
    uint256 public immutable timeToWait;

    // Custom Interchain Security Module (ISM)
    IInterchainSecurityModule public customIsm;

    // Structure to track message verification
    struct Verification {
        IInterchainSecurityModule ism;
        uint256 time;
    }

    // Tracks when an ISM was marked as fraudulent
    mapping(IInterchainSecurityModule => uint256) public ismFlaggedTime;

    // Stores verified messages with timestamp and verifying ISM
    mapping(bytes32 => Verification) public verifiedMessages;

    // Holds status of watchers
    mapping(address => bool) public watcher;

    // Only allows a function to be called by a watcher
    modifier onlyWatcher() {
        require(watcher[msg.sender], "Caller is not a watcher");
        _;
    }

    /**
     * @notice Emitted verify is called
     * @param domain The origin domain.
     * @param module The ISM to use.
     */
    event ModuleSet(uint32 indexed domain, IInterchainSecurityModule module);

    constructor(uint256 _timeToWait) {
        timeToWait = _timeToWait;
    }

    // Allows the contract owner to set a custom ISM
    function setSubModule(IInterchainSecurityModule _ism) external onlyOwner {
        customIsm = _ism;
    }

    // Returns the current custom ISM
    function subModule(
        bytes calldata _message
    ) external view override returns (IInterchainSecurityModule) {
        return customIsm;
    }

    // Allows the owner to add a new watcher
    function addWatcher(address _watcher) external onlyOwner {
        require(
            _watcher != address(0),
            "Invalid address: cannot be zero address"
        );
        watcher[_watcher] = true;
    }

    // Allows the owner to remove an existing watcher
    function removeWatcher(address _watcher) external onlyOwner {
        require(
            _watcher != address(0),
            "Invalid address: cannot be zero address"
        );
        watcher[_watcher] = false;
    }

    // Allows a watcher to mark an ISM as fraudulent
    function markFraudulent(
        IInterchainSecurityModule _ism
    ) external override onlyWatcher {
        require(
            address(_ism) != address(0),
            "Invalid address: cannot be zero address"
        );
        ismFlaggedTime[_ism] = block.timestamp;
    }

    // Allows the owner to switch to a new default ISM after previous one has been flagged as fraudulent
    function switchIsm(IInterchainSecurityModule _ism) external onlyOwner {
        IInterchainSecurityModule prevIsm = IInterchainSecurityModule(
            customIsm
        );
        require(
            ismFlaggedTime[prevIsm] > 0,
            "Previous ISM has not been flagged as fraudulent"
        );
        customIsm = IInterchainSecurityModule(_ism);
    }

    // Performs pre-verification of message and adds it to verified messages
    function preVerify(
        bytes calldata _metadata,
        bytes calldata _message
    ) external override returns (bool) {
        if (address(customIsm) != address(0)) {
            require(
                customIsm.verify(_metadata, _message),
                "Verification failed"
            );
        }

        bytes32 messageId = _message.id();
        require(
            verifiedMessages[messageId].time == 0 &&
                address(verifiedMessages[messageId].ism) == address(0),
            "Message has already been proposed for verification"
        );

        verifiedMessages[messageId] = Verification(
            IInterchainSecurityModule(customIsm),
            block.timestamp
        );

        return true;
    }

    // Verifies message & metadata after required waiting time has elapsed and ISM has not been marked as fraudulent
    function verify(
        bytes calldata _metadata,
        bytes calldata _message
    ) external view returns (bool verified) {
        bytes32 messageId = _message.id();

        Verification memory verifyCtx = verifiedMessages[messageId];

        // If the message is not verified or the verifying ISM has been flagged as fraudulent within the time window
        if (
            ismFlaggedTime[verifyCtx.ism] > verifyCtx.time &&
            ismFlaggedTime[verifyCtx.ism] + timeToWait < verifyCtx.time
        ) {
            return false;
        }

        // If enough time has not elapsed since message proposal
        if (isTimeElapsed(verifyCtx.time)) {
            return false;
        }

        if (address(customIsm) != address(0)) {
            (bool success, bytes memory result) = address(customIsm).staticcall(
                abi.encodeWithSelector(
                    customIsm.verify.selector,
                    _metadata,
                    _message
                )
            );
            return
                success && result.length >= 32
                    ? abi.decode(result, (bool))
                    : false;
        }

        return true;
    }

    // Checks if enough time has elapsed since a timestamp
    function isTimeElapsed(uint256 _timestamp) internal view returns (bool) {
        return block.timestamp - _timestamp < timeToWait;
    }
}
