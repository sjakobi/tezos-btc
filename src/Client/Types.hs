{- SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-Proprietary
 -}
module Client.Types
  ( ClientConfig (..)
  , ForgeOperation (..)
  , InternalOperation (..)
  , OperationContent (..)
  , RunError (..)
  , RunMetadata (..)
  , RunOperation (..)
  , RunOperationResult (..)
  , RunRes (..)
  , TransactionOperation (..)
  , combineResults
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.=), (.:), (.:?), (.!=))
import Data.Aeson.Casing (aesonPrefix, snakeCase)
import Data.Aeson.TH (deriveJSON)
import Fmt (Buildable(..), (+|), (|+))
import Tezos.Base16ByteString (Base16ByteString(..))
import Tezos.Micheline
  (Expression(..), MichelinePrimAp(..), MichelinePrimitive(..))
import Tezos.Json (TezosWord64(..))

import Tezos.Address (Address)
import Tezos.Crypto (Signature, encodeBase58Check)

newtype MichelsonExpression = MichelsonExpression Expression
  deriving newtype FromJSON

instance Buildable MichelsonExpression where
  build (MichelsonExpression expr) = case expr of
    Expression_Int i -> build $ unTezosWord64 i
    Expression_String s -> build s
    Expression_Bytes b ->
      build $ encodeBase58Check $ unbase16ByteString b
    Expression_Seq s -> "(" +| buildSeq s |+ ")"
    Expression_Prim (MichelinePrimAp (MichelinePrimitive text) s) ->
      text <> " " |+ "(" +|
      buildSeq s +| ")"
    where
      buildSeq =
        mconcat . intersperse ", " . map
        (build . MichelsonExpression) . toList

data ForgeOperation = ForgeOperation
  { foBranch :: Text
  , foContents :: [TransactionOperation]
  }

instance ToJSON ForgeOperation where
  toJSON ForgeOperation{..} = object
    [ "branch" .= toString foBranch
    , "contents" .= toJSON foContents
    ]

data RunOperation = RunOperation
  { roBranch :: Text
  , roContents :: [TransactionOperation]
  , roSignature :: Signature
  }

data RunRes = RunRes
  { rrOperationContents :: [OperationContent]
  }

instance FromJSON RunRes where
  parseJSON = withObject "preApplyRes" $ \o ->
    RunRes <$> o .: "contents"

data OperationContent = OperationContent RunMetadata

instance FromJSON OperationContent where
  parseJSON = withObject "operationCostContent" $ \o ->
    OperationContent <$> o .: "metadata"

data RunMetadata = RunMetadata
  { rmOperationResult :: RunOperationResult
  , rmInternalOperationResults :: [InternalOperation]
  }

instance FromJSON RunMetadata where
  parseJSON = withObject "metadata" $ \o ->
    RunMetadata <$> o .: "operation_result" <*>
    o .:? "internal_operation_results" .!= []

newtype InternalOperation = InternalOperation
  { unInternalOperation :: RunOperationResult }

instance FromJSON InternalOperation where
  parseJSON = withObject "internal_operation" $ \o ->
    InternalOperation <$> o .: "result"

data RunError
  = RuntimeError Address
  | ScriptRejected MichelsonExpression
  | BadContractParameter Address
  | InvalidConstant MichelsonExpression MichelsonExpression
  | InconsistentTypes MichelsonExpression MichelsonExpression

instance FromJSON RunError where
  parseJSON = withObject "preapply error" $ \o -> do
    id' <- o .: "id"
    case id' of
      "proto.004-Pt24m4xi.michelson_v1.runtime_error" ->
        RuntimeError <$> o .: "contract_handle"
      "proto.004-Pt24m4xi.michelson_v1.script_rejected" ->
        ScriptRejected <$> o .: "with"
      "proto.004-Pt24m4xi.michelson_v1.bad_contract_parameter" ->
        BadContractParameter <$> o .: "contract"
      "proto.004-Pt24m4xi.michelson_v1.invalid_constant" ->
        InvalidConstant <$> o .: "expected_type" <*> o .: "wrong_expression"
      "proto.004-Pt24m4xi.michelson_v1.inconsistent_types" ->
        InconsistentTypes <$> o .: "first_type" <*> o .: "other_type"
      _ -> fail ("unknown id: " <> id')

instance Buildable RunError where
  build = \case
    RuntimeError addr -> "Runtime error for contract: " +| addr |+ ""
    ScriptRejected expr -> "Script rejected with: " +| expr |+ ""
    BadContractParameter addr -> "Bad contract parameter for: " +| addr |+ ""
    InvalidConstant expectedType expr ->
      "Invalid type: " +| expectedType |+ "\n" +|
      "For: " +| expr |+ ""
    InconsistentTypes type1 type2 ->
      "Inconsistent types: " +| type1 |+ " and " +| type2 |+ ""

data RunOperationResult
  = RunOperationApplied TezosWord64 TezosWord64
  | RunOperationFailed [RunError]

combineResults :: RunOperationResult -> RunOperationResult -> RunOperationResult
combineResults (RunOperationApplied c1 c2) (RunOperationApplied c3 c4) =
  RunOperationApplied (c1 + c3) (c2 + c4)
combineResults (RunOperationApplied _ _) (RunOperationFailed e) =
  RunOperationFailed e
combineResults (RunOperationFailed e) (RunOperationApplied _ _) =
  RunOperationFailed e
combineResults (RunOperationFailed e1) (RunOperationFailed e2) =
  RunOperationFailed $ e1 <> e2

instance FromJSON RunOperationResult where
  parseJSON = withObject "operation_costs" $ \o -> do
    status <- o .: "status"
    case status of
      "applied" -> RunOperationApplied <$> o .: "consumed_gas" <*> o .: "storage_size"
      "failed" -> RunOperationFailed <$> o .: "errors"
      _ -> fail ("unexpected status " ++ status)

data TransactionOperation = TransactionOperation
  { toKind :: Text
  , toSource :: Address
  , toFee :: TezosWord64
  , toCounter :: TezosWord64
  , toGasLimit :: TezosWord64
  , toStorageLimit :: TezosWord64
  , toAmount :: TezosWord64
  , toDestination :: Address
  , toParameters :: Expression
  }

data ClientConfig = ClientConfig
  { ccNodeAddress :: Text
  , ccNodePort :: Int
  , ccContractAddress :: Address
  , ccUserAddress :: Address
  , ccUserAlias :: Text
  , ccTzbtcExecutable :: FilePath
  , ccTezosClientExecutable :: FilePath
  }

deriveJSON (aesonPrefix snakeCase) ''TransactionOperation
deriveJSON (aesonPrefix snakeCase) ''ClientConfig
deriveJSON (aesonPrefix snakeCase) ''RunOperation