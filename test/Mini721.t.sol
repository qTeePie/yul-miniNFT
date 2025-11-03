// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract Mini721Test is Test {
    address deployed;

    // storage memory layout
    uint256 slotTotalSupply = 0x00;

    // selectors
    bytes4 selectorMint = bytes4(keccak256("mint(address)"));
    bytes4 selectorTotalSupply = bytes4(keccak256("totalSupply()"));
    bytes4 selectorTokenURI = bytes4(keccak256("tokenURI(uint256)"));
    bytes4 selectorSVG = bytes4(keccak256("svg()"));

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
        string memory path = "./data/Mini721.bin";
        string memory data = vm.readFile(path);
        bytes memory creation = vm.parseBytes(data);

        address addr;

        assembly {
            // memory slot 0x00 => 0x31F contains bc length
            let size := mload(creation)

            // bc data 0x20 => bc.size
            let ptr := add(creation, 0x20)

            // call create & save address returned from constructor
            addr := create(0, ptr, size)

            // revert if deployment failed
            if iszero(addr) { revert(0, 0) }

            // sstore(deployed.slot, addr) //for some reason this was very buggy ?? 🔴 => store after assembly block instead
        }

        deployed = addr; // comment out this and uncomment the sstore and see it fail...

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
    // DEPLOYMENT
    // -----------------------
    function test_TotalSupplyStartsAtZero() external view {
        uint256 totalSupply = loadSlotValue(deployed, slotTotalSupply);
        assertEq(totalSupply, 0);
    }

    function test_BaseURIStored() external {
        bytes memory tokenIdData = abi.encode(uint256(0)); // encode tokenId = 0
        bytes memory returnData = callMiniStrict(selectorTokenURI, tokenIdData);

        // The return data is the raw bytes returned by your Yul contract
        console.log("Return data length:", returnData.length);
        console.logBytes(returnData);

        // If you want to decode it as a string (assuming it's a URI)
        if (returnData.length > 0) {
            string memory uri = string(returnData);
            console.log("URI:", uri);
        }
    }

    // -----------------------
    // MINTING
    // -----------------------
    function test_MintIncrementsTotalSupply() external {
        uint256 supplyBefore = loadSlotValue(deployed, slotTotalSupply);

        callMintStrict(address(this));

        uint256 supplyAfter = loadSlotValue(deployed, slotTotalSupply);
        assertEq(supplyAfter, supplyBefore + 1, "Mint didn't increment total supply!");
    }

    function test_MintEmitsTransferEvent() external {
        bytes32 sig = keccak256("Transfer(address,address,uint256)");

        vm.recordLogs(); // ExpectEmit seem to have some issues with pure .yul contracts
        callMint(address(this));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        int256 logIndex = checkEventWasEmitted(entries, deployed, sig);
        assertTrue(logIndex >= 0, "Transfer event not found in logs!");
    }

    function test_MintFailsWhenToAddressIsZero() external {
        uint256 supplyBefore = loadSlotValue(deployed, slotTotalSupply);

        address to = address(0);
        bool ok = callMint(to);

        uint256 supplyAfter = loadSlotValue(deployed, slotTotalSupply);

        assertFalse(ok);
        assertEq(supplyAfter, supplyBefore);
    }

    function test_MintUserCanMint() external {
        address user = makeAddr("user");
        uint256 supplyBefore = loadSlotValue(deployed, slotTotalSupply);

        vm.startPrank(user);
        callMintStrict(user);
        vm.stopPrank();

        uint256 supplyAfter = loadSlotValue(deployed, slotTotalSupply);
        assertEq(supplyAfter, supplyBefore + 1);
    }

    function test_MintUserCanMintToOthers() external {
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        uint256 supplyBefore = loadSlotValue(deployed, slotTotalSupply);

        vm.startPrank(sender);
        callMintStrict(receiver);
        vm.stopPrank();

        uint256 supplyAfter = loadSlotValue(deployed, slotTotalSupply);
        assertEq(supplyAfter, supplyBefore + 1);

        // ❗ TODO: test that the other user is set as owner correcty
    }

    // -----------------------
    // EVENT VERIFICATION
    // -----------------------

    /*
        Yul-emitted events still have names like in Solidity,
        but those names are encoded as keccak256 hashes in topic0.
        High-level Solidity syntax hides this detail automatically,
        while raw Yul `log` calls expose it directly.
    */

    /**
     * @dev Mint emits an event with signature:
     *  0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
     *      = Transfer(address, address, uint256)
     */
    function test_EventTransferTopicsAreCorrect() external {
        address from = address(0); // topic 1
        address to = address(this); // topic 2
        uint256 tokenId = loadSlotValue(deployed, slotTotalSupply); // topic 3

        vm.recordLogs();
        callMintStrict(to);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 sig = keccak256("Transfer(address,address,uint256)");
        int256 logIndex = checkEventWasEmitted(entries, deployed, sig);

        assertTrue(logIndex >= 0, "Transfer event not found in logs!");

        Vm.Log memory logEntry = entries[uint256(logIndex)];

        address actualFrom = topicToAddress(logEntry.topics[1]);
        address actualTo = topicToAddress(logEntry.topics[2]);
        uint256 actualTokenId = topicToUint256(logEntry.topics[3]);

        assertEq(actualFrom, from, "Topic 1 (from) not set to address(0) in mint!");
        //assertEq(actualTo, to, "Topic 2 (to) not set as expected in mint!");
        assertEq(actualTokenId, tokenId, "Topic 3 (tokenId) not set as expected in mint!");
    }

    // -----------------------
    // STORAGE LAYOUT
    // -----------------------
    function test_MintStoresOwnerInCorrectSlot() external {}

    function test_DebugSVGRaw() external {
        bytes memory ret = callMiniStrict(selectorSVG, "");

        console.log("Raw length:", ret.length);
        console.logBytes(ret); // print only first 2 ABI words

        uint256 pos = bytePosition(ret, 0);
    }

    // -----------------------
    // 🔧 PRIVATE HELPERS
    // -----------------------

    // --- external calls  ---
    function callMini(bytes4 selector, bytes memory data) internal returns (bool ok, bytes memory returnData) {
        (ok, returnData) = deployed.call(bytes.concat(selector, data));
    }

    function callMiniStrict(bytes4 selector, bytes memory data) internal returns (bytes memory returnData) {
        bool ok;
        (ok, returnData) = callMini(selector, data);
        require(ok, "call failed");
    }

    /// Calls Mini721 mint()
    function callMint(address to) internal returns (bool ok) {
        (ok,) = deployed.call(bytes.concat(hex"6a627842", bytes32(uint256(uint160(to)))));
    }

    /// Calls Mini721 mint() and requires success
    function callMintStrict(address to) internal {
        bool ok = callMint(to);
        require(ok, "call failed");
    }

    /// Loads value at `slot` for given account
    function loadSlotValue(address account, uint256 slot) internal view returns (uint256) {
        bytes32 value = vm.load(account, bytes32(slot));
        return uint256(value);
    }

    /// Loops through log entries and returns match's index if found / -1 if no match.
    function checkEventWasEmitted(Vm.Log[] memory entries, address emitter, bytes32 eventSignature)
        internal
        pure
        returns (int256)
    {
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].emitter == emitter && entries[i].topics[0] == eventSignature) {
                return int256(i);
            }
        }
        return -1;
    }

    // --- byte ops ---
    function topicToAddress(bytes32 topic) internal pure returns (address) {
        return address(uint160(uint256(topic)));
    }

    function topicToUint256(bytes32 topic) internal pure returns (uint256) {
        return uint256(topic);
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

    function countSequentialBytes(bytes memory bc, bytes1 marker) internal pure returns (uint256) {
        uint256 pos = bytePosition(bc, marker);

        uint256 i = pos;
        uint256 counter = 0;

        while (bc[i] == marker) {
            counter++;
            i++;
        }

        return counter;
    }
}
