{- SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-MIT-BitcoinSuisse
 -}

{-# LANGUAGE ApplicativeDo #-}

module CLI.Parser
  ( CmdLnArgs (..)
  , VersionArg (..)
  , MigrationArgs (..)
  , addressArgument
  , addressOption
  , argParser
  , mkCommandParser
  , mTextOption
  , parseSingleTokenMetadata
  ) where

import Named (Name(..), arg)
import Options.Applicative
  (ReadM, command, help, hsubparser, info, long, metavar, progDesc, short, switch)
import qualified Options.Applicative as Opt

import Lorentz.Contracts.Metadata
import Michelson.Text
import Morley.CLI
import Tezos.Address (Address)
import Util.CLI
import Util.Named

-- | Represents the Cmd line commands with inputs/arguments.
data CmdLnArgs
  = CmdPrintInitialStorage Address
  | CmdPrintContract Bool (Maybe FilePath)
  | CmdPrintMultisigContract Bool Bool (Maybe FilePath)
  | CmdPrintDoc VersionArg (Maybe FilePath)
  | CmdParseParameter VersionArg Text
  | CmdTestScenario VersionArg ("verbosity" :! Word) ("dryRun" :! Bool)
  | CmdMigrate ("output" :! Maybe FilePath) MigrationArgs

data VersionArg
  = V0
  | V1
  | V2
  deriving stock (Show)

data MigrationArgs
  = MigrateV1
      ("redeemAddress" :! Address)
      ("tokenMetadata" :! TokenMetadata)
  | MigrateV2
      ("redeemAddress" :! Address)
      ("tokenMetadata" :! TokenMetadata)
  | MigrateV2FromV1

argParser :: Opt.Parser CmdLnArgs
argParser = hsubparser $
  printCmd <> printMultisigCmd
  <> printInitialStorageCmd <> printDoc
  <> parseParameterCmd <> testScenarioCmd <> migrateCmd
  where
    singleLineSwitch = onelineOption
    printCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    printCmd =
      (mkCommandParser
        "printContract"
        (CmdPrintContract <$> singleLineSwitch <*> outputOption)
        "Print token contract (V0 version)")
    printMultisigCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    printMultisigCmd =
      (mkCommandParser
        "printMultisigContract"
        (CmdPrintMultisigContract <$> singleLineSwitch <*> customErrorsFlag <*> outputOption)
        "Print multisig contract")
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
            <$> addressOption Nothing
            (#name .! "owner-address") (#help .! "Owner's address")
         )
         "Print initial contract storage with the given owner and \
         \redeem addresses")
    printDoc :: Opt.Mod Opt.CommandFields CmdLnArgs
    printDoc =
      (mkCommandParser
        "printContractDoc"
        (CmdPrintDoc <$> versionOption <*> outputOption)
        "Print tzbtc contract documentation")
    parseParameterCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    parseParameterCmd =
      (mkCommandParser
          "parseContractParameter"
          (CmdParseParameter <$> versionOption <*> Opt.strArgument mempty)
          "Parse contract parameter to Lorentz representation")
    testScenarioCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    testScenarioCmd =
      (mkCommandParser
          "testScenario"
          (CmdTestScenario
             <$> versionOption
             <*> (#verbosity <.!> genericLength <$> many verbositySwitch)
             <*> (#dryRun <.!> dryRunSwitch))
          "Do smoke tests")
    migrateCmd :: Opt.Mod Opt.CommandFields CmdLnArgs
    migrateCmd =
      mkCommandParser
          "migrate"
          (CmdMigrate
            <$> (#output <.!> outputOption)
            <*> (hsubparser
                  (mconcat
                    [ migrateV1Cmd
                    , migrateV2Cmd
                    , migrateV2FromV1Cmd
                    ])
                  <|> migrateV1Parser
                )
          )
          "Print migration scripts. When version is unspecified, v1 is used."
    migrateV1Parser =
      MigrateV1
          <$> namedParser Nothing "Redeem address"
          <*> fmap (#tokenMetadata .!) parseSingleTokenMetadata
    migrateV1Cmd :: Opt.Mod Opt.CommandFields MigrationArgs
    migrateV1Cmd =
      mkCommandParser
        "v1"
        (MigrateV1
          <$> namedParser Nothing "Redeem address"
          <*> fmap (#tokenMetadata .!) parseSingleTokenMetadata
        )
        "Migration from V0 to V1."
    migrateV2Cmd :: Opt.Mod Opt.CommandFields MigrationArgs
    migrateV2Cmd =
      mkCommandParser
        "v2"
        (MigrateV2
          <$> namedParser Nothing "Redeem address"
          <*> fmap (#tokenMetadata .!) parseSingleTokenMetadata
        )
        "Migration from V0 to V2."
    migrateV2FromV1Cmd :: Opt.Mod Opt.CommandFields MigrationArgs
    migrateV2FromV1Cmd =
      mkCommandParser
        "v1-to-v2"
        (pure MigrateV2FromV1)
        "Migration from V1 to V2."
    versionOption =
      Opt.option versionReadM
        (long "version" <>
         help "Contract version." <>
         metavar "NUMBER" <>
         Opt.value V1 <>
         Opt.showDefaultWith (\_ -> "1"))
    verbositySwitch =
      Opt.flag' ()
                (short 'v' <>
                 long "verbose" <>
                 help "Increase verbosity (pass several times to increase further)")
    dryRunSwitch =
      switch (long "dry-run" <>
              help "Don't run tests over a real network.")

mkCommandParser
  :: String
  -> Opt.Parser a
  -> String
  -> Opt.Mod Opt.CommandFields a
mkCommandParser commandName parser desc =
  command commandName $ info parser $ progDesc desc

addressArgument :: String -> Opt.Parser Address
addressArgument hInfo = mkCLArgumentParser Nothing (#help .! hInfo)

versionReadM :: ReadM VersionArg
versionReadM = eitherReader $ \case
  "0" -> pure V0
  "1" -> pure V1
  "2" -> pure V2
  other -> Left $ "Unknown version identifier " <> show other

-- | Parse `TokenMetadata` for a single token, with no extras
parseSingleTokenMetadata :: Opt.Parser TokenMetadata
parseSingleTokenMetadata = do
  tmTokenId <-
    pure singleTokenTokenId
  tmSymbol <-
    arg (Name @"token-symbol") <$> namedParser (Just [mt|TZBTC|])
      "Token symbol, as described in TZIP-12."
  tmName <-
    arg (Name @"token-name") <$> namedParser (Just [mt|Tezos BTC|])
      "Token name, as in TZIP-12."
  tmDecimals <-
    arg (Name @"token-decimals") <$> namedParser (Just 0)
      "Number of decimals token uses, as in TZIP-12."
  tmExtras <-
    pure mempty
  return TokenMetadata{..}
