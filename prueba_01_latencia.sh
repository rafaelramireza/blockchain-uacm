
#!/usr/bin/env bash
set -u

cd "$(dirname "$0")" || exit 1

source ./00_lib_pruebas_medec.sh

# Los fallos de las transacciones se gestionan explícitamente.
set +e

# ============================================================
# CONFIGURACIÓN
# ============================================================

RESULTADOS_DIR="./resultados"
TOTAL=100
PREFIJO="29-001"
INICIO_MATRICULA=0001

mkdir -p "$RESULTADOS_DIR" || {
    echo "ERROR: no se pudo crear el directorio de resultados."
    exit 1
}

# Cada ejecución conserva su propio CSV.
FECHA_EJECUCION=$(date '+%Y%m%d_%H%M%S_%N')
CSV="$RESULTADOS_DIR/latencia_100_${FECHA_EJECUCION}.csv"

if [[ -e "$CSV" ]]; then
    echo "ERROR: el archivo de resultados ya existe: $CSV"
    exit 1
fi

# ============================================================
# CONFIGURACIÓN DE IDENTIDAD
# ============================================================

if ! usar_identidad \
    "$REGISTRO_MSP" \
    "$REGISTRO_MSP_PATH" \
    "$REGISTRO_PEER" \
    "$REGISTRO_TLS"; then

    echo "ERROR: no se pudo configurar la identidad de Registro Escolar."
    exit 1
fi

# ============================================================
# INFORMACIÓN DE LA PRUEBA
# ============================================================

echo
echo "============================================================"
echo " PRUEBA 01: LATENCIA DE REGISTRO DE INSCRIPCIONES"
echo "============================================================"
echo
echo "Operación       : RegistrarInscripcion"
echo "Transacciones   : $TOTAL"
echo "Ejecución       : Secuencial"
echo "Prefijo         : $PREFIJO"
echo "Primera matrícula: $(printf '%s-%04d' "$PREFIJO" "$INICIO_MATRICULA")"
echo "Última matrícula : $(printf '%s-%04d' "$PREFIJO" "$((INICIO_MATRICULA + TOTAL - 1))")"
echo "Cronómetro      : Invocación de la transacción"
echo "Consulta TxID   : Fuera del cronómetro"
echo "Archivo CSV     : $CSV"
echo
echo "IMPORTANTE: verifica que las 100 matrículas no existan"
echo "antes de ejecutar la prueba."
echo "============================================================"
echo

# ============================================================
# VALIDACIÓN PREVIA DE MATRÍCULAS
# No se ejecutan transacciones si hay colisiones o errores.
# ============================================================

echo
echo "Validando disponibilidad de las $TOTAL matrículas..."

for ((i=1; i<=TOTAL; i++)); do
    MATRICULA=$(printf "%s-%04d" "$PREFIJO" "$((INICIO_MATRICULA + i - 1))")

    if existe_expediente "$MATRICULA"; then
        echo "ERROR: la matrícula ya existe: $MATRICULA"
        echo "Prueba cancelada sin ejecutar transacciones."
        exit 1
    else
        RC=$?
        if [[ "$RC" -ne 1 ]]; then
            echo "ERROR: no se pudo verificar $MATRICULA."
            echo "Prueba cancelada sin ejecutar transacciones."
            exit 1
        fi
    fi
done

echo "Validación previa: PASS ($TOTAL matrículas libres)"
echo

# ============================================================
# INICIALIZACIÓN DE RESULTADOS
# ============================================================

printf 'id,resultado,latencia_ms,txid\n' > "$CSV" || {
    echo "ERROR: no se pudo inicializar el CSV."
    exit 1
}

EXIT_GLOBAL=0
EXITOS=0
FALLOS=0
FALLOS_TXID=0
FALLOS_TIEMPO=0

# ============================================================
# EJECUCIÓN Y MEDICIÓN INDIVIDUAL
# ============================================================

