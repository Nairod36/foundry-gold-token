// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
/**
 * @title ILottery
 * @notice Interface du contrat de loterie qui gère la réception de frais et la logique de loterie
 * intégrant notamment Chainlink VRF pour l'aléatoire.
 */
interface ILottery {
    /**
     * @notice Permet de recevoir un montant de frais en provenance du contrat de token.
     * @param feeAmount Le montant de frais à recevoir.
     */
    function receiveFee(uint256 feeAmount) external;
}