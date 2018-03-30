{-# LANGUAGE LambdaCase #-}

module Nix.Lint (checkExpr) where

import           Control.Monad
import           Control.Monad.Trans.Reader
import           Data.Fix
import qualified Data.Map.Lazy as Map
import           Nix.Atoms
import           Nix.Builtins
import           Nix.Eval
import           Nix.Expr
import           Nix.Monad
import           Nix.Scope

nullVal :: MonadNix m => m (NValue m)
nullVal = return $ NVConstant NNull

-- | Evaluate an nix expression, with a given ValueSet as environment
checkExpr :: MonadNix m => NExpr -> m ()
checkExpr = cata check

check :: MonadNix m => NExprF (m ()) -> m ()

check (NSym var) = lookupVar var >>= \case
    Nothing -> error $ "Undefined variable: " ++ show var
    Just _ -> return ()

check (NSet binds) =
    void $ evalBinds True False (fmap (fmap (const nullVal)) binds)

check (NRecSet binds) =
    void $ evalBinds True True (fmap (fmap (const nullVal)) binds)

check (NLet binds e) =
    (`pushScope` e) . newScope
        =<< evalBinds True True (fmap (fmap (const nullVal)) binds)

-- check (NWith _scope e) = do
--     env <- currentScope
--     pushScope env e

check (NAbs a b) = do
    nv <- buildThunk nullVal
    case a of
        Param name ->
            pushScope (newScope (Map.singleton name nv)) b
        ParamSet (FixedParamSet s) Nothing ->
            pushScope (newScope (nv <$ s)) b
        ParamSet (FixedParamSet s) (Just m) ->
            pushScope (newScope (Map.insert m nv (nv <$ s))) b
        ParamSet (VariadicParamSet s) Nothing ->
            pushScope (newScope (nv <$ s)) b
        ParamSet (VariadicParamSet s) (Just m) ->
            pushScope (newScope (Map.insert m nv (nv <$ s))) b

-- In order to check some of the other operations properly, we'd need static
-- typing
check _ = return ()
