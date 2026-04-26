# Bonken

Score calculator for the Dutch trick-taking card game **Bonken**, built with Flutter. Runs on Android and as a progressive web app.

**Live demo:** https://sunmar.github.io/bonken/

---

## About the game

Bonken is a 4-player Dutch card game played over 12 rounds. Each round one player chooses a mini-game from the catalog below. Points are settled between every pair of players based on the difference in tricks (or cards) won.

### Mini-games

| # | Name | Type | Points |
|---|------|------|--------|
| 1 | Klaveren (Clubs) | Positive | +260 |
| 2 | Ruiten (Diamonds) | Positive | +260 |
| 3 | Harten (Hearts) | Positive | +260 |
| 4 | Schoppen (Spades) | Positive | +260 |
| 5 | Zonder troef (No Trump) | Positive | +260 |
| 6 | Harten Heer (King of Hearts) | Negative | −100 |
| 7 | Heren / Boeren (Kings & Jacks) | Negative | −200 |
| 8 | Vrouwen (Queens) | Negative | −200 |
| 9 | Bukken (Duck) | Negative | −200 |
| 10 | Hartenpunten (Heart Points) | Negative | −130 |
| 11 | 7e / 13e slag (7th & 13th trick) | Negative | −200 |
| 12 | Laatste slag (Last Trick) | Negative | −200 |
| 13 | Domino (Dominoes) | Negative | −200 |

Each player may choose **at most 1 positive** and **at most 2 negative** games per game. Before each round, players declare doubles in turn order (starting left of the chooser, with the chooser going last). On your turn you may double and/or redouble any number of other players in a single action. Once your turn has passed you cannot double or redouble anyone.

---

## Features

- **Game setup** — enter player names (with autocomplete from history) and choose the first dealer.
- **Round tracking** — select a mini-game each round, enter scores, and see a live scoreboard.
- **Doubles & redoubles** — directional double picker showing who doubled whom.
- **Edit & reorder** — edit any completed round or drag-and-drop to reorder rounds.
- **Game history** — past games are persisted locally and listed on the home screen, with undo on delete.
- **Light / dark theme** — follows the system preference, toggleable in-app.
- **Offline** — works fully offline; no network requests at runtime.

---

## Tech stack

| Concern | Library |
|---------|---------|
| Framework | Flutter 3.41.7 / Dart 3.11.5 |
| State management | flutter_riverpod 3.3.1 |
| Persistence | shared_preferences 2.5.3 |
| Fonts | google_fonts 8.0.2 (local assets, no runtime fetching) |
| Design system | Material 3 |

---

## Getting started

### Prerequisites

- Flutter SDK ≥ 3.41.7 ([install](https://docs.flutter.dev/get-started/install))

### Run locally

```bash
git clone https://github.com/SunMar/bonken.git
cd bonken
flutter pub get
flutter run                  # Android device / emulator
flutter run -d chrome        # Web (Chrome)
```

### Build

```bash
flutter build apk --release                          # Android APK
flutter build web --release --base-href /bonken/     # Web (GitHub Pages)
```

---

## Deployment

Pushes to `main` automatically build and deploy the web app to GitHub Pages via the workflow in [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml).

---

## License

This project is licensed under the **GNU Affero General Public License v3.0**.
See [LICENSE](LICENSE) for the full text.

In short: you are free to use, modify, and redistribute the source.
If you run a modified version as a network service,
you must make the source of your modifications available to its users.
