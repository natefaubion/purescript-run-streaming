-- | This module defines primitives for bidirectional streams analagous to
-- | the Haskell `Pipes` library. Namely, streams may be either push or pull
-- | and can propagate information both upstream and downstream.

module Run.Streaming
  ( Step(..)
  , STEP
  , YIELD
  , AWAIT
  , REQUEST
  , RESPOND
  , _yield
  , _await
  , yield
  , await
  , request
  , respond
  , Resume(..)
  , Producer
  , Consumer
  , Transformer
  , Client
  , Server
  , Pipe
  , runStep
  , runYield
  , runAwait
  , interleave
  , substitute
  ) where

import Prelude

import Data.Profunctor (class Profunctor, dimap)
import Data.Symbol (class IsSymbol)
import Prim.Row (class Cons)
import Run (Run)
import Run as Run
import Type.Prelude (Proxy(..))

data Step i o a = Step o (i → a)

derive instance functorStep ∷ Functor (Step i o)

type STEP i o = Step i o

type YIELD a = STEP Unit a

type AWAIT a = STEP a Unit

type REQUEST req res = STEP res req

type RESPOND req res = STEP req res

_yield ∷ Proxy "yield"
_yield = Proxy

_await ∷ Proxy "await"
_await = Proxy

liftYield ∷ ∀ req res r. Step res req ~> Run (yield ∷ STEP res req | r)
liftYield = Run.lift _yield

liftAwait ∷ ∀ req res r. Step req res ~> Run (await ∷ STEP req res | r)
liftAwait = Run.lift _await

-- | Yields a response and waits for a request.
respond ∷ ∀ req res r. res → Run (Server req res r) req
respond res = liftYield (Step res identity)

-- | Issues a request and awaits a response.
request ∷ ∀ req res r. req → Run (Client req res r) res
request req = liftAwait (Step req identity)

-- | Yields a value to be consumed downstream.
yield ∷ ∀ o r. o → Run (Producer o r) Unit
yield = respond

-- | Awaits a value upstream.
await ∷ ∀ i r. Run (Consumer i r) i
await = request unit

-- | Producers yield values of type `o` using effects `r`.
type Producer o r = (yield ∷ YIELD o | r)

-- | Consumers await values of type `i` using effects `r`.
type Consumer i r = (await ∷ AWAIT i | r)

-- | Transformers await values `i` and yield values `o` using effects `r`.
type Transformer i o r = (await ∷ AWAIT i, yield ∷ YIELD o | r)

-- | Servers reply to requests `req` with responses `res` using effects `r`.
type Server req res r = (yield ∷ RESPOND req res | r)

-- | Clients issue requests `req` and await responses `res` using effects `r`.
type Client req res r = (await ∷ REQUEST req res | r)

-- | A full bidirectional Pipe acts as an upstream Client and a downstream Server.
type Pipe req res req' res' r = (await ∷ REQUEST req res, yield ∷ RESPOND req' res' | r)

data Resume r a i o
  = Next o (i → Run r (Resume r a i o))
  | Done a

instance functorResume ∷ Functor (Resume r a i) where
  map f = case _ of
    Next o k → Next (f o) (map (map f) <$> k)
    Done a   → Done a

instance profunctorResume ∷ Profunctor (Resume r a) where
  dimap f g = case _ of
    Next o k → Next (g o) (dimap f (map (dimap f g)) k)
    Done a   → Done a

runStep
  ∷ ∀ sym i o r1 r2 a
  . Cons sym (Step i o) r1 r2
  ⇒ IsSymbol sym
  ⇒ Proxy sym
  → Run r2 a
  → Run r1 (Resume r1 a i o)
runStep p = loop
  where
  loop = Run.resume
    (Run.on p
      (\(Step o k) → pure (Next o (k >>> loop)))
      (\a → Run.send a >>= loop))
    (pure <<< Done)

runYield ∷ ∀ r a i o. Run (Server i o r) a → Run r (Resume r a i o)
runYield = runStep _yield

runAwait ∷ ∀ r a i o. Run (Client i o r) a → Run r (Resume r a o i)
runAwait = runStep _await

-- | Subsitutes the outputs of the second argument with the continuation of the
-- | first argument, and vice versa, interleaving the two.
interleave ∷ ∀ r a i o. (o → Run r (Resume r a o i)) → Resume r a i o → Run r a
interleave k = case _ of
  Next o next → k o >>= interleave next
  Done a → pure a

-- | Substitutes the outputs of the second argument with the effects of the
-- | first argument, feeding the result back in to the stream.
substitute ∷ ∀ r a i o. (o → Run r i) → Resume r a i o → Run r a
substitute k = case _ of
  Next o next → k o >>= next >>= substitute k
  Done a → pure a
