// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import {IInterchainSecurityModule} from "../interfaces/IInterchainSecurityModule.sol";

contract MockCustomIsm is IInterchainSecurityModule {
    // Storage
    bytes public requiredMetadata;

    // Constants
    uint8 public constant moduleType =
        uint8(IInterchainSecurityModule.Types.UNUSED);

    // External functions
    function verify(
        bytes calldata _metadata,
        bytes calldata
    ) external override returns (bool) {
        return true;
    }
}
