#!/usr/bin/env bash
# Prueba de carga controlada MED-EC: 10, 25, 50 y 100 TPS.
# No modifica chaincode ni 00_lib_pruebas_medec.sh.
# Uso:
#   MODO=piloto ./prueba_carga_controlada_medec.sh
#   MODO=definitiva ./prueba_carga_controlada_medec.sh
#
# Requisitos:
# - Ejecutar desde la raíz del repositorio MED-EC.
# - Tener configurada la identidad de Registro Escolar en la biblioteca existente.
# - Definir PEER_ADDRESSES_CSV y PEER_TLS_ROOTS_CSV como listas CSV paralelas
#   (mismo orden y cantidad), con los peers y sus certificados TLS.
# - Definir REGISTRAR_ARGS_JSON_TEMPLATE si RegistrarInscripcion requiere una
#   firma de argumentos distinta de la predeterminada. La plantilla debe contener
#   el marcador __MATRICULA__ y ser un objeto JSON de Fabric, p. ej.:
#   {"function":"RegistrarInscripcion","Args":["__MATRICULA__","HASH_EVIDENCIA"]}
#
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETWORK_DIR="${NETWORK_DIR:-$SCRIPT_DIR}"
LIB="${LIB_PRUEBAS_MEDec:-$NETWORK_DIR/00_lib_pruebas_medec.sh}"
MODO="${MODO:-piloto}"
CANAL="${CHANNEL_NAME:-uacmchannel}"
CHAINCODE="${CHAINCODE_NAME:-uacm}"
FUNCION="${FUNCION_CARGA:-RegistrarInscripcion}"
TASAS_CSV="${TASAS_TPS:-10,25,50,100}"
N_PILOTO="${N_PILOTO:-100}"
N_DEFINITIVA="${N_DEFINITIVA:-600}"
PREFIJO_MATRICULAS="${PREFIJO_MATRICULAS:-28-011}"
TIMEOUT_TX="${TIMEOUT_TX:-120}"
TOLERANCIA_RITMO_PCT="${TOLERANCIA_RITMO_PCT:-10}"
PAUSA_ENTRE_TASAS="${PAUSA_ENTRE_TASAS:-30}"
RESULTADOS_DIR="${RESULTADOS_DIR:-$NETWORK_DIR/resultados/carga_controlada}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$RESULTADOS_DIR/${MODO}_${RUN_ID}"
mkdir -p "$RUN_DIR"
chmod 700 "$RUN_DIR"

# Procesos trabajadores activos: se usan para limpieza ante interrupciones.
ACTIVE_PIDS=()
cleanup_workers() {
  local rc=$?
  trap - EXIT INT TERM HUP
  if (( rc != 0 )) && (( ${#ACTIVE_PIDS[@]} > 0 )); then
    echo "Interrupción/error: terminando procesos trabajadores activos..." >&2
    kill -TERM "${ACTIVE_PIDS[@]}" 2>/dev/null || true
    # Dar oportunidad de terminar y recolectar los procesos.
    for cleanup_pid in "${ACTIVE_PIDS[@]}"; do
      wait "$cleanup_pid" 2>/dev/null || true
    done
  fi
  exit "$rc"
}
trap cleanup_workers EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

case "$MODO" in piloto) N_TX="$N_PILOTO" ;; definitiva) N_TX="$N_DEFINITIVA" ;;
  *) echo "ERROR: MODO debe ser piloto o definitiva." >&2; exit 2 ;;
esac

if [[ ! -f "$LIB" ]]; then
  echo "ERROR: no encuentro la biblioteca: $LIB" >&2
  echo "Ejecuta desde la raíz del repositorio o define LIB_PRUEBAS_MEDec." >&2
  exit 2
fi
# Se carga la biblioteca existente, sin modificarla.
# shellcheck source=/dev/null
source "$LIB"

