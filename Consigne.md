Exam 5IBC 2025:
Par groupe de 2, vous devez faire un token ERC20 dont le prix est calqué sur l'OR.

Un utilisateur doit pouvoir minter un nombre x de token d'or selon le nombre d'ether envoyé à la fonction de mint.
Le ratio d'or par token est de 1token/gr d'or.

Vous utiliserez chainlink Data Feed pour avoir le prix de l'or:
https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1&search=gold

A chaque mint et burn, des frais de 5% seront déduit du wallet de l'utilisateur. 50% de ces frais constitueront une lotterie dont vous etes libre de la logique. L'utilisation de chainlink VRF est demandé dans cette lotterie.


L'utilisateur doit etre capable de bridger ses token d'Ethereum vers et depuis Binance Smart Chain grace à CCIP.
L'implémentation doit elle rester sur Ethereum.


Rendu:
Projet Foundry
Test sur forked mainnet le plus proche de 100% coverage
Test incluant des mocks sur chain local
Détéction automatique de la chain utilisé lors des tests et autre
Script de déploiement et de vérification
Script d'utilisation du protocol
Natspec sur chaque smart contract + documentation
ReadMe propre 
Bonus UUPS
Bonus Safe Wallet