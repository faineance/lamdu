{-# LANGUAGE NoImplicitPrelude, OverloadedStrings #-}
module Lamdu.GUI.ExpressionEdit.ListEdit
    ( make
    ) where

import           Prelude.Compat

import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Lens.Tuple
import           Control.MonadA (MonadA)
import           Data.Monoid ((<>))
import qualified Graphics.UI.Bottle.EventMap as E
import qualified Graphics.UI.Bottle.Widget as Widget
import qualified Lamdu.Config as Config
import qualified Lamdu.GUI.ExpressionEdit.EventMap as ExprEventMap
import           Lamdu.GUI.ExpressionGui (ExpressionGui)
import qualified Lamdu.GUI.ExpressionGui as ExpressionGui
import           Lamdu.GUI.ExpressionGui.Monad (ExprGuiM, holePickersAction)
import qualified Lamdu.GUI.ExpressionGui.Monad as ExprGuiM
import qualified Lamdu.GUI.ExpressionGui.Types as ExprGuiT
import qualified Lamdu.GUI.WidgetIds as WidgetIds
import qualified Lamdu.Sugar.Types as Sugar

make ::
    MonadA m =>
    Sugar.List m (ExprGuiT.SugarExpr m) ->
    Sugar.Payload m ExprGuiT.Payload ->
    ExprGuiM m (ExpressionGui m)
make list pl =
    ExpressionGui.stdWrapParentExpr pl $ \myId ->
    ExprGuiM.assignCursor myId cursorDest $
    do
        config <- ExprGuiM.readConfig
        bracketOpenLabel <-
            ExpressionGui.grammarLabel "[" (Widget.toAnimId bracketsId)
            >>= ExpressionGui.makeFocusableView firstBracketId
            <&>
                ExpressionGui.egWidget %~
                Widget.weakerEvents
                (actionEventMap (Config.listAddItemKeys config) "Add First Item" Sugar.addFirstItem)
        bracketCloseLabel <- ExpressionGui.grammarLabel "]" (Widget.toAnimId bracketsId)
        case ExpressionGui.listWithDelDests firstBracketId firstBracketId itemId (list ^. Sugar.listValues) of
            [] ->
                return $ ExpressionGui.hbox [bracketOpenLabel, bracketCloseLabel]
            firstValue : nextValues ->
                do
                    (_, firstEdit) <- makeItem firstValue
                    nextEdits <- mapM makeItem nextValues

                    jumpHolesEventMap <-
                        firstValue ^. _3 . Sugar.liExpr
                        & ExprGuiT.nextHolesBefore
                        & ExprEventMap.jumpHolesEventMap
                    let nilDeleteEventMap =
                            actionEventMap (Config.delKeys config) "Replace nil with hole" Sugar.replaceNil
                        addLastEventMap =
                            list ^? Sugar.listValues . lastLens . Sugar.liActions . Sugar.itemAddNext
                            & maybe mempty
                            ( Widget.keysEventMapMovesCursor (Config.listAddItemKeys config)
                                (E.Doc ["Edit", "List", "Add Last Item"])
                            . fmap WidgetIds.fromEntityId
                            )
                        closerEventMap = mappend nilDeleteEventMap addLastEventMap
                        closeBracketId = Widget.joinId myId ["close-bracket"]
                    bracketClose <-
                        ExpressionGui.makeFocusableView closeBracketId bracketCloseLabel
                        <&> ExpressionGui.egWidget %~ Widget.weakerEvents closerEventMap
                    return . ExpressionGui.hbox $ concat
                        [ [ bracketOpenLabel
                                & ExpressionGui.egWidget %~ Widget.weakerEvents jumpHolesEventMap
                            , firstEdit
                            ]
                        , nextEdits >>= pairToList
                        , [ bracketClose ]
                        ]
    where
        bracketsId = list ^. Sugar.listNilEntityId & WidgetIds.fromEntityId
        pairToList (x, y) = [x, y]
        itemId = WidgetIds.fromExprPayload . (^. Sugar.liExpr . Sugar.rPayload)
        actionEventMap keys doc actSelect =
            list ^. Sugar.listActions
            & actSelect
            <&> WidgetIds.fromEntityId
            & Widget.keysEventMapMovesCursor keys (E.Doc ["Edit", "List", doc])
        firstBracketId = mappend (Widget.Id ["first bracket"]) bracketsId
        cursorDest =
            list ^? Sugar.listValues . Lens.traversed
            & maybe firstBracketId itemId

makeItem ::
    MonadA m =>
    (Widget.Id, Widget.Id, Sugar.ListItem m (ExprGuiT.SugarExpr m)) ->
    ExprGuiM m (ExpressionGui m, ExpressionGui m)
makeItem (_, nextId, item) =
    do
        config <- ExprGuiM.readConfig
        let mkItemEventMap resultPickers Sugar.ListItemActions
                { Sugar._itemAddNext = addItem
                , Sugar._itemDelete = delItem
                } = mconcat
                    [ E.keyPresses (Config.listAddItemKeys config) (doc resultPickers) $
                      mappend
                      <$> holePickersAction resultPickers
                      <*> (Widget.eventResultFromCursor . WidgetIds.fromEntityId <$> addItem)
                    , Widget.keysEventMapMovesCursor (Config.delKeys config)
                      (E.Doc ["Edit", "List", "Delete Item"]) $
                      nextId <$ delItem
                    ]
        (pair, resultPickers) <-
          ExprGuiM.listenResultPickers $
          Lens.sequenceOf Lens.both
          ( ExpressionGui.grammarLabel ", " (Widget.toAnimId itemWidgetId <> [","])
          , ExprGuiM.makeSubexpression (const 0) itemExpr
          )
        return $ pair
          & _2 . ExpressionGui.egWidget %~
          Widget.weakerEvents (mkItemEventMap resultPickers (item ^. Sugar.liActions))
    where
        itemExpr = item ^. Sugar.liExpr
        itemWidgetId = WidgetIds.fromExprPayload $ itemExpr ^. Sugar.rPayload
        doc [] = E.Doc ["Edit", "List", "Add Next Item"]
        doc _ = E.Doc ["Edit", "List", "Pick Result and Add Next Item"]

lastLens :: Lens.Traversal' [a] a
lastLens = Lens.taking 1 . Lens.backwards $ Lens.traversed
