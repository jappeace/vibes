---
name: dutch-energy-comparison
description: >
  Compare Dutch energy providers and find the cheapest option. Use when the user asks
  about energy providers in the Netherlands, switching energy contracts, comparing gas/electricity
  rates, or wants their annual energy comparison updated.
argument-hint: [electricity-kwh-per-month] [gas-m3-per-month]
disable-model-invocation: true
---

# Dutch Energy Provider Comparison

Compare all Dutch energy providers for a specific consumption profile, accounting for
per-unit rates, sign-up channel bonuses, and contract types. Produce a report the user
can act on immediately.

## User profile

- Location: Netherlands, corner house (hoekwoning), no solar panels
- Postcode: 8262AN, house number: 38
- Default consumption: 1,112 kWh peak + 1,000 kWh off-peak (2,112 kWh/year), 1,200 m3 gas/year
- Override with arguments: `$0` = electricity kWh/month, `$1` = gas m3/month
- Strategy: switch provider every year to maximize welkomstbonus/loyaliteitsbonus

## Previous report

The last report (March 2026) is at `/home/claude/vibes/energy-report/`.
Read it first to understand the baseline and see what changed since last time.

## CRITICAL: Use keuze.nl URL parameters for verified data

**Most comparison sites only show "up to" bonus amounts that are wildly inflated.**
Budget Energie advertised "up to €590" but gave €0 at this consumption level.
Essent advertised "up to €500" but gave €100.

The ONLY reliable method is keuze.nl, which accepts URL parameters and returns
verified, all-in pricing for the exact address and consumption:

```
https://www.keuze.nl/energie/aanvragen?postcode=8262AN&nr=38&electricity=1112&electricityOffPeak=1000&noGas=false&gas=1200&manualInputStep=true
```

This returns ALL providers with:
- Exact monthly/yearly cost (all-in: network, taxes, standing charges, everything)
- Verified cashback amount at the user's consumption level
- Yearly cost without discount (= gross)

**Use this as the primary data source.** Other sites are secondary/unverified.

## Research procedure

### Step 1: Fetch keuze.nl verified data (PRIMARY SOURCE)

Construct the URL with the user's details:
```
https://www.keuze.nl/energie/aanvragen?postcode={POSTCODE}&nr={HOUSE_NUMBER}&electricity={PEAK_KWH}&electricityOffPeak={OFFPEAK_KWH}&noGas=false&gas={GAS_M3}&manualInputStep=true
```

Fetch this URL and extract ALL offers. For each, record:
- Provider name and contract type
- Monthly cost (includes cashback spread)
- Yearly cost (= net)
- Cashback amount
- Yearly without discount (= gross, all-in)

This gives you verified, personalized pricing. No guesswork needed.

### Step 2: Cross-reference other sites (SECONDARY, unverified)

Other sites may show different (higher) bonus amounts but require interactive
forms. Fetch what you can, but flag unverified amounts clearly:

| Source | What it has | Reliability |
|--------|------------|-------------|
| energieaanbiedingen.nu | Bonus listings per provider | Shows "up to" amounts, not personalized |
| energie-aanbiedingen.com | Bonus listings + rates | Has "tot" amounts, unverified |
| easyswitch.nl | Rates + some bonuses | Default consumption, not personalized |
| gaslicht.com | Top 5 offers with bonuses | Requires JS form for personalized results |
| energiecashback.nl | Cashback amounts | Unverified |
| energiehunter.nl | Cashback amounts | Unverified |

### Step 3: Build the report

Output to `/home/claude/vibes/energy-report/energy-comparison-<month>-<year>.md`.

Report structure:
1. How bonuses work (critical context)
2. Fixed 1-year contracts: ranked by verified net cost from keuze.nl
3. "Up to" vs reality comparison table
4. Fixed 3-year contracts: ranked by net 3-year total from keuze.nl
5. Annual switching vs 3-year fixed comparison
6. Variable contracts: for reference only
7. Overall recommendation
8. Bill breakdown: monthly payment vs year-end bonus
9. Unverified bonuses from other sites (clearly flagged)
10. Sign-up links (keuze.nl personalized link + all channels)
11. Sources with dates

## Pitfalls — lessons learned the hard way

