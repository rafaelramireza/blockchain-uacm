
#!/usr/bin/env bash

# ============================================================
# PRUEBA 06: THROUGHPUT CONCURRENTE
# 100 transacciones, con concurrencia máxima de 10
# ============================================================

set -u

cd "$(dirname "$0")" || exit 1

source ./00_lib_pruebas_medec.sh || {
    echo "ERROR: no se pudo cargar 00_lib_pruebas_medec.sh"
    exit 1
}

# Las transacciones individuales pueden fallar sin detener
# la recopilación del resto de los resultados.
set +e

TOTAL="${TOTAL_THROUGHPUT:-100}"
CONCURRENCIA="${CONCURRENCIA_THROUGHPUT:-10}"
PREFIJO="${PREFIJO_THROUGHPUT:-29-006}"
INICIO_MATRICULA="${INICIO_MATRICULA_THROUGHPUT:-1}"

SALIDA_DIR="./resultados"
mkdir -p "$SALIDA_DIR" || exit 1

RUN_DIR=$(mktemp -d \
    "$SALIDA_DIR/prueba06_throughput_concurrente_$(date +%Y%m%d_%H%M%S)_XXXXXX") \
    || exit 1

ARCHIVO_RESULTADOS="$RUN_DIR/throughput_concurrente_${TOTAL}.csv"
ARCHIVO_TXIDS="$RUN_DIR/throughput_concurrente_${TOTAL}_txids.csv"
DIR_TEMP="$RUN_DIR/transacciones"

mkdir -p "$DIR_TEMP" || exit 1

LOG="$RUN_DIR/ejecucion.log"
exec > >(tee -a "$LOG") 2>&1

# ============================================================
# VALIDACIÓN DE CONFIGURACIÓN
# ============================================================

if ! [[ "$TOTAL" =~ ^[1-9][0-9]*$ ]] ||
   ! [[ "$CONCURRENCIA" =~ ^[1-9][0-9]*$ ]] ||
   ! [[ "$INICIO_MATRICULA" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: TOTAL, CONCURRENCIA e INICIO_MATRICULA deben ser enteros positivos."
    exit 1
fi

if (( CONCURRENCIA > TOTAL )); then
    echo "ERROR: la concurrencia no puede superar el total de transacciones."
    exit 1
fi

if (( INICIO_MATRICULA + TOTAL - 1 > 9999 )); then
    echo "ERROR: las matrículas excederían el formato de cuatro dígitos finales."
    exit 1
fi

if ! [[ "$PREFIJO" =~ ^[0-9]{2}-[0-9]{3}$ ]]; then
    echo "ERROR: el prefijo debe tener el formato NN-NNN; por defecto se utiliza 28-006."
    exit 1
fi

for herramienta in peer jq awk date python3; do
    if ! command -v "$herramienta" >/dev/null 2>&1; then
        echo "ERROR: no se encuentra el comando $herramienta."
        exit 1
    fi
done

echo
echo "============================================================"
echo " PRUEBA 06: THROUGHPUT CONCURRENTE"
echo "============================================================"
echo "Operación             : RegistrarInscripcion"
echo "Transacciones         : $TOTAL"
echo "Concurrencia máxima   : $CONCURRENCIA"
echo "Prefijo de matrículas : $PREFIJO"
echo "Matrícula inicial     : $INICIO_MATRICULA"
echo "Ejecución             : Lotes concurrentes"
echo "Inicio                : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Directorio            : $RUN_DIR"
echo "============================================================"
echo

# ============================================================
# IDENTIDAD Y VALIDACIÓN DE MATRÍCULAS
# ============================================================

if ! usar_identidad \
    "${PERFIL_MSP[REGISTRO]}" \
    "${PERFIL_MSP_PATH[REGISTRO]}" \
    "${PERFIL_PEER[REGISTRO]}" \
    "${PERFIL_TLS[REGISTRO]}"; then
    echo "ERROR: no fue posible configurar la identidad de Registro Escolar."
    exit 1
fi

echo "Validando que las matrículas no existan previamente..."

for ((i = 0; i < TOTAL; i++)); do
    numero_matricula=$((INICIO_MATRICULA + i))
    printf -v sufijo '%04d' "$numero_matricula"
    matricula="${PREFIJO}-${sufijo}"

    existe_expediente "$matricula"
    rc=$?

    case "$rc" in
        0)
            echo "ERROR: la matrícula $matricula ya existe."
            echo "No se inició la medición. Configura INICIO_MATRICULA_THROUGHPUT con un rango libre."
            exit 1
            ;;
        1)
            ;;
        *)
            echo "ERROR: no se pudo comprobar la matrícula $matricula."
            echo "No se inició la medición."
            exit 1
            ;;
    esac
