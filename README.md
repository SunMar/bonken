# Bonken

Een app voor het invoeren van scores en het berekenen van uitslagen van het kaartspel **Bonken**, gebouwd met Flutter. Installeerbaar als web-app op elk apparaat.

---

## Spelen

De spelregels staan in de app en zijn te vinden op [sunmar.github.io/bonken/#/spelregels](https://sunmar.github.io/bonken/#/spelregels).

| Platform | Hoe |
|---|---|
| Android | Open [sunmar.github.io/bonken](https://sunmar.github.io/bonken/) in Chrome → Menu → **Toevoegen aan startscherm** |
| iOS / iPadOS | Open [sunmar.github.io/bonken](https://sunmar.github.io/bonken/) in Safari → Delen → **Zet op beginscherm** |
| Desktop | Open [sunmar.github.io/bonken](https://sunmar.github.io/bonken/) — Chrome/Edge toont een installatieknop in de adresbalk |

De web-app is een volledige PWA (Progressive Web App): eenmaal geïnstalleerd werkt hij offline, net als een native app.

---

## Over het spel

Bonken is een kaartspel voor vier spelers. Een spel bestaat uit twaalf rondes. Elke ronde kiest één speler een spelvorm uit de catalogus hieronder; de regels en puntentelling verschillen per spelvorm.

### Spelvormen

| # | Naam | Type | Punten |
|---|------|------|--------|
| 1 | Harten Heer | Negatief | −100 |
| 2 | Heren / Boeren | Negatief | −200 |
| 3 | Vrouwen | Negatief | −180 |
| 4 | Bukken | Negatief | −130 |
| 5 | Harten punten | Negatief | −130 |
| 6 | 7e / 13e slag | Negatief | −100 |
| 7 | Laatste slag | Negatief | −100 |
| 8 | Domino | Negatief | −100 |
| 9 | Klaveren | Positief | +260 |
| 10 | Ruiten | Positief | +260 |
| 11 | Harten | Positief | +260 |
| 12 | Schoppen | Positief | +260 |
| 13 | Zonder troef | Positief | +260 |

---

## Functies

- **Nieuw spel** — voer de namen van de spelers in (met suggesties uit eerder gespeelde spellen); kies de eerste deler handmatig of laat de app er willekeurig een kiezen.
- **Rondes bijhouden** — kies een spelvorm per ronde, voer de dubbels en het resultaat in, en zie een scorebord van de ronde.
- **Spelquota** — elke speler mag per spel maximaal 1 positief en 2 negatieve spelvormen kiezen. De app houdt dit bij en waarschuwt wanneer een speler een keuze maakt die dit overschrijdt.
- **Dubbelen & terug gaan** — dubbels volgen de beurtvolgorde en de app laat zien welke toegestaan zijn; de ingevulde dubbels zijn ook zichtbaar op het invoerscherm en in het overzicht van al gespeelde rondes.
- **Pauzeren en hervatten** — lopende spellen worden automatisch opgeslagen; sluit de app, veeg hem weg of ga ergens anders heen en ga later precies verder waar je gebleven was. Onderbroken rondes worden gemarkeerd en blokkeren andere spelvormen totdat de vorige score is ingevuld of verworpen.
- **Alles bewerken** — bewerk elke afgeronde ronde, pas namen van spelers en eerste deler aan tijdens het spel, of verwijder de laatste ronde.
- **Nieuw spel met dezelfde spelers** — als een spel afgelopen is, start je met één tik een nieuw spel met dezelfde opstelling.
- **Tussenstand & eindstand** — de tussenstand (of eindstand als alle rondes gespeeld zijn) wordt altijd getoond.
- **Spelgeschiedenis** — afgelopen spellen worden lokaal opgeslagen en getoond op het beginscherm, inclusief de eindstand van het spel.
- **Licht / donker thema** — volgt de systeemvoorkeur, of kan handmatig worden aangepast in de app.
- **Offline** — werkt volledig offline; er is geen internetverbinding nodig om de app te gebruiken.

---

## Aan de slag

### Vereisten

- Een recente stabiele [Flutter SDK](https://docs.flutter.dev/get-started/install). De exacte versie is vastgelegd in [`.fvmrc`](.fvmrc).

### Lokaal draaien

```bash
git clone https://github.com/SunMar/bonken.git
cd bonken
flutter pub get
flutter run                  # Android-apparaat / emulator
flutter run -d chrome        # Web (Chrome)
```

### Bouwen

```bash
flutter build apk --release                          # Android APK
flutter build web --release --base-href /bonken/     # Web (GitHub Pages)
```

### Tests

```bash
flutter test
```

---

## Privacybeleid

Het privacybeleid is beschikbaar op [sunmar.github.io/bonken/privacy.html](https://sunmar.github.io/bonken/privacy.html).

---

## Licentie

Dit project is gelicentieerd onder de **GNU Affero General Public License v3.0**.
Zie [LICENSE](LICENSE) voor de volledige tekst.

