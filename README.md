# Collar Protocol Core

## Setup

This repo primarily uses forge for development. See [foundry specific commands here](./FOUNDRY.md).

Tests are run automatically via [GitHub Actions](https://github.com/CollarNetworks/protocol-core/actions) on every push & pr. This configuration can be found in [.github/workflows/test.yml](.github/workflows/test.yml). Consider installing the VSCode [GitHub Actions extension](https://marketplace.visualstudio.com/items?itemName=cschleiden.vscode-github-actions) for a better experience.

## Documentation

Solidity docs are automatically created from [Solidity NatSpec](https://docs.soliditylang.org/en/latest/style-guide.html#natspec) via the [forge doc command](https://book.getfoundry.sh/reference/forge/forge-doc#forge-doc) and are automatically regenerated via Github Actions on every PR. This configuration can be found in [.github/workflows/tests-and-docgen.yml](.github/workflows/doc.yml). You can run this docgen locally via `forge doc --build`