done

echo "PASS: las $TOTAL matrículas están disponibles."
echo

# ============================================================
# EJECUCIÓN DE UNA TRANSACCIÓN
# ============================================================

ejecutar_transaccion() {
    local numero="$1"
    local matricula="$2"
    local archivo="$DIR_TEMP/resultado_${numero}.txt"
    local log="$DIR_TEMP/transaccion_${numero}.log"
    local inicio fin latencia resultado

    inicio=$(python3 -c 'import time; print(time.monotonic_ns())')

    if invocar "RegistrarInscripcion" "$matricula" >"$log" 2>&1; then
        resultado="PASS"
    else
        resultado="FAIL"
    fi

    fin=$(python3 -c 'import time; print(time.monotonic_ns())')
    latencia=$(( (fin - inicio) / 1000000 ))

    printf '%s|%s|%s\n' \
        "$matricula" "$resultado" "$latencia" > "$archivo"

    if [[ "$resultado" == "FAIL" ]]; then
        echo "ERROR en transacción $numero ($matricula):"
        tail -n 8 "$log"
    fi
}

# ============================================================
# MEDICIÓN GLOBAL
# ============================================================

INICIO_GLOBAL=$(python3 -c 'import time; print(time.monotonic_ns())')
numero=1

while (( numero <= TOTAL )); do
    pids=()
    fin_lote=$((numero + CONCURRENCIA - 1))

    if (( fin_lote > TOTAL )); then
        fin_lote="$TOTAL"
    fi

    # Lanzar como máximo CONCURRENCIA procesos por lote.
    while (( numero <= fin_lote )); do
        numero_matricula=$((INICIO_MATRICULA + numero - 1))
        printf -v sufijo '%04d' "$numero_matricula"
        matricula="${PREFIJO}-${sufijo}"

        ejecutar_transaccion "$numero" "$matricula" &
        pids+=( "$!" )

        echo "Lanzada transacción ${numero}/${TOTAL}: ${matricula}"
        numero=$((numero + 1))
    done

    # No comenzar el siguiente lote hasta que finalice el actual.
    for pid in "${pids[@]}"; do
        wait "$pid"
        rc=$?

        if (( rc != 0 )); then
            echo "ERROR: el proceso con PID $pid terminó con código $rc."
        fi
    done
done

FIN_GLOBAL=$(python3 -c 'import time; print(time.monotonic_ns())')
TIEMPO_TOTAL_MS=$(( (FIN_GLOBAL - INICIO_GLOBAL) / 1000000 ))

# ============================================================
# RECOPILACIÓN DE RESULTADOS Y TXID
# Esta fase queda fuera del cronómetro global.
# ============================================================

printf 'id,matricula,resultado,latencia_ms,txid\n' \
    > "$ARCHIVO_RESULTADOS"

printf 'id,matricula,resultado,txid\n' \
    > "$ARCHIVO_TXIDS"

exitosas=0
fallidas=0
txids_no_extraidos=0
resultados_invalidos=0

