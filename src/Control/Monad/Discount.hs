{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE MonoLocalBinds      #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeOperators       #-}
{-# LANGUAGE UnicodeSyntax       #-}

module Control.Monad.Discount
  ( module Control.Monad.Discount
  , module Control.Monad.Discount.Effect
  , module Control.Monad.Discount.Lift
  , Member
  , decomp
  , prj
  ) where

import Data.Functor.Identity
import Data.Tuple
import Data.OpenUnion
import Control.Monad.Discount.Effect
import Control.Monad (join)
import Control.Monad.Discount.Lift
import qualified Control.Monad.Trans.State.Strict as S
import Control.Monad.Trans.State.Strict (StateT)

type Eff r = Freer (Union r)

newtype Freer f a = Freer
  { runFreer
        :: ∀ m
         . Monad m
        => (∀ x. f (Freer f) x -> m x)
        -> m a
  }

usingFreer :: Monad m => (∀ x. f (Freer f) x -> m x) -> Freer f a -> m a
usingFreer k m = runFreer m k
{-# INLINE usingFreer #-}


instance Functor (Freer f) where
  fmap f (Freer m) = Freer $ \k -> fmap f $ m k
  {-# INLINE fmap #-}


instance Applicative (Freer f) where
  pure a = Freer $ const $ pure a
  {-# INLINE pure #-}

  Freer f <*> Freer a = Freer $ \k -> f k <*> a k
  {-# INLINE (<*>) #-}


instance Monad (Freer f) where
  return = pure
  {-# INLINE return #-}

  Freer ma >>= f = Freer $ \k -> do
    z <- ma k
    runFreer (f z) k
  {-# INLINE (>>=) #-}

liftEff :: f (Freer f) a -> Freer f a
liftEff u = Freer $ \k -> k u
{-# INLINE liftEff #-}

hoistEff :: (∀ x. f (Freer f) x -> g (Freer g) x) -> Freer f a -> Freer g a
hoistEff nat (Freer m) = Freer $ \k -> m $ \u -> k $ nat u
{-# INLINE hoistEff #-}


send :: Member e r => e (Eff r) a -> Eff r a
send = liftEff . inj
{-# INLINE send #-}


sendM :: Member (Lift m) r => m a -> Eff r a
sendM = send . Lift
{-# INLINE sendM #-}


run :: Eff '[] a -> a
run (Freer m) = runIdentity $ m $ \u -> error "absurd"
{-# INLINE run #-}


runM :: Monad m => Eff '[Lift m] a -> m a
runM (Freer m) = m $ \u -> error "absurd"
{-# INLINE runM #-}


interpret
    :: Effect e
    => (∀ x. e (Eff (e ': r)) x -> Eff r x)
    -> Eff (e ': r) a
    -> Eff r a
interpret f (Freer m) = m $ \u ->
  case decomp u of
    Left  x -> liftEff $ hoist (interpret f) x
    Right y -> f y
{-# INLINE interpret #-}


stateful
    :: forall e s r a
     . Effect e
    => (∀ x. e (StateT s (Eff r)) x -> StateT s (Eff r) x)
    -> s
    -> Eff (e ': r) a
    -> Eff r (s, a)
stateful f s = \e -> fmap swap $ S.runStateT (go e) s
  where
    go :: Eff (e ': r) x -> StateT s (Eff r) x
    go (Freer m) = m $ \u ->
      case decomp u of
        Left x -> S.StateT $ \s' ->
          liftEff . fmap swap
                  . weave (s', ()) (uncurry $ stateful f)
                  $ x
        Right y -> f $ hoist go y
{-# INLINE stateful #-}


reinterpret
    :: Effect f
    => (∀ x. f (Eff (g ': r)) x -> Eff (g ': r) x)
    -> Eff (f ': r) a
    -> Eff (g ': r) a
reinterpret f (Freer m) = m $ \u ->
  case decomp u of
    Left  x -> liftEff $ weaken $ hoist (reinterpret f) x
    Right y -> f $ hoist (reinterpret f) $ y
{-# INLINE reinterpret #-}

