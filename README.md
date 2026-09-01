<p align="center">
  <img src="assets/agency.webp" alt="An empty rating agency lobby" width="100%">
</p>

<h1 align="center">AAA</h1>

<p align="center"><b>A rating agency with nobody inside.</b></p>

<p align="center">
  <img src="https://img.shields.io/badge/tests-passing-3fb950" alt="tests">
  <img src="https://img.shields.io/badge/solidity-0.8.26-363636" alt="solidity">
  <img src="https://img.shields.io/badge/chain-Robinhood-ff5100" alt="chain">
  <img src="https://img.shields.io/badge/analysts-0-000000" alt="analysts">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="license">
</p>

---

In 2008 the AAA stamp was something people sold. The agencies that sold it are
still the agencies, and their product is still the same three letters, decided
by people in rooms.

This agency hands out the same letters and cannot be talked to, paid, or
pressured, because there is nobody in the building. A grade is computed from a
feed's own published history, on chain, at the moment you ask for it. Ask
again and it is computed again. There is no committee, no analyst, no owner,
and no number to call.

What it grades: tokenized stocks. Real US equities trade on chain now, and
every one of them hangs off a price feed. Whether that feed shows up for work
is the whole ballgame, and nobody was grading it. Now something is.

## The report card

Every single-stock feed publishing on Robinhood chain, graded by the contract
itself on a fork of mainnet:

```
TICKER  GRADE   worst silence   dark now   trips  rounds
AAPL    BBB        382m       349m       0     300
AMD     BBB        222m        20m       0     300
AMZN    BBB        372m       232m       1     300
ASML    BBB        336m        15m       0     300
BABA    BBB        288m        74m       1     300
CLSK    BB         108m         0m      27     300
COIN    A          117m        70m       1     300
CRCL    A           97m         0m       2     300
CRWV    BB         127m         0m       3     300
DELL    AA          73m        20m       0     300
GME     BB         282m         0m      19     300
GOOGL   BBB        375m        70m       0     300
INTC    BB         228m         3m       3     300
IONQ    BBB        248m         2m       2     300
META    BBB        288m         0m       0     300
MSFT    BBB        390m         0m       0     300
MSTR    A          100m        71m       0     300
MU      BBB        238m         7m       0     300
NBIS    A          143m         0m       1     300
NVDA    BBB        349m       220m       1     300
ORCL    A          172m         0m       0     300
PLTR    BBB        240m        15m       0     300
RGTI    BB         127m         0m      22     300
RKLB    BB         147m        37m       5     300
SNDK    A          135m         0m       0     300
SPCX    BBB        295m         7m       0     300
TSLA    BBB        235m         8m       0     300
TSM     BBB        365m         0m       0     300
USAR    BB         112m         0m      11     300
```

Graded 2026-09-09, all twenty nine stocks, three hundred rounds each. Read the
top line of the board: **nobody earned a AAA.** The agency's first act was
declining to hand out its own name. One AA on the whole chain, and it is DELL.
And look at the trips column: CLSK's price walked away and came back to the
exact same print twenty seven times.

## How a feed earns its letter

The agency walks the feed's last 300 stored rounds and measures four things.
Everything is judged against the exchange calendar that lives inside the
contract: weekends, NYSE holidays, and the overnight count for nothing, and
the session clock follows US daylight saving.

| worst silence during market hours | grade ceiling |
| --- | --- |
| 30 minutes | AAA |
| 90 minutes | AA |
| half a session | A |
| one full session | BBB |
| two sessions | BB |
| a week of half days | B |
| worse | CCC |

Then the overrides, in the order they bite:

**Dark right now beats everything.** More than a full session of market hours
without a print means the feed is not at work today: **D**, whatever the
history says.