for ((i = 1; i <= TOTAL; i++)); do
    archivo="$DIR_TEMP/resultado_${i}.txt"

    numero_matricula=$((INICIO_MATRICULA + i - 1))
    printf -v sufijo '%04d' "$numero_matricula"
    matricula="${PREFIJO}-${sufijo}"

    resultado="FAIL"
    latencia="0"

    if [[ -f "$archivo" ]]; then
        IFS='|' read -r matricula resultado latencia < "$archivo"
    else
        echo "ERROR: falta el archivo de resultado de la transacción $i."
        resultados_invalidos=$((resultados_invalidos + 1))
    fi

    if ! [[ "$latencia" =~ ^[0-9]+$ ]] ||
       ! [[ "$resultado" =~ ^(PASS|FAIL)$ ]]; then
        echo "ERROR: resultado inválido en la transacción $i."
        resultado="FAIL"
        latencia="0"
        resultados_invalidos=$((resultados_invalidos + 1))
    fi

    txid="NO_EXTRAIDO"

    if [[ "$resultado" == "PASS" ]]; then
        txid_obtenido="$(
            obtener_txid_evento \
                "$matricula" "INSCRIPCION" "REGISTRO" 2>/dev/null
        )"
        codigo_txid=$?

        if (( codigo_txid == 0 )) &&
           [[ -n "$txid_obtenido" ]] &&
           [[ "$txid_obtenido" != "null" ]] &&
           [[ "$txid_obtenido" != "NO_EXTRAIDO" ]]; then
            txid="$txid_obtenido"
            exitosas=$((exitosas + 1))
        else
            txids_no_extraidos=$((txids_no_extraidos + 1))
            echo "ERROR: no se pudo extraer el TXID de $matricula."
        fi
    else
        fallidas=$((fallidas + 1))
    fi

    printf '%s,%s,%s,%s,%s\n' \
        "$i" "$matricula" "$resultado" "$latencia" "$txid" \
        >> "$ARCHIVO_RESULTADOS"

    printf '%s,%s,%s,%s\n' \
        "$i" "$matricula" "$resultado" "$txid" \
        >> "$ARCHIVO_TXIDS"
done

# ============================================================
# CÁLCULO DEL THROUGHPUT
# ============================================================

awk \
    -v total="$TOTAL" \
    -v ok="$exitosas" \
    -v fail="$fallidas" \
    -v txids_faltantes="$txids_no_extraidos" \
    -v tiempo_ms="$TIEMPO_TOTAL_MS" \
    -v concurrencia="$CONCURRENCIA" \
    'BEGIN {
        tiempo_s = tiempo_ms / 1000

        if (tiempo_s > 0)
            throughput = ok / tiempo_s
        else
            throughput = 0

        tasa = (total > 0) ? (ok * 100 / total) : 0

        printf "\n"
        printf "============================================================\n"
        printf " RESULTADOS DE THROUGHPUT CONCURRENTE\n"
        printf "============================================================\n"
        printf "Transacciones solicitadas : %d\n", total
        printf "Transacciones exitosas    : %d\n", ok
        printf "Transacciones fallidas    : %d\n", fail
        printf "Tasa de éxito              : %.2f%%\n", tasa
        printf "TXID no extraídos          : %d\n", txids_faltantes
        printf "Tiempo total               : %.3f s\n", tiempo_s
        printf "Throughput                 : %.6f tx/s\n", throughput
        printf "Concurrencia máxima        : %d\n", concurrencia
        printf "============================================================\n"
    }'

echo
echo "CSV de resultados: $ARCHIVO_RESULTADOS"
echo "CSV de TXID      : $ARCHIVO_TXIDS"
echo "Registro         : $LOG"
echo "Fin              : $(date '+%Y-%m-%d %H:%M:%S')"

# ============================================================
# RESULTADO GLOBAL
# ============================================================

echo
echo "============================================================"
echo " RESULTADO GLOBAL: THROUGHPUT CONCURRENTE"
echo "============================================================"

if (( exitosas == TOTAL &&
      fallidas == 0 &&
      txids_no_extraidos == 0 &&
      resultados_invalidos == 0 )); then
    echo "Resultado: PASS"
    RESULTADO_GLOBAL=0
else
    echo "Resultado: FAIL"
    RESULTADO_GLOBAL=1
fi

echo "Transacciones solicitadas : $TOTAL"
echo "Transacciones exitosas    : $exitosas"
echo "Transacciones fallidas    : $fallidas"
echo "TXID no extraídos         : $txids_no_extraidos"
echo "Resultados inválidos      : $resultados_invalidos"
echo "Directorio de evidencias  : $RUN_DIR"
echo "Registro de ejecución     : $LOG"

exit "$RESULTADO_GLOBAL"
