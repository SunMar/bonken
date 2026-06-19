# Bonken

Een app voor het invoeren van scores en het berekenen van uitslagen van het kaartspel **Bonken**, gebouwd met Flutter. Installeerbaar als web-app op elk apparaat.

---

## Spelen

| Platform | Hoe |
|---|---|
| Android | Open [sunmar.github.io/bonken](https://sunmar.github.io/bonken/) in Chrome → Menu → **Toevoegen aan startscherm** |
| iOS / iPadOS | Open [sunmar.github.io/bonken](https://sunmar.github.io/bonken/) in Safari → Delen → **Zet op beginscherm** |
| Desktop | Open [sunmar.github.io/bonken](https://sunmar.github.io/bonken/) — Chrome/Edge toont een installatieknop in de adresbalk |

De web-app is een volledige PWA (Progressive Web App): eenmaal geïnstalleerd werkt hij offline, net als een native app.

---

## Het spel

Bonken is een kaartspel voor vier spelers. Een spel bestaat uit twaalf rondes; elke ronde kiest één speler een van de dertien spelvormen. Spelers kunnen elkaar dubbelen om meer punten te winnen (of verliezen). Je vindt [de spelregels](https://sunmar.github.io/bonken/#/spelregels) in de app.


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

## Functionaliteiten

- **Nieuw spel** — voer de namen van de spelers in (met suggesties uit eerder gespeelde spellen); kies de eerste deler handmatig of laat de app er willekeurig een kiezen.
- **Spelnaam** — geef een spel een optionele naam die zichtbaar is op het scorebord en in gedeelde uitslagen.
- **Spelregels** — de volledige spelregels zijn in de app te raadplegen, ook per spelvorm vanuit het invoerscherm. Het spel ondersteunt verschillende regelvarianten (wie de eerste slag opent en wanneer harten gespeeld mogen worden) die per spel zijn aan te passen; ook als app-brede standaard in te stellen via Instellingen.
- **Rondes bijhouden** — kies een spelvorm per ronde, voer de dubbels en het resultaat in, en zie een scorebord van de ronde.
- **Dubbelen & terug gaan** — dubbels volgen de beurtvolgorde en de app laat zien welke toegestaan zijn; snelknoppen voor zaal en slappe hap passen alle dubbels in één tik aan. De ingevulde dubbels zijn ook zichtbaar op het invoerscherm en in het overzicht van al gespeelde rondes.
- **Tussenstand & eindstand** — de tussenstand (of eindstand als alle rondes gespeeld zijn) wordt altijd getoond.
- **Pauzeren en hervatten** — lopende spellen worden automatisch opgeslagen; sluit de app, veeg hem weg of ga ergens anders heen en ga later precies verder waar je gebleven was. Onderbroken rondes worden gemarkeerd en blokkeren andere spelvormen totdat de vorige score is ingevuld of verworpen.
- **Nieuw spel met dezelfde spelers** — als een spel afgelopen is, start je met één tik een nieuw spel met dezelfde opstelling.
- **Deel uitslag** — de einduitslag snel en makkelijk met anderen delen via een deelknop.
- **Spelgeschiedenis** — afgelopen spellen worden lokaal opgeslagen en getoond op het beginscherm, inclusief de eindstand van het spel.
- **Exporteer & importeer** — maak een backup van alle spelgeschiedenis en instellingen en herstel ze op hetzelfde of een ander apparaat.
- **Licht / donker thema** — volgt de systeemvoorkeur, of kan handmatig worden aangepast in de app.
- **Offline** — werkt volledig offline; er is geen internetverbinding nodig om de app te gebruiken.

---

## Technologie

De app is gebouwd met [Flutter](https://flutter.dev/) en levert vanuit één codebase een PWA, een native Android-app en een iOS/iPadOS-app. State management is gebaseerd op [Riverpod](https://riverpod.dev/); het scoredomein is pure Dart zonder frameworkafhankelijkheden. De UI volgt Material 3.

Voor een uitgebreide beschrijving van de architectuur, het domeinmodel, de opslag en de CI-pipeline: zie [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Lokaal ontwikkelen

De Flutter-versie is vastgelegd in [`.fvmrc`](.fvmrc). Installeer [FVM](https://fvm.app/) en gebruik `fvm flutter` / `fvm dart` voor alle aanroepen.

```bash
git clone https://github.com/SunMar/bonken.git
cd bonken
fvm install
fvm flutter pub get
fvm flutter run -d chrome        # Web (PWA in Chrome)
fvm flutter run                  # Android-apparaat / emulator
```

Bouwen:

```bash
fvm flutter build web --release --base-href /bonken/   # Web (GitHub Pages)
fvm flutter build apk --release                        # Android APK
```

Tests en validaties (drie CI-gates: format → analyze → test):

```bash
fvm dart format --output=none --set-exit-if-changed .
fvm flutter analyze --fatal-infos
fvm flutter test
```

Zie [ARCHITECTURE.md §12](ARCHITECTURE.md#12-build-run--release) voor uitgebreide informatie.

---

## Privacybeleid

Het privacybeleid is beschikbaar op [sunmar.github.io/bonken/privacy.html](https://sunmar.github.io/bonken/privacy.html).

---

## Licentie

Dit project is gelicentieerd onder de **GNU Affero General Public License v3.0**.
Zie [LICENSE](LICENSE) voor de volledige tekst.
