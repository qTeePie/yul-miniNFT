/*
  📝 Note: this contract intentionally **does not** follow the ERC-721 standard".

  This is an educational demo 📚 

  - Free-mint NFT
  - No max supply 
  - Not ERC-721 compliant (no EIP-165, no safeTransfer, raw SVG, etc.)
  - Cannot be sold through marketplace, only minted and transferred
  - Focus is on exploring different storage layouts, not production rules

  ---

  🔍 Storage layout:
    
  0x00 - TotalSupply
  
  0x10 - Owners Base
    TokenId N is stored at (0x10 + N)
    Not real mapping layout - a simplified, linear style mapping 
    Used on purpose to demonstrate how it differs from a real-life mapping like balances

0x100 - Balances Base
    → stored using the *real* EVM mapping pattern:
    balanceOf[addr] is located at:
    keccak256( addr , balanacesBaseSlot )
   
  🧠 *Balances* is how Solidity stores mappings internally.

  ---

  🎨 On-chain SVG with dynamic color mode is baked into the bytecode. 

*/

// ❗ TODO: So much unused stuff in TotalSupply
// => Pack flags and supply into slot 0x00 
// [  1 bit mintPaused | 200 bits empty | 32bits TotalSupply ]

// ❗ TODO: some cool revert function that returns some hardcoded "failed because ABC" ?
// ❗ Fuzz test the sequential owners mapping and keccak(address, uint256) balanceof never ever ever colliding

// ❗ TODO: i want color for nft so ill do a mode bitpacked with the 256-bit storage slot
//  [  2 bit color   |      94 bits empty     |   160 bits address   ] 

object "MiniNFT" {

  // top `code` block is the constructor for MiniNFT
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
      // prevents contract receiving eth
      require(iszero(callvalue())) 

      // --- dispatcher ---
      switch selector() 
      case 0x6a627842 /* mint(address) */ {
        mint(calldataDecodeAsAddress(0))
      }
      case 0x6352211e /* ownerOf(uint256) */ {
        ownerOf(calldataDecodeAsUint(0))
      }
      case 0x70a08231 /* balanceOf(address) */ {
        balanceOf(calldataDecodeAsAddress(0))
      } 
      case 0x44b285db /* svg(uint256) */ {
        svg(calldataDecodeAsUint(0))
      }
      case 0x18160ddd /* totalSupply() */ {
        totalSupply()
      }
      // case 0xc87b56dd /* tokenURI(id) */ {
      //  tokenURI()  // ❗ Not in use, maybe later if someone implements a yul base64Encoder (...)
      //}
      default {
        revert(0x00, 0x00) /* no match */
      }

      // --- external interactions ---
      function mint(to) {
        if iszero(to) { revert(0x00, 0x00) } // no address found

        // load current supply
        let supply := sload(totalSupplySlot())

        // next tokenId = supply + 1 (not allowing tokenId 0)  
        let id := add(supply, 1)
        let slot := add(ownersBaseSlot(), id)

        // write new owner to mapping
        sstore(slot, to)

        // increment totalSupply
        sstore(totalSupplySlot(), id)

        // emit Transfer(address indexed from, address indexed to, uint256 indexed tokenId)
        log4( // ❗ TODO: make generic function for emitting events
          0x00, 0x00,   // no data payload
          0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef, // topic 0: signatureHash 
          0,    // topic 1: newly minted nft => from = address(0) 
          to,   // topic 2: mintedTo
          id    // topic 3: tokenId
        )
      }

      function totalSupply() {
        let ts := sload(totalSupplySlot())
        mstore(0x00, ts)
        return(0x00, 0x20)
      }

      function ownerOf(tokenId){
        if iszero(tokenId) { revert(0x00, 0x00) } 
        
        let slot := add(ownersBaseSlot(), tokenId)
        let owner := sload(slot)

        mstore(0x00, owner)
        return(0x00, 0x20)
      }

      // ❗ TODO: implement balance being stored
      function balanceOf(addr) {
        
      }
    
