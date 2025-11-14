// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract MiniNFTTest is Test {
    address deployedMini;

    // storage memory layout
    uint256 slotTotalSupply = 0x00;
    uint256 slotOwnersBase = 0x10;

    // write actions
    bytes4 selectorMint = bytes4(keccak256("mint(address)"));
    bytes4 selectorTransfer = bytes4(keccak256("transfer(address,uint256)"));
    bytes4 selectorSetColor = bytes4(keccak256("setColor(uint256,uint256)"));

    // read actions
    bytes4 selectorOwnerOf = bytes4(keccak256("ownerOf(uint256)"));
    bytes4 selectorBalanceOf = bytes4(keccak256("balanceOf(address)"));
    bytes4 selectorTotalSupply = bytes4(keccak256("totalSupply()"));
    bytes4 selectorSVG = bytes4(keccak256("svg(uint256)"));
    bytes4 selectorColorOf = bytes4(keccak256("colorOf(uint256)"));

    // -----------------------
    // SETUP
    // -----------------------

    /**
     *  @dev Deploys the MiniNFT Yul contract manually using `create`.
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

            // sstore(deployedMini.slot, addr) //for some reason this was very buggy ?? 🔴 => store after assembly block instead
        }

        deployedMini = addr;
        console.log("--------------------------------------------------------------");
        console.log("MiniNFT deployedMini at:  %s", deployedMini);
        console.log("--------------------------------------------------------------");

        runtimeCodeIsDeployedCorrectly(creation);
    }

    /**
     * @dev Ensures the deployedMini MiniNFT contract actually matches
     * the runtime compiled from `MiniNFT.yul`.
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

        assertEq(runtime, deployedMini.code, "runtime doesn't match!");
        assertEq(keccak256(runtime), keccak256(deployedMini.code), "runtime doesn't match!");
    }

    // -----------------------
    // DEPLOYMENT
    // -----------------------
    function test_Deploy_TotalSupplyStartsAtZero() external view {
        uint256 totalSupply = loadSlotValue(deployedMini, slotTotalSupply);
        assertEq(totalSupply, 0);
    }

    // -----------------------
    // MINT
    // -----------------------
    function test_Mint_IncrementsTotalSupply() external {
        uint256 supplyBefore = loadSlotValue(deployedMini, slotTotalSupply);

        callMiniStrict(selectorMint, abi.encode(address(this)));

        uint256 supplyAfter = loadSlotValue(deployedMini, slotTotalSupply);
        assertEq(supplyAfter, supplyBefore + 1, "mint didn't increment total supply!");
    }

    function test_Mint_IncrementsBalanceOfReceiver() external {
        address recipient = address(this);

        uint256 balanceBefore = getBalanceOf(recipient);
        callMiniStrict(selectorMint, abi.encode(recipient));
        uint256 balanceAfter = getBalanceOf(recipient);

        assertEq(balanceAfter, balanceBefore + 1, "mint didn't increment recipient balance!");
    }

    function test_Mint_EmitsTransferEvent() external {
        bytes32 sig = keccak256("Transfer(address,address,uint256)");

        vm.recordLogs(); // ExpectEmit seem to have some issues with pure .yul contracts
        (bool ok,) = callMini(selectorMint, abi.encode(address(this)));
        assertTrue(ok, "mint call failed");
        Vm.Log[] memory entries = vm.getRecordedLogs();

        int256 logIndex = checkEventWasEmitted(entries, deployedMini, sig);
        assertTrue(logIndex >= 0, "transfer event not found in logs!");
    }

    function test_Mint_RevertsWhenToAddressIsZero() external {
        uint256 supplyBefore = loadSlotValue(deployedMini, slotTotalSupply);

        address zeroAddress = address(0);
        (bool ok,) = callMini(selectorMint, abi.encode(zeroAddress));

        uint256 supplyAfter = loadSlotValue(deployedMini, slotTotalSupply);

        assertFalse(ok);
        assertEq(supplyAfter, supplyBefore);
    }

    function test_Mint_UserCanMint() external {
        address user = makeAddr("user");
        uint256 supplyBefore = loadSlotValue(deployedMini, slotTotalSupply);

        vm.prank(user);
        callMiniStrict(selectorMint, abi.encode(user));

        uint256 supplyAfter = loadSlotValue(deployedMini, slotTotalSupply);
        assertEq(supplyAfter, supplyBefore + 1);
    }

    function test_Mint_UserCanMintToOthers() external {
        address minter = makeAddr("minter");
        address recipient = makeAddr("recipient");
        uint256 supplyBefore = loadSlotValue(deployedMini, slotTotalSupply);

        vm.prank(minter);
        callMiniStrict(selectorMint, abi.encode(recipient));

        uint256 supplyAfter = loadSlotValue(deployedMini, slotTotalSupply);
        assertEq(supplyAfter, supplyBefore + 1);

        uint256 tokenId = supplyAfter;
        address actualOwner = getOwnerOf(tokenId);
        assertEq(actualOwner, recipient, "owner mismatch");
    }

    /**
     * @dev Mint emits an event with signature:
     *  0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
     *      = Transfer(address, address, uint256)
     */
    function test_Mint_EmitsCorrectTransferEvent() external {
        address from = address(0); // topic 1
        address recipient = address(this); // topic 2
        uint256 tokenId = (loadSlotValue(deployedMini, slotTotalSupply)) + 1; // skips token 0

        vm.recordLogs();
        callMiniStrict(selectorMint, abi.encode(recipient));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 sig = keccak256("Transfer(address,address,uint256)");
        int256 logIndex = checkEventWasEmitted(entries, deployedMini, sig);

        assertTrue(logIndex >= 0, "transfer event not found in logs!");

        Vm.Log memory logEntry = entries[uint256(logIndex)];

        address actualFrom = topicToAddress(logEntry.topics[1]);
        address actualTo = topicToAddress(logEntry.topics[2]);
        uint256 actualTokenId = topicToUint256(logEntry.topics[3]);

        assertEq(actualFrom, from, "topic 1 (from) not set to address(0) in mint!");
        assertEq(actualTo, recipient, "topic 2 (to) not set as expected in mint!");
        assertEq(actualTokenId, tokenId, "topic 3 (tokenId) not set as expected in mint!");
    }

    // ❗ TODO: fuzz this assuring owners is stored correct for multiple nfts
    function test_Mint_StoresOwnerInCorrectSlot() external {
        address recipient = address(this);

        callMiniStrict(selectorMint, abi.encode(recipient));
        uint256 tokenId = loadSlotValue(deployedMini, slotTotalSupply);

        address actualOwner = getOwnerOf(tokenId);
        assertEq(actualOwner, recipient, "owner mismatch");
    }

    // -----------------------
    // MINT AND TRANSFER HELPER
    // -----------------------

    function test_MintAndTransfer_WorksCorrectly() external {
        address currentOwner = address(this);
        address newOwner = makeAddr("newOwner");

        uint256 tokenId = mintAndTransfer(currentOwner, newOwner);

        address actualOwner = getOwnerOf(tokenId);
        assertEq(actualOwner, newOwner, "token should be owned by newOwner");
    }

    // -----------------------
    // TRANSFER
    // -----------------------
    function test_Transfer_UpdatesOwnership() external {
        address currentOwner = address(this);
        address newOwner = makeAddr("newOwner");

        uint256 tokenId = mintAndTransfer(currentOwner, newOwner);

        address actualOwnerAfterTransfer = toAddr(loadSlotValue(deployedMini, (slotOwnersBase + tokenId)));
        assertEq(actualOwnerAfterTransfer, newOwner);
    }

    function test_Transfer_UpdatesBalances() external {
        address currentOwner = address(this);
        address newOwner = makeAddr("newOwner");

        uint256 fromBefore = getBalanceOf(currentOwner);
        uint256 toBefore = getBalanceOf(newOwner);

        mintAndTransfer(currentOwner, newOwner);

        uint256 fromAfter = getBalanceOf(currentOwner);
        uint256 toAfter = getBalanceOf(newOwner);

        assertEq(fromAfter, fromBefore, "currentOwner balance should stay same (mint then transfer out)");
        assertEq(toAfter, toBefore + 1, "newOwner balance should increment by 1");
    }

    function test_Transfer_DoesNotOverwriteColor() external {
        address currentOwner = address(this);

        callMiniStrict(selectorMint, abi.encode(currentOwner));
        uint256 tokenId = loadSlotValue(deployedMini, slotTotalSupply);

        uint256 colorBefore = getColorOf(tokenId);

        address newOwner = makeAddr("newOwner");
        callMiniStrict(selectorTransfer, abi.encode(newOwner, tokenId));

        uint256 colorAfter = getColorOf(tokenId);

        assertTrue(colorBefore != 0, "colorBefore should not be null/zero");
        assertTrue(colorAfter != 0, "colorAfter should not be null/zero");
        assertEq(colorBefore, colorAfter);
    }

    function test_Transfer_EmitsTransferEvent() external {
        address recipient = makeAddr("recipient");

        // Setup: mint first
        callMiniStrict(selectorMint, abi.encode(address(this)));
        uint256 tokenId = loadSlotValue(deployedMini, slotTotalSupply);

        // Test: just the transfer event
        bytes32 sig = keccak256("Transfer(address,address,uint256)");
        vm.recordLogs();
        callMiniStrict(selectorTransfer, abi.encode(recipient, tokenId));
        Vm.Log[] memory entries = vm.getRecordedLogs();

        int256 logIndex = checkEventWasEmitted(entries, deployedMini, sig);
        assertTrue(logIndex >= 0, "transfer event not found in logs!");
    }

    function test_Transfer_RevertsWhenCallerIsNotOwner() external {
        address tokenOwner = makeAddr("tokenOwner");

        callMiniStrict(selectorMint, abi.encode(tokenOwner));
        uint256 tokenId = loadSlotValue(deployedMini, slotTotalSupply);

        address unauthorizedCaller = address(this);
        bytes memory cd = abi.encode(unauthorizedCaller, tokenId);

        callMiniReverts(selectorTransfer, cd);
    }

    function test_Transfer_RevertsWhenReceiverIsZero() external {
        address currentOwner = address(this);

        callMiniStrict(selectorMint, abi.encode(currentOwner));
        uint256 tokenId = loadSlotValue(deployedMini, slotTotalSupply);

        address zeroRecipient = address(0);
        bytes memory cd = abi.encode(zeroRecipient, tokenId);

        callMiniReverts(selectorTransfer, cd);
    }

    // -----------------------
    // SET COLOR
    // -----------------------
    function test_SetColor_SetsCorrectColor() external {
        address owner = address(this);
        callMiniStrict(selectorMint, abi.encode(owner));
        uint256 tokenId = getTotalSupply();

        uint256 newColor = packRGB(255, 128, 64);
        setColorOf(tokenId, newColor);

        uint256 actualColor = getColorOf(tokenId);
        assertEq(actualColor, newColor, "Color was not set correctly");

        (uint8 r, uint8 g, uint8 b) = unpackRGB(actualColor);
        assertEq(r, 255, "Red component incorrect");
        assertEq(g, 128, "Green component incorrect");
        assertEq(b, 64, "Blue component incorrect");
    }

    // -----------------------
    // STORAGE LAYOUT
    // -----------------------
    function test_DebugSVGRaw() external {
        callMiniStrict(selectorMint, abi.encode(address(this)));
        uint256 tokenId = loadSlotValue(deployedMini, slotTotalSupply);

        bytes memory ret = callMiniStrict(selectorSVG, abi.encode(tokenId));

        console.log("Raw length:", ret.length);
        console.logBytes(ret); // print only first 2 ABI words

        uint256 pos = bytePosition(ret, 0);
    }

    function test_TotalSupply_ReturnsCorrectValue() external {
        callMiniStrict(selectorMint, abi.encode(address(this)));

        uint256 supply = getTotalSupply();
        uint256 raw = loadSlotValue(deployedMini, slotTotalSupply);

        assertEq(supply, raw, "totalSupply() does not match storage slot!");
    }

    // -----------------------
    // 🔧 HELPERS
    // -----------------------

    // --- external calls  ---
    function callMini(bytes4 selector, bytes memory data) internal returns (bool ok, bytes memory returnData) {
        (ok, returnData) = deployedMini.call(bytes.concat(selector, data));
    }

    function callMiniStrict(bytes4 selector, bytes memory data) internal returns (bytes memory returnData) {
        bool ok;
        (ok, returnData) = callMini(selector, data);
        require(ok, "call failed");
    }

    /**
     * On low-level calls, `expectRevert` flips reality:
     *  The returned `bool` no longer means "call succeeded" —
     *  it means "the expected revert was caught successfully." 💫
     */
    function callMiniReverts(bytes4 selector, bytes memory data) internal {
        vm.expectRevert(bytes(""));
        (bool revertsAsExpected,) = deployedMini.call(bytes.concat(selector, data));
        assertTrue(revertsAsExpected, "expectRevert: call did not revert");
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

    // --- WRITE MINI HELPERS ---

    /// Helper: Mints to `from` then immediately transfers to `to`
    function mintAndTransfer(address from, address to) internal returns (uint256 tokenId) {
        callMiniStrict(selectorMint, abi.encode(from));
        tokenId = getTotalSupply();
        callMiniStrict(selectorTransfer, abi.encode(to, tokenId));
    }

    /// Helper: Sets color of a token
    /// Will revert if not called by owner of token with id = tokenId
    function setColorOf(uint256 tokenId, uint256 color) internal {
        callMiniStrict(selectorSetColor, abi.encode(tokenId, color));
    }

    // --- READ MINI HELPERS ---

    /// Helper: Gets color of a token
    function getColorOf(uint256 tokenId) internal returns (uint256) {
        bytes memory colorBytes = callMiniStrict(selectorColorOf, abi.encode(tokenId));
        return abi.decode(colorBytes, (uint256));
    }

    /// Helper: Packs RGB values into a single uint256
    function packRGB(uint8 r, uint8 g, uint8 b) internal pure returns (uint256) {
        uint256 redBits = uint256(r) << 16;
        uint256 greenBits = uint256(g) << 8;
        uint256 blueBits = uint256(b);

        return redBits | greenBits | blueBits;
    }

    /// Helper: Unpacks RGB values from a uint256
    function unpackRGB(uint256 packed) internal pure returns (uint8 r, uint8 g, uint8 b) {
        r = uint8((packed >> 16) & 0xFF);
        g = uint8((packed >> 8) & 0xFF);
        b = uint8(packed & 0xFF);
    }

    /// Helper: Gets owner of a token using high-level call
    function getOwnerOf(uint256 tokenId) internal returns (address) {
        bytes memory ownerBytes = callMiniStrict(selectorOwnerOf, abi.encode(tokenId));
        return abi.decode(ownerBytes, (address));
    }

    /// Helper: Gets balance of an address
    function getBalanceOf(address owner) internal returns (uint256) {
        bytes memory balanceBytes = callMiniStrict(selectorBalanceOf, abi.encode(owner));
        return abi.decode(balanceBytes, (uint256));
    }

    /// Helper: Gets total supply
    function getTotalSupply() internal returns (uint256) {
        bytes memory supplyBytes = callMiniStrict(selectorTotalSupply, abi.encode());
        return abi.decode(supplyBytes, (uint256));
    }

    /// Loads value at `slot` for given account
    function loadSlotValue(address account, uint256 slot) internal view returns (uint256) {
        bytes32 value = vm.load(account, bytes32(slot));
        return uint256(value);
    }

    // --- byte ops ---
    function topicToAddress(bytes32 topic) internal pure returns (address) {
        return address(uint160(uint256(topic)));
    }

    function topicToUint256(bytes32 topic) internal pure returns (uint256) {
        return uint256(topic);
    }

    function toAddr(uint256 value) internal pure returns (address) {
        return address(uint160(value));
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
