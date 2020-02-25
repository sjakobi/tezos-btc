{- SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-Proprietary
 -}
module CLI.Parser
  ( CmdLnArgs(..)
  , TestScenarioOptions(..)
  , HasParser(..)
  , addressArgument
  , addressOption
  , mTextOption
  , argParser
  , mkCommandParser
  , namedAddressOption
  ) where

import GHC.TypeLits (KnownSymbol, Symbol, symbolVal)

import Data.Char (toUpper)
import Fmt (Buildable, pretty)
import Named (Name(..))
import Options.Applicative
  (argument, auto, command, eitherReader, help, hsubparser, info, long, metavar, option, progDesc,
  showDefaultWith, str, switch, value)
import qualified Options.Applicative as Opt

import Lorentz ((:!))
import Michelson.Text (MText, mkMText, mt)
import Tezos.Address (Address, parseAddress)
import Util.Named

-- | Represents the Cmd line commands with inputs/arguments.
data CmdLnArgs
  = CmdPrintInitialStorage Address
  | CmdPrintContract Bool (Maybe FilePath)
  | CmdPrintMultisigContract Bool Bool (Maybe FilePath)
  | CmdPrintDoc (Maybe FilePath)
  | CmdParseParameter Text
  | CmdTestScenario TestScenarioOptions
  | CmdMigrate
      ("version" :! Natural)
      ("redeemAddress" :! Address)
      ("tokenName" :! MText)
      ("tokenCode" :! MText)
      ("output" :! Maybe FilePath)

data TestScenarioOptions = TestScenarioOptions
  { tsoMaster :: !Address
  , tsoOutput :: !(Maybe FilePath)
  , tsoAddresses :: ![Address]
  }

argParser :: Opt.Parser CmdLnArgs
argParser = hsubparser $
  printCmd <> printMultisigCmd
  <> printInitialStorageCmd <> printDoc
  <> parseParameterCmd <> testScenarioCmd <> migrateCmd
  where
    singleLineSwitch =
            switch (long "oneline" <> help "Single line output")
    printCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    printCmd =
      (mkCommandParser
        "printContract"
        (CmdPrintContract <$> singleLineSwitch <*> outputOption)
        "Print token contract")
    printMultisigCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    printMultisigCmd =
      (mkCommandParser
        "printMultisigContract"
        (CmdPrintMultisigContract <$> singleLineSwitch <*> customErrorsFlag <*> outputOption)
        "Print token contract")
      where
        customErrorsFlag = switch
          (long "use-custom-errors" <>
           help "By default the multisig contract fails with 'unit' in all error cases.\n\
                \This flag will deploy the custom version of multisig\n\
                \contract with human-readable string errors.")
    printInitialStorageCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    printInitialStorageCmd =
      (mkCommandParser
         "printInitialStorage"
         (CmdPrintInitialStorage
            <$> namedAddressOption Nothing "owner-address" "Owner's address")
         "Print initial contract storage with the given owner and \
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
    migrateCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    migrateCmd =
      (mkCommandParser
          "migrate"
          (CmdMigrate
            <$> getParser Nothing "Target version"
            <*> getParser Nothing "Redeem address"
            <*> getParser (Just $ #tokenName .! [mt|TZBTC|]) "Token name"
            <*> getParser (Just $ #tokenCode .! [mt|TZBTC|]) "Token code"
            <*> (#output <.!> outputOption))
          "Print migration scripts.")

mkCommandParser
  :: String
  -> Opt.Parser a
  -> String
  -> Opt.Mod Opt.CommandFields a
mkCommandParser commandName parser desc =
  command commandName $ info parser $ progDesc desc

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

instance HasReader MText where
  getReader = eitherReader (first toString . mkMText . toText)

instance HasReader Address where
  getReader = eitherReader parseAddrDo

-- | Typeclass used to define general instance for named fields
class HasParser a where
  getParser :: Maybe a -> String -> Opt.Parser a

instance
  (Buildable a, HasReader a, KnownSymbol name) =>
    HasParser ((name :: Symbol) :! a)  where
  getParser defValue hInfo =
    let
      name = (symbolVal (Proxy @name))
    in option ((Name @name) <.!> getReader) $
         mconcat
         [ long name
         , metavar (toUpper <$> name)
         , help hInfo
         , maybeAddDefault pretty defValue
         ]

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

mTextOption :: Maybe MText -> String -> String -> Opt.Parser MText
mTextOption defValue name hInfo =
  option getReader $
  mconcat
    [ metavar "MICHELSON STRING"
    , long name
    , help hInfo
    , maybeAddDefault pretty defValue
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

parseAddrDo :: String -> Either String Address
parseAddrDo addr =
  either (Left . mappend "Failed to parse address: " . pretty) Right $
  parseAddress $ toText addr
