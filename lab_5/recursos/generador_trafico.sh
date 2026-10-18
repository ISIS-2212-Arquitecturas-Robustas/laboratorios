#!/usr/bin/env bash
# Generador de tráfico de estado estable para los experimentos de caos del Lab 5.
#
# Envía tráfico bajo y CONSTANTE (lazo abierto): cada petición sale en segundo plano,
# así que la tasa no baja aunque el sistema se vuelva lento. No es una prueba de carga:
# la carga es la misma en todos los experimentos; lo que cambia es el fallo inyectado.
#
# Uso:
#   BASE_URL=https://<API_ID>.execute-api.us-east-1.amazonaws.com/lab ./generador_trafico.sh tormenta_completa.csv
#
# Variables opcionales:
#   RATE        ventas por segundo a POST /ventas/ventas (por defecto 2)
#   EXTRA_EVERY cada cuántos segundos se consultan los demás endpoints (por defecto 5)
#   VENTA_JSON  cuerpo de la venta (por defecto venta.json)
#   ITEM_ID     ítem de inventario a consultar (por defecto el del seed)
#   VENTA_URL, LOGISTICA_URL, INVENTARIO_URL, CATALOGO_URL  para sobrescribir cada endpoint
#                (por ejemplo, para correr contra Docker Compose en local)
#
# Salida (CSV): ts,endpoint,http_code,latencia_s,pending
#   pending = 1 si la respuesta trae status: pending_stock_confirmation
# Detenga el generador de tráfico con Ctrl+C.

set -u

OUT="${1:?Indique el archivo CSV de salida, p. ej. ./generador_trafico.sh estado_estable.csv}"
RATE="${RATE:-2}"
EXTRA_EVERY="${EXTRA_EVERY:-5}"
VENTA_JSON="${VENTA_JSON:-venta.json}"
ITEM_ID="${ITEM_ID:-11111111-1111-4111-8111-111111111111}"

VENTA_URL="${VENTA_URL:-${BASE_URL:?Defina BASE_URL}/ventas/ventas}"
LOGISTICA_URL="${LOGISTICA_URL:-${BASE_URL}/logistica/health}"
INVENTARIO_URL="${INVENTARIO_URL:-${BASE_URL}/inventario/items/${ITEM_ID}}"
CATALOGO_URL="${CATALOGO_URL:-${BASE_URL}/ventas/productos-externos}"

[ -f "$VENTA_JSON" ] || { echo "No existe $VENTA_JSON" >&2; exit 1; }

echo "ts,endpoint,http_code,latencia_s,pending" > "$OUT"

# Una petición: registra la hora de ENVÍO (no la de respuesta) para poder ubicar
# cada resultado frente a T_inj y T_rem.
probe() {
  local name="$1" method="$2" url="$3" ts body meta code lat pending
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [ "$method" = POST ]; then
    body=$(curl -s --max-time 30 -w '\n%{http_code} %{time_total}' -X POST "$url" \
      -H 'Content-Type: application/json' -d @"$VENTA_JSON")
  else
    body=$(curl -s --max-time 30 -w '\n%{http_code} %{time_total}' "$url")
  fi
  meta=$(printf '%s' "$body" | tail -n 1)
  code=${meta% *}
  lat=${meta#* }
  case "$body" in *pending_stock_confirmation*) pending=1 ;; *) pending=0 ;; esac
  echo "$ts,$name,$code,$lat,$pending" >> "$OUT"
}

trap 'wait; echo; echo "Generador de tráfico detenido. Resultados en $OUT"; exit 0' INT TERM

interval=$(awk "BEGIN { print 1 / $RATE }")
start=$(date +%s)
last_extra=0
echo "Generador de tráfico en marcha: $RATE ventas/s, otros endpoints cada ${EXTRA_EVERY}s → $OUT (Ctrl+C para detener)"
while true; do
  probe venta POST "$VENTA_URL" &
  now=$(date +%s)
  if [ $((now - last_extra)) -ge "$EXTRA_EVERY" ]; then
    last_extra=$now
    probe logistica_health GET "$LOGISTICA_URL" &
    probe inventario_item GET "$INVENTARIO_URL" &
    probe catalogo GET "$CATALOGO_URL" &
  fi
  sleep "$interval"
done
