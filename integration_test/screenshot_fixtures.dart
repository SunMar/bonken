// ignore_for_file: prefer_single_quotes
// Stable, hardcoded UUIDs so the fixture data is deterministic across runs.
// Player names are chosen for the screenshot aesthetic; adjust here to change
// what appears in the store listings.

// Players (same across all fixtures)
const _pA = '00000000-0000-4000-a000-000000000001'; // Piet
const _pB = '00000000-0000-4000-a000-000000000002'; // Marie
const _pC = '00000000-0000-4000-a000-000000000003'; // Kees
const _pD = '00000000-0000-4000-a000-000000000004'; // Ans

// Game IDs
const _gA = '00000000-0000-4000-b000-000000000001'; // completed (all 12 rounds)
const _gB = '00000000-0000-4000-b000-000000000002'; // in-progress (4 rounds)
const _gC =
    '00000000-0000-4000-b000-000000000003'; // session B: minigame selection
const _gD =
    '00000000-0000-4000-b000-000000000004'; // session B: doubles/redoubles
const _gE = '00000000-0000-4000-b000-000000000005'; // session B: 7e / 13e
const _gF = '00000000-0000-4000-b000-000000000006'; // session B: Zonder troef

const _players = [
  {"id": _pA, "name": "Piet"},
  {"id": _pB, "name": "Marie"},
  {"id": _pC, "name": "Kees"},
  {"id": _pD, "name": "Ans"},
];

const _ruleVariants = {
  "starterVariant": "dealerStarts",
  "heartsVariant": "onlyAfterPlayedHeart",
};

