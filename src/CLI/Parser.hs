{- SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-Proprietary
 -}
module CLI.Parser
  ( CmdLnArgs(..)
  , TestScenarioOptions(..)
  , HasParser(..)
  , addressArgument
  , argParser
  , mkCommandParser
  , namedAddressOption
  ) where

import GHC.TypeLits (KnownSymbol, Symbol, symbolVal)

import Data.Char (toUpper)
import Fmt (pretty)
import Named (Name(..))
import Options.Applicative
  (argument, auto, command, eitherReader, help, hsubparser, info, long, metavar, option, progDesc,
  showDefaultWith, str, switch, value)
import qualified Options.Applicative as Opt

import Lorentz ((:!), ContractAddr(..), View(..))
import Lorentz.Contracts.TZBTC.Types
import Tezos.Address
import Util.Named

-- | Represents the Cmd line commands with inputs/arguments.
data CmdLnArgs
  = CmdMint MintParams (Maybe FilePath)
  | CmdBurn BurnParams (Maybe FilePath)
  | CmdTransfer TransferParams
  | CmdApprove ApproveParams
  | CmdGetAllowance (View GetAllowanceParams Natural)
  | CmdGetBalance (View GetBalanceParams Natural)
  | CmdAddOperator OperatorParams (Maybe FilePath)
  | CmdRemoveOperator OperatorParams (Maybe FilePath)
  | CmdPause (Maybe FilePath)
  | CmdUnpause (Maybe FilePath)
  | CmdSetRedeemAddress SetRedeemAddressParams (Maybe FilePath)
  | CmdTransferOwnership TransferOwnershipParams (Maybe FilePath)
  | CmdAcceptOwnership AcceptOwnershipParams
  | CmdStartMigrateTo StartMigrateToParams (Maybe FilePath)
  | CmdStartMigrateFrom StartMigrateFromParams (Maybe FilePath)
  | CmdMigrate MigrateParams
  | CmdPrintInitialStorage Address Address
  | CmdPrintContract Bool (Maybe FilePath)
  | CmdPrintAgentContract Bool (Maybe FilePath)
  | CmdPrintProxyContract Bool (Maybe FilePath)
  | CmdPrintDoc (Maybe FilePath)
  | CmdParseParameter Text
  | CmdTestScenario TestScenarioOptions

data TestScenarioOptions = TestScenarioOptions
  { tsoMaster :: !Address
  , tsoOutput :: !(Maybe FilePath)
  , tsoAddresses :: ![Address]
  }

