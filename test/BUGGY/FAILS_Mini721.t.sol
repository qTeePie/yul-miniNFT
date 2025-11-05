// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract BUGGY_MiniNFTTest is Test {
    uint256 annoyingSlot = 1; // and ICING ON THE CONFUSION TODO: When all tests pass, simply comment out this and they fail even without sstore!
    address deployed;

    // storage memory layout
    uint256 slotTotalSupply = 0x00;

    // -----------------------
    // SETUP
    // -----------------------

    /**
     *  @dev Deploys the Mini721 Yul contract manually using `create`.
     *
     *  We run the post-deployment verification `runtimeCodeIsDeployedCorrectly`
     *  to make sure the constructor actually returned the correct runtime segment.
     */
    function setUp() public {
        string memory path = "./data/MiniNFT.bin";
        string memory data = vm.readFile(path);
        bytes memory creation = vm.parseBytes(data);

        // address addr; // using this and deployed = addr above makes it work !?

        assembly {
            // memory slot 0x00 => 0x31F contains bc length
            let size := mload(creation)

            // bc data 0x20 => bc.size
            let ptr := add(creation, 0x20)

            // call create & save address returned from constructor
            let addr := create(0, ptr, size) // buggy
            // let addr := create(0, ptr, size) // works

            // revert if deployment failed
            if iszero(addr) { revert(0, 0) }

            sstore(deployed.slot, addr) //for some reason this was very buggy ?? 🔴 => store after assembly block instead
        }

        // deployed = addr; // using this and init memory var addr above assembly makes it work !?

        bytes memory out;

        assembly {
            // get size
            let size := extcodesize(sload(deployed.slot))
            // allocate memory
            out := mload(0x40)
            mstore(out, size)
            // copy bytecode
            extcodecopy(sload(deployed.slot), add(out, 0x20), 0, size)
            // update free memory pointer
            mstore(0x40, add(add(out, 0x20), size))
        }

        console.log("Runtime loaded via extcodecopy, length:", out.length);
        console.logBytes(out);

        bytes memory code = deployed.code;
        console.log("Runtime code length:", code.length);
        console.logBytes(code);

        console.log("--------------------------------------------------------------");
        console.log("Mini721 deployed at:  %s", deployed);
        console.log("--------------------------------------------------------------");

        runtimeCodeIsDeployedCorrectly(creation);
    }

    /**
     * @dev Ensures the deployed Mini721 contract actually matches
     * the runtime compiled from `Mini721.yul`.
     *
     * This doesn’t test contract logic — it catches setup or deployment
     * issues (e.g. wrong byte offsets, truncated code, or bad CREATE params).
     */
    function runtimeCodeIsDeployedCorrectly(bytes memory creation) internal view {
        uint256 pos = bytePosition(creation, bytes1(0xfe)); // 0xfe
        bytes memory runtime = new bytes(creation.length - (pos + 1));

        for (uint256 i = 0; i < runtime.length; i++) {
            runtime[i] = creation[i + pos + 1];
        }

        assertEq(runtime, deployed.code, "runtime doesn't match!");
        assertEq(keccak256(runtime), keccak256(deployed.code), "runtime doesn't match!");
    }

    // -----------------------
    // JUST TO MAKE IT RUN SETUP FAILS / NOT FAILS MYSTERIOUSLY
    // -----------------------
    function test_SOMETHING() external view {
        assertTrue(true);
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
