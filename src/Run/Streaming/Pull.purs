-- | This modules defines primitive fusion operations for pull streams.

module Run.Streaming.Pull
  ( identity
  , chain
  , traverse
  , for
  , compose
  , composeFlipped
  , draw
  , feed
  , from
  , into
  , consume
  ) where

import Prelude hiding (compose, identity)
import Run (Run)
import Run.Streaming as RS

identity ∷ ∀ r i o a. i → Run (RS.Pipe i o i o r) a
identity i = RS.request i >>= \o → RS.respond o >>= identity

-- | Connects a Server to a Client which can fulfill requests from the Client.
chain ∷ ∀ r i o a. (i → Run (RS.Server i o r) a) → Run (RS.Client i o r) a → Run r a
chain k ra = RS.runAwait ra >>= RS.interleave (RS.runYield <$> k)

-- | Fulfills a Client with effects.
traverse ∷ ∀ r i o a. (i → Run r o) → Run (RS.Client i o r) a → Run r a
traverse k ra = RS.runAwait ra >>= RS.substitute k

-- | `traverse` with the arguments flipped.
for ∷ ∀ r i o a. Run (RS.Client i o r) a → (i → Run r o) → Run r a
for = flip traverse

-- | Point-free pull composition.
compose
  ∷ ∀ r i o x a
  . (i → Run (RS.Server i o r) a)
  → (x → Run (RS.Client i o r) a)
  → (x → Run r a)
compose ra rb x = chain ra (rb x)

-- | `compose` with the arguments flipped.
composeFlipped
  ∷ ∀ r i o x a
  . (x → Run (RS.Client i o r) a)
  → (i → Run (RS.Server i o r) a)
  → (x → Run r a)
composeFlipped = flip compose

-- | Connects a Consumer to a Producer.
feed ∷ ∀ r x a. Run (RS.Consumer x r) a → Run (RS.Producer x r) a → Run r a
feed ra rb = chain (const rb) ra

-- | Connects a Producer to a Consumer.
draw ∷ ∀ r x a. Run (RS.Producer x r) a → Run (RS.Consumer x r) a → Run r a
draw rb ra = chain (const rb) ra

-- | Connects a Consumer to an effect which fulfills the request.
into ∷ ∀ r x a. Run (RS.Consumer x r) a → Run r x → Run r a
into ra rb = for ra (const rb)

-- | Connect an effect to a Consumer, fulfilling the request.
from ∷ ∀ r x a. Run r x → Run (RS.Consumer x r) a → Run r a
from ra rb = for rb (const ra)

-- | Consumes all values with effects.
consume ∷ ∀ r x a b. (x → Run (RS.Consumer x r) a) → Run (RS.Consumer x r) b
consume f = go
  where
  go = do
    _ ← f =<< RS.await
    go
