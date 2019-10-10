{- SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-Proprietary
 -}
module Client.API
  ( forgeOperation
  , getFromBigMap
  , getMainChainId
  , getCounter
  , getStorage
  , getLastBlock
  , injectOperation
  , runOperation
  ) where

import Servant.API
  (Capture, Get, JSON, Post, ReqBody, QueryParam, (:>), (:<|>)(..))
import Servant.Client (ClientM, client)
import Tezos.Json (TezosWord64)
import Tezos.Micheline (Expression)

import Michelson.Untyped (InternalByteString(..))

import Client.Types

type NodeAPI =
  "chains/main/blocks/head/helpers/forge/operations"
  :> ReqBody '[JSON] ForgeOperation :> Post '[JSON] InternalByteString :<|>
  "chains/main/blocks/head/hash"
  :> Get '[JSON] Text :<|>
  "injection/operation" :> QueryParam "chain" Text :> ReqBody '[JSON] Text
  :> Post '[JSON] Text :<|>
  "chains/main/blocks/head/context/contracts"
  :> Capture "contract" Text :> "counter" :> Get '[JSON] TezosWord64 :<|>
  "chains/main/blocks/head/helpers/scripts/run_operation"
  :> ReqBody '[JSON] RunOperation :> Post '[JSON] RunRes :<|>
  "chains/main/blocks/head/context/contracts"
  :> Capture "contract" Text :> "storage" :> Get '[JSON] Expression :<|>
  "chains/main/chain_id" :> Get '[JSON] Text :<|>
  "chains/main/blocks/head/context/big_maps" :> Capture "big_map_id" Natural
  :> Capture "script_expr" Text :> Get '[JSON] Expression


nodeAPI :: Proxy NodeAPI
nodeAPI = Proxy

getLastBlock :: ClientM Text
forgeOperation :: ForgeOperation -> ClientM InternalByteString
injectOperation :: Maybe Text -> Text -> ClientM Text
getCounter :: Text -> ClientM TezosWord64
runOperation :: RunOperation -> ClientM RunRes
getStorage :: Text -> ClientM Expression
getMainChainId :: ClientM Text
getFromBigMap :: Natural -> Text -> ClientM Expression
forgeOperation :<|>
  getLastBlock :<|>
  injectOperation :<|>
  getCounter :<|>
  runOperation :<|>
  getStorage :<|>
  getMainChainId :<|>
  getFromBigMap = client nodeAPI
