{- SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-Proprietary
 -}
module Client.Parser
  ( AddrOrAlias
  , ClientArgs(..)
  , ClientArgsRaw(..)
  , clientArgParser
  , parseAddressFromOutput
  , parseSignatureFromOutput
  ) where

import Data.Char (isAlpha, isDigit, toUpper)
import Fmt (pretty)
import Options.Applicative
  (argument, auto, eitherReader, help, long, metavar, option,
  showDefaultWith, str, switch, value)
import qualified Options.Applicative as Opt
import qualified Text.Megaparsec as P
  (Parsec, customFailure, many, parse, satisfy)
import Text.Megaparsec.Char (space, newline)
import Text.Megaparsec.Char.Lexer (symbol)
import Text.Megaparsec.Error (ParseErrorBundle, ShowErrorComponent(..))

import Tezos.Crypto (PublicKey, Signature, parsePublicKey, parseSignature)
import Tezos.Address (Address, parseAddress)

import CLI.Parser
import Client.Types
import Lorentz.Contracts.TZBTC.Types

-- | Client argument with optional dry-run flag
data ClientArgs = ClientArgs ClientArgsRaw Bool

type AddrOrAlias = Text

data ClientArgsRaw
  = CmdMint AddrOrAlias Natural (Maybe FilePath)
  | CmdBurn BurnParams (Maybe FilePath)
  | CmdTransfer AddrOrAlias AddrOrAlias Natural
  | CmdApprove AddrOrAlias Natural
  | CmdGetAllowance (AddrOrAlias, AddrOrAlias) AddrOrAlias
  | CmdGetBalance AddrOrAlias AddrOrAlias
  | CmdAddOperator AddrOrAlias (Maybe FilePath)
  | CmdRemoveOperator AddrOrAlias (Maybe FilePath)
  | CmdPause (Maybe FilePath)
  | CmdUnpause (Maybe FilePath)
  | CmdSetRedeemAddress AddrOrAlias (Maybe FilePath)
  | CmdTransferOwnership AddrOrAlias (Maybe FilePath)
  | CmdAcceptOwnership AcceptOwnershipParams
  | CmdStartMigrateTo AddrOrAlias (Maybe FilePath)
  | CmdStartMigrateFrom AddrOrAlias (Maybe FilePath)
  | CmdMigrate MigrateParams
  | CmdSetupClient ClientConfig
  | CmdGetOpDescription FilePath
  | CmdGetPackageDescription FilePath
  | CmdGetBytesToSign FilePath
  | CmdAddSignature PublicKey Signature FilePath
  | CmdCallMultisig (NonEmpty FilePath)

clientArgParser :: Opt.Parser ClientArgs
clientArgParser = ClientArgs <$> clientArgRawParser <*> dryRunSwitch
  where
    dryRunSwitch =
      switch (long "dry-run" <>
              help "Dry run command to ensure correctness of the arguments")

