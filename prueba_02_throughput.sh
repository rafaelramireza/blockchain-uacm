#!/usr/bin/env bash
# Prueba 02 MED-EC: throughput secuencial de 100 registros de inscripción.
# El cronómetro incluye exclusivamente las invocaciones secuenciales confirmadas
# (incluido el tiempo de espera de commit VALID); excluye preflight y consultas TxID.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LIB="./00_lib_pruebas_medec.sh"
if [[ ! -r "$LIB" ]]; then
    echo "ERROR: no se encuentra $LIB en $SCRIPT_DIR" >&2
    exit 1
fi

source "$LIB" || {
    echo "ERROR: no se pudo cargar la biblioteca MED-EC." >&2
    exit 1
}

# Configurar la identidad en el proceso principal antes del preflight.
# Esta preparación queda fuera del intervalo cronometrado.
if ! usar_identidad \
    "$REGISTRO_MSP" \
    "$REGISTRO_MSP_PATH" \
    "$REGISTRO_PEER" \
    "$REGISTRO_TLS"; then
    echo "ERROR: no se pudo configurar la identidad de Registro Escolar." >&2
    exit 1
fi

TOTAL="${TOTAL_TRANSACCIONES:-100}"
PREFIJO="${PREFIJO_MATRICULA:-29-002}"
INICIO="${INICIO_MATRICULA:-0001}"
RESULTADOS_DIR="./resultados"
mkdir -p "$RESULTADOS_DIR" || exit 1

if ! [[ "$TOTAL" =~ ^[1-9][0-9]*$ && "$INICIO" =~ ^[0-9]+$ && "$PREFIJO" =~ ^[0-9]{2}-[0-9]{3}$ ]]; then
    echo "ERROR: configuración inválida. Use TOTAL_TRANSACCIONES, INICIO_MATRICULA y PREFIJO_MATRICULA válidos." >&2
    exit 2
fi
if (( INICIO + TOTAL - 1 > 9999 )); then
    echo "ERROR: la numeración excede el formato 00-000-0000." >&2
    exit 2
fi

FECHA="$(date +%Y%m%d_%H%M%S)"
CSV="$RESULTADOS_DIR/throughput_secuencial_${FECHA}.csv"
CSV_TXID="$RESULTADOS_DIR/throughput_secuencial_txids_${FECHA}.csv"
LOG="$RESULTADOS_DIR/throughput_secuencial_${FECHA}.log"
for f in "$CSV" "$CSV_TXID" "$LOG"; do
    if [[ -e "$f" ]]; then
        echo "ERROR: el archivo ya existe; no se sobrescribirá: $f" >&2
        exit 1
    fi
done

matricula_de() {
    printf '%s-%04d' "$PREFIJO" "$1"
}

declare -a MATRICULAS=()
declare -a RESULTADOS=()
declare -a SALIDAS=()
declare -a TXIDS=()

printf '============================================================\n'
printf ' PRUEBA 02: THROUGHPUT SECUENCIAL\n'
printf '============================================================\n'
printf 'Operación             : RegistrarInscripcion\n'
printf 'Transacciones previstas: %s\n' "$TOTAL"
printf 'Muestra                : %s ... %s\n' "$(matricula_de "$INICIO")" "$(matricula_de "$((INICIO + TOTAL - 1))")"
printf 'Modo                   : secuencial\n'
printf 'Confirmación           : commit VALID mediante --waitForEvent\n'
printf 'Cronómetro             : solo el ciclo de invocaciones\n'
printf 'Preflight/TxID          : fuera del cronómetro\n'
printf 'CSV                    : %s\nCSV TxID                : %s\nLog                    : %s\n' "$CSV" "$CSV_TXID" "$LOG"
printf '============================================================\n\n'

# Preflight de solo lectura: si hay una colisión o una consulta incierta, aborta
# antes de registrar cualquier expediente.
printf 'Validando que las %s matrículas estén libres...\n' "$TOTAL"
for ((i=0; i<TOTAL; i++)); do
    MATRICULA="$(matricula_de "$((INICIO + i))")"
    MATRICULAS[i]="$MATRICULA"
    if existe_expediente "$MATRICULA"; then
        echo "ERROR: la matrícula ya existe: $MATRICULA. No se ejecutó ninguna transacción." >&2
        exit 3
    else
        rc=$?
        if (( rc != 1 )); then
            echo "ERROR: no se pudo confirmar si $MATRICULA está libre (código $rc). No se ejecutó ninguna transacción." >&2
            exit 4
        fi
    fi
done
echo "Validación previa: PASS ($TOTAL matrículas libres)"

# El tiempo empieza justo antes de la primera invocación y termina justo después
# de la última. Las salidas se guardan en memoria y se imprimen después.
INICIO_NS="$(date +%s%N)"
for ((i=0; i<TOTAL; i++)); do
    MATRICULA="${MATRICULAS[i]}"
    if SALIDA="$(invocar "RegistrarInscripcion" "$MATRICULA" 2>&1)"; then
        VALID_COUNT="$(printf '%s\n' "$SALIDA" | grep -Fc 'committed with status (VALID)' || true)"
        if (( VALID_COUNT >= 1 )); then
            RESULTADOS[i]="PASS"
            SALIDAS[i]="$SALIDA
