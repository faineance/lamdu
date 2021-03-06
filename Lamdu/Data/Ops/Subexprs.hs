{-# LANGUAGE RankNTypes #-}
module Lamdu.Data.Ops.Subexprs
    ( onMatchingSubexprs
    , onMatchingSubexprsWithPath
    , toHole
    , onGetVars
    , getVarsToHole
    ) where


import qualified Control.Lens as Lens
import           Control.Monad (void)
import           Control.MonadA (MonadA)
import           Data.Store.Transaction (Transaction)
import qualified Lamdu.Data.Ops as DataOps
import           Lamdu.Expr.IRef (ValIProperty)
import qualified Lamdu.Expr.Lens as ExprLens
import           Lamdu.Expr.Val (Val(..))
import qualified Lamdu.Expr.Val as V

type T = Transaction

onMatchingSubexprs ::
    MonadA m => (a -> m ()) -> Lens.Fold (Val ()) b -> Val a -> m ()
onMatchingSubexprs action predicate =
    Lens.itraverseOf_ (ExprLens.subExprPayloads . Lens.ifiltered (\i _ -> Lens.has predicate i))
    (const action)

onMatchingSubexprsWithPath ::
    MonadA m => (a -> m ()) -> ([Val ()] -> Bool) -> Val a -> m ()
onMatchingSubexprsWithPath action predicate =
    Lens.itraverseOf_ (ExprLens.payloadsIndexedByPath . Lens.ifiltered (\i _ -> predicate i))
    (const action)

toHole :: MonadA m => ValIProperty m -> T m ()
toHole = void . DataOps.setToHole

onGetVars ::
    MonadA m => (ValIProperty m -> T m ()) -> V.Var ->
    Val (ValIProperty m) -> T m ()
onGetVars f var =
    onMatchingSubexprs f (ExprLens.valVar . Lens.only var)

getVarsToHole :: MonadA m => V.Var -> Val (ValIProperty m) -> T m ()
getVarsToHole = onGetVars toHole
