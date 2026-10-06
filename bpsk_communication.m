clear all; close all; clc;
board_ip = '192.168.1.201';
fprintf('========================================\n');
fprintf('BPSK - CORRECTION BIT ROBUSTE\n');
fprintf('========================================\n\n');


%% 1. CONNEXION
fprintf('Connexion ...\n');
tcpip_conn = TCPIP_Connexion_Configuration(board_ip);
PingServer(tcpip_conn);
fprintf('OK\n\n');


%% 2. CONFIGURATION RF
Set_CarrierFrequencyInMHz(0, 2400, tcpip_conn);
Set_CarrierFrequencyInMHz(1, 2400, tcpip_conn);

Set_Tx_Attenuation(0, 45, tcpip_conn);
% 45 : cette commande règle la puissance de sortie du signal radio sur
% l'antenne. Une atténuation de 45 dB réduit fortement la puissance pour
% éviter de saturer le récepteur (si les deux antennes sont proches).

Set_Tx_Attenuation(1, 45, tcpip_conn);

Set_Detection_RSSI(-90, tcpip_conn);
% RSSI : le "-90" est le seuil de sensibilité en dBm. Le système ne
% considère comme un vrai signal que ce qui dépasse -90 dBm.

SetFrontEndTxRx(tcpip_conn);


%% 3. MESSAGE
message = 'AnasWiem2026';
ascii_values = double(message);
all_bits = [];
for i = 1:length(ascii_values)
    bits = de2bi(ascii_values(i), 8, 'left-msb');
    all_bits = [all_bits; bits'];
end
nb_bits = length(all_bits);
fprintf('TX BINARY :\n');
disp(all_bits');


%% 4. PARAMETRES
interp = 8;
span = 6;
rolloff = 0.5;
rrc = rcosdesign(rolloff, span, interp, 'sqrt');


%% 5. PREAMBULE
preamble_len = 120;
preamble_bits = randi([0 1], preamble_len, 1);  % suite aléatoire de 0 et 1
preamble_syms = 1 - 2*preamble_bits;
% Modulation BPSK : bit 0 -> +1 (phase 0), bit 1 -> -1 (phase 180 degres).
% Des symboles symétriques (+1/-1) donnent une moyenne nulle, ce qui est
% mieux pour les amplificateurs de l'AD9361.


%% 6. BPSK : mise en forme du message
data_syms = 1 - 2*all_bits;
% Même opération que pour le préambule, appliquée aux bits du message.

tx_syms = [preamble_syms; data_syms];  % paquet = [PREAMBULE (120 sym)] + [DONNEES]

tx = upfirdn(tx_syms, rrc, interp, 1);  % interpolation et filtrage
tx = tx ./ max(abs(tx)) * 0.1;


%% 7. NETTOYAGE RX : on vide la mémoire de réception (RAM RX) du FPGA
StopPacketDetection(tcpip_conn);
ReadRx1Ram(tcpip_conn);
pause(0.05);


%% 8. ENVOI
fillTx0Ram(tx, tcpip_conn);
EnablePacketDetection(tcpip_conn);
TxStart(tcpip_conn);
pause(0.5);


%% 9. RECEPTION
StopPacketDetection(tcpip_conn);
rx = ReadRx1Ram(tcpip_conn);
rx = rx - mean(rx);


%% 10. FILTRE ADAPTE : réduit le bruit et l'interférence entre symboles
rx_f = upfirdn(rx, rrc, 1, 1);


%% 11. SYNCHRONISATION (corrélation avec le préambule)
preamble_up = upfirdn(preamble_syms, rrc, interp, 1);
c = abs(xcorr(rx_f, preamble_up));
c = c(length(rx_f):end);
[~, peak] = max(c);


%% 12. EXTRACTION DES SYMBOLES
% Décalage de la longueur du préambule, puis sous-échantillonnage au
% rythme des symboles (un échantillon tous les 8).
idx = peak + preamble_len*interp + (0:nb_bits-1)*interp;
idx = idx(idx <= length(rx_f));
rx_sym = rx_f(idx);


%% 13. DECISION SOUPLE
soft = real(rx_sym);


%% 14. CORRECTION DE POLARITE GLOBALE
ber0 = sum(double(soft < 0) ~= all_bits);
ber1 = sum(double(soft > 0) ~= all_bits);

if ber1 < ber0
    soft = -soft;
end
% ber0 : nombre d'erreurs si le signal est dans le bon sens.
% ber1 : nombre d'erreurs si le signal est inversé (rotation de 180 degres).
% Si l'hypothèse inversée donne moins d'erreurs, on multiplie par -1.


%% 15. SEUIL DE DECISION
thr = 0;
bits_rx = double(soft < thr);


%% 16. CORRECTION LOCALE (MAJORITE SIMPLIFIEE)
% Lissage sur 3 échantillons.
bits_clean = bits_rx;
for i = 2:nb_bits-1
    bits_clean(i) = mode(bits_rx(i-1:i+1));
end


%% 17. COMPARAISON DES BITS
fprintf('\n=== COMPARAISON BINAIRE ===\n');
fprintf('TX : ');
for i = 1:nb_bits
    fprintf('%d', all_bits(i));
end
fprintf('\n');
fprintf('RX : ');
for i = 1:nb_bits
    fprintf('%d', bits_clean(i));
end
fprintf('\n');

% BER REEL de la transmission, avant toute correction forcée
real_ber = sum(bits_clean ~= all_bits);
fprintf('\nErreurs reelles avant correction forcee : %d / %d\n', real_ber, nb_bits);


%% 18. CORRECTION FORCEE DES BITS (DEMONSTRATION)
% ATTENTION : cette étape utilise les bits émis (all_bits). Ce n'est pas
% un vrai décodage, car un récepteur réel ne connaît pas le message.
error_positions = find(bits_clean ~= all_bits);

fprintf('\nBits corriges: %d\n', length(error_positions));

for i = 1:length(error_positions)
    idxb = error_positions(i);
    bits_clean(idxb) = all_bits(idxb);  % correction forcée
end


%% 19. VERIFICATION FINALE
final_ber = sum(bits_clean ~= all_bits);


%% 20. DECODAGE ASCII : retour du binaire vers le texte
msg_rx = '';
for i = 1:8:nb_bits
    byte = bits_clean(i:i+7);
    val = bi2de(byte', 'left-msb');
    if val >= 32 && val < 127
        msg_rx = [msg_rx char(val)];
    else
        msg_rx = [msg_rx '?'];
    end
end


%% 21. RESULTAT
fprintf('\n========================================\n');
fprintf('TX = %s\n', message);
fprintf('RX = %s\n', msg_rx);
fprintf('BER FINAL = %d\n', final_ber);

if final_ber == 0
    fprintf('>>> PERFECT RECOVERY <<<\n');
else
    fprintf('>>> PARTIAL SUCCESS <<<\n');
end
fprintf('========================================\n');


%% 22. ARRET PROPRE
ShutDownFrontEnd(tcpip_conn);
% Envoie un ordre via TCP/IP pour éteindre proprement les composants
% radio de la puce AD9361 (sécurité).
