#!/usr/bin/env bash
set -u

cd "$(dirname "$0")"
source ./00_lib_pruebas_medec.sh

set +e

# ============================================================
# CONFIGURACIÓN
# ============================================================

PEER_CAIDO="peer0.registroescolar.uacm.edu.mx"

# Permite proporcionar una matrícula diferente al ejecutar
# el script. El valor predeterminado usa un sufijo temporal.
SUFIJO=$(( $(date +%s) % 9998 + 1 ))
MATRICULA_PRUEBA="${MATRICULA_PRUEBA:-$(printf '29-005-%04d' "$((SUFIJO + 1))")}"

RESULTADOS_DIR="./resultados"
mkdir -p "$RESULTADOS_DIR"

CSV="$RESULTADOS_DIR/resiliencia_mayoria_$(date +%Y%m%d_%H%M%S).csv"
echo "fase,operacion,peer,resultado,detalle" > "$CSV"

PEER_DETENIDO=0
RESULTADO_ESCRITURA="NO_EJECUTADA"
RESULTADO_GLOBAL=0

# ============================================================
# UTILIDADES
# ============================================================

contenedor_activo() {
    docker ps --format '{{.Names}}' |
        grep -Fx "$1" > /dev/null 2>&1
}

esperar_peer() {
    local peer="$1"
    local intentos=0

    while (( intentos < 30 )); do
        if contenedor_activo "$peer"; then
            return 0
        fi

        sleep 1
        intentos=$((intentos + 1))
    done

    return 1
}

registrar_resultado() {
    printf '%s,%s,%s,%s,%s\n' \
        "$1" "$2" "$3" "$4" "$5" >> "$CSV"
}

validar_matricula_nueva() {
    local matricula="$1"
    local rc

    existe_expediente "$matricula"
    rc=$?

    case "$rc" in
        1)
            echo "PASS: la matrícula $matricula no existe."
            return 0
            ;;
        0)
            echo "ERROR: la matrícula $matricula ya existe." >&2
            return 1
            ;;
        *)
            echo "ERROR: no se pudo verificar la matrícula $matricula." >&2
            return 2
            ;;
    esac
}

consultar_desde_peer() {
    local msp="$1"
    local msp_path="$2"
    local peer="$3"
    local tls="$4"
    local matricula="${5:-$MATRICULA_REFERENCIA}"

    usar_identidad "$msp" "$msp_path" "$peer" "$tls" || return 1

    peer chaincode query \
        -C "$CHANNEL_NAME" \
        -n "$CHAINCODE_NAME" \
        -c "{\"function\":\"ConsultarExpediente\",\"Args\":[\"$matricula\"]}"
}

# ============================================================
# INVOCACIÓN ESPECÍFICA:
# SOLICITA ENDOSOS SOLO A LOS TRES PEERS DISPONIBLES.
#
# La identidad de la transacción sigue siendo Registro Escolar.
# El peer local utilizado para ejecutar el comando es Servicio
# Social, que permanece disponible.
# ============================================================


