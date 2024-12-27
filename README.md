# Gold Token Project

Ce projet implémente :

- **Un token ERC20 indexé sur l'or** (via [Chainlink Price Feeds](https://docs.chain.link/data-feeds/price-feeds)).
- **Un système de loterie** utilisant [Chainlink VRF](https://docs.chain.link/vrf).
- **Un pont cross-chain** utilisant [Chainlink CCIP](https://docs.chain.link/ccip).

## Fonctionnalités

1. **Mint** de GLD en échange d'ETH (avec un ratio basé sur XAU/USD et ETH/USD).
2. **Burn** de GLD (avec 5% de frais).
3. **Frais** de 5% sur mint et burn, envoyés à la loterie.
4. **Loterie** décentralisée basée sur Chainlink VRF.
5. **Bridge** cross-chain pour déplacer les tokens GLD vers la BSC.

## Installation

```bash
git clone ...
cd foundry-gold-token
forge install