clientArgRawParser :: Opt.Parser ClientArgsRaw
clientArgRawParser = Opt.hsubparser $
  mintCmd <> burnCmd <> transferCmd <> approveCmd
  <> getAllowanceCmd <> getBalanceCmd <> addOperatorCmd
  <> removeOperatorCmd <> pauseCmd <> unpauseCmd
  <> setRedeemAddressCmd <> transferOwnershipCmd <> acceptOwnershipCmd
  <> startMigrateFromCmd <> startMigrateToCmd
  <> migrateCmd <> setupUserCmd <> getOpDescriptionCmd
  <> getPackageDescriptionCmd <> getBytesToSignCmd
  <> addSignatureCmd <> callMultisigCmd
  where
    multisigOption =
      Opt.optional $ Opt.strOption $ mconcat
      [ long "multisig"
      , metavar "FILEPATH"
      , help "Create package for multisig transaction and write it to the given file"
      ]
    setupUserCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    setupUserCmd = (mkCommandParser
                    "setupClient"
                    (CmdSetupClient <$>
                     (ClientConfig <$>
                      urlArgument "Node url" <*>
                      intArgument "Node port" <*>
                      namedAddressOption Nothing "contract-address"
                      "Contract's address" <*>
                      namedAddressOption Nothing "multisig-address" "Multisig contract address" <*>
                      (option str $ mconcat
                       [ long "alias"
                       , metavar "ADDRESS_ALIAS"
                       , help "tezos-client alias"
                       ])
                      <*> tezosClientFilePathOption
                     ))
                    ("Setup client using node url, node port, contract address, \
                     \user address, user address alias and \
                     \filepath to the tezos-client executable"))
    mintCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    mintCmd =
      (mkCommandParser
         "mint"
         (CmdMint <$> addrOrAliasOption "to" "Address to mint to" <*>
          natOption "value" "Amount to mint" <*> multisigOption)
         "Mint tokens for an account")
    burnCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    burnCmd =
      (mkCommandParser
         "burn"
         (CmdBurn <$> burnParamsParser <*> multisigOption)
         "Burn tokens from an account")
    transferCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    transferCmd =
      (mkCommandParser
         "transfer"
         (CmdTransfer <$>
          addrOrAliasOption "from" "Address to transfer from" <*>
          addrOrAliasOption "to" "Address to transfer to" <*>
          natOption "value" "Amount to transfer"
         )
         "Transfer tokens from one account to another")
    approveCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    approveCmd =
      (mkCommandParser
         "approve"
         (CmdApprove <$>
          addrOrAliasOption "spender" "Address of the spender" <*>
          natOption "value" "Amount to approve"
         )
         "Approve transfer of tokens from one account to another")
    getAllowanceCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    getAllowanceCmd =
      (mkCommandParser
         "getAllowance"
         (CmdGetAllowance <$>
          ((,) <$> addrOrAliasOption "owner" "Address of the owner" <*>
          addrOrAliasOption "spender" "Address of the spender") <*>
          addrOrAliasOption "callback" "Callback address"
         )
         "Get allowance for an account")
    getBalanceCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    getBalanceCmd =
      (mkCommandParser
         "getBalance"
         (CmdGetBalance <$>
          addrOrAliasOption "address" "Address of the owner" <*>
          addrOrAliasOption "callback" "Callback address"
         )
         "Get balance for an account")
    addOperatorCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    addOperatorCmd =
      (mkCommandParser
         "addOperator"
         (CmdAddOperator <$>
          addrOrAliasOption "operator" "Address of the operator" <*>
          multisigOption
         )
         "Add an operator")
    removeOperatorCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    removeOperatorCmd =
      (mkCommandParser
         "removeOperator"
         (CmdRemoveOperator <$>
          addrOrAliasOption "operator" "Address of the operator" <*>
          multisigOption
         )
         "Remove an operator")
    pauseCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    pauseCmd =
      (mkCommandParser
         "pause"
         (CmdPause <$> multisigOption)
         "Pause the contract")
    unpauseCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    unpauseCmd =
      (mkCommandParser
         "unpause"
         (CmdUnpause <$> multisigOption)
         "Unpause the contract")
    setRedeemAddressCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    setRedeemAddressCmd =
      (mkCommandParser
         "setRedeemAddress"
         (CmdSetRedeemAddress <$>
          addrOrAliasArg "Redeem address" <*>
          multisigOption
         )
         "Set redeem address")
    transferOwnershipCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    transferOwnershipCmd =
      (mkCommandParser
         "transferOwnership"
         (CmdTransferOwnership <$>
          addrOrAliasArg "new-owner" <*>
          multisigOption
         )
         "Transfer ownership")
    acceptOwnershipCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    acceptOwnershipCmd =
      (mkCommandParser
         "acceptOwnership"
         (pure $ CmdAcceptOwnership ())
         "Accept ownership")
    startMigrateFromCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    startMigrateFromCmd =
      (mkCommandParser
         "startMigrateFrom"
         (CmdStartMigrateFrom <$>
          addrOrAliasArg "Manager contract address" <*>
          multisigOption
         )
         "Start contract migration")
    startMigrateToCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    startMigrateToCmd =
      (mkCommandParser
         "startMigrateTo"
         (CmdStartMigrateTo <$>
          addrOrAliasArg "Manager contract address" <*>
          multisigOption
         )
         "Start contract migration")
    migrateCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    migrateCmd =
      (mkCommandParser
         "migrate"
         (pure $ CmdMigrate ())
         "Migrate contract")

    getOpDescriptionCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    getOpDescriptionCmd =
      mkCommandParser
      "getOpDescription"
      (CmdGetOpDescription <$> namedFilePathOption "package" "Package filepath")
      "Get operation description from given multisig package"

    getPackageDescriptionCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    getPackageDescriptionCmd =
      mkCommandParser
      "getPackageDescription"
      (CmdGetPackageDescription <$> namedFilePathOption "package" "Package filepath")
      "Get human-readable description for given multisig package"

    getBytesToSignCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    getBytesToSignCmd =
      mkCommandParser
      "getBytesToSign"
      (CmdGetBytesToSign <$> namedFilePathOption "package" "Package filepath")
      "Get bytes that need to be signed from given multisig package"

    addSignatureCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    addSignatureCmd =
      mkCommandParser
      "addSignature"
      (CmdAddSignature <$> publicKeyOption <*> signatureOption <*>
       namedFilePathOption "package" "Package filepath"
      )
      "Add signature assosiated with the given public key to the given package"

    callMultisigCmd :: Opt.Mod Opt.CommandFields ClientArgsRaw
    callMultisigCmd =
      mkCommandParser
      "callMultisig"
      (CmdCallMultisig <$>
       nonEmptyParser (namedFilePathOption "package" "Package filepath")
      )
      "Call multisig contract with the given packages"