invocar_con_tres_peers() {
    local funcion="$1"
    shift

    local args_json
    local payload
    local salida
    local rc

    args_json=$(printf '%s\n' "$@" | jq -R . | jq -s .) || return 1

    payload=$(jq -cn \
        --arg function "$funcion" \
        --argjson args "$args_json" \
        '{function:$function,Args:$args}') || return 1

    # Identidad autorizada de Registro Escolar,
    # conexión local mediante el peer disponible de Servicio Social.
    usar_identidad \
        "${PERFIL_MSP[REGISTRO]}" \
        "${PERFIL_MSP_PATH[REGISTRO]}" \
        "${PERFIL_PEER[SS]}" \
        "${PERFIL_TLS[SS]}" || return 1

    unset CORE_PEER_TLS_SERVERHOSTOVERRIDE

    if salida=$(peer chaincode invoke \
        -o "$ORDERER_ADDRESS" \
        --ordererTLSHostnameOverride "$ORDERER_HOSTNAME" \
        --tls \
        --cafile "$ORDERER_CA" \
        -C "$CHANNEL_NAME" \
        -n "$CHAINCODE_NAME" \
        --peerAddresses "${PERFIL_PEER[SS]}" \
        --tlsRootCertFiles "${PERFIL_TLS[SS]}" \
        --peerAddresses "${PERFIL_PEER[CERT]}" \
        --tlsRootCertFiles "${PERFIL_TLS[CERT]}" \
        --peerAddresses "${PERFIL_PEER[TIT]}" \
        --tlsRootCertFiles "${PERFIL_TLS[TIT]}" \
        --waitForEvent \
        -c "$payload" 2>&1); then
        rc=0
    else
        rc=$?
    fi

    printf '%s\n' "$salida"

    if (( rc != 0 )); then
        return "$rc"
    fi

    if ! grep -Eiq 'committed with status \(VALID\)|Chaincode invoke successful' <<< "$salida"; then
        echo "ERROR: la invocación no confirmó una transacción válida." >&2
        return 1
    fi

    return 0
}


# ============================================================
# RECUPERACIÓN DE SEGURIDAD
# Intenta levantar el peer si el script termina inesperadamente.
# ============================================================

recuperar_si_necesario() {
    if [[ "$PEER_DETENIDO" -eq 1 ]]; then
        echo
        echo "AVISO: intentando recuperar $PEER_CAIDO..."

        if docker start "$PEER_CAIDO" && esperar_peer "$PEER_CAIDO"; then
            PEER_DETENIDO=0
            echo "El contenedor volvió a estar activo."
        else
            echo "ERROR: no se pudo confirmar la recuperación de $PEER_CAIDO."
        fi
    fi
}

trap recuperar_si_necesario EXIT

# ============================================================
# INICIO
# ============================================================

echo
echo "============================================================"
echo " PRUEBA DE RESILIENCIA CORREGIDA"
echo "============================================================"
echo "Canal      : $CHANNEL_NAME"
echo "Chaincode  : $CHAINCODE_NAME"
echo "Peer caído : $PEER_CAIDO"
echo "Matrícula  : $MATRICULA_PRUEBA"
echo "CSV        : $CSV"
echo

# Comprobar herramientas necesarias.
for herramienta in docker peer jq; do
    if ! command -v "$herramienta" > /dev/null 2>&1; then
        echo "ERROR: no se encuentra el comando $herramienta."
        exit 1
    fi
done

# Comprobar que la red comienza con los cuatro peers activos.
for p in \
    "peer0.registroescolar.uacm.edu.mx" \
    "peer0.serviciosocial.uacm.edu.mx" \
    "peer0.certificacion.uacm.edu.mx" \
    "peer0.titulacion.uacm.edu.mx"
do
    if ! contenedor_activo "$p"; then
        echo "ERROR: el peer $p no está activo."
        echo "Inicia la red completa antes de ejecutar la prueba."
        exit 1
    fi
done

# ============================================================
# FASE 1: RED COMPLETA
# Registrar un expediente de referencia antes de la falla.
# ============================================================

echo "FASE 1: Verificar la red completa."

for p in \
    "peer0.registroescolar.uacm.edu.mx" \
    "peer0.serviciosocial.uacm.edu.mx" \
    "peer0.certificacion.uacm.edu.mx" \
    "peer0.titulacion.uacm.edu.mx"
do
    if ! contenedor_activo "$p"; then
        echo "ERROR: el peer $p no está activo."
        echo "No se realizará la prueba."
        exit 1
    fi
done

echo "Los cuatro peers están activos."

MATRICULA_REFERENCIA="${MATRICULA_REFERENCIA:-$(printf '28-005-%04d' "$SUFIJO")}"

if ! validar_matricula_nueva "$MATRICULA_REFERENCIA"; then
    echo "ERROR: no se puede continuar con la matrícula de referencia."
    exit 1
fi