Confirmaciones VALID observadas: $VALID_COUNT"
        else
            RESULTADOS[i]="FAIL"
            SALIDAS[i]="La invocación terminó con código cero, pero no se encontró confirmación VALID.
$SALIDA"
        fi
    else
        rc=$?
        RESULTADOS[i]="FAIL"
        SALIDAS[i]="Código de salida: $rc
$SALIDA"
    fi
done
FIN_NS="$(date +%s%N)"

DURACION_NS=$((FIN_NS - INICIO_NS))
DURACION_S="$(awk -v ns="$DURACION_NS" 'BEGIN { printf "%.6f", ns/1000000000 }')"

# Todas las consultas de TxID y escrituras de resultados quedan fuera del intervalo medido.
printf 'id,matricula,resultado,txid\n' > "$CSV"
printf 'id,matricula,resultado,txid\n' > "$CSV_TXID"
printf 'PRUEBA 02 - THROUGHPUT SECUENCIAL\nFecha: %s\nTransacciones previstas: %s\nDuración medida (s): %s\n\n' "$FECHA" "$TOTAL" "$DURACION_S" > "$LOG"
EXITOSAS=0
FALLIDAS=0
TXID_OK=0
TXID_ERROR=0

for ((i=0; i<TOTAL; i++)); do
    MATRICULA="${MATRICULAS[i]}"
    RESULTADO="${RESULTADOS[i]}"
    TXID=""
    if [[ "$RESULTADO" == "PASS" ]]; then
        EXITOSAS=$((EXITOSAS + 1))
        if TXID="$(obtener_txid_evento "$MATRICULA" "INSCRIPCION" 2>/dev/null)" && [[ -n "$TXID" ]]; then
            TXID_OK=$((TXID_OK + 1))
        else
            TXID="NO_DISPONIBLE"
            TXID_ERROR=$((TXID_ERROR + 1))
        fi
    else
        FALLIDAS=$((FALLIDAS + 1))
        TXID="NO_APLICA"
    fi
    printf '%d,%s,%s,%s\n' "$((i + 1))" "$MATRICULA" "$RESULTADO" "$TXID" >> "$CSV"
    printf '%d,%s,%s,%s\n' "$((i + 1))" "$MATRICULA" "$RESULTADO" "$TXID" >> "$CSV_TXID"
    {
        printf '[%d/%s] %s: %s\n' "$((i + 1))" "$TOTAL" "$MATRICULA" "$RESULTADO"

        # Registrar la salida completa de peer tanto para PASS como para FAIL.
        # Esto conserva los TxID y los mensajes de commit VALID emitidos por Fabric.
        if [[ -n "${SALIDAS[i]}" ]]; then
            printf '%s\n' "${SALIDAS[i]}"
        else
            printf 'ADVERTENCIA: la invocación no produjo salida capturada.\n'
        fi

        if [[ "$TXID" == "NO_DISPONIBLE" ]]; then
            printf 'ADVERTENCIA: la invocación fue PASS, pero no se pudo recuperar el TxID del historial.\n'
        fi
        printf '\n'
    } >> "$LOG"
done

THROUGHPUT="$(awk -v n="$EXITOSAS" -v s="$DURACION_S" 'BEGIN { if (s > 0) printf "%.6f", n/s; else print "0" }')"
TASA_EXITO="$(awk -v n="$EXITOSAS" -v t="$TOTAL" 'BEGIN { printf "%.2f", (n/t)*100 }')"

{
    printf '\nResumen\n'
    printf 'Previstas: %s\nExitosas: %s\nFallidas: %s\nTxID recuperados: %s\nTxID no recuperados: %s\nDuración medida (s): %s\nThroughput confirmado (tx/s): %s\nTasa de éxito (%%): %s\n' \
        "$TOTAL" "$EXITOSAS" "$FALLIDAS" "$TXID_OK" "$TXID_ERROR" "$DURACION_S" "$THROUGHPUT" "$TASA_EXITO"
} >> "$LOG"

printf '\n================ RESUMEN ================\n'
printf 'Transacciones previstas : %s\n' "$TOTAL"
printf 'Invocaciones PASS       : %s\n' "$EXITOSAS"
printf 'Invocaciones FAIL       : %s\n' "$FALLIDAS"
printf 'TxID recuperados         : %s\n' "$TXID_OK"
printf 'TxID no recuperados      : %s\n' "$TXID_ERROR"
printf 'Duración medida          : %s s\n' "$DURACION_S"
printf 'Throughput confirmado    : %s tx/s\n' "$THROUGHPUT"
printf 'Tasa de éxito            : %s %%\n' "$TASA_EXITO"
printf 'CSV                      : %s\n' "$CSV"
printf 'CSV TxID                 : %s\n' "$CSV_TXID"
printf 'Log                      : %s\n' "$LOG"
if (( FALLIDAS == 0 )); then
    echo 'RESULTADO GLOBAL: PASS (invocaciones)'
else
    echo 'RESULTADO GLOBAL: FAIL (revisar CSV y log)'
fi

if (( TXID_ERROR > 0 )); then
    echo "ADVERTENCIA: $TXID_ERROR TxID no se pudieron recuperar; revisar CSV y log."
fi

printf '=========================================\n'

# No se elimina ni reinicia ningún expediente; las matrículas quedan registradas.