argParser :: Opt.Parser CmdLnArgs
argParser = hsubparser $
  mintCmd <> burnCmd <> transferCmd <> approveCmd
  <> getAllowanceCmd <> getBalanceCmd <> addOperatorCmd
  <> removeOperatorCmd <> pauseCmd <> unpauseCmd
  <> setRedeemAddressCmd <> transferOwnershipCmd <> acceptOwnershipCmd
  <> startMigrateFromCmd <> startMigrateToCmd
  <> migrateCmd <> printCmd
  <> printAgentCmd <> printProxyCmd
  <> printInitialStorageCmd <> printDoc
  <> parseParameterCmd <> testScenarioCmd
  where
    singleLineSwitch =
            switch (long "oneline" <> help "Single line output")
    multisigOption =
      Opt.optional $ Opt.strOption $ mconcat
      [ long "multisig"
      , metavar "FILEPATH"
      , help "Create package for multisig transaction and write it to the given file"
      ]
    printCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    printCmd =
      (mkCommandParser
        "printContract"
        (CmdPrintContract <$> singleLineSwitch <*> outputOption)
        "Print token contract")
    printAgentCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    printAgentCmd =
      (mkCommandParser
        "printAgentContract"
        (CmdPrintAgentContract <$> singleLineSwitch <*> outputOption)
        "Print migration agent contract")
    printProxyCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    printProxyCmd =
      (mkCommandParser
        "printProxyContract"
        (CmdPrintProxyContract <$> singleLineSwitch <*> outputOption)
        "Print proxy contract")
    printInitialStorageCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    printInitialStorageCmd =
      (mkCommandParser
         "printInitialStorage"
         (CmdPrintInitialStorage
            <$> namedAddressOption Nothing "admin-address" "Administrator's address"
            <*> namedAddressOption Nothing "redeem-address" "Redeem address")
         "Print initial contract storage with the given administrator and \
         \redeem addresses")
    printDoc :: Opt.Mod Opt.CommandFields CmdLnArgs
    printDoc =
      (mkCommandParser
        "printContractDoc"
        (CmdPrintDoc <$> outputOption)
        "Print tzbtc contract documentation")
    parseParameterCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    parseParameterCmd =
      (mkCommandParser
          "parseContractParameter"
          (CmdParseParameter <$> Opt.strArgument mempty)
          "Parse contract parameter to Lorentz representation")
    testScenarioCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    testScenarioCmd =
      (mkCommandParser
          "testScenario"
          (CmdTestScenario <$> testScenarioOptions)
          "Print parameters for smoke tests")
    mintCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    mintCmd =
      (mkCommandParser
         "mint"
         (CmdMint <$> mintParamParser <*> multisigOption)
         "Mint tokens for an account")
    burnCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    burnCmd =
      (mkCommandParser
         "burn"
         (CmdBurn <$> burnParamsParser <*> multisigOption)
         "Burn tokens from an account")
    transferCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    transferCmd =
      (mkCommandParser
         "transfer"
         (CmdTransfer <$> transferParamParser)
         "Transfer tokens from one account to another")
    approveCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    approveCmd =
      (mkCommandParser
         "approve"
         (CmdApprove <$> approveParamsParser)
         "Approve transfer of tokens from one account to another")
    getAllowanceCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    getAllowanceCmd =
      (mkCommandParser
         "getAllowance"
         (CmdGetAllowance <$> getAllowanceParamsParser)
         "Get allowance for an account")
    getBalanceCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    getBalanceCmd =
      (mkCommandParser
         "getBalance"
         (CmdGetBalance <$> getBalanceParamsParser)
         "Get balance for an account")
    addOperatorCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    addOperatorCmd =
      (mkCommandParser
         "addOperator"
         (CmdAddOperator <$> operatorParamsParser <*> multisigOption)
         "Add an operator")
    removeOperatorCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    removeOperatorCmd =
      (mkCommandParser
         "removeOperator"
         (CmdRemoveOperator <$> operatorParamsParser <*> multisigOption)
         "Remove an operator")
    pauseCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    pauseCmd =
      (mkCommandParser
         "pause"
         (CmdPause <$> multisigOption)
         "Pause the contract")
    unpauseCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    unpauseCmd =
      (mkCommandParser
         "unpause"
         (CmdUnpause <$> multisigOption)
         "Unpause the contract")
    setRedeemAddressCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    setRedeemAddressCmd =
      (mkCommandParser
         "setRedeemAddress"
         (CmdSetRedeemAddress <$> setRedeemAddressParamsParser <*> multisigOption)
         "Set redeem address")
    transferOwnershipCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    transferOwnershipCmd =
      (mkCommandParser
         "transferOwnership"
         (CmdTransferOwnership <$> transferOwnershipParamsParser <*> multisigOption)
         "Transfer ownership")
    acceptOwnershipCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    acceptOwnershipCmd =
      (mkCommandParser
         "acceptOwnership"
         (pure $ CmdAcceptOwnership ())
         "Accept ownership")
    startMigrateFromCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    startMigrateFromCmd =
      (mkCommandParser
         "startMigrateFrom"
         (CmdStartMigrateFrom <$> startMigrateFromParamsParser <*> multisigOption)
         "Start contract migration")
    startMigrateToCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    startMigrateToCmd =
      (mkCommandParser
         "startMigrateTo"
         (CmdStartMigrateTo <$> startMigrateToParamsParser <*> multisigOption)
         "Start contract migration")
    migrateCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    migrateCmd =
      (mkCommandParser
         "migrate"
         (pure $ CmdMigrate ())
         "Migrate contract")

mkCommandParser
  :: String
  -> Opt.Parser a
  -> String
  -> Opt.Mod Opt.CommandFields a
mkCommandParser commandName parser desc =
  command commandName $ info parser $ progDesc desc


mintParamParser :: Opt.Parser MintParams
mintParamParser =
  (,) <$> (getParser "Address to mint to")
       <*> (getParser "Amount to mint")

burnParamsParser :: Opt.Parser BurnParams
burnParamsParser = getParser "Amount to burn"

approveParamsParser :: Opt.Parser ApproveParams
approveParamsParser =
  (,) <$> (getParser "Address of the spender")
       <*> (getParser "Amount to approve")

transferParamParser :: Opt.Parser TransferParams
transferParamParser =
  (,,) <$> (getParser "Address to transfer from")
       <*> (getParser "Address to transfer to")
       <*> (getParser "Amount to transfer")

