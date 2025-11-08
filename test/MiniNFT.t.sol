// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract MiniNFTTest is Test {
    address deployed;

    // storage memory layout
    uint256 slotTotalSupply = 0x00;
    uint256 slotOwnersBase = 0x10;

    // write actions
    bytes4 selectorMint = bytes4(keccak256("mint(address)"));

    // read actions
    bytes4 selectorSVG = bytes4(keccak256("svg(uint256)"));
    bytes4 selectorOwnerOf = bytes4(keccak256("ownerOf(uint256)"));
    bytes4 selectorBalanceOf = bytes4(keccak256("balanceOf(address)"));
    bytes4 selectorTotalSupply = bytes4(keccak256("totalSupply()"));

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

        deployed = addr;
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
    function test_Deploy_TotalSupplyStartsAtZero() external view {
        uint256 totalSupply = loadSlotValue(deployed, slotTotalSupply);
        assertEq(totalSupply, 0);
    }

    /*
    function test_BaseURIStored() external {
        bytes memory tokenIdData = abi.encode(uint256(1));
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
    */

    // -----------------------
    // MINTING
    // -----------------------
    function test_Mint_IncrementsTotalSupply() external {
        uint256 supplyBefore = loadSlotValue(deployed, slotTotalSupply);

        callMintStrict(address(this));

        uint256 supplyAfter = loadSlotValue(deployed, slotTotalSupply);
        assertEq(supplyAfter, supplyBefore + 1, "mint didn't increment total supply!");
    }

    function test_Mint_IncrementsBalanceOfReceiver() external {
        address receiver = address(this);
        bytes memory receiverEncoded = abi.encode(receiver);

         uint256 balanceBefore = abi.decode(
            callMiniStrict(selectorBalanceOf, receiverEncoded),
            (uint256)
        );
        callMiniStrict(selectorMint, receiverEncoded);
        
        uint256 balanceAfter = abi.decode(
            callMiniStrict(selectorBalanceOf, receiverEncoded),
            (uint256)
        );

        assertEq(balanceBefore + 1, balanceAfter, "mint didn't increment receiver balance!");
    }

    function test_Mint_EmitsTransferEvent() external {
        bytes32 sig = keccak256("Transfer(address,address,uint256)");

        vm.recordLogs(); // ExpectEmit seem to have some issues with pure .yul contracts
        callMint(address(this));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        int256 logIndex = checkEventWasEmitted(entries, deployed, sig);
        assertTrue(logIndex >= 0, "transfer event not found in logs!");
    }

    function test_Mint_RevertsWhenToAddressIsZero() external {
        uint256 supplyBefore = loadSlotValue(deployed, slotTotalSupply);

        address to = address(0);
        bool ok = callMint(to);

        uint256 supplyAfter = loadSlotValue(deployed, slotTotalSupply);

        assertFalse(ok);
        assertEq(supplyAfter, supplyBefore);
    }

    function test_Mint_UserCanMint() external {
        address user = makeAddr("user");
        uint256 supplyBefore = loadSlotValue(deployed, slotTotalSupply);

        vm.startPrank(user);
        callMintStrict(user);
        vm.stopPrank();

        uint256 supplyAfter = loadSlotValue(deployed, slotTotalSupply);
        assertEq(supplyAfter, supplyBefore + 1);
    }

    function test_Mint_UserCanMintToOthers() external {
        address sender = makeAddr("sender");
        address receiver = makeAddr("receiver");
        uint256 supplyBefore = loadSlotValue(deployed, slotTotalSupply);

        vm.startPrank(sender);
        callMiniStrict(selectorMint, abi.encode(receiver));
        vm.stopPrank();

        uint256 supplyAfter = loadSlotValue(deployed, slotTotalSupply);
        assertEq(supplyAfter, supplyBefore + 1);

        uint256 tokenId = supplyAfter;
        bytes memory ret = callMiniStrict(selectorOwnerOf, abi.encode(tokenId));
        require(ret.length <= 32, "unexpected returndata size");

        address actualOwner = abi.decode(ret, (address));
        assertEq(receiver, actualOwner, "owner mismatch");
    }

    /**
     * @dev Mint emits an event with signature:
     *  0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
     *      = Transfer(address, address, uint256)
     */
    function test_Mint_EmitsCorrectTransferEvent() external {
        address from = address(0); // topic 1
        address to = address(this); // topic 2
        uint256 tokenId = (loadSlotValue(deployed, slotTotalSupply)) + 1; // skips token 0

        vm.recordLogs();
        callMintStrict(to);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 sig = keccak256("Transfer(address,address,uint256)");
        int256 logIndex = checkEventWasEmitted(entries, deployed, sig);

        assertTrue(logIndex >= 0, "transfer event not found in logs!");

        Vm.Log memory logEntry = entries[uint256(logIndex)];

        address actualFrom = topicToAddress(logEntry.topics[1]);
        address actualTo = topicToAddress(logEntry.topics[2]);
        uint256 actualTokenId = topicToUint256(logEntry.topics[3]);

        assertEq(actualFrom, from, "topic 1 (from) not set to address(0) in mint!");
        assertEq(actualTo, to, "topic 2 (to) not set as expected in mint!");
        assertEq(actualTokenId, tokenId, "topic 3 (tokenId) not set as expected in mint!");
    }

    // ❗ TODO: fuzz this assuring owners is stored correct for multiple nfts
    function test_Mint_StoresOwnerInCorrectSlot() external {
        address to = address(this);
        callMiniStrict(selectorMint, abi.encode(to));

        uint256 tokenId = loadSlotValue(deployed, slotTotalSupply);

        bytes memory ret = callMiniStrict(selectorOwnerOf, abi.encode(tokenId));
        require(ret.length <= 32, "unexpected returndata size");

        address actualOwner = abi.decode(ret, (address));
        assertEq(actualOwner, to, "owner mismatch");
    }

    // -----------------------
    // Balance Of
    // -----------------------
    function test_BalanceOf_ReturnsZeroForUnmintedAddress() external {}

    function test_BalanceOf_IncrementsAfterMint() external {}

    // -----------------------
    // Owner Of
    // -----------------------
    function test_OwnerOf_Reverts_ForNonexistentToken() external {}

    // -----------------------
    // STORAGE LAYOUT
    // -----------------------
    function test_DebugSVGRaw() external {
        bytes memory ret = callMiniStrict(selectorSVG, abi.encode(1));

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
