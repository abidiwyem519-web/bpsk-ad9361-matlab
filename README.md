# Système de communication BPSK sur AD9361

Transmission d'un message texte (`AnasWiem2026`) en modulation BPSK avec une carte radio AD9361, programmée sous MATLAB.

## Fonctionnement

Message → bits ASCII → préambule + symboles BPSK → filtre RRC → émission →
réception → filtre adapté → synchronisation par corrélation → décision → texte.

## Prérequis

- MATLAB avec la Communications Toolbox
- Carte AD9361 (adresse IP configurée dans `board_ip`)
- Bibliothèque de fonctions de la carte (`TCPIP_Connexion_Configuration`, `fillTx0Ram`, `TxStart`, etc.), **non incluse** dans ce dépôt

## Utilisation

1. Brancher la carte et vérifier son adresse IP.
2. Modifier `board_ip` dans `bpsk_communication.m` si besoin.
3. Lancer le script sous MATLAB.

## Remarque

L'étape 18 (« correction forcée des bits ») sert uniquement de démonstration : elle utilise les bits émis. Le nombre d'erreurs réelles de la transmission est affiché juste avant.

## Auteurs

Anas et Wiem