addrOrAliasOption :: String -> String -> Opt.Parser AddrOrAlias
addrOrAliasOption name hInfo =
  option str $ mconcat
  [ metavar "ADDRESS | ALIAS"
  , long name
  , help hInfo
  ]

addrOrAliasArg :: String -> Opt.Parser AddrOrAlias
addrOrAliasArg hInfo =
  argument str $ mconcat
  [ metavar "ADDRESS | ALIAS"
  , help hInfo
  ]

natOption :: String -> String -> Opt.Parser Natural
natOption name hInfo =
  option auto $ mconcat
  [ metavar $ toUpper <$> name
  , long name
  , help hInfo
  ]

burnParamsParser :: Opt.Parser BurnParams
burnParamsParser = getParser "Amount to burn"

urlArgument :: String -> Opt.Parser Text
urlArgument hInfo = argument str $
  mconcat [metavar "URL", help hInfo]

signatureOption :: Opt.Parser Signature
signatureOption = option (eitherReader parseSignatureDo) $ mconcat
  [ long "signature", metavar "SIGNATURE"]

parseSignatureDo :: String -> Either String Signature
parseSignatureDo sig =
  either (Left . mappend "Failed to parse signature: " . pretty) Right $
  parseSignature $ toText sig

publicKeyOption :: Opt.Parser PublicKey
publicKeyOption = option (eitherReader parsePublicKeyDo) $ mconcat
  [ long "public-key", metavar "PUBLIC KEY"]

parsePublicKeyDo :: String -> Either String PublicKey
parsePublicKeyDo pk =
  either (Left . mappend "Failed to parse signature: " . pretty) Right $
  parsePublicKey $ toText pk

intArgument :: String -> Opt.Parser Int
intArgument hInfo = argument auto $
  mconcat [metavar "PORT", help hInfo]

tezosClientFilePathOption :: Opt.Parser FilePath
tezosClientFilePathOption = option str $
  mconcat [ long "tezos-client", metavar "FILEPATH", help "tezos-client executable"
          , value "tezos-client", showDefaultWith (<> " from $PATH")
          ]

namedFilePathOption :: String -> String -> Opt.Parser FilePath
namedFilePathOption name hInfo = option str $
  mconcat [long name, metavar "FILEPATH", help hInfo]

nonEmptyParser :: Opt.Parser a -> Opt.Parser (NonEmpty a)
nonEmptyParser p = (:|) <$> p <*> many p

-- Tezos-client output parsers
data OutputParseError = OutputParseError Text Text
  deriving stock (Eq, Show, Ord)

instance ShowErrorComponent OutputParseError where
  showErrorComponent (OutputParseError name err) = toString $
    "Failed to parse " <> name <> ": " <> err

type Parser = P.Parsec OutputParseError Text

isBase58Char :: Char -> Bool
isBase58Char c =
  (isDigit c && c /= '0') || (isAlpha c && c /= 'O' && c /= 'I' && c /= 'l')

tezosClientSignatureParser :: Parser Signature
tezosClientSignatureParser = do
  void $ symbol space "Signature:"
  rawSignature <- P.many (P.satisfy isBase58Char)
  case parseSignature (fromString rawSignature) of
    Left err -> P.customFailure $ OutputParseError "signature" $ pretty err
    Right sign -> return sign

tezosClientAddressParser :: Parser (Address, PublicKey)
tezosClientAddressParser = do
  void $ symbol space "Hash:"
  rawAddress <- fromString <$> P.many (P.satisfy isBase58Char)
  void $ newline
  void $ symbol space "Public Key:"
  rawPublicKey <- fromString <$> P.many (P.satisfy isBase58Char)
  case (parseAddress rawAddress, parsePublicKey rawPublicKey) of
    (Right addr, Right pk) -> return (addr, pk)
    (Left err, Right _) -> P.customFailure $ OutputParseError "address" $ pretty err
    (Right _, Left err) -> P.customFailure $ OutputParseError "public key" $ pretty err
    (Left err1, Left err2) -> P.customFailure $
      OutputParseError "address and public key" $ pretty err1 <> "\n" <> pretty err2

parseSignatureFromOutput
  :: Text -> Either (ParseErrorBundle Text OutputParseError) Signature
parseSignatureFromOutput output = P.parse tezosClientSignatureParser "" output

parseAddressFromOutput
  :: Text -> Either (ParseErrorBundle Text OutputParseError) (Address, PublicKey)
parseAddressFromOutput output = P.parse tezosClientAddressParser "" output
