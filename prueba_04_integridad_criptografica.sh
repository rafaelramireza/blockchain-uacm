#!/usr/bin/env bash
set -u

cd "$(dirname "$0")" || exit 1
source ./00_lib_pruebas_medec.sh || exit 1

# ============================================================
# CONFIGURACIÓN Y DIRECTORIO ÚNICO POR EJECUCIÓN
# ============================================================

RESULTADOS_BASE="./resultados"
mkdir -p "$RESULTADOS_BASE" || exit 1

MATRICULA="${MATRICULA:-29-001-0001}"

RUN_DIR=$(mktemp -d \
    "$RESULTADOS_BASE/prueba04_integridad_$(date +%Y%m%d_%H%M%S)_XXXXXX") \
    || exit 1

CSV="$RUN_DIR/integridad_criptografica.csv"
LOG="$RUN_DIR/ejecucion.log"

REGISTRO_JSON="$RUN_DIR/integridad_registro.json"
SS_JSON="$RUN_DIR/integridad_ss.json"
CERT_JSON="$RUN_DIR/integridad_certificacion.json"
TIT_JSON="$RUN_DIR/integridad_titulacion.json"

# Conservar la salida de la ejecución.
exec > >(tee -a "$LOG") 2>&1

echo "============================================================"
echo " PRUEBA 04: INTEGRIDAD CRIPTOGRÁFICA"
echo "============================================================"
echo "Matrícula : $MATRICULA"
echo "Algoritmo : SHA-256"
echo "Directorio: $RUN_DIR"
echo
echo "Representación canónica:"
echo "id|estadoAnterior|evento|estadoNuevo|emisor|timestamp"
echo

printf 'peer,evidencias,hashes_correctos,hashes_incorrectos,resultado\n' \
    > "$CSV" || exit 1

# Estados: 0 = PASS; 1 = FAIL.
RESULTADO_REGISTRO=1
RESULTADO_SS=1
RESULTADO_CERT=1
RESULTADO_TIT=1
HASHES_OK=1
FALLO_GLOBAL=0

# ============================================================
# CONSULTAR UN PEER
# ============================================================

consultar_peer() {
    local msp="$1"
    local msp_path="$2"
    local peer_addr="$3"
    local tls="$4"
    local salida="$5"
    local nombre="$6"
    local error_log="${salida%.json}.stderr.log"

    echo "Consultando $nombre..."

    : > "$salida" || return 1
    : > "$error_log" || return 1

    if ! usar_identidad "$msp" "$msp_path" "$peer_addr" "$tls"; then
        echo "ERROR: no se pudo configurar la identidad de $nombre."
        return 1
    fi

    if ! peer chaincode query \
        -C "$CHANNEL_NAME" \
        -n "$CHAINCODE_NAME" \
        -c "{\"function\":\"ConsultarExpediente\",\"Args\":[\"$MATRICULA\"]}" \
        > "$salida" 2> "$error_log"; then
        echo "ERROR: falló la consulta a $nombre."
        echo "Detalles: $error_log"
        cat "$error_log"
        return 1
    fi

    if ! jq -e 'type == "object"' "$salida" >/dev/null 2>&1; then
        echo "ERROR: la respuesta de $nombre no es un objeto JSON válido."
        echo "Respuesta conservada en: $salida"
        return 1
    fi

    echo "PASS: consulta y JSON válidos para $nombre."
    return 0
}

# ============================================================
# VALIDAR ESTRUCTURA DEL EXPEDIENTE Y SUS EVIDENCIAS
# ============================================================

