module Run.Streaming.Prelude
  ( forever
  , cat
  , map
  , filter
  , each
  , concat
  , concatMap
  , take
  , takeWhile
  , drop
  , dropWhile
  , scan
  , zipWith
  , zip
  , succ
  , null
  , head
  , last
  , all
  , any
  , and
  , or
  , elem
  , find
  , index
  , findIndex
  , fold
  , fold'
  , foldM
  , foldM'
  , length
  , sum
  , product
  , minimum
  , maximum
  , unfold
  , module Exports
  ) where

import Prelude hiding (map)
import Prelude as P
import Data.Either (Either(..))
import Data.Enum as E
import Data.Foldable as F
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Run (Run)
import Run.Streaming (Producer, Transformer, yield, await)
import Run.Streaming as RS
import Run.Streaming.Pull as Pull

-- Reexports
import Run.Streaming (Consumer, Producer, Transformer, Server, Client, Pipe, respond, request, yield, await) as Exports
import Run.Streaming.Pull (feed, into, consume) as Exports
import Run.Streaming.Push (for, traverse, produce) as Exports

-- | Loop an effect forever.
forever ∷ ∀ r a b. Run r a → Run r b
forever go = go >>= \_ → forever go

-- | Forwards incoming values downstream.
cat ∷ ∀ r x a. Run (Transformer x x r) a
cat = Pull.identity unit

-- | Adapts incoming values.
map ∷ ∀ r i o a. (i → o) → Run (Transformer i o r) a
map f = forever (await >>= f >>> yield)

-- | Filters incoming values based on a predicate.
filter ∷ ∀ r x a. (x → Boolean) → Run (Transformer x x r) a
filter f = forever do
  x ← await
  when (f x) do
    yield x

-- | Turns an arbitrary Foldable into a Producer.
each ∷ ∀ r x f. F.Foldable f ⇒ f x → Run (Producer x r) Unit
each = F.traverse_ yield

-- | Forwards all individual values in an incoming Foldable downstream.
concat ∷ ∀ r x f a. F.Foldable f ⇒ Run (Transformer (f x) x r) a
concat = forever (await >>= each)

-- | Composition of `map` followed by `concat`.
concatMap ∷ ∀ r i o f a. F.Foldable f ⇒ (i → f o) → Run (Transformer i o r) a
concatMap f = forever (await >>= f >>> each)

-- | Takes a specified number of values from the head of the stream, terminating
-- | upon completion.
take ∷ ∀ r x. Int → Run (Transformer x x r) Unit
take n =
  when (n > 0) do
    await >>= yield
    take (n - 1)

-- | Takes values from the head of the stream as determined by the provided
-- | predicate. Terminates when the predicate fails.
takeWhile ∷ ∀ r x. (x → Boolean) → Run (Transformer x x r) Unit
takeWhile f = go
  where
  go = do
    x ← await
    when (f x) do
      yield x
      go

-- | Drops a specified number of values from the head of the stream.
drop ∷ ∀ r x a. Int → Run (Transformer x x r) a
drop n =
  if n <= 0
    then cat
    else do
      _ ← await
      drop (n - 1)

-- | Drops values from the head of the stream as determined by the provided
-- | predicate. Forwards all subsequent values.
dropWhile ∷ ∀ r x a. (x → Boolean) → Run (Transformer x x r) a
dropWhile f = go
  where
  go = do
    x ← await
    if f x
      then do
        _ ← await
        go
      else do
        yield x
        cat

-- | Folds over the input, yielding each step.
scan ∷ ∀ r i o x a. (x → i → x) → x → (x → o) → Run (Transformer i o r) a
scan step init done = go init
  where
  go x = do
    yield (done x)
    i ← await
    go (step x i)

-- | Joins two Producers into one.
zipWith
  ∷ ∀ r i j k a
  . (i → j → k)
  → Run (Producer i (Producer k r)) a
  → Run (Producer j (Producer k r)) a
  → Run (Producer k r) a
zipWith f = \ra rb → go (RS.runYield ra) (RS.runYield rb)
  where
  go ra rb = ra >>= case _ of
    RS.Next o k → rb >>= case _ of
      RS.Next p j → do
        yield (f o p)
        go (k unit) (j unit)
      RS.Done a → pure a
    RS.Done a → pure a

-- | Joins two Producers with a Tuple.
zip
  ∷ ∀ r i j a
  . Run (Producer i (Producer (Tuple i j) r)) a
  → Run (Producer j (Producer (Tuple i j) r)) a
  → Run (Producer (Tuple i j) r) a
zip = zipWith Tuple

-- | Yields successive values until exhausted.
succ ∷ ∀ r x. E.Enum x ⇒ x → Run (Producer x r) Unit
succ n = do
  yield n
  F.for_ (E.succ n) succ

-- | Checks whether a Producer is empty.
null ∷ ∀ r x. Run (Producer x r) Unit → Run r Boolean
null = P.map go <<< RS.runYield
  where
  go = case _ of
    RS.Next _ _ → false
    RS.Done _ → true

-- | Returns the first value of a Producer.
head ∷ ∀ r x. Run (Producer x r) Unit → Run r (Maybe x)
head = P.map go <<< RS.runYield
  where
  go = case _ of
    RS.Next x _ → Just x
    RS.Done _ → Nothing

