{- SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-MIT-BitcoinSuisse
 -}
module Lorentz.Contracts.TZBTC.Test
  ( smokeTests
  ) where

import Control.Lens ((<>~), _Just)
import Data.Typeable (cast)
import System.Environment (setEnv)
import System.Exit (ExitCode(..))
import System.Process (readProcessWithExitCode)

import Lorentz (TrustEpName(..), View(..), arg, mkView, toMutez)
import Lorentz.Contracts.Metadata
import Lorentz.Contracts.Upgradeable.Common (EpwUpgradeParameters(..), emptyPermanentImpl)
import Lorentz.Test (contractConsumer)
import Lorentz.UStore.Migration
import Michelson.Typed.Haskell.Value
import Michelson.Untyped.Entrypoints
import Morley.Client.Init (mccAliasPrefixL)
import qualified Morley.Client.TezosClient as TezosClient
import Morley.Nettest
import qualified Morley.Nettest.Client as TezosClient
import Tezos.Address
import Util.Named

import Client.Parser (parseContractAddressFromOutput)
import Lorentz.Contracts.TZBTC
import qualified Lorentz.Contracts.TZBTC.V1.Types as TZBTCTypes

-- Prerequisites:
-- 1. `tezos-client` program should be available or configured via env variable
--    just like required for `tzbtc-client` config.
-- 2. `tezos-client` alias `nettest` should exist with some balance.
smokeTests :: Maybe MorleyClientConfig -> IO ()
smokeTests mconfig = do
  runNettestViaIntegrational $ simpleScenario True
  whenJust mconfig $ \config ->
    sequence_
    [ do
        let config' = config & mccAliasPrefixL . _Just <>~ "_tezos_client"
        env <- mkMorleyClientEnv config'
        runNettestClient (NettestEnv env Nothing) $ simpleScenario True
    , do
        let config' = config & mccAliasPrefixL . _Just <>~ "_tzbtc_client"
        env <- mkMorleyClientEnv config'
        runNettestTzbtcClient env $ simpleScenario False
    ]

dummyV1Parameters :: Address -> TokenMetadata -> Map Address Natural -> V1Parameters
dummyV1Parameters redeem tokenMetadata balances = V1Parameters
  { v1RedeemAddress = redeem
  , v1TokenMetadata = tokenMetadata
  , v1Balances = balances
  }