      function svg(tokenId) {
        // iszero(tokenId) { revert(0x00, 0x00) } 

        // size and offset of HEAD and TAIL
        let h := dataoffset("SVG_HEAD")
        let hs := datasize("SVG_HEAD")
        let t := dataoffset("SVG_TAIL")
        let ts := datasize("SVG_TAIL")

        // SVG_HEAD  +  color  +  SVG_TAIL
        let size := add(add(0x40, hs), add(1, ts))

        let ptr := mload(0x40) // (we don't have to follow thsi practice since we know the memory layout, but its good practice)
        mstore(0x40, add(ptr, size)) // reserving our slots 

        // Allocate ABI wrapper
        mstore(ptr, 0x20) // offset
        mstore(add(ptr, 0x20), add(add(hs, 1), ts))

        let dataPtr := add(ptr, 0x40)

        // COPY HEAD
        datacopy(dataPtr, h, hs)

        // store byte (color)
        mstore8(add(dataPtr, hs), 0x41)

        // COPY TAIL
        datacopy(add(add(dataPtr, hs), 1), t, ts)

        return(ptr, size)
      }

      // --- calldata ops ---
      function selector() -> s {
        s := shr(224, calldataload(0))  // discards all but 4 byte selector => right-shift 224 bits
      }

      function calldataDecodeAsUint(offset) -> uint {
        let ptr := add(4, mul(offset, 0x20)) // ptr past 4 byte selector, offset = 1 => add 32 bytes to ptr 
        // revert if word pointed at by ptr is beyond calldatasize 
        if lt(calldatasize(), add(ptr, 0x20)) {
          revert (0, 0)
        }
        uint := calldataload(ptr)
      }

      function calldataDecodeAsAddress(offset) -> addr {
        let v := calldataDecodeAsUint(offset) // decode as uint256
        
        if shr(v,160) { revert(0, 0) } // assumed padding not 0 => revert
        
        addr := v // safely cast to address
      }

      // --- storage layout ---
      function totalSupplySlot() -> slot {
        slot := 0x00
      }

      function ownersBaseSlot() -> slot {
        slot := 0x10
      }

      // --- utility ---
      function require(condition) {
        if iszero(condition) { revert(0x00, 0x00) }
      }

