#!/usr/bin/env python3
"""Agrupa el CSV de generador_trafico.sh en ventanas de tiempo (Lab 5).

Uso:
    python3 ventanas.py tormenta_local_sin_sidecar.csv            # ventanas de 10 s
    python3 ventanas.py tormenta_local_sin_sidecar.csv --ventana 5 --umbral 3

Imprime, por ventana y por endpoint: peticiones, disponibilidad percibida
(respuestas útiles / total; útil = 2xx, incluidas las 201 con
pending_stock_confirmation, respondida en menos de --umbral segundos),
% de respuestas pending y p99 de latencia. Genera además <archivo>_ventanas.csv
para graficar la línea de tiempo en una hoja de cálculo.

Solo resume los datos: decidir qué es el estado estable, cuándo se desvió y
cuándo se recuperó es parte de su análisis.
"""
import argparse
import csv
import math
from collections import defaultdict
from datetime import datetime, timezone


def p99(valores):
    if not valores:
        return float("nan")
    orden = sorted(valores)
    return orden[max(0, math.ceil(0.99 * len(orden)) - 1)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("archivo")
    parser.add_argument("--ventana", type=int, default=10, help="segundos por ventana")
    parser.add_argument("--umbral", type=float, default=3.0,
                        help="latencia máxima (s) para contar una respuesta 2xx como útil")
    args = parser.parse_args()

    grupos = defaultdict(list)
    with open(args.archivo, newline="") as f:
        for fila in csv.DictReader(f):
            ts = datetime.strptime(fila["ts"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            inicio = int(ts.timestamp()) // args.ventana * args.ventana
            grupos[(inicio, fila["endpoint"])].append(fila)

    salida = args.archivo.rsplit(".", 1)[0] + "_ventanas.csv"
    with open(salida, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["ventana_utc", "endpoint", "peticiones", "disponibilidad_pct", "pending_pct", "p99_s"])
        print(f"{'ventana (UTC)':<10} {'endpoint':<17} {'n':>4} {'disp %':>7} {'pend %':>7} {'p99 s':>7}")
        for (inicio, endpoint), filas in sorted(grupos.items()):
            n = len(filas)
            ok = sum(1 for r in filas
                     if r["http_code"].startswith("2") and float(r["latencia_s"]) < args.umbral)
            pend = sum(1 for r in filas if r["pending"] == "1")
            lat = [float(r["latencia_s"]) for r in filas]
            hora = datetime.fromtimestamp(inicio, timezone.utc).strftime("%H:%M:%S")
            disp, pp, q = 100 * ok / n, 100 * pend / n, p99(lat)
            w.writerow([hora, endpoint, n, f"{disp:.1f}", f"{pp:.1f}", f"{q:.3f}"])
            print(f"{hora:<10} {endpoint:<17} {n:>4} {disp:>7.1f} {pp:>7.1f} {q:>7.3f}")
    print(f"\nTabla por ventanas guardada en {salida}")


if __name__ == "__main__":
    main()
