module Control.Effect.Coroutine
  ( Coroutine(..)
  , yield
  , Status(..)
  , runCoroutine
  ) where

import Control.Effect.Base

data Coroutine i o :: Effect where
  Yield :: o -> Coroutine i o m i

yield :: Coroutine i o :< effs => o -> Eff effs i
yield = send . Yield

data Status effs i o a
  = Done a
  | Yielded o !(i -> Eff (Coroutine i o ': effs) a)

runCoroutine :: Eff (Coroutine i o ': effs) a -> Eff effs (Status effs i o a)
runCoroutine = handle (pure . Done) \case
  Yield a -> control0 \k -> pure $! Yielded a k