// Twelve completed rounds for game A, one of each mini-game (8 negative + 4
// positive; noTrump is excluded so it can headline the session-B screenshot).
// Rounds are shuffled so positives appear throughout the final score screen.
// Σ scores == totalPoints for every round (engine invariant).
// kingsAndJacks stays at index 3 so _roundsGameD can skip it by index.
const _roundsCompleted = [
  // Round 1 – Bukken: 13 tricks, −10 each
  {
    "roundNumber": 1,
    "gameId": "duck",
    "chooserId": _pD,
    "scores": {_pA: -40, _pB: -30, _pC: -20, _pD: -40},
    "input": {
      "counts": [
        {_pA: 4, _pB: 3, _pC: 2, _pD: 4},
      ],
    },
    "doublesJson": <String, dynamic>{},
  },
  // Round 2 – Klaveren: +20 per trick, Piet dominant
  {
    "roundNumber": 2,
    "gameId": "clubs",
    "chooserId": _pA,
    "scores": {_pA: 100, _pB: 80, _pC: 40, _pD: 40},
    "input": {
      "counts": [
        {_pA: 5, _pB: 4, _pC: 2, _pD: 2},
      ],
    },
    "doublesJson": <String, dynamic>{},
  },
  // Round 3 – Laatste slag: Ans wins the last trick (−100)
  {
    "roundNumber": 3,
    "gameId": "finalTrick",
    "chooserId": _pC,
    "scores": {_pA: 0, _pB: 0, _pC: 0, _pD: -100},
    "input": {
      "counts": [
        {_pD: 1},
      ],
    },
    "doublesJson": <String, dynamic>{},
  },
  // Round 4 – Heren / Boeren: 8 cards total, −25 each
  {
    "roundNumber": 4,
    "gameId": "kingsAndJacks",
    "chooserId": _pB,
    "scores": {_pA: -50, _pB: -25, _pC: -75, _pD: -50},
    "input": {
      "counts": [
        {_pA: 2, _pB: 1, _pC: 3, _pD: 2},
      ],
    },
    "doublesJson": <String, dynamic>{},
  },
  // Round 5 – Harten: Kees dominant
  {
    "roundNumber": 5,
    "gameId": "hearts",
    "chooserId": _pC,
    "scores": {_pA: 40, _pB: 60, _pC: 100, _pD: 60},
    "input": {
      "counts": [
        {_pA: 2, _pB: 3, _pC: 5, _pD: 3},
      ],
    },
    "doublesJson": <String, dynamic>{},
  },
  // Round 6 – Harten punten: 13 hearts, −10 each
  {
    "roundNumber": 6,
    "gameId": "heartPoints",
    "chooserId": _pA,
    "scores": {_pA: -20, _pB: -50, _pC: -40, _pD: -20},
    "input": {
      "counts": [
        {_pA: 2, _pB: 5, _pC: 4, _pD: 2},
      ],
    },
    "doublesJson": <String, dynamic>{},
  },
  // Round 7 – Harten Heer: Marie wins the KoH (-100)
  {
    "roundNumber": 7,
    "gameId": "kingOfHearts",
    "chooserId": _pA,
    "scores": {_pA: 0, _pB: -100, _pC: 0, _pD: 0},
    "input": {
      "counts": [
        {_pB: 1},
      ],
    },
    "doublesJson": <String, dynamic>{},
  },
  // Round 8 – 7e / 13e: Kees 7th (−50), Piet 13th (−50); Kees doubled Piet
  {
    "roundNumber": 8,
    "gameId": "seventhAndThirteenth",
    "chooserId": _pB,
    "scores": {_pA: -50, _pB: 0, _pC: -50, _pD: 0},
    "input": {
      "counts": [
        {_pC: 1},
        {_pA: 1},
      ],
    },
    "doublesJson": {
      _pairAC: {"state": "doubled", "initiator": _pC},
    },
  },
  // Round 9 – Schoppen: Piet and Ans share top; Marie doubled Piet, Kees doubled Ans
  {
    "roundNumber": 9,
    "gameId": "spades",
    "chooserId": _pD,
    "scores": {_pA: 80, _pB: 60, _pC: 40, _pD: 80},
    "input": {
      "counts": [
        {_pA: 4, _pB: 3, _pC: 2, _pD: 4},
      ],
    },
    "doublesJson": {
      _pairAB: {"state": "doubled", "initiator": _pB},
      _pairCD: {"state": "doubled", "initiator": _pC},
    },
  },
  // Round 10 – Vrouwen: 4 queens, −45 each; Ans doubled Piet, Piet went back
  {
    "roundNumber": 10,
    "gameId": "queens",
    "chooserId": _pC,
    "scores": {_pA: -45, _pB: 0, _pC: -90, _pD: -45},
    "input": {
      "counts": [
        {_pA: 1, _pB: 0, _pC: 2, _pD: 1},
      ],
    },
    "doublesJson": {
      _pairAD: {"state": "redoubled", "initiator": _pD},
    },
  },
  // Round 11 – Ruiten: Marie dominant; Marie doubled Kees
  {
    "roundNumber": 11,
    "gameId": "diamonds",
    "chooserId": _pB,
    "scores": {_pA: 60, _pB: 120, _pC: 40, _pD: 40},
    "input": {
      "counts": [
        {_pA: 3, _pB: 6, _pC: 2, _pD: 2},
      ],
    },
    "doublesJson": {
      _pairBC: {"state": "doubled", "initiator": _pB},
    },
  },
  // Round 12 – Domino: Marie plays the last card (−100); Piet doubled Marie
  // (Marie went back), Ans doubled Kees
  {
    "roundNumber": 12,
    "gameId": "dominoes",
    "chooserId": _pD,
    "scores": {_pA: 0, _pB: -100, _pC: 0, _pD: 0},
    "input": {
      "counts": [
        {_pB: 1},
      ],
    },
    "doublesJson": {
      _pairAB: {"state": "redoubled", "initiator": _pA},
      _pairCD: {"state": "doubled", "initiator": _pD},
    },
  },
];

// Same first 4 rounds reused for the in-progress game.
// List indexing is not a constant expression in Dart, so this is final.
final _roundsPartial = [
  _roundsCompleted[0],
  _roundsCompleted[1],
  _roundsCompleted[2],
  _roundsCompleted[3],
];

// Game D history: omits round 4 (kingsAndJacks, index 3) because that game is
// pending. A pending round must not also appear in history, or the tile is
// hidden by the "already played" filter.
final _roundsGameD = [
  _roundsCompleted[0],
  _roundsCompleted[1],
  _roundsCompleted[2],
];

// ============================================================
// Session A — screenshots 01_home, 02_new_game, 07_final_score
// ============================================================

final sessionAFixture = {
  "version": 10,
  "games": [
    // Game A: completed, shown as finished in home list + final score screen
    {
      "id": _gA,
      "createdAt": "2025-06-01T14:00:00.000Z",
      "updatedAt": "2025-06-01T16:30:00.000Z",
      "scoredAt": "2025-06-01T16:30:00.000Z",
      "gameName": null,
      "players": _players,
      "firstDealerId": _pA,
      "ruleVariants": _ruleVariants,
      "rounds": _roundsCompleted,
      "pendingRound": null,
    },
    // Game B: in-progress after 4 rounds, shown as ongoing in home list
    {
      "id": _gB,
      "createdAt": "2025-06-15T10:00:00.000Z",
      "updatedAt": "2025-06-15T10:45:00.000Z",
      "scoredAt": "2025-06-15T10:45:00.000Z",
      "gameName": null,
      "players": _players,
      "firstDealerId": _pC,
      "ruleVariants": _ruleVariants,
      "rounds": _roundsPartial,
      "pendingRound": null,
    },
  ],
};

