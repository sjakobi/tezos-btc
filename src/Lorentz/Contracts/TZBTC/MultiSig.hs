{- SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-Proprietary
 -}
{-# LANGUAGE RebindableSyntax #-}
{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}

module Lorentz.Contracts.TZBTC.MultiSig
  ( ParamAction(..)
  , ParamPayload
  , Parameter(..)
  , Storage
  , contractToLambda
  , mkStorage
  )
where

import Prelude hiding (drop, toStrict, (>>))

import Lorentz

import Michelson.Text (mkMTextUnsafe)

import Lorentz.Contracts.TZBTC as TZBTC hiding (Parameter, Storage)
import qualified Lorentz.Contracts.TZBTC as TZBTC (Parameter)

data Parameter
  = Default ()
  | ParameterMain ParamMain
  deriving stock Generic
  deriving anyclass IsoValue

type Counter = Natural
type Threshold = Natural

type Storage
  = (Counter, (Threshold, [PublicKey]))

type ParamMain
  = (ParamPayload, ParamSignatures)

type ParamPayload
  = (Counter, ParamAction)

data ParamAction
  = ParamLambda (Lambda () [Operation])
  | ParamManage ParamManage
  deriving stock Generic
  deriving anyclass IsoValue

type ParamManage
  = (Natural, [PublicKey])

type ParamSignatures = [Maybe Signature]

contractToLambda
  :: forall a. Address -> SafeParameter a -> Lambda () [Operation]
contractToLambda addr param = do
  drop
  push addr
  contract
  if IsNone
  then do push (mkMTextUnsafe "Invalid contract type"); failWith
  else do
    push param
    wrap_ @(TZBTC.Parameter a) #cSafeEntrypoints
    dip $ push $ toMutez 0
    transferTokens
    dip nil
    cons

mkStorage :: Natural -> Natural -> [PublicKey] -> Storage
mkStorage counter threshold keys_ = (counter, (threshold, keys_))