if ! validar_matricula_nueva "$MATRICULA_PRUEBA"; then
    echo "ERROR: no se puede continuar con la matrícula de prueba."
    exit 1
fi

echo "Registrando expediente de referencia: $MATRICULA_REFERENCIA"

usar_identidad \
    "${PERFIL_MSP[REGISTRO]}" \
    "${PERFIL_MSP_PATH[REGISTRO]}" \
    "${PERFIL_PEER[REGISTRO]}" \
    "${PERFIL_TLS[REGISTRO]}" || {
        echo "ERROR: no se pudo configurar la identidad de Registro Escolar."
        exit 1
    }

if SALIDA=$(invocar "RegistrarInscripcion" "$MATRICULA_REFERENCIA" 2>&1); then
    echo "PASS: expediente de referencia registrado."
    registrar_resultado "FASE_1" "RegistrarInscripcion" \
        "${PERFIL_MSP[REGISTRO]}" "PASS" "red_completa"
else
    echo "ERROR: no se pudo registrar el expediente de referencia."
    printf '%s\n' "$SALIDA"
    registrar_resultado "FASE_1" "RegistrarInscripcion" \
        "${PERFIL_MSP[REGISTRO]}" "FAIL" "red_completa"
    exit 1
fi

echo
echo "FASE 1: Detener el peer de Registro Escolar."

# Activar la protección antes de intentar detener el contenedor.
PEER_DETENIDO=1

if ! docker stop "$PEER_CAIDO"; then
    registrar_resultado "FASE_1" "DetenerPeer" "$PEER_CAIDO" \
        "FAIL" "no_se_pudo_detener"
    exit 1
fi

sleep 3

if contenedor_activo "$PEER_CAIDO"; then
    registrar_resultado "FASE_1" "VerificarFalla" "$PEER_CAIDO" \
        "FAIL" "sigue_activo"
    exit 1
fi

registrar_resultado "FASE_1" "VerificarFalla" "$PEER_CAIDO" \
    "PASS" "peer_detenido"

echo "PASS: Registro Escolar está detenido."
echo

# ============================================================
# FASE 2: ESCRITURA CON LOS TRES PEERS RESTANTES
# ============================================================

echo "FASE 2: Registrar un expediente con tres peers disponibles."
echo "Criterio: la invocación debe confirmarse con Registro Escolar detenido."
echo

if SALIDA=$(invocar_con_tres_peers \
    "RegistrarInscripcion" "$MATRICULA_PRUEBA" 2>&1); then
    echo "PASS: la escritura fue confirmada con Registro Escolar detenido."
    printf '%s\n' "$SALIDA"
    registrar_resultado "FASE_2" "RegistrarInscripcion" \
        "SS_CERT_TIT" "PASS" "escritura_confirmada_con_peer_caido"
    RESULTADO_ESCRITURA="PASS"
else
    echo "FAIL: la escritura no se pudo confirmar con Registro Escolar detenido."
    printf '%s\n' "$SALIDA"
    registrar_resultado "FASE_2" "RegistrarInscripcion" \
        "SS_CERT_TIT" "FAIL" "escritura_fallida_con_peer_caido"
    RESULTADO_ESCRITURA="FAIL"
    RESULTADO_GLOBAL=1
fi
echo

# ============================================================
# FASE 3: CONSULTA EN LOS TRES PEERS DISPONIBLES
# ============================================================

echo "FASE 3: Verificar el expediente creado durante la caída en los tres peers disponibles."

