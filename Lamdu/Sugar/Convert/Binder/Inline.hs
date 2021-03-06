{-# LANGUAGE NoImplicitPrelude #-}

module Lamdu.Sugar.Convert.Binder.Inline
    ( inlineLet
    ) where

import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Lens.Tuple
import           Control.MonadA (MonadA)
import qualified Data.Store.Property as Property
import           Data.Store.Transaction (Transaction)
import           Lamdu.Expr.IRef (ValIProperty, ValI)
import qualified Lamdu.Expr.IRef as ExprIRef
import           Lamdu.Expr.Val (Val(..))
import qualified Lamdu.Expr.Val as V
import           Lamdu.Sugar.Convert.Binder.Redex (Redex(..))
import qualified Lamdu.Sugar.Internal.EntityId as EntityId
import           Lamdu.Sugar.Types

import           Prelude.Compat

insideRedexes :: (Val a -> Val a) -> Val a -> Val a
insideRedexes f (Val a (V.BApp (V.Apply (V.Val l (V.BAbs lam)) arg))) =
    lam
    & V.lamResult %~ insideRedexes f
    & V.BAbs & Val l
    & flip V.Apply arg & V.BApp & Val a
insideRedexes f expr = f expr

redexes :: Val a -> ([(V.Var, Val a)], Val a)
redexes (Val _ (V.BApp (V.Apply (V.Val _ (V.BAbs lam)) arg))) =
    redexes (lam ^. V.lamResult)
    & _1 %~ (:) (lam ^. V.lamParamId, arg)
redexes v = ([], v)

inlineLetH :: V.Var -> Val (Maybe a) -> Val (Maybe a) -> Val (Maybe a)
inlineLetH var arg body =
    foldr wrapWithRedex newBody innerRedexes
    where
        (innerRedexes, newBody) = go body
        go (Val stored b) =
            case (b, arg ^. V.body) of
            (V.BLeaf (V.LVar v), _) | v == var -> redexes arg
            (V.BApp (V.Apply (Val _ (V.BLeaf (V.LVar v))) a)
              , V.BAbs (V.Lam param lamBody))
              | v == var ->
                redexes lamBody
                & _1 %~ (:) (param, a)
            _ ->
                ( r ^.. Lens.traverse . _1 . Lens.traverse
                , r <&> (^. _2) & Val stored
                )
                where
                    r = b <&> go
        wrapWithRedex (v, val) b =
            V.Apply (Val Nothing (V.BAbs (V.Lam v b))) val
            & V.BApp
            & Val Nothing

cursorDest :: Val a -> a
cursorDest val =
    case val ^. V.body of
    V.BAbs lam -> lam ^. V.lamResult
    _ -> val
    & redexes
    & (^. _2 . V.payload)

inlineLet ::
    MonadA m => ValIProperty m -> Redex (ValI m) -> Transaction m EntityId
inlineLet topLevelProp redex =
    redexLam redex ^. V.lamResult
    <&> Just
    & insideRedexes (inlineLetH (redexLam redex ^. V.lamParamId) (redexArg redex <&> Just))
    <&> flip (,) ()
    & ExprIRef.writeValWithStoredSubexpressions
    <&> (^. V.payload . _1)
    >>= Property.set topLevelProp
    <&> const (cursorDest (redexArg redex <&> EntityId.ofValI))
