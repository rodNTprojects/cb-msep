# Compléter les graphes — extraire sur ~/cbmsep-net, réseau déployé + brique A jouée
pip install matplotlib   # une fois

bash scripts/test_phase7.sh            # progression en direct ; CSV data/phase7_overhead_results.csv
python3 scripts/plot_overhead.py

bash scripts/test_phase7_throughput.sh # progression en direct ; CSV data/phase7_throughput_results.csv
python3 scripts/plot_throughput.py

# Chaque harnais fait d'abord un PREFLIGHT : une attestation de test. S'il échoue,
# il affiche l'erreur réelle et s'arrête au lieu de tourner en silence.
