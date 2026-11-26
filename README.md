# Tmog (Patched for WoW 1.12 / Turtle WoW)

> Item browser, outfit manager, and transmog collection tooltip addon for Turtle WoW, enhanced with optional client-mod acceleration and bug fixes.

## Client Mods Used

| Mod | Purpose in this addon | Required? |
|---|---|---|
| **ClassicAPI** | Throttled async item caching (`C_Item.RequestLoadItemDataByID`, `ITEM_DATA_LOAD_RESULT`, `C_Timer`), tooltip-free `GetTransmogSlot` / `IsUsableItem` (`C_Item.GetItemDataByID`, `GetItemSubClassInfo`), and `HookScript` / `hooksecurefunc` tooltip hooks | Optional |
| **SuperWoW** | Outfit and collection backup/restore via `ExportFile` / `ImportFile` (`/tmogmod backup`, `/tmogmod restore`), plus `GetInboxItemLink` for inbox tooltips | Optional |
| **VanillaHelpers** | Client-side character appearance preview (`SetUnitVisibleItemID` via `/tmogmod morph` / `unmorph`) and `GetItemDisplayID` lookup for appearance group auditing | Optional |

*(The addon works in stock WoW 1.12 without any client mods; features that depend on optional DLLs are disabled automatically when absent.)*

## Features

- **Tooltip Collection Info:** Displays whether an item's appearance is `Collected` or `Not collected`, whether it is `Unique`, `Non-unique` (with shared-appearance count), or `Unknown`, and lists any saved outfits using it.
- **3D Item Browser & Dressing Room:** Browse all transmog-eligible items by slot and armor/weapon type, filter by `Collected`, `Not collected`, `Only usable`, and `Ignore level`, search by name, and inspect shared-appearance items (`Right-Click`).
- **Outfit Manager:** Save, rename, delete, share (`T.O.L.` codes and database links), and link outfits directly into chat (`|Houtfit:...|h`).
- **Fullscreen Preview:** Toggle a fullscreen 3D model view with rotation, pan, zoom, and screenshot support.
- **Automatic Collection Sync:** Records unlocked appearances from equipped gear (`UNIT_INVENTORY_CHANGED`) and Turtle WoW `TW_TRANSMOG` addon messages.

## What Was Added / Improved

- **Added (`TmogModern.lua`):**
  - Throttled ClassicAPI item prefetching (`30` items per `0.05s` tick) to eliminate UI freezes when opening uncached slots.
  - Tooltip-free `Tmog.GetTransmogSlot` and `Tmog.IsUsableItem` fast-path (falling back to tooltip scan only for race/skill/faction/honor/spell restrictions) when ClassicAPI is loaded.
  - O(1) `Tmog.IsKnownAppearance` lookup index built from `Tmog.ItemDB`.
  - Appearance group auditing/supplementing (`/tmogmod audit`, `/tmogmod groups`), local client-side morphing (`/tmogmod morph`, `/tmogmod unmorph`), and SuperWoW file backup/restore (`/tmogmod backup`, `/tmogmod restore`).
- **Improved:**
  - `TmogLoadingFrame` now prunes cached IDs and rebuilds `Tmog.UpdatePreviewsData()` once loading completes so newly cached items appear immediately without re-clicking the slot.
  - `M.Prefetch` now tracks progress reliably via tick count and cleans up timed-out entries so `inFlight` does not leak.
- **Fixed:**
  - `Constants.lua`: Mapped `highelf` preview camera positions to `bloodelf` so High Elf characters on Turtle WoW get proper model framing instead of falling back to defaults.
  - `Utility.lua`: Fixed `GetSameAppearanceItems()` inserting at index `0` / reversing order (`table.insert(ret, table.getn(ret), id)` -> `table.insert(ret, id)`).
  - `Tooltip.lua`: Fixed `SetCraftItem` fallback typo (`self.nsideHook` -> `self.insideHook`), added duplicate-line guard (`self.tmogLine`) in `ExtendTooltip`, and guarded `TMOG_CACHE[slot]`.
  - `Outfits.lua`: Fixed `ValidateOutfitCode()` leaving `"T.O.L."` in the string (which caused every `T.O.L.` import and `/tmogmod restore` outfit restore to fail) and passing `nil` (`itemID`) to `Tmog.CacheItem()`; fixed `ParseOutfitLink()` to handle full chat hyperlinks; capped `OutfitsDropDown_Initialize()` at `UIDROPDOWNMENU_MAXBUTTONS`; guarded `ShareOutfit()` against uncached `GetItemInfo()` `nil` returns and `DeleteOutfitButton_OnLoad()` against nil dropdown buttons.
  - `Tmog.lua`: Fixed Outfits tab tooltip showing the wrong outfit when searching (`Tmog.OutfitsSorted[self:GetID()]` instead of `TMOG_PLAYER_OUTFITS[self:GetID()]`); added nil-safety guards for `CHAT_MSG_ADDON` (`TMOG_CACHE[slot]`), `DISPLAY_SIZE_CHANGED`, `UpdatePreviews()` `positionInfo`, `UpdateSelection()` `TmogFramePreview1ButtonPlus`, `PreviewButton_OnEnter()` `itemID`, and `ItemDB[slot][type]`.
  - `Tmog.xml`: Switched `TmogButton` from `<OnMouseUp>` to `<OnClick>` so dragging the minimap button does not toggle the dressing room.

## Usage

### Core Commands (`/tmog`)
- `/tmog show` — Toggle the dressing room window
- `/tmog reset` — Reset minimap button position
- `/tmog lock` — Lock/unlock minimap button
- `/tmog wipe` — Reset this character's collected appearances cache
- `/tmog repair` — Attempt to repair this character's cache
- `/tmog debug` — Toggle debug messages in chat

### Client-Mod Commands (`/tmogmod`)
- `/tmogmod status` — Show detected client mods and current settings
- `/tmogmod cache on|off` — Toggle ClassicAPI async item caching (on by default)
- `/tmogmod groups [auto on|off]` — Supplement missing appearance groups from client display IDs
- `/tmogmod audit` — Audit static appearance groups against client display IDs
- `/tmogmod morph [outfit]` — Preview current dressing room gear or named outfit on your character locally (requires VanillaHelpers)
- `/tmogmod unmorph` — Clear local morph (requires VanillaHelpers)
- `/tmogmod backup` / `restore` — Export/import outfits and collection to `imports/` (requires SuperWoW)
- `/tmogmod dump <itemID>` — Print item data, display ID, and resolved transmog slot

### Initial Collection Caching
To cache existing transmogs on first use, speak to the Fashionista NPC in Stormwind or Orgrimmar and click through each armor slot and each weapon type you have unlocked while wearing an item of that type.

## Preview

![tooltip2](https://github.com/user-attachments/assets/6a306561-45c8-4c5b-9f12-1e9179a496ab)
![tooltip1](https://github.com/user-attachments/assets/01ccac85-ef1d-45d5-91f7-c448c13af8b5)
![gui1](https://github.com/user-attachments/assets/3c361dd1-ce43-43be-8bbd-06382e22841c)
![gui2](https://github.com/user-attachments/assets/5c2bfcf8-bb83-43a3-97c2-5df0e27d5d53)

## Credits & License

- **Original addon:** [Otari98](https://github.com/Otari98/Tmog) (v5.0.1)
- **Original thanks:** [Shagu](https://github.com/shagu), [Zaas](https://github.com/Zebouski), [CosminPOP](https://github.com/CosminPOP)
- **License:** Same as original addon unless stated otherwise.
