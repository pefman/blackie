# Blackie

Blacksmithing companion addon for **WoW Forever** (standalone client, build 1.60.1.x, `Interface: 16001`).

Design goals:

- **GUI-first** — a draggable panel with three tabs (Recipes / Plan / Shopping). A minimap button or `/blackie` opens it. Slash commands remain for diagnostics.
- **API-only discovery** — recipes, trainers, vendor stock and loot are discovered live from the client APIs and gameplay events. No bundled recipe/trainer datasets, no curated guides.
- **Dynamic leveling paths** — a DP solver computes an optimal 1–300 route from whatever the addon currently knows, using live prices (bags → AH cache → vendor fallback).
- Profession-agnostic core; Blacksmithing ships first.

## Status

Early development (v0.1.0: discovery + costing + solver core verified against an offline Lua 5.1 test harness; GUI panel Batch F). Live in-game API pinning against a 1.60.1 client is in progress.

## Install

Copy the `Blackie/` folder into your client's `Interface/AddOns/` directory (for WoW Forever that is `World of Warcraft/_forever_/Interface/AddOns/`). Type `/reload` after copying.

## Using the panel

Open it with the **minimap button** (bottom of the minimap) or by typing `/blackie` (no arguments). Drag it anywhere; `ESC` closes it.

- **Recipes tab** — every recipe Blackie has learned about, color-coded by skill band (grey/green/yellow/orange/red) against your current Blacksmithing level. Filter box + `known` toggle. Hover a row for the item tooltip. `rescan tradeskill` pulls the current recipe list from the client's tradeskill API (open your tradeskill window first).
- **Plan tab** — set the target skill, optionally allow orange-band risk, press **RUN PLAN**: a dynamic-programming path (craft steps with quantities and costs, rank-up stops) optimized against live prices. A saved plan is restored when you reopen the tab.
- **Shopping tab** — the buy list from the last plan: quantities, unit prices, totals, and where each price came from (AH cache / vendor / your bags). Hover rows for tooltips.

Typical loop: open tradeskill window → `rescan` → optionally scan a **trainer** (`/blackie trainer` with the trainer window open — gives rank costs and trainer-learnable recipes) and a **vendor** (`/blackie vendor` with a merchant open — reagent unit prices) → stand near an AH so cached bids populate → **RUN PLAN** → buy from the **Shopping** tab. The solver refuses to price a recipe it cannot price, so the more live knowledge it has, the cheaper and more complete the plan.

## How the API layer works (research findings baked in)

Per the official WoW Forever dev notes (2026-09-15) and community reports, **WoW Forever shares Mainline WoW's UI architecture and the vast majority of the APIs available in Mainline 12.1.5** — it is *not* a 1.12 Classic Era client. Blackie is therefore written against the modern API baseline:

- Foreground window: `ProfessionsFrame`; `C_TradeSkillUI.GetRecipeInfo`, `GetBaseProfessionInfo`, `GetChildProfessionInfo`, `GetRecipeInfoForSkillLineAbility`, `CraftRecipe`. `TradeSkillFrame` / `SkillFrame` classic globals are kept as pinned-first fallbacks.
- **Secret values are active** (the Midnight "addon disarmament" applies to Forever): arithmetic on a secret raises a Lua error. Blackie keeps numeric paths on item IDs / its own cached numbers and never renders secret-derived strings, so it degrades to display-only instead of erroring.
- `GetFrameStrata` can return a secret for Blizzard-owned frames: Blackie never reads strata from foreign frames and only ever sets strata on its own frames.
- Game type detection: `WOW_PROJECT_CAMELOT` (18) for Forever clients, interface range `16000–19999`; detection is informational only and never gates features.
- Minimap note: since Beta 5 (build 70425) the minimap header/frames were reskinned — the minimap button is created inside a `pcall` and `/blackie` (or `/bl`) always works as the fallback.
- Client updates (next up: **1.60.2**) can add or gate APIs overnight — `/blackie probe` re-runs the verification against the live client and the report can be pasted for pinning.

Still **probe-verify rather than assume** (documented but unconfirmed for this specific client): which recipe-enumeration driver exists live (`GetRecipeNumDisplayRecipes`/`GetRecipeDisplayRecipe` — unverified in the public mirror — vs `GetNumTradeSkills`/`GetTradeSkillInfo`), the exact live-AH surface, and trainer-learn APIs. The probe and the driver pinning in `Core/Compat.lua` keep these from breaking the whole addon.

## Slash commands (secondary diagnostics)

```
/blackie                open/close the panel
/blackie recipes        open the panel on the Recipes tab
/blackie probe [full]   verify the documented API baseline against this client build
/blackie rescan         refresh recipe cache from tradeskill window
/blackie trainer        scan open trainer window (ranks + learnable recipes)
/blackie vendor         scan open merchant window (stock + unit prices)
/blackie price <item>   price one item (bags / AH cache / vendor)
/blackie plan           compute optimal leveling path + shopping list (also on the Plan tab)
/blackie shopping       reprint the last saved plan
/blackie target <n>     set skill target (default 225)
/blackie compat         show API compatibility state
/blackie reset          wipe cached probe state
/blackie version        print version + detected client
```

## Offline tests

Solver models are pure Lua and unit-testable without the game client:

```sh
lua5.1 Blackie/tests/harness.lua
```

## Roadmap (next batches)

- Batch G: self-test suite (`/blackie selftest`), probe report copy support
- Runtime verification follow-ups: live recipe-enumeration winner, AH posting surface, trainer-learn API
- Trainer rank purchase helper, crafted-item quality hooks