for ((i=1; i<=TOTAL; i++)); do

    MATRICULA=$(printf "%s-%04d" "$PREFIJO" "$((INICIO_MATRICULA + i - 1))")

    echo "[$i/$TOTAL] Matrícula: $MATRICULA"

    INICIO=$(date +%s%N)

    if SALIDA=$(invocar "RegistrarInscripcion" "$MATRICULA" 2>&1); then
        RETORNO=0
    else
        RETORNO=$?
    fi

    FIN=$(date +%s%N)

    # Validar los valores del reloj antes de hacer aritmética.
    if [[ ! "$INICIO" =~ ^[0-9]+$ ||
          ! "$FIN" =~ ^[0-9]+$ ]]; then

        echo "ERROR: no se pudo medir el tiempo de $MATRICULA."
        printf '%s,FAIL,,ERROR_TIEMPO\n' "$MATRICULA" >> "$CSV"
        ((FALLOS_TIEMPO++))
        EXIT_GLOBAL=1
        continue
    fi

    LATENCIA_NS=$((FIN - INICIO))

    if (( LATENCIA_NS < 0 )); then
        echo "ERROR: medición negativa para $MATRICULA."
        printf '%s,FAIL,,ERROR_TIEMPO\n' "$MATRICULA" >> "$CSV"
        ((FALLOS_TIEMPO++))
        EXIT_GLOBAL=1
        continue
    fi

    # Conservar tres decimales de milisegundo.
    LATENCIA_MS=$(awk -v ns="$LATENCIA_NS" \
        'BEGIN { printf "%.3f", ns / 1000000 }')

    if [[ "$RETORNO" -eq 0 ]]; then

        # La consulta del TxID se realiza después de detener
        # el cronómetro; no forma parte de la latencia medida.
        TXID=$(obtener_txid_evento \
            "$MATRICULA" "INSCRIPCION" 2>/dev/null)
        TXID_RC=$?

        if [[ "$TXID_RC" -ne 0 ||
              -z "$TXID" ||
              "$TXID" == "null" ||
              "$TXID" == "NO_EXTRAIDO" ]]; then

            TXID="NO_EXTRAIDO"
            ((FALLOS_TXID++))
            EXIT_GLOBAL=1
            echo "      ADVERTENCIA: no se pudo extraer el TxID."
        fi

        echo "      Resultado : PASS"
        echo "      Latencia  : ${LATENCIA_MS} ms"
        echo "      TxID      : $TXID"

        printf '%s,PASS,%s,%s\n' \
            "$MATRICULA" "$LATENCIA_MS" "$TXID" >> "$CSV"

        ((EXITOS++))

    else

        echo "      Resultado : FAIL"
        echo "      Código de retorno: $RETORNO"
        echo "      Salida de invocar:"
        printf '%s\n' "$SALIDA"

        printf '%s,FAIL,%s,ERROR_INVOCACION\n' \
            "$MATRICULA" "$LATENCIA_MS" >> "$CSV"

        ((FALLOS++))
        EXIT_GLOBAL=1
    fi

    echo

done

# ============================================================
# CÁLCULO DE ESTADÍSTICAS
# Solo se consideran las transacciones PASS con latencia válida.
# ============================================================

echo
echo "============================================================"
echo " RESULTADOS ESTADÍSTICOS DE LATENCIA"
echo "============================================================"

awk -F',' '
    NR > 1 && $2 == "PASS" && $3 ~ /^[0-9]+([.][0-9]+)?$/ {
        valores[++n] = $3 + 0
        suma += $3
    }

    END {
        if (n == 0) {
            print "ERROR: no hay latencias válidas para calcular estadísticas."
            exit 1
        }

        media = suma / n

        for (i = 1; i <= n; i++) {
            ordenados[i] = valores[i]
            varianza += (valores[i] - media) ^ 2
        }

        # Ordenamiento ascendente.
        for (i = 2; i <= n; i++) {
            actual = ordenados[i]
            j = i - 1

            while (j >= 1 && ordenados[j] > actual) {
                ordenados[j + 1] = ordenados[j]
                j--
            }

            ordenados[j + 1] = actual
        }

        if (n % 2 == 1) {
            mediana = ordenados[(n + 1) / 2]
        } else {
            mediana = (ordenados[n / 2] + ordenados[n / 2 + 1]) / 2
        }

        desviacion = sqrt(varianza / n)

        # Percentil 95 mediante rango más cercano.
        posicion_p95 = int(0.95 * n)
        if (posicion_p95 < 0.95 * n) {
            posicion_p95++
        }
        if (posicion_p95 < 1) {
            posicion_p95 = 1
        }

        printf "Transacciones con latencia válida: %d\n", n
        printf "Mínimo:              %.3f ms\n", ordenados[1]
        printf "Máximo:              %.3f ms\n", ordenados[n]
        printf "Promedio:            %.3f ms\n", media
        printf "Mediana:             %.3f ms\n", mediana
        printf "Desviación estándar: %.3f ms\n", desviacion
        printf "Percentil 95 (P95):  %.3f ms\n", ordenados[posicion_p95]
    }
' "$CSV"

ESTADISTICAS_RC=$?

if [[ "$ESTADISTICAS_RC" -ne 0 ]]; then
    EXIT_GLOBAL=1
fi

# ============================================================
# RESUMEN FINAL
# ============================================================

echo
echo "============================================================"
echo " RESUMEN DE LA EJECUCIÓN"
echo "============================================================"
echo "Transacciones previstas : $TOTAL"
echo "Invocaciones exitosas   : $EXITOS"
echo "Invocaciones fallidas   : $FALLOS"
echo "TxID no extraídos       : $FALLOS_TXID"
echo "Errores de medición     : $FALLOS_TIEMPO"
echo "Archivo de resultados   : $CSV"
echo

if [[ "$EXITOS" -ne "$TOTAL" ||
      "$FALLOS" -gt 0 ||
      "$FALLOS_TXID" -gt 0 ||
      "$FALLOS_TIEMPO" -gt 0 ]]; then
    EXIT_GLOBAL=1
fi

if [[ "$EXIT_GLOBAL" -eq 0 ]]; then
    echo "RESULTADO GLOBAL: PASS"
else
    echo "RESULTADO GLOBAL: FAIL"
fi

echo "============================================================"

exit "$EXIT_GLOBAL"