validar_estructura() {
    local archivo="$1"
    local nombre="$2"

    echo
    echo "Validando estructura: $nombre"

    if [[ ! -s "$archivo" ]]; then
        echo "ERROR: el archivo no existe o está vacío: $archivo"
        return 1
    fi

    if ! jq -e --arg matricula "$MATRICULA" '
        type == "object"
        and .id == $matricula
        and (.historialTransiciones | type == "array")
        and (
            [.historialTransiciones[]
             | select(.tipo == "TRANSICION")] | length > 0
        )
        and all(
            [.historialTransiciones[]
             | select(.tipo == "TRANSICION")][];
            ((.hash | type) == "string")
            and (.hash | test("^[0-9a-fA-F]{64}$"))
            and ((.txId | type) == "string")
            and ((.txId | length) > 0)
            and (.estadoAnterior | type == "string")
            and ((.evento | type) == "string")
            and ((.evento | length) > 0)
            and ((.estadoNuevo | type) == "string")
            and ((.estadoNuevo | length) > 0)
            and ((.emisor | type) == "string")
            and ((.emisor | length) > 0)
            and ((.timestamp | type) == "string")
            and ((.timestamp | length) > 0)
        )
    ' "$archivo" >/dev/null 2>&1; then
        echo "FAIL: expediente inválido o evidencia incompleta en $nombre."
        echo "Revise el JSON y los campos obligatorios."
        return 1
    fi

    local total
    total=$(jq -er '
        [.historialTransiciones[]
         | select(.tipo == "TRANSICION")] | length
    ' "$archivo") || return 1

    if [[ ! "$total" =~ ^[0-9]+$ ]] || (( total < 1 )); then
        echo "FAIL: cantidad de evidencias inválida en $nombre."
        return 1
    fi

    echo "PASS: expediente válido; evidencias de transición: $total."
    return 0
}

# ============================================================
# RECALCULAR SHA-256
# ============================================================

validar_hashes() {
    local archivo="$1"
    local nombre="$2"
    local salida_hashes="$3"

    local id_expediente
    local entradas="$RUN_DIR/entradas_hash_${nombre}.jsonl"
    local total=0
    local correctos=0
    local incorrectos=0

    echo
    echo "------------------------------------------------------------"
    echo "Validación SHA-256: $nombre"
    echo "------------------------------------------------------------"

    id_expediente=$(jq -er '.id' "$archivo") || {
        echo "ERROR: no se pudo leer el ID del expediente."
        return 1
    }

    # Crear primero un archivo intermedio y comprobar jq.
    # Así, un fallo de extracción no se confunde con cero errores.
    if ! jq -ce --arg id "$id_expediente" '
        .historialTransiciones[]
        | select(.tipo == "TRANSICION")
        | [
            .hash,
            (
                $id
                + "|" + .estadoAnterior
                + "|" + .evento
                + "|" + .estadoNuevo
                + "|" + .emisor
                + "|" + .timestamp
            )
        ]
    ' "$archivo" > "$entradas"; then
        echo "ERROR: falló la extracción de evidencias de $nombre."
        return 1
    fi

    if [[ ! -s "$entradas" ]]; then
        echo "ERROR: no se extrajo ninguna evidencia de $nombre."
        return 1
    fi

    : > "$salida_hashes" || return 1

    while IFS= read -r linea; do
        local hash_almacenado
        local datos
        local hash_calculado

        hash_almacenado=$(jq -er '.[0]' <<< "$linea") || {
            echo "ERROR: no se pudo extraer el hash almacenado."
            return 1
        }

        datos=$(jq -er '.[1]' <<< "$linea") || {
            echo "ERROR: no se pudo reconstruir la evidencia."
            return 1
        }

        hash_calculado=$(
            printf '%s' "$datos" |
                sha256sum |
                awk '{print $1}'
        ) || {
            echo "ERROR: falló el cálculo SHA-256."
            return 1
        }

        if [[ ! "$hash_calculado" =~ ^[0-9a-f]{64}$ ]]; then
            echo "ERROR: el cálculo no produjo un SHA-256 válido."
            return 1
        fi

        total=$((total + 1))

        printf '%s|%s\n' "$hash_almacenado" "$hash_calculado" \
            >> "$salida_hashes" || return 1

        if [[ "${hash_almacenado,,}" == "$hash_calculado" ]]; then
            correctos=$((correctos + 1))
            echo "Evidencia #$total: PASS"
        else
            incorrectos=$((incorrectos + 1))
            echo "Evidencia #$total: FAIL"
            echo "  Almacenado: $hash_almacenado"
            echo "  Calculado : $hash_calculado"
        fi
    done < "$entradas"

    echo "Total evidencias   : $total"
    echo "Hashes correctos   : $correctos"
    echo "Hashes incorrectos : $incorrectos"

    if (( total > 0 && correctos == total && incorrectos == 0 )); then
        echo "$nombre,$total,$correctos,$incorrectos,PASS" >> "$CSV" \
            || return 1
        echo "Resultado peer: PASS"
        return 0
    else
        echo "$nombre,$total,$correctos,$incorrectos,FAIL" >> "$CSV" \
            || return 1
        echo "Resultado peer: FAIL"
        return 1
    fi
}

# ============================================================
# CONSULTAS A LOS CUATRO PEERS
# ============================================================

consultar_peer \
    "${PERFIL_MSP[REGISTRO]}" "${PERFIL_MSP_PATH[REGISTRO]}" \
    "${PERFIL_PEER[REGISTRO]}" "${PERFIL_TLS[REGISTRO]}" \
    "$REGISTRO_JSON" "RegistroEscolarMSP" || FALLO_GLOBAL=1

consultar_peer \
    "${PERFIL_MSP[SS]}" "${PERFIL_MSP_PATH[SS]}" \
    "${PERFIL_PEER[SS]}" "${PERFIL_TLS[SS]}" \
    "$SS_JSON" "ServicioSocialMSP" || FALLO_GLOBAL=1

consultar_peer \
    "${PERFIL_MSP[CERT]}" "${PERFIL_MSP_PATH[CERT]}" \
    "${PERFIL_PEER[CERT]}" "${PERFIL_TLS[CERT]}" \
    "$CERT_JSON" "CertificacionMSP" || FALLO_GLOBAL=1

consultar_peer \
    "${PERFIL_MSP[TIT]}" "${PERFIL_MSP_PATH[TIT]}" \
    "${PERFIL_PEER[TIT]}" "${PERFIL_TLS[TIT]}" \
    "$TIT_JSON" "TitulacionMSP" || FALLO_GLOBAL=1

# ============================================================
# VALIDACIÓN INDIVIDUAL
# ============================================================

if validar_estructura "$REGISTRO_JSON" "RegistroEscolarMSP" &&
   validar_hashes "$REGISTRO_JSON" "RegistroEscolarMSP" \
       "$RUN_DIR/hashes_calculados_registro.txt"; then
    RESULTADO_REGISTRO=0
else
    RESULTADO_REGISTRO=1
    FALLO_GLOBAL=1
fi

if validar_estructura "$SS_JSON" "ServicioSocialMSP" &&
   validar_hashes "$SS_JSON" "ServicioSocialMSP" \
       "$RUN_DIR/hashes_calculados_ss.txt"; then
    RESULTADO_SS=0
else
    RESULTADO_SS=1
    FALLO_GLOBAL=1
fi

if validar_estructura "$CERT_JSON" "CertificacionMSP" &&
   validar_hashes "$CERT_JSON" "CertificacionMSP" \
       "$RUN_DIR/hashes_calculados_certificacion.txt"; then
    RESULTADO_CERT=0
else
    RESULTADO_CERT=1
    FALLO_GLOBAL=1
fi

if validar_estructura "$TIT_JSON" "TitulacionMSP" &&
   validar_hashes "$TIT_JSON" "TitulacionMSP" \
       "$RUN_DIR/hashes_calculados_titulacion.txt"; then
    RESULTADO_TIT=0
else
    RESULTADO_TIT=1
    FALLO_GLOBAL=1
fi

# ============================================================
# COMPARACIÓN ENTRE PEERS
# ============================================================

echo
echo "============================================================"
echo "COMPARACIÓN ENTRE PEERS"
echo "============================================================"

extraer_lista() {
    local archivo="$1"
    local destino="$2"

    if ! jq -ce '
        .historialTransiciones[]
        | select(.tipo == "TRANSICION")
        | [.txId, .hash]
    ' "$archivo" > "$destino"; then
        echo "ERROR: no se pudo extraer la lista de $archivo."
        return 1
    fi

    if [[ ! -s "$destino" ]]; then
        echo "ERROR: lista vacía: $destino"
        return 1
    fi

    return 0
}

HASHES_REGISTRO="$RUN_DIR/lista_registro.jsonl"
HASHES_SS="$RUN_DIR/lista_ss.jsonl"
HASHES_CERT="$RUN_DIR/lista_certificacion.jsonl"
HASHES_TIT="$RUN_DIR/lista_titulacion.jsonl"

if [[ "$RESULTADO_REGISTRO" -eq 0 &&
      "$RESULTADO_SS" -eq 0 &&
      "$RESULTADO_CERT" -eq 0 &&
      "$RESULTADO_TIT" -eq 0 ]] &&
   extraer_lista "$REGISTRO_JSON" "$HASHES_REGISTRO" &&
   extraer_lista "$SS_JSON" "$HASHES_SS" &&
   extraer_lista "$CERT_JSON" "$HASHES_CERT" &&
   extraer_lista "$TIT_JSON" "$HASHES_TIT"; then

    if cmp -s "$HASHES_REGISTRO" "$HASHES_SS" &&
       cmp -s "$HASHES_REGISTRO" "$HASHES_CERT" &&
       cmp -s "$HASHES_REGISTRO" "$HASHES_TIT"; then
        echo "Hashes y TxID entre peers: PASS"
        HASHES_OK=0
    else
        echo "Hashes y TxID entre peers: FAIL"
        HASHES_OK=1
        FALLO_GLOBAL=1
    fi
else
    echo "Hashes y TxID entre peers: FAIL"
    echo "No se compararon listas incompletas o inválidas."
    HASHES_OK=1
    FALLO_GLOBAL=1
fi

# ============================================================
# RESULTADO GLOBAL
# ============================================================

TOTAL_EVIDENCIAS=0

if [[ -s "$REGISTRO_JSON" ]] &&
   jq -e 'type == "object"' "$REGISTRO_JSON" >/dev/null 2>&1; then
    TOTAL_EVIDENCIAS=$(jq -er '
        [.historialTransiciones[]
         | select(.tipo == "TRANSICION")] | length
    ' "$REGISTRO_JSON") || {
        TOTAL_EVIDENCIAS=0
        FALLO_GLOBAL=1
    }
else
    FALLO_GLOBAL=1
fi

if [[ "$RESULTADO_REGISTRO" -ne 0 ||
      "$RESULTADO_SS" -ne 0 ||
      "$RESULTADO_CERT" -ne 0 ||
      "$RESULTADO_TIT" -ne 0 ||
      "$HASHES_OK" -ne 0 ||
      "$FALLO_GLOBAL" -ne 0 ]]; then
    RESULTADO_GLOBAL="FAIL"
else
    RESULTADO_GLOBAL="PASS"
fi

echo
echo "============================================================"
echo "RESULTADO GLOBAL: $RESULTADO_GLOBAL"
echo "============================================================"
echo "Expediente consultado : $MATRICULA"
echo "Evidencias en Registro: $TOTAL_EVIDENCIAS"
echo "Peers verificados     : 4"
echo "Comparación entre peers: $([[ "$HASHES_OK" -eq 0 ]] && echo PASS || echo FAIL)"
echo "CSV                   : $CSV"
echo "Registro de ejecución : $LOG"
echo "Directorio de salida  : $RUN_DIR"
echo "============================================================"

if [[ "$RESULTADO_GLOBAL" == "PASS" ]]; then
    exit 0
else
    exit 1
fi