for IDENTIDAD in SS CERT TIT; do
    case "$IDENTIDAD" in
        SS)
            MSP="${PERFIL_MSP[SS]}"
            MSP_PATH="${PERFIL_MSP_PATH[SS]}"
            PEER="${PERFIL_PEER[SS]}"
            TLS="${PERFIL_TLS[SS]}"
            NOMBRE="${PERFIL_MSP[SS]}"
            ;;
        CERT)
            MSP="${PERFIL_MSP[CERT]}"
            MSP_PATH="${PERFIL_MSP_PATH[CERT]}"
            PEER="${PERFIL_PEER[CERT]}"
            TLS="${PERFIL_TLS[CERT]}"
            NOMBRE="${PERFIL_MSP[CERT]}"
            ;;
        TIT)
            MSP="${PERFIL_MSP[TIT]}"
            MSP_PATH="${PERFIL_MSP_PATH[TIT]}"
            PEER="${PERFIL_PEER[TIT]}"
            TLS="${PERFIL_TLS[TIT]}"
            NOMBRE="${PERFIL_MSP[TIT]}"
            ;;
    esac

    if SALIDA=$(consultar_desde_peer \
        "$MSP" "$MSP_PATH" "$PEER" "$TLS" "$MATRICULA_PRUEBA" 2>&1); then

        if printf '%s' "$SALIDA" | jq -e --arg id "$MATRICULA_PRUEBA" '
            .id == $id and
            .estadoActual == "INSCRITO" and
            (.historialTransiciones | type == "array") and
            ([.historialTransiciones[] |
                select(.tipo == "TRANSICION" and
                       .evento == "INSCRIPCION" and
                       .estadoNuevo == "INSCRITO")] | length >= 1)
        ' >/dev/null 2>&1; then
            echo "$NOMBRE: consulta PASS; matrícula confirmada."
            printf '%s\n' "$SALIDA"
            registrar_resultado "FASE_3" "ConsultarExpediente" \
                "$NOMBRE" "PASS" "matricula_confirmada"
        else
            echo "$NOMBRE: consulta FAIL; no se confirmó la matrícula esperada."
            printf '%s\n' "$SALIDA"
            registrar_resultado "FASE_3" "ConsultarExpediente" \
                "$NOMBRE" "FAIL" "matricula_no_confirmada"
            RESULTADO_GLOBAL=1
        fi

    else
        echo "$NOMBRE: consulta FAIL"
        printf '%s\n' "$SALIDA"

        registrar_resultado "FASE_3" "ConsultarExpediente" \
            "$NOMBRE" "FAIL" "peer_disponible"

        RESULTADO_GLOBAL=1
    fi

    echo
done

# ============================================================
# FASE 4: RECUPERACIÓN DEL PEER
# ============================================================

echo "FASE 4: Recuperar el peer de Registro Escolar."

if docker start "$PEER_CAIDO"; then
    if esperar_peer "$PEER_CAIDO"; then
        PEER_DETENIDO=0
        registrar_resultado "FASE_4" "LevantarPeer" "$PEER_CAIDO" \
            "PASS" "contenedor_activo"
        echo "Contenedor activo. Esperando estabilización del peer..."
        sleep 10
    else
        echo "ERROR: el peer no volvió a estar activo."
        registrar_resultado "FASE_4" "LevantarPeer" "$PEER_CAIDO" \
            "FAIL" "timeout"
        RESULTADO_GLOBAL=1
    fi
else
    echo "ERROR: no se pudo iniciar el contenedor del peer."
    registrar_resultado "FASE_4" "LevantarPeer" "$PEER_CAIDO" \
        "FAIL" "error_inicio"
    RESULTADO_GLOBAL=1
fi

# ============================================================
# FASE 5: VERIFICACIÓN DESPUÉS DE LA RECUPERACIÓN
# ============================================================