command -v peer >/dev/null || { echo "ERROR: peer no está en PATH." >&2; exit 2; }
command -v jq >/dev/null || { echo "ERROR: se requiere jq para construir y validar JSON." >&2; exit 2; }
command -v python3 >/dev/null || { echo "ERROR: se requiere python3." >&2; exit 2; }
command -v flock >/dev/null || { echo "ERROR: se requiere flock para sincronizar el CSV." >&2; exit 2; }

: "${ORDERER_ADDRESS:?Falta ORDERER_ADDRESS (biblioteca o entorno)}"
: "${ORDERER_CA:?Falta ORDERER_CA (biblioteca o entorno)}"
: "${ORDERER_HOSTNAME:?Falta ORDERER_HOSTNAME (biblioteca o entorno)}"
: "${REGISTRO_MSP:?Falta REGISTRO_MSP (biblioteca o entorno)}"
: "${REGISTRO_PEER:?Falta REGISTRO_PEER (biblioteca o entorno)}"
: "${REGISTRO_TLS:?Falta REGISTRO_TLS (biblioteca o entorno)}"
: "${PEER_ADDRESSES_CSV:?Define PEER_ADDRESSES_CSV con los peers de endoso separados por comas}"
: "${PEER_TLS_ROOTS_CSV:?Define PEER_TLS_ROOTS_CSV con los certificados TLS paralelos separados por comas}"

