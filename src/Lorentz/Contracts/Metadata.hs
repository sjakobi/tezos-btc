{- SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-MIT-BitcoinSuisse
 -}
{-# LANGUAGE RebindableSyntax #-}
{-# OPTIONS_GHC -fno-warn-unused-do-bind -Wno-orphans #-}

module Lorentz.Contracts.Metadata
  ( TokenId
  , TokenMetadata(..)
  , singleTokenResolveMetadata
  , singleTokenTokenId
  ) where

import Lorentz

import Lorentz.Contracts.Spec.FA2Interface (TokenId, TokenMetadata(..), theTokenId)

-- | The `TokenId` of a token in a single-token contract is @0@
singleTokenTokenId :: TokenId
singleTokenTokenId = theTokenId

-- | Assert that each `TokenId` is @0@ (`singleTokenTokenId`) and replace each one in the input
-- list with the given `TokenMetadata`
singleTokenResolveMetadata ::
     [TokenId] & TokenMetadata & s :-> [TokenMetadata] & s
singleTokenResolveMetadata = do
  map $ do
    push singleTokenTokenId
    assertEq $ CustomError #invalidSingleTokenId
    dup
  dip drop

----------------------------------------------------------------------------
-- Errors
----------------------------------------------------------------------------
-- | For the get `TokenMetadata` entry point,
-- if the `TokenId` is not @0@ (the only valid `TokenId` for a single token).
type instance ErrorArg "invalidSingleTokenId" = ()

instance CustomErrorHasDoc "invalidSingleTokenId" where
  customErrClass = ErrClassBadArgument
  customErrDocMdCause = "The only valid token id is 0"