      function safeAdd(a, b) -> r {
        r := add(a, b)
        if or(lt(r, a), lt(r, b)) { revert(0, 0) }
      }
    }

    data "SVG_HEAD" "<?xml version='1.0' encoding='UTF-8'?><svg xmlns='http://www.w3.org/2000/svg' width='1600' height='1600' viewBox='0 0 1200 1200'><defs><linearGradient id='A' gradientUnits='userSpaceOnUse'><stop offset='0%' stop-color='#93c5fd'/><stop offset='100%' stop-color='#1e293b'/></linearGradient><linearGradient id='B' gradientUnits='userSpaceOnUse'><stop offset='0%' stop-color='#b87333'/><stop offset='100%' stop-color='#4b2e18'/></linearGradient><linearGradient id='C' gradientUnits='userSpaceOnUse'><stop offset='0%' stop-color='#34ffbe'/><stop offset='100%' stop-color='#003b28'/></linearGradient><path id='D' d='m712.5 581.25c0 10.355-8.3945 18.75-18.75 18.75s-18.75-8.3945-18.75-18.75 8.3945-18.75 18.75-18.75 18.75 8.3945 18.75 18.75z'/></defs><g fill='none' stroke='url(#"
    data "SVG_TAIL" ")' stroke-width='8'><path d='m1031.2 337.5h-675c-4.9727 0-9.7422 1.9766-13.258 5.4922-3.5156 3.5156-5.4922 8.2852-5.4922 13.258v675c0 4.9727 1.9766 9.7422 5.4922 13.258 3.5156 3.5156 8.2852 5.4922 13.258 5.4922h675c4.9727 0 9.7422-1.9766 13.258-5.4922 3.5156-3.5156 5.4922-8.2852 5.4922-13.258v-675c0-4.9727-1.9766-9.7422-5.4922-13.258-3.5156-3.5156-8.2852-5.4922-13.258-5.4922zm-530.53 613.22c11.156-11.062 21.656-19.969 31.875-28.125 31.781-27.188 59.344-50.719 67.406-114 2.4258-25.711 2.832-51.57 1.2188-77.344h0.46875c6.6992-0.60156 12.566-4.7344 15.395-10.836 2.8281-6.1016 2.1836-13.25-1.6875-18.75-3.8711-5.5-10.383-8.5156-17.082-7.9141-4.7773 0.24609-9.5664 0.24609-14.344 0-1.3398-0.14453-2.6914-0.14453-4.0312 0-19.969-0.9375-51.75-5.5312-72.281-24.375-13.996-13.375-21.371-32.242-20.156-51.562-0.34766-18.41 9.1133-35.617 24.844-45.188 14.633-10.113 32.938-13.363 50.156-8.9062v5.4375 49.594c0 6.6992 3.5742 12.887 9.375 16.238 5.8008 3.3477 12.949 3.3477 18.75 0 5.8008-3.3516 9.375-9.5391 9.375-16.238v-49.594c0.023438-21.648 8.6367-42.402 23.945-57.711 15.309-15.309 36.062-23.922 57.711-23.945h58.969c22.379 0 43.84 8.8906 59.664 24.711 15.82 15.824 24.711 37.285 24.711 59.664v73.5c-3.3672-2.1445-6.8398-4.1172-10.406-5.9062-5.9609-2.7383-12.922-2.1602-18.352 1.5234-5.4297 3.6836-8.5391 9.9375-8.1992 16.488 0.33984 6.5508 4.082 12.449 9.8633 15.551 30.129 16.348 52.477 44.059 62.062 76.969h-91.219c-6.6992 0-12.887 3.5742-16.238 9.375-3.3477 5.8008-3.3477 12.949 0 18.75 3.3516 5.8008 9.5391 9.375 16.238 9.375h89.719c-10.688 23.812-41.25 37.5-70.969 37.5-32.918 1-65.008-10.41-89.906-31.969-4.8281-4.1328-11.418-5.543-17.512-3.7383-6.0977 1.8008-10.863 6.5664-12.664 12.664-1.8047 6.0938-0.39453 12.684 3.7383 17.512 12.027 11.535 26.031 20.805 41.344 27.375-0.53125 13.492 2.8281 26.848 9.6758 38.484 6.8477 11.637 16.898 21.059 28.949 27.141 4.8711 2.9023 9.4531 6.2578 13.688 10.031 11.012 9.9805 23.156 18.637 36.188 25.781 27.469 16.688 55.688 33.938 60.562 64.125h-374.06c-0.84375-18.656 1.6875-50.062 13.219-61.688zm511.78 61.781h-112.5c-4.6875-51-46.875-76.969-79.031-96.188-10.363-5.7383-20.129-12.488-29.156-20.156-6.2188-5.7773-13.113-10.781-20.531-14.906-10.312-6.6562-16.875-10.875-19.688-21.938 11.84 2.1992 23.863 3.2656 35.906 3.1875 55.312 0 112.5-35.062 112.5-93.75-1.3125-33.828-14.602-66.094-37.5-91.031v-105.84c0-32.324-12.84-63.324-35.695-86.18-22.855-22.855-53.855-35.695-86.18-35.695h-58.969c-24.75 0.046875-48.871 7.7852-69.027 22.148-20.152 14.359-35.348 34.633-43.473 58.008h-0.84375c-20.344-9.375-51.75-4.4062-76.312 11.438-26.344 16.332-42.266 45.223-42 76.219-1.2305 29.922 10.609 58.902 32.438 79.406 23.031 19.059 51.383 30.551 81.188 32.906 1.5391 24.582 1.2266 49.246-0.9375 73.781-6.1875 49.031-24.281 64.312-54.281 89.625-10.312 8.625-21.938 18.75-34.125 30.75-23.156 23.062-25.219 67.312-24.75 88.219h-74.531v-637.5h637.5z'/><path d='m281.25 825h-93.75v-637.5h637.5v93.75c0 6.6992 3.5742 12.887 9.375 16.238 5.8008 3.3477 12.949 3.3477 18.75 0 5.8008-3.3516 9.375-9.5391 9.375-16.238v-112.5c0-4.9727-1.9766-9.7422-5.4922-13.258-3.5156-3.5156-8.2852-5.4922-13.258-5.4922h-675c-4.9727 0-9.7422 1.9766-13.258 5.4922-3.5156 3.5156-5.4922 8.2852-5.4922 13.258v675c0 4.9727 1.9766 9.7422 5.4922 13.258 3.5156 3.5156 8.2852 5.4922 13.258 5.4922h112.5c6.6992 0 12.887-3.5742 16.238-9.375 3.3477-5.8008 3.3477-12.949 0-18.75-3.3516-5.8008-9.5391-9.375-16.238-9.375z'/><use href='#D'/><use href='#D' x='75'/></g></svg>"
  }
}