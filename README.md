# WoW Companion

A mobile World of Warcraft companion app. View your characters, gear, Mythic+ scores, and raid progression — all pulled from the official Battle.net API.

<p align="center">
  <img src="assets/screenshots/wow-companion-1.png" width="280" alt="Character List" />
  &nbsp;&nbsp;&nbsp;
  <img src="assets/screenshots/wow-companion-2.png" width="280" alt="Character Dashboard" />
</p>

## Features

- **Battle.net Sign In** — Log in with your Battle.net account to see all your characters
- **Character List** — Search, sort, and group by realm, class, race, or faction
- **Character Dashboard** — Hero card with your character's render and class-colored theme
- **Equipment** — Two-column gear layout with item icons, quality colors, enchants, and gems
- **Mythic+** — Rating, best dungeon runs, and affix filtering
- **Raid Progression** — Current expansion raids with boss-by-boss kill tracking and portraits
- **Fast** — Cached data, parallel loading, images load progressively

## Try It

**Web App** — [faizal97.github.io/mobile-wow-companion](https://faizal97.github.io/mobile-wow-companion/)

**Android** — [Download APK](https://github.com/faizal97/mobile-wow-companion/releases/latest)

> On Android, you may need to enable "Install from unknown sources" in Settings.

## Building from Source

Requires Flutter 3.2+ and a [Battle.net Developer](https://develop.battle.net/) application.

```bash
git clone https://github.com/faizal97/mobile-wow-companion.git
cd mobile-wow-companion
```

Create a `.env` file with your credentials, then run:
```bash
./run_dev.sh
```

See [`worker/`](worker/) for the auth proxy setup (Cloudflare Worker).

## Disclaimer

This project is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft and Battle.net are trademarks of Blizzard Entertainment, Inc.