-- | Returns the last value of a Producer.
last ∷ ∀ r x. Run (Producer x r) Unit → Run r (Maybe x)
last = go Nothing <=< RS.runYield
  where
  go acc = case _ of
    RS.Next x k → k unit >>= go (Just x)
    RS.Done _ → pure acc

-- | Checks if all yielded values from a Producer satisfy the predicate. Stops
-- | as soon as one fails.
all ∷ ∀ r x. (x → Boolean) → Run (Producer x (Producer x r)) Unit → Run r Boolean
all f = null <<< Pull.feed (filter (not f))

-- | Checks if any yielded values from a Producer satisfy the predicate. Stops as
-- | soon as one passes.
any ∷ ∀ r x. (x → Boolean) → Run (Producer x (Producer x r)) Unit → Run r Boolean
any f = P.map not <<< null <<< Pull.feed (filter f)

-- | Checks if all yielded values are true.
and ∷ ∀ r. Run (Producer Boolean (Producer Boolean r)) Unit → Run r Boolean
and = all id

-- | Checks if any yielded values are true.
or ∷ ∀ r. Run (Producer Boolean (Producer Boolean r)) Unit → Run r Boolean
or = any id

-- | Checks if a value occurs in the stream.
elem ∷ ∀ r x. Eq x ⇒ x → Run (Producer x (Producer x r)) Unit → Run r Boolean
elem = any <<< eq

-- | Finds the first value that satisfies the provided predicate.
find ∷ ∀ r x. (x → Boolean) → Run (Producer x (Producer x r)) Unit → Run r (Maybe x)
find f = head <<< Pull.feed (filter f)

-- | Finds the value at the given offset in the stream.
index ∷ ∀ r x. Int → Run (Producer x (Producer x r)) Unit → Run r (Maybe x)
index ix = head <<< Pull.feed (drop ix)

-- | Finds the index for the first value that satisfies the provided predicate.
findIndex
  ∷ ∀ r x
  . (x → Boolean)
  → Run
      (Producer x
        (Producer (Tuple Int x)
          (Producer (Tuple Int x) r)))
      Unit
  → Run r (Maybe (Tuple Int x))
findIndex f = find (f <<< snd) <<< zip (succ 0)

-- | Folds over a Producer, returning the summary.
fold
  ∷ ∀ r i o x
  . (x → i → x)
  → x
  → (x → o)
  → Run (Producer i r) Unit
  → Run r o
fold step init done ra =
  fst <$> fold' step init done ra

-- | Folds over a Producer, but also returns the final value of the stream.
fold'
  ∷ ∀ r i o x a
  . (x → i → x)
  → x
  → (x → o)
  → Run (Producer i r) a
  → Run r (Tuple o a)
fold' step init done ra = RS.runYield ra >>= go init
  where
  go acc = case _ of
    RS.Next o k → k unit >>= go (step acc o)
    RS.Done a → pure (Tuple (done acc) a)

-- | Folds over a Producer with `Run` effects.
foldM
  ∷ ∀ r i o x
  . (x → i → Run r x)
  → Run r x
  → (x → Run r o)
  → Run (Producer i r) Unit
  → Run r o
foldM step init done ra =
  fst <$> foldM' step init done ra

-- | Folds over a Producer with `Run` effects, but also returns the final value
-- | of the stream.
foldM'
  ∷ ∀ r i o x a
  . (x → i → Run r x)
  → Run r x
  → (x → Run r o)
  → Run (Producer i r) a
  → Run r (Tuple o a)
foldM' step init done ra = do
  acc ← init
  RS.runYield ra >>= go acc
  where
  go acc = case _ of
    RS.Next o k → do
      acc' ← step acc o
      k unit >>= go acc'
    RS.Done a → do
      o ← done acc
      pure (Tuple o a)

-- | Returns the number of values yielded by a Producer.
length ∷ ∀ r x. Run (Producer x r) Unit → Run r Int
length = fold (const <<< add 1) 0 id

-- | Returns the sum of values yielded by a Producer.
sum ∷ ∀ r x. Semiring x ⇒ Run (Producer x r) Unit → Run r x
sum = fold (+) zero id

-- | Returns the product of values yielded by a Producer.
product ∷ ∀ r x. Semiring x ⇒ Run (Producer x r) Unit → Run r x
product = fold (*) one id

-- | Returns the minimum value yielded by a Producer.
minimum ∷ ∀ r x. Ord x ⇒ Run (Producer x r) Unit → Run r (Maybe x)
minimum = fold go Nothing id
  where
  go x y = Just case x of
    Nothing → y
    Just x' → min x' y

-- | Returns the maximum value yielded by a Producer.
maximum ∷ ∀ r x. Ord x ⇒ Run (Producer x r) Unit → Run r (Maybe x)
maximum = fold go Nothing id
  where
  go x y = Just case x of
    Nothing → y
    Just x' → max x' y

-- | Unfold into a Producer given a seed.
unfold ∷ ∀ r x o a. (x → Either a (Tuple o x)) → x → Run (Producer o r) a
unfold f = go
  where
  go x = case f x of
    Left a → pure a
    Right (Tuple o x') → do
      yield o
      go x'
