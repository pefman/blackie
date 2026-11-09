# Blackie

Blacksmithing companion addon for **WoW Forever** (standalone client, build 1.60.1.x, `Interface: 16001`).

Design goals:

- **API-only discovery** — recipes, trainers, vendor stock and loot are discovered live from the client APIs and gameplay events. No bundled recipe/trainer datasets, no curated guides.
- **Dynamic leveling paths** — a DP solver computes an optimal 1–300 route from whatever the addon currently knows, using live prices (bags → AH cache → vendor fallback).
- Profession-agnostic core; Blacksmithing ships first.

## Status

Early development (v0.1.0, discovery + solver core verified against an offline Lua 5.1 test harness). Live in-game API pinning against a 1.60.1 client is in progress.

## Install

Copy the `Blackie/` folder into your client's `Interface/AddOns/` directory.

## Slash commands

```
/blackie probe [full]   dump client API capability report
/blackie rescan         refresh recipe cache from tradeskill window
/blackie trainer        scan open trainer window (ranks + learnable recipes)
/blackie vendor         scan open merchant window (stock + unit prices)
/blackie price <item>   price one item (bags / AH cache / vendor)
/blackie plan           compute optimal leveling path + shopping list
/blackie shopping       reprint the last saved plan
/blackie target <n>     set skill target (default 225)
/blackie compat         show API compatibility state
/blackie reset          wipe cached state
/blackie version        print version
```

## Offline tests

Solver models are pure Lua and unit-testable without the game client:

```sh
lua5.1 Blackie/tests/harness.lua
```
