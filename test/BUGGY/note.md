### ⚠️ Foundry Quirk / Bug Note: The “Useless Variable That Fixes Everything” Mystery

During testing, I ran into a **completely non-intuitive Foundry behavior**:

✅ My Yul contract deployed correctly
✅ `extcodesize()` returned the _correct_ runtime size (1055 bytes)
✅ `extcodecopy()` returned the full correct runtime bytecode
❌ But `address.code.length` inside Solidity returned **0 bytes**
❌ All tests that compared runtime code → failed
❌ This ONLY happened when the test contract **had no other state variables**

And here’s the wild part:

```solidity
// If I add this completely useless variable... everything works.
uint256 whyDoesThisFixIt = 1;
```

Just having **any extra state variable of any type** makes `deployed.code` behave correctly again.

Remove it → `deployed.code.length == 0`
Add it → `deployed.code.length == 1055` (correct)

The deployed address and runtime bytecode are identical in both cases.
The only difference is whether the test contract has **at least one other storage slot**.

It was not:

- a storage layout issue ✅
- an optimizer issue ✅
- a bytecode parsing issue ✅
- a bad `mload` length ✅
- a broken deployment ✅
- a logic bug in the Yul contract ✅

The issue is only reproducible **inside Foundry tests**, when:

- a contract writes to storage using `sstore(deployed.slot, addr)` inside inline assembly
- AND the contract has no other state vars
- AND the deployed address is later read as `deployed.code` from Solidity
- BUT `extcodesize`/`extcodecopy` _still work normally_

In other words:

> **The deployed contract exists and contains valid bytecode,
> but Foundry’s `.code` view returns zero unless there's at least one extra state variable.**

So yes, the temporary workaround was literally:

```solidity
uint256 annoyingSlot = 1; // <-- uncomment to make Foundry behave
```

And yes, I am 100% serious.

---

### 🧠 Why this matters

This is not a logic bug in my contract — it’s a **Foundry test-environment edge case involving assembly + storage initialization**.
In real deployment (on a chain), this does **not** happen.
It only affects how the `.code` property behaves inside tests.

---

### 📌 TODO

✅ Build minimal reproducible example
✅ Open issue on Foundry GitHub
🔲 Wait for someone smarter than me to explain why this happens
🔲 Possibly marry them

> If you understand _exactly_ why this happens, DM me.
> I am willing to offer **eternal gratitude, coffee, or marriage** depending on explanation quality.

---

### 🪄 Final workaround

Instead of writing the deployed address to storage inside assembly:

```solidity
sstore(deployed.slot, addr);
```

Just store it in Solidity afterwards:

```solidity
deployed = addr;
```

That instantly fixes the issue — no dummy variable needed.

---
