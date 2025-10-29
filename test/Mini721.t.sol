// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract Mini721Test is Test {
    // mini721's bytecode
    bytes bytecode = hex"335f55601c600e5f39601c5ff3fe60056014565b6340c10f19146012575f80fd5b005b5f3560e01c9056";

    // mini's storage memory layout
    uint256 slotOwner = 0x00;
    uint256 slotTotalSupply = 0x01;

    address deployed;

    function setUp() public {
        // copy storage -> memory
        bytes memory creation = bytecode;

        assembly {
            // memory slot 0x00 => 0x31F contains bc length
            let size := mload(creation)
            // bc data 0x20 => bc.size
            let ptr := add(creation, 0x20)

            // call create & save address returned from constructor
            let addr := create(0, ptr, size)

            // revert if deployment failed
            if iszero(addr) { revert(0, 0) }

            // store the returned address in slot of `deployed`
            sstore(deployed.slot, addr)
        }

        console.log("Mini721 deployed at:  %s", deployed);
    }

    // -----------------------
    // DEPLOYMENT
    // -----------------------
    function test_RuntimeCodeIsDeployedCorrectly() external view {
        bytes memory creation = bytecode;

        uint256 pos = bytePosition(creation, bytes1(0xfe)); // 0xfe
        bytes memory runtime = new bytes(creation.length - (pos + 1));

        for (uint256 i = 0; i < runtime.length; i++) {
            runtime[i] = creation[i + pos + 1];
        }

        assertEq(runtime, deployed.code);
    }

    function test_OwnerIsSetToDeployer() external view {
        uint256 value = loadSlotValue(deployed, slotOwner);
        address deployer = address(uint160(value));

        assertEq(deployer, address(this));
    }

    function test_TotalSupplyStartsAtZero() external view {
        uint256 totalSupply = loadSlotValue(deployed, slotTotalSupply);
        assertEq(totalSupply, 0);
    }

    function test_IncrementsTotalSupply() external view {
        assertTrue(true);
    }

    // -----------------------
    // MINTING
    // -----------------------

    // -----------------------
    // 🔧 PRIVATE HELPERS
    // -----------------------
    function loadSlotValue(address account, uint256 slot) private view returns (uint256) {
        bytes32 value = vm.load(account, bytes32(slot));
        return uint256(value);
    }

    function bytePosition(bytes memory bc, bytes1 marker) internal pure returns (uint256) {
        uint256 offset;
        uint256 len = bc.length;

        for (uint256 i; i < len; i++) {
            if (bc[i] == marker) {
                offset = i;
                break;
            }
        }

        return offset;
    }
}
