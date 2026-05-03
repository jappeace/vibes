---
name: investment-review
description: Review and document investment portfolio positions from Interactive Brokers statements. Use when the user wants to review stocks, document investment theses, set exit strategies, or analyze portfolio positions. Also trigger when discussing IB statements, stock positions, or investment decisions.
argument-hint: [ib-statement-path]
user-invocable: false
---

# Investment Portfolio Review

You are helping the user review and document their investment portfolio.
The investment report lives at: `/home/claude/vibes/jappie-software/strategy/investments.org`

## Workflow

### 1. Parse the IB Statement

If an Interactive Brokers HTML statement path is provided via `$ARGUMENTS[0]`,
or one exists in `/home/claude/vibes/ib/`, parse it to extract open positions:
- Symbol, quantity, cost price, cost basis, close price, current value, unrealized P/L
- Group by currency (AUD, EUR, JPY, USD, etc.)

### 2. For Each Position

Go through positions one at a time with the user:

1. **Identify the company** — look up ticker if needed via web search
2. **Ask the user for their thesis** — why did they buy it?
   - If they don't remember, research the company and present what it does to jog their memory
3. **Document the thesis** in the investments.org report
4. **Set exit strategies** with both downside and upside:

#### Downside (cut losses / thesis invalidation):
- Set concrete internal company targets with deadlines
- Give the company reasonable slack beyond their own stated targets
- Example: "If X hasn't happened by [date], sell everything"

#### Upside (take profits, tiered):
- Research the company's targets, market cap, and comparable valuations
- Calculate reasonable price targets based on projected fundamentals
- Propose a tiered profit-taking plan to derisk and rebalance
- Example: "Sell 50% at $X, sell remaining at $Y"

### 3. Flag Action Items

Maintain an Action Items section at the top of the report with:
- **SELL** — positions where the thesis is broken, with reasons
- **FURTHER ANALYSIS** — positions needing more research
- Resolved items marked as RESOLVED with outcome

### 4. Portfolio-Level Notes

Document the overall portfolio strategy (diversification thesis,
currency strategy, sector themes) at the top of the report.

## Report Format

Use org-mode (`.org`) format. Each position should have:

```org
*** TICKER — Company Name (Exchange)
- Quantity: N
- Cost basis: CUR X (CUR Y/share)
- *Thesis:* Why the position was bought
- *Exit strategy:*
  Downside (cut losses):
  1. [Concrete milestone + deadline]. If not met, sell.
  Upside (take profits, tiered):
  1. Sell N shares at $X (rationale)
  2. Sell remaining N shares at $Y (rationale)
```

## Guidelines

- Be proactive about researching companies the user doesn't remember
- Present financials (revenue, market cap, EBITDA) when setting price targets
- Use web search to look up company info, recent performance, and analyst outlook
- When the user says a thesis is broken, add it to the SELL action items immediately
- For tiered profit-taking, calculate targets based on company fundamentals, not vibes
- Keep the conversation flowing naturally — go stock by stock, don't overwhelm
