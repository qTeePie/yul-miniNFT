# MiniNFT 🐥

**⚠️ DISCLAIMER: This NFT is only for educational purposes only. It is not ERC-721 compliant, not production-ready, and not intended for wallet or marketplace support**

I wanted to understand the EVM on an opcode level and found that implementing an NFT was a fun way to do exactly that. 🚀

This NFT is not ERC-721 compliant, but it is a non-fungable token. Some educational stuff like bitpacking NFT specs into the `ownerOf` mapping makes this NFT implementation kind of wild, perfect for _play and learn_.

✅ It **mints**, **tracks ownership**, and **emits events**
❌ It does **not follow the ERC-721 spec**
🎯 It exists purely as a playground to learn low-level EVM, storage, and gas behavior

---

## 🖼️ Extract the on-chain SVG

```bash
cast call <CONTRACT_ADDRESS> "svg()" \
  --rpc-url http://127.0.0.1:8545 \
  | cast --to-ascii > output.svg
```

Now open `output.svg` in any browser or image viewer.

---

## 🛠 Available Make Commands

| Command            | Description                                            |
| ------------------ | ------------------------------------------------------ |
| `make build`       | Compile the Yul contract → outputs raw bytecode (.bin) |
| `make deploy`      | Deploy via Foundry script (`DeployMini721.s.sol`)      |
| `make mint`        | Mint a token to `USER_ADDR` (from `.env`)              |
| `make totalSupply` | Read the on-chain total supply                         |
| `make fork-anvil`  | Start an Anvil mainnet fork (for testing)              |
| `make clean`       | Remove build artifacts                                 |

✅ All variables (`RPC_URL`, `PRIVATE_KEY`, `CONTRACT_ADDR`, `USER_ADDR`, etc.) are loaded from `.env`.

---

### If `.env` already has everything:

```
RPC_URL=http://127.0.0.1:8545
PRIVATE_KEY=0x...
CONTRACT_ADDR=0x...
USER_ADDR=0x...
```

then you can just run:

```
make deploy
make mint
make totalSupply
```