simpleScenario :: Bool -> NettestScenario m
simpleScenario requireUpgrade = uncapsNettest $ do
  admin <- resolveNettestAddress -- Fetch address for alias `nettest`.

  -- Originate and upgrade
  tzbtc <- originateSimple "TZBTCContract" (mkEmptyStorageV0 admin) tzbtcContract

  -- Originate Address view callback
  addressView <- originateSimple "Address view" [] (contractConsumer @Address)

  -- Originate Natural view callback
  naturalView <- originateSimple "Natural view" [] (contractConsumer @Natural)

  -- Originate [TokenMetadata] view callback
  tokenMetadatasView <- originateSimple "[TokenMetadata] view" [] (contractConsumer @[TokenMetadata])

  let
    fromFlatParameterV1  :: FlatParameter TZBTCv1 -> Parameter TZBTCv1
    fromFlatParameterV1 = fromFlatParameter
    adminAddr = AddressResolved admin
    opTZBTC = dummyV1Parameters admin defaultTZBTCMetadata mempty
    upgradeParams :: OneShotUpgradeParameters TZBTCv0
    upgradeParams = makeOneShotUpgradeParameters @TZBTCv0 EpwUpgradeParameters
      { upMigrationScripts =
        Identity $
        manualConcatMigrationScripts (migrationScripts opTZBTC)
      , upNewCode = tzbtcContractRouter
      , upNewPermCode = emptyPermanentImpl
      }
  when requireUpgrade $
    callFrom
      adminAddr
      tzbtc
      (TrustEpName DefEpName)
      (fromFlatParameter $ Upgrade upgradeParams :: Parameter TZBTCv0)

  -- Add an operator
  (operator, operatorAddr) <- newAddress' "operator"

  -- Transfer some credits to operator for further
  -- operations.
  transfer $ TransferData
    { tdFrom = AddressResolved admin
    , tdTo = operator
    , tdAmount = toMutez $ 5000 * 1000 -- 5 XTZ
    , tdEntrypoint = DefEpName
    , tdParameter = ()
    }

  callFrom
    (AddressAlias "nettest")
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ AddOperator (#operator .! operatorAddr))

  -- Add another operator
  (operatorToRemove, operatorToRemoveAddr) <- newAddress' "operator_to_remove"
  callFrom
    (AddressAlias "nettest")
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ AddOperator (#operator .! operatorToRemoveAddr))

  -- Mint some coins for alice
  (alice, aliceAddr) <- newAddress' "alice"

  callFrom
    operatorToRemove -- use the new operator to make sure it has been added.
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ Mint (#to .! aliceAddr, #value .! 100))

  -- Remove an operator
  callFrom
    (AddressAlias "nettest")
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ RemoveOperator (#operator .! operatorToRemoveAddr))

  -- Set allowance
  -- Mint some coins for john
  (john, johnAddr) <- newAddress' "john"

  callFrom
    operator
    -- We use alias instead of address to let the nettest implementation
    -- to call the `tzbtc-client` program with --user override (which does not work with addresses)
    -- using the alias.
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ Mint (#to .! johnAddr , #value .! 100))

  -- Set allowance for alice to transfer from john

  callFrom
    john
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ Approve (#spender .! aliceAddr, #value .! 100))

  -- Transfer coins from john to alice by alice
  callFrom
    alice
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ Transfer (#from .! johnAddr, #to .! aliceAddr, #value .! 15))

  -- Burn some coins from john to redeem address to burn
  callFrom
    john
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ Transfer (#from .! johnAddr, #to .! admin, #value .! 7))

  -- Burn it
  callFrom
    operator
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ Burn (#value .! 7))

  -- Pause operations
  callFrom
    operator
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ Pause ())

  -- Resume operations
  callFrom
    (AddressAlias "nettest")
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ Unpause ())

  -- Transfer ownership
  (newOwner, newOwnerAddr) <- newAddress' "newOwner"
  callFrom
    (AddressAlias "nettest")
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ TransferOwnership (#newOwner .! newOwnerAddr))

  -- Accept ownership
  callFrom
    newOwner
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ AcceptOwnership ())

  -- Make an anonymous address
  (guest, _) <- newAddress' "guest"

  -- Transfer some credits to guest for further
  -- operations.
  transfer $ TransferData
    { tdFrom = AddressResolved admin
    , tdTo = guest
    , tdAmount = toMutez $ 5000 * 1000 -- 5 XTZ
    , tdEntrypoint = DefEpName
    , tdParameter = ()
    }

  callFrom
    guest
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ GetAllowance (mkView (#owner .! johnAddr, #spender .! aliceAddr) naturalView))

  callFrom
    guest
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ GetBalance (mkView (#owner .! johnAddr) naturalView))

  callFrom
    guest
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ GetTotalSupply (mkView () naturalView))

  callFrom
    guest
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ GetTotalMinted (mkView () naturalView))

  callFrom
    guest
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ GetTotalBurned (mkView () naturalView))

  callFrom
    guest
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ GetTokenMetadata (mkView [0] tokenMetadatasView))

  callFrom
    guest
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ GetOwner (mkView () addressView))

  callFrom
    guest
    tzbtc
    (TrustEpName DefEpName)
    (fromFlatParameterV1 $ GetRedeemAddress (mkView () addressView))

-- | This is a version of 'newAddress' that returns both an address and an alias.
--
-- This is necessary, because tezos-client key revelaing does not work on
-- addresses somehow.
newAddress' :: MonadNettest caps base m => TezosClient.Alias -> m (AddressOrAlias, Address)
newAddress' alias = do
  addr <- newAddress alias
  prefixedAlias <- getAlias (AddressResolved addr)
  return (AddressAlias prefixedAlias, addr)

runNettestTzbtcClient :: MorleyClientEnv -> NettestScenario IO -> IO ()
runNettestTzbtcClient env scenario = do
  scenario $ nettestImplTzbtcClient env

nettestImplTzbtcClient :: MorleyClientEnv -> NettestImpl IO
nettestImplTzbtcClient env = NettestImpl
  { niOriginateUntyped = tzbtcClientOriginate
  , niTransfer = tzbtcClientTransfer
  , ..
  }
  where
    NettestImpl {..} = TezosClient.nettestImplClient env

    tzbtcClientOriginate :: UntypedOriginateData -> IO Address
    tzbtcClientOriginate od@(UntypedOriginateData {..}) =
      if uodName == "TZBTCContract" then do
        output <- callTzbtcClient
          [ "deployTzbtcContract"
          , "--owner", toString (formatAddressOrAlias uodFrom)
          , "--redeem", toString (formatAddressOrAlias uodFrom)
          , "--user", toString (formatAddressOrAlias uodFrom)
          ]
        case parseContractAddressFromOutput output of
          Right a -> pure a
          Left err -> throwM $ TezosClient.UnexpectedClientFailure 1 "" (show err)
      else niOriginateUntyped od

    tzbtcClientTransfer :: TransferData -> IO ()
    tzbtcClientTransfer td@(TransferData {..}) =
      -- If we had a Typeable constraint for `v` in definition of
      -- `TransferData`, we could save this use of toVal/fromVal conversion and
      -- use `tdParameter` directly.
      case cast (toVal tdParameter) of
        Just srcVal -> case (fromVal srcVal :: TZBTCTypes.Parameter SomeTZBTCVersion) of
          TZBTCTypes.GetTotalSupply (viewCallbackTo -> (crAddress -> view_)) ->
            callTzbtc
              [ "getTotalSupply"
              , "--callback", toString (formatAddress view_)
              ]

          TZBTCTypes.GetTotalMinted (viewCallbackTo -> (crAddress -> view_)) ->
            callTzbtc
              [ "getTotalMinted"
              , "--callback", toString (formatAddress view_)
              ]

          TZBTCTypes.GetTotalBurned (viewCallbackTo -> (crAddress -> view_)) ->
            callTzbtc
              [ "getTotalBurned"
              , "--callback", toString (formatAddress view_)
              ]

          TZBTCTypes.GetAllowance
            (View (arg #owner -> owner, arg #spender -> spender) (crAddress -> view_)) ->
              callTzbtc
                [ "getAllowance"
                , "--owner", toString (formatAddress owner)
                , "--spender", toString (formatAddress spender)
                , "--callback", toString (formatAddress view_)
                ]

          TZBTCTypes.GetOwner (viewCallbackTo -> (crAddress -> view_)) ->
            callTzbtc
              [ "getOwner"
              , "--callback", toString (formatAddress view_)
              ]

          TZBTCTypes.GetRedeemAddress (viewCallbackTo -> (crAddress -> view_)) ->
            callTzbtc
              [ "getRedeemAddress"
              , "--callback", toString (formatAddress view_)
              ]

          TZBTCTypes.GetTokenMetadata (viewCallbackTo -> (crAddress -> view_)) ->
            callTzbtc
              [ "getTokenMetadata"
              , "--callback", toString (formatAddress view_)
              ]

          TZBTCTypes.SafeEntrypoints sp -> case sp of
            TZBTCTypes.Transfer (arg #from -> from, arg #to -> to, arg #value -> value) ->
              callTzbtc
                [ "transfer"
                , "--from", toString $ formatAddress from
                , "--to", toString $ formatAddress to
                , "--value", show value
                ]

            TZBTCTypes.Approve (arg #spender -> spender, arg #value -> value) ->
              callTzbtc
                [ "approve"
                , "--spender", toString $ formatAddress spender
                , "--value", show value
                ]

            TZBTCTypes.Mint (arg #to -> to, arg #value -> value) ->
              callTzbtc
                [ "mint"
                , "--to", toString $ formatAddress to
                , "--value", show value
                ]

            TZBTCTypes.Burn (arg #value -> value) -> callTzbtc [ "burn" , "--value", show value ]
            TZBTCTypes.AddOperator (arg #operator -> operator) ->
              callTzbtc [ "addOperator" , "--operator", toString $ formatAddress operator ]
            TZBTCTypes.RemoveOperator (arg #operator -> operator) ->
              callTzbtc [ "removeOperator" , "--operator", toString $ formatAddress operator ]
            TZBTCTypes.Pause _  -> callTzbtc $ [ "pause" ]
            TZBTCTypes.Unpause _  -> callTzbtc $ [ "unpause" ]
            TZBTCTypes.TransferOwnership (arg #newOwner -> newOwnerAddress) ->
              callTzbtc [ "transferOwnership" , toString $ formatAddress newOwnerAddress ]
            TZBTCTypes.AcceptOwnership _ -> callTzbtc $ [ "acceptOwnership" ]
            _ -> niTransfer td
          _ -> niTransfer td
        Nothing -> niTransfer td
      where
        callTzbtc :: [String] -> IO ()
        callTzbtc args = void $ callTzbtcClient $
          args <> ["--user", toString (formatAddressOrAlias tdFrom)
                  , "--contract-addr", toString (formatAddressOrAlias tdTo)
                  ]

    formatAddressOrAlias :: AddressOrAlias -> Text
    formatAddressOrAlias = \case
      AddressResolved addr -> formatAddress addr
      AddressAlias name ->
        -- we rely on alias to be already prefixed
        -- in order not to diverge with nettest primitives taken from Morley
        name

-- | Write something to stderr.
putErrLn :: Print a => a -> IO ()
putErrLn = hPutStrLn stderr

callTzbtcClient :: [String] -> IO Text
callTzbtcClient args = toText <$> do
  setEnv "TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER" "YES"
  readProcessWithExitCode "tzbtc-client" args "N" >>=
    \case
      (ExitSuccess, output, errOutput) ->
        output <$ putErrLn errOutput
      (ExitFailure code, toText -> output, toText -> errOutput) ->
        throwM $ TezosClient.UnexpectedClientFailure code output errOutput
