# HydraFuel

A precise water, macro and micronutrient tracker for iOS, built with Flutter.
Everything is stored on the phone — no account, no server, no network calls.

Built around two ideas:

1. **Water is the headline feature.** It gets its own tab, its own ring, a
   pace readout that tells you whether you are ahead or behind *right now*,
   and local notifications that fire on schedule without an internet
   connection.
2. **The arithmetic is exact.** You weigh your food, so the app should not
   round your inputs, guess at portions, or hide how a target was calculated.

---

## Getting it onto your phone

You need a Mac with Xcode and the Flutter SDK installed
([install guide](https://docs.flutter.dev/get-started/install/macos)).

```bash
git clone <this repo>
cd fitness
./tool/bootstrap.sh        # generates ios/ and android/, restores lib/, runs pub get
flutter test               # 100+ tests, all offline
flutter devices            # plug the iPhone in and check it appears
flutter run                # builds, signs and installs
```

The first `flutter run` will ask Xcode for a signing identity. Open
`ios/Runner.xcworkspace`, select the **Runner** target → **Signing &
Capabilities**, and pick your Apple ID.

**On signing:** a free Apple ID re-signs apps for 7 days, after which the app
stops launching until you `flutter run` again. A paid Apple Developer account
($99/year) extends that to a year. Either works; the free one just needs a
weekly reconnect.

Once installed it runs entirely offline. Both your iPhone 17 and iPhone 11 can
have it, but they keep separate data — there is no sync. Use **Profile →
Export a backup** to move data between them.

---

## How the numbers are worked out

Every target in the app can be traced back to a formula. Tap any nutrient on
the **All nutrients** screen to see the reasoning that produced its number.

### Energy

| Step | Formula |
|---|---|
| BMR | Mifflin-St Jeor by default; Katch-McArdle if you enter body fat % |
| TDEE | BMR × activity factor (1.20 sedentary → 1.90 twice-daily training) |
| Budget | TDEE + goal adjustment |
| Goal adjustment | `rate_kg_per_week × 7700 ÷ 7` kcal/day |

The deficit is **clamped so your budget never falls below BMR**. Asking for
1.5 kg/week when your maintenance is 2136 kcal gets you a 356 kcal deficit,
not a 1650 kcal one.

### Macros

| Macro | Rule |
|---|---|
| Protein | g/kg of body weight, or of lean mass if you know your body fat % |
| Fat | % of energy at 9 kcal/g, with a hard floor of 0.5 g/kg body weight |
| Carbs | whatever energy remains, at 4 kcal/g |
| Fibre | 14 g per 1000 kcal (Institute of Medicine) |

The three macros always reconstruct the calorie budget exactly — that is
asserted in the test suite, not assumed.

### Water

```
baseline   = body weight (kg) × 35 ml/kg
exercise   = minutes/day × 12 ml/min
climate    = 0 / 500 / 1000 ml for temperate / warm / hot
─────────────────────────────────────────────
total      = baseline + exercise + climate
to drink   = total − water from food (optional, off by default)
```

The food-water credit is opt-in and can never drag the goal below 1 litre.
Every term is adjustable in **Profile → Water**, and the breakdown is shown
on the Water tab so you can see where the number came from.

### Limits

Saturated fat ≤10% of energy, trans fat ≤1%, added sugar ≤10% (WHO), sodium
≤2000 mg, cholesterol ≤300 mg. Micronutrient targets are adult RDAs adjusted
for your sex and age.

**Any of these can be overridden.** When you have a blood report telling you
to cap sodium at 1500 mg or push fibre to 40 g, open **All nutrients**, tap
the nutrient, and set your own figure. Overrides always win over the formula
and are labelled as yours.

---

## Precision, specifically

These are deliberate design decisions, not incidental details:

- **Nothing is rounded until it is drawn on screen.** Values are stored and
  summed as doubles. A day's total is the exact sum of its entries.
- **One multiplication.** Nutrition is stored per 100 g. Everything else —
  servings, millilitres, "two rotis" — is converted to grams once, then
  scaled as `per_100g × grams ÷ 100`. Errors cannot compound.
- **Unknown is not zero.** A food whose label omitted iron shows "—", not
  "0 mg". The app will not claim a food contains none of something just
  because you did not type a number.
- **Logged entries snapshot their food.** Correcting a food's nutrition
  tomorrow does not rewrite what you ate last Tuesday. Deleting a food from
  your library leaves your history intact.
- **Bad data is caught at entry.** Saving a food cross-checks its stated
  calories against its own macros using Atwater factors (protein 4, carbs 4,
  fibre 2, fat 9, alcohol 7 kcal/g). If the label claims 1200 kcal for
  something whose macros imply 120, it says so before you save. It also
  rejects impossible combinations — fat fractions exceeding total fat, sugars
  plus fibre exceeding carbohydrate, macros summing past 100 g per 100 g.
- **Volumes convert through real density.** Milk at 1.03 g/ml, oil at 0.92.
  A food with no recorded density refuses to guess rather than assuming 1.0.
- **Days are local calendar days**, stored as `yyyy-MM-dd` next to each
  timestamp, so grouping never depends on timezone maths at query time.

---

## Water reminders

Scheduled as **local** notifications, held by the phone itself. No push
server, no certificate, no internet.

- Spread evenly between your wake and sleep times at your chosen interval.
- Each one names the amount to drink and the cumulative total you should be
  at by that time.
- The last one of the day is a "last call" rather than another interval
  prompt.
- iOS holds at most 64 pending local notifications per app. If your interval
  would need more than that, the app **widens the interval and tells you**,
  rather than letting the evening reminders silently vanish.

**Profile → Reminders → See schedule** lists every reminder and its exact
wording. **Send a test** fires one immediately so you can confirm permissions
actually took.

---

## Logging food

The library is yours to build. 26 reference foods are seeded on first launch
(USDA FoodData Central values, Indian composition tables for roti and paneer)
— edit them, delete them, or replace the numbers with what is printed on the
packet you actually buy. A weighed input against your own packet beats a
database average every time.

When adding a food you can type values **per 100 g, per 100 ml, or per
serving**, and the app normalises to per 100 g on save. Most packets label per
serving, so this saves doing the division by hand.

Foods sort by how often you use them, so your real diet floats to the top
within a week.

---

## Your data

Local only, on one device. There is no account and nothing leaves the phone.

That also means **an export is your only backup**. Profile → Export a backup
produces a JSON document with everything in it — profile, foods, every logged
meal and drink. Restoring replaces the contents of the phone in a single
transaction, so a malformed file leaves your existing data untouched.

---

## Project layout

```
lib/
  core/          dates, number and unit formatting, theme
  domain/        pure Dart: nutrients, targets, profile, day summaries
  data/          SQLite schema and repositories
  services/      notifications, backup
  state/         Riverpod providers and mutations
  ui/            screens and widgets
test/            unit tests for the arithmetic, widget tests for the app
```

`lib/domain/` has no Flutter imports and no I/O. Every calculation in the app
lives there and is unit-tested against hand-computed reference values.

```bash
flutter test              # everything
flutter analyze           # zero issues expected
```
