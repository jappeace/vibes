-- | Select the review harness and its model names without mixing providers.
module Claude.Gate.ReviewerBackend
  ( ReviewerBackend (ClaudeCode, OpenCode)
  , ReviewPhase (ComplexityCanary, AdversarialCritic, RuleReviewer)
  , reviewerBackend
  , backendExecutable
  , reviewModel
  ) where

import Data.Text (Text)
import Data.Text qualified as Text
import Claude.Gate.GateConfig (envStr)
import System.Environment (lookupEnv)

-- | The CLI and authentication context used by an independent reviewer.
data ReviewerBackend = ClaudeCode | OpenCode

-- | The phase whose model override is being resolved.
data ReviewPhase = ComplexityCanary | AdversarialCritic | RuleReviewer

-- | Read the explicit backend, defaulting to Claude Code for its existing hooks.
reviewerBackend :: IO ReviewerBackend
reviewerBackend = do
  configured <- lookupEnv "CLAUDE_GATE_BACKEND"
  case configured of
    Nothing -> pure ClaudeCode
    Just "claude" -> pure ClaudeCode
    Just "opencode" -> pure OpenCode
    Just backend -> ioError (userError ("Unknown gate reviewer backend: " <> backend <> ". Set CLAUDE_GATE_BACKEND to claude or opencode."))

-- | Executable resolved through the gate process's PATH.
backendExecutable :: ReviewerBackend -> String
backendExecutable ClaudeCode = "claude"
backendExecutable OpenCode = "opencode"

-- Decision: use GPT-5.6 Terra Fast for the OpenAI canary and GPT-5.6 Luna for
-- rules, reserving the worker's model for adversarial critique. Both were tested
-- through the ChatGPT login; the catalogue's Mini, Spark, and GPT-5.4 entries
-- were rejected by that endpoint. Other providers retain their worker model,
-- avoiding an unexpected OpenAI login requirement. Per-phase overrides win.
-- | Select a phase override or the backend's default model tier.
reviewModel :: ReviewPhase -> IO Text
reviewModel phase = do
  backend <- reviewerBackend
  case backend of
    ClaudeCode -> case phase of
      ComplexityCanary -> envStr "CLAUDE_DUMBIFY_MODEL" "claude-haiku-4-5"
      -- Decision: the critic defaults to the current Opus (5.5 since 2026-09-29).
      -- It leads Fable 5.1 on every published coding and review benchmark at
      -- $4/$20 per MTok, cheaper than the Opus 4.8 it replaces. Fable was
      -- considered and rejected: 2.5x the price for no measured review gain.
      AdversarialCritic -> envStr "CLAUDE_CRITIQUE_MODEL" "claude-opus-5-5"
      RuleReviewer -> envStr "CLAUDE_REVIEWER_MODEL" "claude-sonnet-5"
    OpenCode -> do
      inherited <- envStr "OPENCODE_GATE_MODEL" ""
      model <- envStr (openCodeModelVariable phase) (defaultOpenCodeModel phase inherited)
      if Text.null (Text.strip model) || not ("/" `Text.isInfixOf` model)
        then ioError (userError "OpenCode reviewer has no provider/model. Set OPENCODE_GATE_MODEL to an available openai/model-id.")
        else pure model

defaultOpenCodeModel :: ReviewPhase -> Text -> Text
defaultOpenCodeModel phase worker =
  if "openai/" `Text.isPrefixOf` worker
    then case phase of
      ComplexityCanary -> "openai/gpt-5.6-terra-fast"
      AdversarialCritic -> worker
      RuleReviewer -> "openai/gpt-5.6-luna"
    else worker

openCodeModelVariable :: ReviewPhase -> String
openCodeModelVariable ComplexityCanary = "OPENCODE_DUMBIFY_MODEL"
openCodeModelVariable AdversarialCritic = "OPENCODE_CRITIQUE_MODEL"
openCodeModelVariable RuleReviewer = "OPENCODE_REVIEWER_MODEL"