getAllowanceParamsParser :: Opt.Parser (View GetAllowanceParams Natural)
getAllowanceParamsParser = let
  iParam =
    (,) <$> (getParser "Address of the owner")
        <*> (getParser "Address of spender")
  contractParam = callBackAddressOption
  in View <$> iParam <*> contractParam

getBalanceParamsParser :: Opt.Parser (View GetBalanceParams Natural)
getBalanceParamsParser = let
  iParam = addressOption Nothing "Address of the owner"
  in View <$> iParam <*> callBackAddressOption

operatorParamsParser :: Opt.Parser OperatorParams
operatorParamsParser = getParser "Address of the operator"

setRedeemAddressParamsParser :: Opt.Parser SetRedeemAddressParams
setRedeemAddressParamsParser = #redeem <.!> addressArgument "Redeem address"

transferOwnershipParamsParser :: Opt.Parser TransferOwnershipParams
transferOwnershipParamsParser = #newOwner
  <.!> addressArgument "Address of the new owner"

startMigrateFromParamsParser :: Opt.Parser StartMigrateFromParams
startMigrateFromParamsParser = #migrationManager <.!>
  (ContractAddr <$> addressArgument "Source contract address")

startMigrateToParamsParser :: Opt.Parser StartMigrateToParams
startMigrateToParamsParser = #migrationManager <.!>
  (ContractAddr <$> addressArgument "Manager contract address")

-- Maybe add default value and make sure it will be shown in help message.
maybeAddDefault :: Opt.HasValue f => (a -> String) -> Maybe a -> Opt.Mod f a
maybeAddDefault printer = maybe mempty addDefault
  where
    addDefault v = value v <> showDefaultWith printer

-- The following, HasReader/HasParser typeclasses are used to generate
-- parsers for a named fields with options name and metavars derived from
-- the name of the field itself.
--
-- | Supporting typeclass for HasParser.
class HasReader a where
  getReader :: Opt.ReadM a

instance HasReader Natural where
  getReader = auto

instance HasReader Int where
  getReader = auto

instance HasReader Text where
  getReader = str

instance HasReader Address where
  getReader = eitherReader parseAddrDo

-- | Typeclass used to define general instance for named fields
class HasParser a where
  getParser :: String -> Opt.Parser a

instance
  (HasReader a, KnownSymbol name) =>
    HasParser ((name :: Symbol) :! a)  where
  getParser hInfo =
    let
      name = (symbolVal (Proxy @name))
    in option ((Name @name) <.!> getReader) $
         mconcat [ long name , metavar (toUpper <$> name), help hInfo ]

testScenarioOptions :: Opt.Parser TestScenarioOptions
testScenarioOptions = TestScenarioOptions <$>
  addressArgument "Owner's address" <*>
  outputOption <*>
  (many $ addressOption Nothing "Other owned addresses")

addressOption :: Maybe Address -> String -> Opt.Parser Address
addressOption defAddress hInfo =
  option (eitherReader parseAddrDo) $
  mconcat
    [ metavar "ADDRESS"
    , long "address"
    , help hInfo
    , maybeAddDefault pretty defAddress
    ]

namedAddressOption :: Maybe Address -> String -> String -> Opt.Parser Address
namedAddressOption defAddress name hInfo = option (eitherReader parseAddrDo) $
  mconcat
    [ metavar "ADDRESS"
    , long name
    , help hInfo
    , maybeAddDefault pretty defAddress
    ]

addressArgument :: String -> Opt.Parser Address
addressArgument hInfo =
  argument (eitherReader parseAddrDo) $
  mconcat
    [ metavar "ADDRESS", help hInfo
    ]

outputOption :: Opt.Parser (Maybe FilePath)
outputOption = Opt.optional $ Opt.strOption $ mconcat
  [ Opt.short 'o'
  , Opt.long "output"
  , Opt.metavar "FILEPATH"
  , Opt.help "Output file"
  ]

callBackAddressOption :: Opt.Parser (ContractAddr a)
callBackAddressOption = ContractAddr <$> caddr
  where
    caddr = option (eitherReader parseAddrDo) $
      mconcat
        [ metavar "CALLBACK-ADDRESS"
        , long "callback"
        , help "Callback address"
        ]

parseAddrDo :: String -> Either String Address
parseAddrDo addr =
  either (Left . mappend "Failed to parse address: " . pretty) Right $
  parseAddress $ toText addr