IFS=',' read -r -a PEERS <<< "$PEER_ADDRESSES_CSV"
IFS=',' read -r -a TLS_ROOTS <<< "$PEER_TLS_ROOTS_CSV"
if (( ${#PEERS[@]} == 0 || ${#PEERS[@]} != ${#TLS_ROOTS[@]} )); then
  echo "ERROR: PEER_ADDRESSES_CSV y PEER_TLS_ROOTS_CSV deben tener igual número de elementos." >&2
  exit 2
fi
for i in "${!PEERS[@]}"; do
  [[ -n "${PEERS[$i]}" && -f "${TLS_ROOTS[$i]}" ]] || {
    echo "ERROR: peer/certificado TLS inválido en posición $((i+1)): ${PEERS[$i]} / ${TLS_ROOTS[$i]}" >&2
    exit 2
  }
done
[[ -f "$ORDERER_CA" ]] || { echo "ERROR: ORDERER_CA no existe: $ORDERER_CA" >&2; exit 2; }

if [[ -n "${REGISTRAR_ARGS_JSON_TEMPLATE:-}" ]]; then
  ARGS_TEMPLATE="$REGISTRAR_ARGS_JSON_TEMPLATE"
else
  # IMPORTANTE: confirma que la firma real de RegistrarInscripcion coincide
  # con esta plantilla antes de iniciar incluso el piloto.
  ARGS_TEMPLATE='{"function":"RegistrarInscripcion","Args":["__MATRICULA__"]}'
fi
jq -e --arg m "__MATRICULA__" '.function and (.Args|type=="array") and any(.Args[]; . == $m)' \
  <<<"$ARGS_TEMPLATE" >/dev/null || {
    echo "ERROR: REGISTRAR_ARGS_JSON_TEMPLATE debe ser JSON válido y contener __MATRICULA__ como elemento de Args." >&2
    exit 2
  }

# Configurar la identidad administrativa de Registro Escolar.
TEST_NETWORK="${TEST_NETWORK:-$HOME/hyperledger/fabric-samples/test-network-4org}"

REGISTRO_MSP_PATH="$TEST_NETWORK/organizations/peerOrganizations/registroescolar.uacm.edu.mx/users/Admin@registroescolar.uacm.edu.mx/msp"

if [[ ! -d "$REGISTRO_MSP_PATH" ]]; then
  echo "ERROR: no existe el directorio MSP: $REGISTRO_MSP_PATH" >&2
  exit 2
fi

usar_identidad \
  "$REGISTRO_MSP" \
  "$REGISTRO_MSP_PATH" \
  "$REGISTRO_PEER" \
  "$REGISTRO_TLS"

CSV="$RUN_DIR/transacciones.csv"
SUMMARY="$RUN_DIR/resumen_por_tasa.csv"
LOG="$RUN_DIR/ejecucion.log"
ENVFILE="$RUN_DIR/entorno.txt"
exec > >(tee -a "$LOG") 2>&1

cat > "$CSV" <<'CSVHDR'
modo,tasa_objetivo_tps,n_transaccion,matricula,instante_programado_epoch_ns,instante_inicio_epoch_ns,instante_fin_epoch_ns,retardo_inicio_ms,latencia_desde_inicio_ms,latencia_desde_programacion_ms,rc_cli,estado_commit,txid,resultado,detalle
CSVHDR
cat > "$SUMMARY" <<'SUMHDR'
modo,tasa_objetivo_tps,n_programadas,registros,intentos_registrados,valid,invalid,fallidas_o_no_confirmadas,registros_ausentes,tasa_exito_pct,tps_inicio_observado,tps_valid_sobre_ventana_inicio,latencia_inicio_media_ms,latencia_inicio_p50_ms,latencia_inicio_p95_ms,latencia_programacion_media_ms,retardo_inicio_p95_ms,desviacion_media_intervalo_pct,p95_desviacion_intervalo_pct,ritmo_aceptable
SUMHDR

{
  echo "run_id=$RUN_ID"
  echo "modo=$MODO"
  echo "host=$(hostname)"
  echo "kernel=$(uname -srmo)"
  echo "fecha_utc=$(date -u --iso-8601=seconds)"
  echo "canal=$CANAL"
  echo "chaincode=$CHAINCODE"
  echo "funcion=$FUNCION"
  echo "tasas_tps=$TASAS_CSV"
  echo "n_por_tasa=$N_TX"
  echo "prefijo_matriculas=$PREFIJO_MATRICULAS"
  echo "peer_addresses=$PEER_ADDRESSES_CSV"
  echo "timeout_tx=$TIMEOUT_TX"
  echo "tolerancia_ritmo_pct=$TOLERANCIA_RITMO_PCT"
  echo "args_template=$ARGS_TEMPLATE"
  env | grep -E '^(CORE_PEER_LOCALMSPID|CORE_PEER_ADDRESS|FABRIC_CFG_PATH|ORDERER_ADDRESS|CHANNEL_NAME|CHAINCODE_NAME)=' | sort || true
} > "$ENVFILE"

# No se permite reutilizar resultados anteriores.
# Prefijo con 2 dígitos + 3 dígitos + 4 dígitos: 28-011-0001.
if [[ ! "$PREFIJO_MATRICULAS" =~ ^[0-9]{2}-[0-9]{3}$ ]]; then
  echo "ERROR: PREFIJO_MATRICULAS debe tener formato NN-NNN, p. ej. 28-011." >&2
  exit 2
fi
[[ "$N_TX" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: N_TX debe ser un entero positivo." >&2; exit 2; }
[[ "$TIMEOUT_TX" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: TIMEOUT_TX debe ser un entero positivo." >&2; exit 2; }
[[ "$TOLERANCIA_RITMO_PCT" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: TOLERANCIA_RITMO_PCT debe ser numérica y no negativa." >&2; exit 2; }
[[ "$PAUSA_ENTRE_TASAS" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERROR: PAUSA_ENTRE_TASAS debe ser numérica y no negativa." >&2; exit 2; }
if (( N_TX > 9999 )); then echo "ERROR: N_TX no puede superar 9999 por tasa con este prefijo." >&2; exit 2; fi

# Las cuatro tasas requieren espacios de matrícula disjuntos dentro del mismo prefijo.
# Asigna bloques por tasa: base 0001, 1001, 2001 y 3001. El piloto/definitiva
# comparte los bloques, así que para repetir una campaña debe cambiarse el prefijo.
declare -A BASES=( [10]=1 [25]=1001 [50]=2001 [100]=3001 )
IFS=',' read -r -a TASAS <<< "$TASAS_CSV"
for rate in "${TASAS[@]}"; do
  [[ "$rate" =~ ^(10|25|50|100)$ ]] || { echo "ERROR: tasa no permitida: $rate" >&2; exit 2; }
  (( N_TX + BASES[$rate] - 1 <= 9999 )) || { echo "ERROR: bloque de matrículas excede 4 dígitos para $rate TPS." >&2; exit 2; }
done

echo "Modo: $MODO; transacciones por tasa: $N_TX; tasas: $TASAS_CSV"
echo "Resultados: $RUN_DIR"
echo "ATENCIÓN: validar la firma de RegistrarInscripcion y las matrículas disponibles antes del envío."

# Verificación previa obligatoria: todas las matrículas antes de enviar.
echo "Verificando disponibilidad de todas las matrículas..."
total_ids=0
ids_existentes=0
ids_error=0

for rate_check in "${TASAS[@]}"; do
  for ((i_check=1; i_check<=N_TX; i_check++)); do
    seq_check=$((BASES[$rate_check] + i_check - 1))
    matricula_check="${PREFIJO_MATRICULAS}-$(printf '%04d' "$seq_check")"
    total_ids=$((total_ids + 1))

    if salida_check="$(consultar "$matricula_check" 2>&1)"; then
      echo "OCUPADA: $matricula_check"
      ids_existentes=$((ids_existentes + 1))
    elif grep -Fq "el expediente $matricula_check no existe" <<<"$salida_check"; then
      :
    else
      echo "ERROR DE CONSULTA: $matricula_check" >&2
      echo "$salida_check" >&2
      ids_error=$((ids_error + 1))
    fi
  done
done

echo "Preflight: total=$total_ids; ocupadas=$ids_existentes; errores=$ids_error"

if (( ids_existentes > 0 || ids_error > 0 )); then
  echo "ABORTADO: no se enviarán transacciones." >&2
  exit 2
fi

echo "Preflight aprobado: todas las matrículas están disponibles."

for rate in "${TASAS[@]}"; do
  interval_ns=$((1000000000 / rate))
  echo "=== Inicio tasa objetivo ${rate} TPS; N=$N_TX; intervalo=${interval_ns} ns ==="
  rate_csv="$RUN_DIR/tasa_${rate}tps.csv"
  cat > "$rate_csv" <<'RATEHDR'
tasa,n,matricula,scheduled_ns,start_ns,end_ns,lag_ms,lat_start_ms,lat_sched_ms,rc,status,txid,result,detail
RATEHDR
  # Cronograma de llegada abierto: el instante programado no depende del tiempo
  # que tarde la transacción anterior. Invocaciones simultáneas según la cadencia.
  declare -a pids=()
  rate_start_ns="$(date +%s%N)"
  for ((i=1; i<=N_TX; i++)); do
    seq=$((BASES[$rate] + i - 1))
    matricula="${PREFIJO_MATRICULAS}-$(printf '%04d' "$seq")"
    if [[ ! "$matricula" =~ ^[0-9]{2}-[0-9]{3}-[0-9]{4}$ ]]; then
      echo "ERROR interno: matrícula inválida: $matricula" >&2; exit 2
    fi
    scheduled_ns=$((rate_start_ns + (i-1)*interval_ns))
    # Espera hasta el instante absoluto programado; si se acumula retraso no
    # reprograma la llegada, lo que permite medir la incapacidad del generador.
    now_ns="$(date +%s%N)"
    while (( now_ns < scheduled_ns )); do
      sleep_s="$(awk -v d="$((scheduled_ns-now_ns))" 'BEGIN{printf "%.6f", d/1000000000}')"
      sleep "$sleep_s"
      now_ns="$(date +%s%N)"
    done

    (
      set +e
      start_ns="$(date +%s%N)"
      start_lag_ms="$(awk -v a="$start_ns" -v b="$scheduled_ns" 'BEGIN{printf "%.3f",(a-b)/1000000}')"
      args_json="$(jq -c --arg m "$matricula" '(.Args |= map(if .=="__MATRICULA__" then $m else . end))' <<<"$ARGS_TEMPLATE")"
            cmd=(peer chaincode invoke
           -o "$ORDERER_ADDRESS"
           --ordererTLSHostnameOverride "$ORDERER_HOSTNAME"
           --tls
           --cafile "$ORDERER_CA"
           -C "$CANAL"
           -n "$CHAINCODE"
           -c "$args_json"
           --waitForEvent)

      for j in "${!PEERS[@]}"; do
        cmd+=(--peerAddresses "${PEERS[$j]}"
              --tlsRootCertFiles "${TLS_ROOTS[$j]}")
      done
      output="$(timeout "$TIMEOUT_TX" "${cmd[@]}" 2>&1)"
      rc=$?
      end_ns="$(date +%s%N)"
      lat_start_ms="$(awk -v a="$end_ns" -v b="$start_ns" 'BEGIN{printf "%.3f",(a-b)/1000000}')"
      lat_sched_ms="$(awk -v a="$end_ns" -v b="$scheduled_ns" 'BEGIN{printf "%.3f",(a-b)/1000000}')"
      txid="$(grep -oE 'txid \[[[:xdigit:]]{64}\]' <<<"$output" \
  | head -n1 \
  | sed -E 's/^txid \[([[:xdigit:]]{64})\]$/\1/')"
    if (( rc == 0 )) && [[ ! "$txid" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "ERROR: la invocación no devolvió un TXID válido para $matricula" >&2
  echo "Salida de Fabric: $output" >&2
fi
      if (( rc == 0 )) && grep -Eqi 'Chaincode invoke successful' <<<"$output" &&
         ! grep -Eqi 'committed with status \(INVALID\)|status \(INVALID\)|MVCC_READ_CONFLICT|ENDORSEMENT_POLICY_FAILURE|Error:' <<<"$output"; then
        status="VALID"; result="VALID"
      elif grep -Eqi 'committed with status \(INVALID\)|status \(INVALID\)|MVCC_READ_CONFLICT|ENDORSEMENT_POLICY_FAILURE' <<<"$output"; then
        status="INVALID"; result="FAIL"
      elif (( rc == 124 )); then
        status="TIMEOUT"; result="FAIL"
      else
        status="NO_CONFIRMADO"; result="FAIL"
      fi
      # Una sola sección crítica protege ambos CSV frente a escrituras concurrentes.
      clean_output="$(tr '\n\r\t' '   ' <<<"$output" | sed 's/"/""/g')"
      {
        flock -x 9
        printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
          "$rate" "$i" "$matricula" "$scheduled_ns" "$start_ns" "$end_ns" \
          "$start_lag_ms" "$lat_start_ms" "$lat_sched_ms" "$rc" "$status" "$txid" "$result" "$clean_output" \
          >> "$rate_csv"
        printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
          "$MODO" "$rate" "$i" "$matricula" "$scheduled_ns" "$start_ns" "$end_ns" \
          "$start_lag_ms" "$lat_start_ms" "$lat_sched_ms" "$rc" "$status" "$txid" "$result" "$clean_output" \
          >> "$CSV"
        flock -u 9
      } 9>"$RUN_DIR/csv.lock"
    ) &
    pids+=("$!")
    ACTIVE_PIDS=("${pids[@]}")
  done

  # Esperar todos los workers; el script conserva datos aun si una tx falla.
  failures=0
  for pid in "${pids[@]}"; do wait "$pid" || failures=$((failures+1)); done
  ACTIVE_PIDS=()
  echo "Fin tasa ${rate} TPS. Procesos con error de shell: $failures"
  sleep "$PAUSA_ENTRE_TASAS"

  # Analítica de la tasa desde el CSV específico, excluyendo solo cabecera (no fallas).
  python3 - "$rate_csv" "$MODO" "$rate" "$N_TX" "$TOLERANCIA_RITMO_PCT" "$SUMMARY" <<'PY'
import csv, sys, statistics, math
path, mode, rate, expected_s, tol_s, summary = sys.argv[1:]
expected, tol = int(expected_s), float(tol_s)

with open(path, newline='', encoding='utf-8') as f:
    rows = list(csv.DictReader(f))

valid = sum(1 for r in rows if r.get('status') == 'VALID')
invalid = sum(1 for r in rows if r.get('status') == 'INVALID')
records = len(rows)
# Esto es el número de intentos con una fila registrada, no una garantía
# de que el sistema operativo haya llegado a iniciar todos los procesos.
attempts = sum(1 for r in rows if r.get('rc', '') != '')
missing = max(0, expected - records)
failed = sum(1 for r in rows if r.get('status') != 'VALID')

def nums(key):
    out = []
    for r in rows:
        try:
            value = float(r[key])
            if math.isfinite(value):
                out.append(value)
        except (ValueError, KeyError, TypeError):
            pass
    return out

lat_start = nums('lat_start_ms')
lat_sched = nums('lat_sched_ms')
lags = nums('lag_ms')
starts = nums('start_ns')
ends = nums('end_ns')

interval_ms = 1000.0 / float(rate)
starts_sorted = sorted(starts)
actual_intervals = [(b-a)/1e6 for a, b in zip(starts_sorted, starts_sorted[1:])]
mean_interval = statistics.mean(actual_intervals) if actual_intervals else float('nan')
deviation = abs(mean_interval - interval_ms) / interval_ms * 100 if actual_intervals else float('inf')
# P95 de la desviación absoluta de cada intervalo respecto al intervalo objetivo.
interval_deviations = [abs(x - interval_ms) / interval_ms * 100 for x in actual_intervals]
def percentile(a, p):
    if not a:
        return float('nan')
    a = sorted(a)
    return a[max(0, math.ceil(p * len(a)) - 1)]

p95_interval_deviation = percentile(interval_deviations, .95)
# La aceptación exige cobertura completa, una fila por intento, y tanto
# promedio como P95 de desviación dentro de la tolerancia configurada.
rhythm_ok = (
    records == expected
    and attempts == expected
    and len(starts) == expected
    and deviation <= tol
    and p95_interval_deviation <= tol
)

# TPS de inicio observado: ventana entre el primer y último inicio.
start_duration = (max(starts) - min(starts)) / 1e9 if len(starts) > 1 else 0.0
tps_attempts = attempts / start_duration if start_duration > 0 else 0.0
# Tasa válida normalizada por la misma ventana de inicio; no es una tasa
# de confirmación calculada sobre una ventana independiente de commits.
tps_valid = valid / start_duration if start_duration > 0 else 0.0

def fmt(v):
    return f"{v:.3f}" if math.isfinite(v) else ""

summary_row = [
    mode, rate, expected, records, attempts, valid, invalid, failed, missing,
    fmt(valid / expected * 100 if expected else 0),
    fmt(tps_attempts), fmt(tps_valid),
    fmt(statistics.mean(lat_start) if lat_start else float('nan')),
    fmt(statistics.median(lat_start) if lat_start else float('nan')),
    fmt(percentile(lat_start, .95)),
    fmt(statistics.mean(lat_sched) if lat_sched else float('nan')),
    fmt(percentile(lags, .95)), fmt(deviation),
    fmt(p95_interval_deviation), "SI" if rhythm_ok else "NO"
]

with open(summary, 'a', newline='', encoding='utf-8') as f:
    csv.writer(f).writerow(summary_row)

print(
    f"Resumen {rate} TPS: registros={records}/{expected}, "
    f"intentos registrados={attempts}, VALID={valid}, INVALID={invalid}, "
    f"fallidas/no válidas registradas={failed}, ausentes={missing}, "
    f"éxito={summary_row[9]}%, TPS de inicio observado={summary_row[10]}, "
    f"desviación media={summary_row[17]}%, "
    f"P95 desviación de intervalo={summary_row[18]}%, "
    f"ritmo aceptable={summary_row[19]}"
)
PY
done

echo "=== Resumen final ==="
cat "$SUMMARY"
echo "Archivos conservados en: $RUN_DIR"
echo "Estado: ejecución finalizada; revisar el log y los CSV antes de aceptar resultados."
echo "No se inicia automáticamente la campaña definitiva tras el piloto."
