// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Utility library for mining CREATE2 salts that produce hook addresses with required flag bits.
/// Used in deployment scripts only — not deployed on-chain.
library HookMiner {
    // The deterministic CREATE2 factory deployed on most EVM chains.
    address internal constant CREATE2_FACTORY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice Find a salt such that CREATE2(factory, salt, initcodeHash) produces an address
    ///         whose lower 14 bits match `flags` exactly.
    /// @param flags  The required lower-bit pattern (e.g. 0x1F80 for BracketSwapHook)
    /// @param mask   Which bits to check (typically Hooks.ALL_HOOK_MASK = 0x3FFF)
    /// @param creationCode  type(BracketSwapHook).creationCode
    /// @param constructorArgs  abi.encode(...) of constructor arguments
    /// @return salt       The found salt
    /// @return hookAddress The resulting hook address
    function find(uint160 flags, uint160 mask, bytes memory creationCode, bytes memory constructorArgs)
        internal
        pure
        returns (bytes32 salt, address hookAddress)
    {
        bytes32 initcodeHash = keccak256(abi.encodePacked(creationCode, constructorArgs));
        for (uint256 i = 0; i < 300_000; i++) {
            salt = bytes32(i);
            hookAddress = _computeCreate2Address(salt, initcodeHash);
            if (uint160(hookAddress) & mask == flags) {
                return (salt, hookAddress);
            }
        }
        revert("HookMiner: could not find valid salt in 300k attempts");
    }

    function _computeCreate2Address(bytes32 salt, bytes32 initcodeHash)
        private
        pure
        returns (address)
    {
        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY, salt, initcodeHash))
                )
            )
        );
    }
}
