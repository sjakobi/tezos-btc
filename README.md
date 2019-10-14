<!--
 - SPDX-FileCopyrightText: 2019 Bitcoin Suisse
 -
 - SPDX-License-Identifier: LicenseRef-Proprietary
 -->

# ZBTC

Wrapped Bitcoin on Tezos Blockchain called ZBTC


## Build Instructions [↑](#ZBTC)

`stack build`

## Usage [↑](#ZBTC)

Run `stack test` and explore the tests.


### `tzbtc` executable


You can use `tzbtc` executable in order to get contract code converted
to Michelson, raw Michelson contract storage. This stuff can be used for
contract origination via `tezos-client`. Also you can print other contracts
that are used along with TZBTC contract: agent, proxy.
`parseContractParameter` subcommand can be used for debugging,
it parses raw Michelson value to the TZBTC contract parameter.

Use `tzbtc --help` to get a list of available commands.

### `tzbtc-client` executable

Also you can use `tzbtc-client` executable.
This executable performs transactions injection to the chain using remote
tezos-node.

Use `tzbtc-client --help` to get a list of available commands.

#### `tzbtc-client` prerequisites

In order to use `tzbtc-client` you will need to obtain `tezos-client`
executable. You can use one (built for alphanet) located in the
`bin/` folder. `tezos-client` is used for key storing, operation signing and
ledger interaction.

#### `tzbtc-client` usage

`setupClient` command is required for setting up `tzbtc-client`
environment. It takes information about node, user information
(specifically address and name alias from the `tezos-client`), contract address
and also path to the `tezos-client` executable, which is used for
transaction signing and ledger interaction. The `setupClient` command
can be called without any values, which places a template config file in
the proper path, filled with placeholders. The `config --edit` command
can be used to edit the config values in the file. When called with no
arguments, `config --edit` command will open an editor (Not available in
windows), with the config contents. After saving the content and
closing the editor, the config file will be updated with the new
contents.

Other commands will perform injection of desired transaction to the
TZBTC contract. E.g. `tzbtc-client mint --to tz1U1h1YzBJixXmaTgpwDpZnbrYHX3fMSpvby --value 100500`
will mint 100500 tokens to the `tz1U1h1YzBJixXmaTgpwDpZnbrYHX3fMSpvby` address.
This command will change actual contract storage in the chain.

`tzbtc-client` interacts with the tezos node using [RPC API](https://tezos.gitlab.io/master/api/rpc.html).
Transaction forging takes place in several stages:

* Get latest block hash, in which our transaction is going to be injected.
* Get sender counter, so that we can construct correct transaction.
* Dry-run this transaction in order to get estimated consumed gas and storage size.
Also, on this stage transaction correctness is ensured.
* Forge transaction with estimated consumed gas, storage size and fee.
* Sign the transaction using `tezos-client`. If your secret key is stored on the
ledger, you will have to open `Tezos Wallet` app and confirm this signing on
your device.
* Inject signed operation using hexademical representation and signature obtained
on the previous steps.


So the workflow for interacting with the TZBTC contract on the chain is the following:
* Use `tzbtc-client setupClient` to set up the environment.
* Use `tzbtc-client <subcommand>` to submit desired operation.

All `tzbtc-client` commands can be performed with `--dry-run` flag, thus they won't
interact with the chain at all. This flag is basically used for testing purposes in
order to check that argument parser is sane.

Note that instead of plain addresses you can use `tezos-client` aliases as an arguments
in `tzbtc-client`. E.g. `tzbtc-client mint --to alice --value 500` (assuming that
`alice` is an alias for some address in `tezos-client`).

`tzbtc-client` also provides multisig support.

Multisig interaction based on [generic multisig contract](contracts/MultiSigGeneric.tz).
This contract has threshold (minimal required amount of signatures) and list of signers
public keys in its storage.

`tzbtc-client` supports multisig for administrative operations (such as `mint`, `burn`,
`add/removeOperator`, `pause`, `unpause`, `setRedeemAddress`, `transferOwnership`,
`startMigrateTo/From`)
In order to perform these actions make sure, that multisig contract's address is
an admin/operator of the TZBTC contract.

All administrative operations can be performed using multisig.
In order to create multisig package you should provide `--multisig` flag.
E.g. `tzbtc-client pause --multisig`. This command will return encoded multisig package.

You can get operation description from this package using `tzbtc-client getOpDescription` command.

There are two ways to sign multisig package:
* Sign package via `tzbtc-client signPackage --package <package filepath>` command.
Thus given package will be signed by the user configured during `tzbtc-client setupClient`.
* Manually sign package. In order to extract bytes that needs to be signed you should use
`tzbtc-client getBytesToSign` command. After these bytes are signed, the signature can be
added using `tzbtc-client addSignature` command.

Once multisig operation initiator have obtained enough signed packages he can start this
operation using `tzbtc-client callMultisig` command.


## Contract documentation

Contract documentation is located in [ContractDoc.md](ContractDoc.md).

## Issue Tracker [↑](#ZBTC)

We use [YouTrack](https://issues.serokell.io/issues/TBTC)

## For Contributors [↑](#ZBTC)

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for more information.

## License

TODO
