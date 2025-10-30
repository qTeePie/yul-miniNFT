/*
  ❕ Note: this implementation favors gas savings over full ERC-721 compatibility.

  To-the-bone minimal nft implemented in yul (evm ecducational lab, not commercial)

  - Free-mint NFT.
  - No max supply. 
  - Cannot be sold through marketplace, only minted and transferred.

  Storage layout:
    0x00 - TotalSupply
    0x01 - BaseURI  
    -- some offset for future vars --
    0x10 - Base slot mapping tokenId => address

  No keccak hashing of slots in mapping
  Instead: increment from offset + overwrite past ownership
  Reason: slight gas improvement 
*/

// ❗ TODO: bitpack totalSupply etc etc and see if its possible to utilize the whole 32 byte word loaded in selector() (just for the heck of it, its a demo)
// ❗ TODO: i want modes for nft so ill do a mode bitpacked with the 256-bit storage slot
// ❗ TODO: some cool revert function that returns some hardcoded "failed because ABC" ?

//  [  1 bit   |      95 bits empty     |   160 bits address   ] - in the mapping (address is only 160 bits)

object "Mini721" {
  // top `code` block is the constructor for Mini721

  // the constructor copies `runtime` bytecode into memory and returns this memory segment to the EVM 
  // EVM hashes bytecode and saves hash as account object's `codeHash` in the World State
    
  // the actual bytecode is stored in some read-only "code database" hosted on each node seperate from main execution layer
  // the hash works as a pointer to where the bytecode is stored
  
  code {
    // copies code from execution context to memory
    // equivalent to opcode 0x39 CODECOPY
    datacopy(0x00, dataoffset("runtime"), datasize("runtime"))
    return(0x00, datasize("runtime"))
  }

  // contract’s on-chain bytecode
  object "runtime" {
    code {

      // --- dispatcher ---
      switch selector() 
        case 0x6a627842  /* mint(address) */ {
          // calldataload(4) to load word beyond 4 byte selector + address is 160 bits => right shift 96 bits
          let to := shr(96, calldataload(4))
          
          mint(to)
          stop()
      }
        default {
        revert(0x00, 0x00) /* no match */
      }

      // --- external interactions ---
      function mint(to) {
        if iszero(to) { revert(0x00, 0x00) } // no address found

        // load to-be tokenId + next available slot in owners mapping  
        let id := sload(totalSupplyPos())
        let slot := add(ownersBasePos(), id)

        // write mini's new owner
        sstore(slot, to) 

        // increment totalSupply
        sstore(totalSupplyPos(), add(id, 1))

        // emit Transfer(address indexed from, address indexed to, uint256 indexed tokenId)
        log4( // ❗ TODO: make generic function for emitting events
            0x00, 0x00,   // no data payload
            0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef, // topic 0: signatureHash 
            0,    // topic 1: newly minted nft => from = address(0) 
            to,   // topic 2: mintedTo
            id    // topic 3: tokenId
        )
      }

      // --- calldata ops ---
      function selector() -> s {
        s := shr(224, calldataload(0))  // discards all but 4 byte selector => right-shift 224 bits
      }

      // --- storage layout ---
      function totalSupplyPos() -> pos {
        pos := 0x00
      }

      function ownersBasePos() -> pos {
        pos := 0x10
      }

      // --- utility ---
      function require(condition) {
        if iszero(condition) { revert(0x00, 0x00) } // given condition is false => stop program
      }
    }
  }
}
