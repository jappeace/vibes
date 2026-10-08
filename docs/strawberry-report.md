# How Many R's Are in "Strawberry"?

## Answer

The word **strawberry** contains exactly **three** letter R's.

They appear at positions 3, 8, and 9:

```
s  t  r  a  w  b  e  r  r  y
1  2  3  4  5  6  7  8  9  10
      ^              ^  ^
```

The first R appears in the "str-" onset. The second and third form the geminate "rr" in "be**rr**y."

## Why This Matters: The AI Strawberry Meme of 2024

In mid-2024, this trivially easy question went massively viral when users discovered that leading AI chatbots — including OpenAI's GPT-4o and others — consistently answered **two** instead of three. Videos of users arguing with ChatGPT, which stubbornly insisted there were "indeed only two R's," spread across TikTok, Reddit, and X (formerly Twitter), turning the question into a de facto litmus test for AI reasoning ability.

The incident was widely covered by outlets including [TechCrunch](https://techcrunch.com/2024/08/27/why-ai-cant-spell-strawberry/), [Inc.](https://www.inc.com/kit-eaton/how-many-rs-in-strawberry-this-ai-cant-tell-you.html), and the linguistics blog [Language Log](https://languagelog.ldc.upenn.edu/nll/?p=65667).

## Why AI Got It Wrong

The failure traces to several well-documented technical causes ([SecWest](https://www.secwest.net/strawberry), [Arbisoft](https://arbisoft.com/blogs/why-ll-ms-can-t-count-the-r-s-in-strawberry-and-what-it-teaches-us)):

1. **Subword tokenization.** LLMs don't process text character-by-character. A tokenizer might split "strawberry" into tokens like `straw` + `berry`. The model manipulates these token vectors, not raw letters, so it has no native mechanism to iterate over individual characters within a token.

2. **No built-in counting algorithm.** Transformer attention operates on tokens as atomic units. There is no internal procedure to "attend to the second letter of token 'berry'." Answers are produced by pattern matching against training data, not by executing a counting algorithm.

3. **Training data conflation.** English spelling guides often highlight the *double-r* in "strawberry" as a common misspelling trap. Models likely learned "strawberry has a double-r" and conflated "two R's together" with "two R's total," missing the lone R in "str-."

4. **No self-verification.** Early chat models generated answers in a single forward pass with no mechanism to verify the result. Chain-of-thought and tool-use capabilities in later models (such as OpenAI's o1, codenamed "Strawberry") were partly developed in response to exactly this class of failure.

## Resolution

OpenAI's September 2024 release of the **o1** reasoning model — internally codenamed "Strawberry" — was widely seen as a direct response to this embarrassment. The o1 model uses chain-of-thought reasoning to break down problems step-by-step, and correctly answers that there are three R's. As of 2025, most frontier models (including Claude) answer this question correctly.

## Sources

- [TechCrunch — "Why AI can't spell 'strawberry'"](https://techcrunch.com/2024/08/27/why-ai-cant-spell-strawberry/)
- [Inc. — "How Many R's in 'Strawberry'? This AI Doesn't Know"](https://www.inc.com/kit-eaton/how-many-rs-in-strawberry-this-ai-cant-tell-you.html)
- [Language Log — "AIs on Rs in 'strawberry'"](https://languagelog.ldc.upenn.edu/nll/?p=65667)
- [SecWest — "The Strawberry R Counting Problem in LLMs: Causes and Solutions"](https://www.secwest.net/strawberry)
- [Arbisoft — "Why LLMs Can't Count the R's in 'Strawberry' & What It Teaches Us"](https://arbisoft.com/blogs/why-ll-ms-can-t-count-the-r-s-in-strawberry-and-what-it-teaches-us)
- [Distractify — "Man Asks ChatGPT How Many R's in Word 'Strawberry,' Chaos Ensues"](https://www.distractify.com/p/chatgpt-how-many-rs-in-strawberry)
- [Jerry Cuomo on Medium — "Why AI Gets the 'Strawberry' Question Wrong"](https://medium.com/@JerryCuomo/why-ai-gets-the-strawberry-question-wrong-eba66c7dedd2)
