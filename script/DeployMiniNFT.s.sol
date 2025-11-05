// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

contract DeployMiniNFT is Script {
    function run() external {
        string memory path = "./data/MiniNFT.bin";
        string memory data = vm.readFile(path);
        bytes memory bytecode = vm.parseBytes(data);

        vm.startBroadcast();
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(deployed) { revert(0, 0) }
        }
        vm.stopBroadcast();

        console2.log("MiniNFT deployed at:", deployed);
    }
}
