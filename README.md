# Collar Protocol Core

Collar Protocol is a lending protocol that enables liquidation-free and high LTV borrowing against crypto assets by combining dex swaps and options-like payoff structures.

# For Auditors

[Audit briefing notes](./devdocs/audits.briefing.md)

## Setup

This repo primarily uses forge for development. See [foundry specific commands here](./devdocs/FOUNDRY.md).

Tests are run automatically via [GitHub Actions](https://github.com/CollarNetworks/protocol-core/actions) on every push & pr. This configuration can be found in [.github/workflows/test.yml](.github/workflows/test.yml). Consider installing the VSCode [GitHub Actions extension](https://marketplace.visualstudio.com/items?itemName=cschleiden.vscode-github-actions) for a better experience.

## Documentation

Solidity docs can be created from [Solidity NatSpec](https://docs.soliditylang.org/en/latest/style-guide.html#natspec) via the [forge doc command](https://book.getfoundry.sh/reference/forge/forge-doc#forge-doc). You can run this docgen locally via `forge doc --build`

Developer docs are contained in the [devdocs folder](./devdocs/), but are currently outdated.

Docs on how to run the local devleopment scripts can be found in [script/readme.md](./script/readme.md).