### 1. "Up to" bonuses are DRASTICALLY inflated — not 10-15%, more like 50-100%

In March 2026, verified with the user's actual address on keuze.nl:

| Provider | Headline "up to" | Real cashback | Difference |
|----------|----------------:|-------------:|----------:|
| Budget Energie | €590 | **€0** | -100% |
| Essent | €500 | **€100** | -80% |
| Energiedirect | €500 | **€50** | -90% |
| Vattenfall | €400 | **€260** | -35% |
| Greenchoice | €350 | **€350** | 0% |

NEVER use "up to" amounts in calculations. ALWAYS verify with actual address.
Only Greenchoice delivered its advertised amount. The rest were fantasy.

### 2. This completely changes the recommendation

With "up to" bonuses, annual switching appeared to save €492 over 3 years vs a
3-year fixed contract. With REAL bonuses, the 3-year fixed (Innova) was actually
€83 CHEAPER than annual switching. The entire strategy flipped.

### 3. Bonuses vary by sign-up channel — but less than advertised

keuze.nl is the best verified source because it accepts URL parameters.
Other sites (energieaanbiedingen.nu, easyswitch.nl) show higher bonuses
but we could not verify them at the user's consumption level. They may be
just as inflated as the headline amounts.

### 4. No renewal required for bonus

ACM regulations (since June 2023) ensure the loyaliteitsbonus is paid on the
jaarafrekening after completing the full contract term. You do NOT need to renew.
Cancel early = lose the bonus AND pay a termination fee (€50-100 for 1yr).

### 5. High bonuses hide high rates

A provider offering €590 bonus but charging €0.278/kWh + €1.525/m3 may be cheaper
net than one charging €0.266/kWh + €1.459/m3 with only €350 bonus — BUT the high-rate
provider is a worse deal if you forget to switch or if bonuses change next year.

Always present BOTH the gross ranking (rate-based) and net ranking (after bonus).

### 6. "New customer" restriction

You typically can't return to the same provider within 12 months and still qualify
for the welkomstbonus. Plan a 3-provider rotation cycle.

### 7. Variable rates are deceptive

Variable rates often look cheaper per-unit than fixed, but:
- No price protection against gas price spikes
- No bonus available
- The user's 1,200 m3/year gas consumption creates heavy exposure to volatility

### 8. Don't forget the monthly payment reality

The "net year 1" figure divides the bonus across 12 months. But your actual monthly
bill is based on the gross rate. The bonus comes back as a lump sum on the
jaarafrekening. Make this clear so the user budgets correctly.

### 9. Gift card bonuses

Some channels offer gift cards instead of cash. Only count cash/bank transfer bonuses
unless the user explicitly wants gift cards. Flag gift-card-only bonuses separately.

## CSV format for bonus-per-channel.csv

```
Provider,€/kWh (1yr),€/m3 (1yr),Gross Annual,Direct Site,easyswitch.nl,gaslicht.com,energieaanbiedingen.nu,keuze.nl,energie-aanbiedingen.com,energiehunter.nl,energiecashback.nl,Best Bonus,Best Channel,Net Year 1 (best bonus)
```

## Useful Dutch energy terminology

| Dutch | English | Notes |
|-------|---------|-------|
| Loyaliteitsbonus | Loyalty bonus | Paid at end of contract |
| Welkomstkorting | Welcome discount | Sometimes applied monthly |
| Cashback | Cashback | Via comparison site, not provider |
| Jaarafrekening | Annual statement | When bonus is settled |
| Vaste leveringskosten | Standing charge | ~€6/month |
| Netbeheerkosten | Network costs | ~€700/yr, same for all providers |
| Energiebelasting (EB) | Energy tax | Included in all-in rates |
| ODE | Sustainable energy surcharge | Included in all-in rates |
| Staffel | Tier/bracket | Consumption-based bonus tiers |
| Hoekwoning | Corner house | Higher gas usage expected |
| Opzegvergoeding | Early termination fee | €50-150 depending on contract |

## After completing the report

1. Compare with the previous report to highlight what changed (new providers,
   rate movements, channel bonus shifts)
2. If a provider from last year's rotation is no longer competitive, flag it
3. Remind the user to set a calendar reminder for month 11 of their contract