// ============================================================
// Session B — screenshots 03_minigame_selection, 04_doubles,
//             05_seventh_thirteenth, 06_no_trump, 08_rules
// ============================================================

// Pair keys: lexicographically smaller UUID first (all six pairs).
const _pairAB = '$_pA,$_pB'; // Piet  vs Marie
const _pairAC = '$_pA,$_pC'; // Piet  vs Kees
const _pairAD = '$_pA,$_pD'; // Piet  vs Ans
const _pairBC = '$_pB,$_pC'; // Marie vs Kees
const _pairBD = '$_pB,$_pD'; // Marie vs Ans
const _pairCD = '$_pC,$_pD'; // Kees  vs Ans

final sessionBFixture = {
  "version": 10,
  "games": [
    // Game C: 4 rounds played, no pending round → game screen shows pickable tiles
    {
      "id": _gC,
      "createdAt": "2025-06-14T09:00:00.000Z",
      "updatedAt": "2025-06-14T09:30:00.000Z",
      "scoredAt": "2025-06-14T09:30:00.000Z",
      "gameName": "Avondje bonken",
      "players": _players,
      "firstDealerId": _pB,
      "ruleVariants": _ruleVariants,
      "rounds": _roundsPartial,
      "pendingRound": null,
    },
    // Game D: pending Heren/Boeren round with Marie doubled Kees
    {
      "id": _gD,
      "createdAt": "2025-06-13T20:00:00.000Z",
      "updatedAt": "2025-06-13T20:20:00.000Z",
      "scoredAt": "2025-06-13T20:20:00.000Z",
      "gameName": "Dubbelen",
      "players": _players,
      "firstDealerId": _pA,
      "ruleVariants": _ruleVariants,
      "rounds": _roundsGameD,
      "pendingRound": {
        "gameId": "kingsAndJacks",
        "chooserId": _pA,
        "input": {
          "counts": [
            {_pA: 0, _pB: 0, _pC: 0, _pD: 0},
          ],
        },
        "doublesJson": {
          _pairBC: {"state": "doubled", "initiator": _pB},
        },
      },
    },
    // Game E: pending 7e / 13e round, no doubles
    {
      "id": _gE,
      "createdAt": "2025-06-12T18:00:00.000Z",
      "updatedAt": "2025-06-12T18:25:00.000Z",
      "scoredAt": "2025-06-12T18:25:00.000Z",
      "gameName": "Zeventje",
      "players": _players,
      "firstDealerId": _pD,
      "ruleVariants": _ruleVariants,
      "rounds": _roundsPartial,
      "pendingRound": {
        "gameId": "seventhAndThirteenth",
        "chooserId": _pD,
        "input": {
          "counts": [
            {_pD: 1}, // 7th trick: Ans
            {_pB: 1}, // 13th trick: Marie
          ],
        },
        "doublesJson": <String, dynamic>{},
      },
    },
    // Game F: pending Zonder troef round.
    // chooser=Kees (seat 2) → doubling order: Ans→Piet→Marie→Kees.
    // Ans doubled everyone; only Piet went back on Ans (redoubled).
    {
      "id": _gF,
      "createdAt": "2025-06-11T19:00:00.000Z",
      "updatedAt": "2025-06-11T19:20:00.000Z",
      "scoredAt": "2025-06-11T19:20:00.000Z",
      "gameName": "Troefje",
      "players": _players,
      "firstDealerId": _pC,
      "ruleVariants": _ruleVariants,
      "rounds": _roundsPartial,
      "pendingRound": {
        "gameId": "noTrump",
        "chooserId": _pC,
        "input": {
          "counts": [
            {_pA: 5, _pB: 2, _pC: 4, _pD: 2},
          ],
        },
        "doublesJson": {
          _pairAD: {
            "state": "redoubled",
            "initiator": _pD,
          }, // Ans doubled Piet, Piet went back
          _pairBD: {"state": "doubled", "initiator": _pD}, // Ans doubled Marie
          _pairCD: {"state": "doubled", "initiator": _pD}, // Ans doubled Kees
        },
      },
    },
  ],
};
