{-# LANGUAGE OverloadedStrings #-}
module Editor.CodeEdit.ExpressionEdit.PiEdit(make) where

import Control.Monad (liftM)
import Editor.CodeEdit.ExpressionEdit.ExpressionGui (ExpressionGui)
import Editor.CodeEdit.ExpressionEdit.ExpressionGui.Monad (ExprGuiM)
import Editor.MonadF (MonadF)
import qualified Editor.BottleWidgets as BWidgets
import qualified Editor.CodeEdit.ExpressionEdit.ExpressionGui as ExpressionGui
import qualified Editor.CodeEdit.ExpressionEdit.ExpressionGui.Monad as ExprGuiM
import qualified Editor.CodeEdit.ExpressionEdit.FuncEdit as FuncEdit
import qualified Editor.CodeEdit.Parens as Parens
import qualified Editor.CodeEdit.Sugar as Sugar
import qualified Editor.Config as Config
import qualified Editor.WidgetEnvT as WE
import qualified Editor.WidgetIds as WidgetIds
import qualified Graphics.UI.Bottle.Widget as Widget

make
  :: MonadF m
  => Sugar.HasParens
  -> Sugar.Pi m (Sugar.Expression m)
  -> Widget.Id
  -> ExprGuiM m (ExpressionGui m)
make hasParens (Sugar.Pi param resultType) =
  ExpressionGui.wrapParenify hasParens Parens.addHighlightedTextParens $ \myId ->
  ExprGuiM.assignCursor myId typeId $ do
    -- We allocate a name in the resultTypeEdit context even if we end
    -- up non-dependent and don't have a name. This is the only way to
    -- do it (until 2-pass gui gen), but it is also desirable: when
    -- holes spring up, we don't get all the names shuffled
    -- confusingly.
    (name, (resultTypeEdit, usedVars)) <-
      ExprGuiM.withParamName paramGuid $ \name ->
      liftM ((,) name) . ExprGuiM.usedVariables $
      FuncEdit.makeResultEdit [paramId] resultType
    let
      paramUsed = paramGuid `elem` usedVars
      redirectCursor cursor
        | paramUsed = cursor
        | otherwise =
          case Widget.subId paramId cursor of
          Nothing -> cursor
          Just _ -> typeId
    ExprGuiM.atEnv (WE.atEnvCursor redirectCursor) $ do
      paramTypeEdit <- ExprGuiM.makeSubexpresion $ Sugar.fpType param
      paramEdit <-
        if paramUsed
        then do
          paramNameEdit <- FuncEdit.makeParamNameEdit name paramGuid
          colonLabel <- ExprGuiM.widgetEnv . BWidgets.makeLabel ":" $ Widget.toAnimId paramId
          return $ ExpressionGui.hbox
            [ ExpressionGui.fromValueWidget paramNameEdit
            , ExpressionGui.fromValueWidget colonLabel
            , paramTypeEdit
            ]
        else return paramTypeEdit
      rightArrowLabel <-
        ExprGuiM.atEnv (WE.setTextSizeColor Config.rightArrowTextSize Config.rightArrowColor) .
        ExprGuiM.widgetEnv . BWidgets.makeLabel "→" $ Widget.toAnimId myId
      return $ ExpressionGui.hboxSpaced
        [paramEdit, ExpressionGui.fromValueWidget rightArrowLabel, resultTypeEdit]
  where
    paramGuid = Sugar.fpGuid param
    paramId = WidgetIds.fromGuid paramGuid
    typeId =
      WidgetIds.fromGuid . Sugar.rGuid . Sugar.fpType $
      param
