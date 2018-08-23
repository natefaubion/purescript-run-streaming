-- | This modules defines primitive fusion operations for push streams.

module Run.Streaming.Push
  ( identity
  , chain
  , traverse
  , for
  , compose
  , composeFlipped
  , produce
  ) where

import Prelude hiding (compose, identity)
import Run (Run)
import Run.Streaming as RS

identity ∷ ∀ r i o a. o → Run (RS.Pipe i o i o r) a
identity o = RS.respond o >>= \i → RS.request i >>= identity

-- | Connects a Client to a Server which can react to responses from the Server.
chain ∷ ∀ r i o a. (o → Run (RS.Client i o r) a) → Run (RS.Server i o r) a → Run r a
chain k ra = RS.runYield ra >>= RS.interleave (RS.runAwait <$> k)

-- | Loops over a Server/Producer with effects, feeding the result in as a request.
traverse ∷ ∀ r i o a. (o → Run r i) → Run (RS.Server i o r) a → Run r a
traverse k ra = RS.runYield ra >>= RS.substitute k

-- | `traverse` with the arguments flipped.
for ∷ ∀ r i o a. Run (RS.Server i o r) a → (o → Run r i) → Run r a
for = flip traverse

-- | Point-free push composition.
compose
  ∷ ∀ r i o x a
  . (o → Run (RS.Client i o r) a)
  → (x → Run (RS.Server i o r) a)
  → (x → Run r a)
compose ra rb x = chain ra (rb x)

-- | `compose` with the arguments flipped.
composeFlipped
  ∷ ∀ r i o x a
  . (x → Run (RS.Server i o r) a)
  → (o → Run (RS.Client i o r) a)
  → (x → Run r a)
composeFlipped = flip compose

-- | Produce values via an effect.
produce ∷ ∀ r x a. Run (RS.Producer x r) x → Run (RS.Producer x r) a
produce f = go
  where
  go = do
    RS.yield =<< f
    go