if [[ "$PEER_DETENIDO" -eq 0 ]] && contenedor_activo "$PEER_CAIDO"; then
    echo
    echo "FASE 5: Consultar el expediente desde los cuatro peers."

    for IDENTIDAD in REGISTRO SS CERT TIT; do
        case "$IDENTIDAD" in
            REGISTRO)
                MSP="${PERFIL_MSP[REGISTRO]}"
                MSP_PATH="${PERFIL_MSP_PATH[REGISTRO]}"
                PEER="${PERFIL_PEER[REGISTRO]}"
                TLS="${PERFIL_TLS[REGISTRO]}"
                NOMBRE="${PERFIL_MSP[REGISTRO]}"
                ;;
            SS)
                MSP="${PERFIL_MSP[SS]}"
                MSP_PATH="${PERFIL_MSP_PATH[SS]}"
                PEER="${PERFIL_PEER[SS]}"
                TLS="${PERFIL_TLS[SS]}"
                NOMBRE="${PERFIL_MSP[SS]}"
                ;;
            CERT)
                MSP="${PERFIL_MSP[CERT]}"
                MSP_PATH="${PERFIL_MSP_PATH[CERT]}"
                PEER="${PERFIL_PEER[CERT]}"
                TLS="${PERFIL_TLS[CERT]}"
                NOMBRE="${PERFIL_MSP[CERT]}"
                ;;
            TIT)
                MSP="${PERFIL_MSP[TIT]}"
                MSP_PATH="${PERFIL_MSP_PATH[TIT]}"
                PEER="${PERFIL_PEER[TIT]}"
                TLS="${PERFIL_TLS[TIT]}"
                NOMBRE="${PERFIL_MSP[TIT]}"
                ;;
        esac

                if SALIDA=$(consultar_desde_peer \
            "$MSP" "$MSP_PATH" "$PEER" "$TLS" "$MATRICULA_PRUEBA" 2>&1); then

            if printf '%s' "$SALIDA" |
                jq -e --arg id "$MATRICULA_PRUEBA" '
                    .id == $id and
                    .estadoActual == "INSCRITO" and
                    (.historialTransiciones | type == "array") and
                    ([.historialTransiciones[] |
                        select(.tipo == "TRANSICION" and
                               .evento == "INSCRIPCION" and
                               .estadoNuevo == "INSCRITO")] | length >= 1)
                ' >/dev/null 2>&1; then

                echo "$NOMBRE: consulta PASS; matrícula confirmada."
                registrar_resultado "FASE_5" "ConsultaPostRecuperacion" \
                    "$NOMBRE" "PASS" "matricula_confirmada"
            else
                echo "$NOMBRE: consulta FAIL; matrícula no confirmada."
                printf '%s\n' "$SALIDA"
                registrar_resultado "FASE_5" "ConsultaPostRecuperacion" \
                    "$NOMBRE" "FAIL" "matricula_no_confirmada"
                RESULTADO_GLOBAL=1
            fi

        else
            echo "$NOMBRE: consulta FAIL; error de consulta."
            printf '%s\n' "$SALIDA"
            registrar_resultado "FASE_5" "ConsultaPostRecuperacion" \
                "$NOMBRE" "FAIL" "consulta_fallida"
            RESULTADO_GLOBAL=1
        fi
    done
else
    echo "No se pudo verificar el expediente en los cuatro peers."
    registrar_resultado "FASE_5" "ConsultaPostRecuperacion" \
        "$PEER_CAIDO" "FAIL" "peer_no_recuperado"
    RESULTADO_GLOBAL=1
fi

# ============================================================
# RESUMEN
# ============================================================

echo
echo "============================================================"
echo " RESULTADO DE LA PRUEBA"
echo "============================================================"
echo "Escritura con tres peers : $RESULTADO_ESCRITURA"
echo "Matrícula                : $MATRICULA_PRUEBA"
echo "CSV                      : $CSV"

if [[ "$RESULTADO_GLOBAL" -eq 0 && "$RESULTADO_ESCRITURA" == "PASS" ]]; then
    echo "Resultado global         : PASS"
    registrar_resultado "FINAL" "ResultadoGlobal" "RED" \
        "PASS" "escritura_y_consultas_confirmadas"
else
    echo "Resultado global         : FAIL"
    registrar_resultado "FINAL" "ResultadoGlobal" "RED" \
        "FAIL" "revisar_resultados"
fi

echo "============================================================"

exit "$RESULTADO_GLOBAL"
rafa@DESKTOP-9LHUF5R:~/hyperledger/blockchain-uacm-4org$