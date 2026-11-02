#!/bin/bash
set -euo pipefail

NETWORK_DIR="$HOME/hyperledger/fabric-samples/test-network-4org"
FABRIC_CFG_PATH="$HOME/hyperledger/fabric-samples/config"
export FABRIC_CFG_PATH

CHANNEL_NAME="uacmchannel"
CHAINCODE_NAME="uacm"

# ============================================================
# CONFIGURACIÓN DEL ORDERER
# ============================================================

ORDERER_ADDRESS="localhost:7050"
ORDERER_HOSTNAME="orderer.example.com"
ORDERER_CA="$NETWORK_DIR/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"

# ============================================================
# REGISTRO ESCOLAR
# ============================================================

REGISTRO_MSP="RegistroEscolarMSP"
REGISTRO_MSP_PATH="$NETWORK_DIR/organizations/peerOrganizations/registroescolar.uacm.edu.mx/users/Admin@registroescolar.uacm.edu.mx/msp"
REGISTRO_PEER="peer0.registroescolar.uacm.edu.mx:7051"
REGISTRO_TLS="$NETWORK_DIR/organizations/peerOrganizations/registroescolar.uacm.edu.mx/peers/peer0.registroescolar.uacm.edu.mx/tls/ca.crt"

# ============================================================
# SERVICIO SOCIAL
# ============================================================

SS_MSP="ServicioSocialMSP"
SS_MSP_PATH="$NETWORK_DIR/organizations/peerOrganizations/serviciosocial.uacm.edu.mx/users/Admin@serviciosocial.uacm.edu.mx/msp"
SS_PEER="peer0.serviciosocial.uacm.edu.mx:8051"
SS_TLS="$NETWORK_DIR/organizations/peerOrganizations/serviciosocial.uacm.edu.mx/peers/peer0.serviciosocial.uacm.edu.mx/tls/ca.crt"

# ============================================================
# CERTIFICACIÓN
# ============================================================

CERT_MSP="CertificacionMSP"
CERT_MSP_PATH="$NETWORK_DIR/organizations/peerOrganizations/certificacion.uacm.edu.mx/users/Admin@certificacion.uacm.edu.mx/msp"
CERT_PEER="peer0.certificacion.uacm.edu.mx:9051"
CERT_TLS="$NETWORK_DIR/organizations/peerOrganizations/certificacion.uacm.edu.mx/peers/peer0.certificacion.uacm.edu.mx/tls/ca.crt"

# ============================================================
# TITULACIÓN
# ============================================================

TIT_MSP="TitulacionMSP"
TIT_MSP_PATH="$NETWORK_DIR/organizations/peerOrganizations/titulacion.uacm.edu.mx/users/Admin@titulacion.uacm.edu.mx/msp"
TIT_PEER="peer0.titulacion.uacm.edu.mx:10051"
TIT_TLS="$NETWORK_DIR/organizations/peerOrganizations/titulacion.uacm.edu.mx/peers/peer0.titulacion.uacm.edu.mx/tls/ca.crt"

# ============================================================
# PERFILES DE LAS CUATRO ORGANIZACIONES
# Compatibilidad con los scripts de evaluación
# ============================================================

declare -A PERFIL_MSP
declare -A PERFIL_MSP_PATH
declare -A PERFIL_PEER
declare -A PERFIL_TLS

PERFIL_MSP[REGISTRO]="$REGISTRO_MSP"
PERFIL_MSP_PATH[REGISTRO]="$REGISTRO_MSP_PATH"
PERFIL_PEER[REGISTRO]="$REGISTRO_PEER"
PERFIL_TLS[REGISTRO]="$REGISTRO_TLS"

PERFIL_MSP[SS]="$SS_MSP"
PERFIL_MSP_PATH[SS]="$SS_MSP_PATH"
PERFIL_PEER[SS]="$SS_PEER"
PERFIL_TLS[SS]="$SS_TLS"

PERFIL_MSP[CERT]="$CERT_MSP"
PERFIL_MSP_PATH[CERT]="$CERT_MSP_PATH"
PERFIL_PEER[CERT]="$CERT_PEER"
PERFIL_TLS[CERT]="$CERT_TLS"

PERFIL_MSP[TIT]="$TIT_MSP"
PERFIL_MSP_PATH[TIT]="$TIT_MSP_PATH"
PERFIL_PEER[TIT]="$TIT_PEER"
PERFIL_TLS[TIT]="$TIT_TLS"

# ============================================================
# SELECCIONAR IDENTIDAD FABRIC
# ============================================================

usar_identidad() {
    export CORE_PEER_LOCALMSPID="$1"
    export CORE_PEER_MSPCONFIGPATH="$2"
    export CORE_PEER_ADDRESS="$3"
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_TLS_ROOTCERT_FILE="$4"

    # La invocación utiliza cuatro peers con diferentes
    # nombres TLS. No debe existir un override global.
    unset CORE_PEER_TLS_SERVERHOSTOVERRIDE
}

# ============================================================
# INVOCAR TRANSACCIÓN
# ============================================================

invocar() {
    # Conserva la identidad seleccionada por quien llama a esta función.

    local funcion="$1"
    shift

    local args_json
    args_json="$(printf '%s\n' "$@" | jq -R -s -c 'split("\n")[:-1]')"

    # Garantizar que ninguna variable de entorno externa
    # fuerce el hostname TLS de todos los peers.
    unset CORE_PEER_TLS_SERVERHOSTOVERRIDE

    peer chaincode invoke \
        -o "$ORDERER_ADDRESS" \
        --ordererTLSHostnameOverride "$ORDERER_HOSTNAME" \
        --tls \
        --cafile "$ORDERER_CA" \
        -C "$CHANNEL_NAME" \
        -n "$CHAINCODE_NAME" \
        --peerAddresses "$REGISTRO_PEER" \
        --tlsRootCertFiles "$REGISTRO_TLS" \
        --peerAddresses "$SS_PEER" \
        --tlsRootCertFiles "$SS_TLS" \
        --peerAddresses "$CERT_PEER" \
        --tlsRootCertFiles "$CERT_TLS" \
        --peerAddresses "$TIT_PEER" \
        --tlsRootCertFiles "$TIT_TLS" \
        -c "{\"function\":\"$funcion\",\"Args\":$args_json}" \
        --waitForEvent
}

# ============================================================
# CONSULTAR EXPEDIENTE
# ============================================================

consultar() {
    local id="$1"

    usar_identidad \
        "$REGISTRO_MSP" \
        "$REGISTRO_MSP_PATH" \
        "$REGISTRO_PEER" \
        "$REGISTRO_TLS"

    peer chaincode query \
        -C "$CHANNEL_NAME" \
        -n "$CHAINCODE_NAME" \
        -c "{\"function\":\"ConsultarExpediente\",\"Args\":[\"$id\"]}"
}

# ============================================================
# OBTENER TXID DE UNA TRANSICIÓN
# ============================================================

obtener_txid_evento() {
    local id="$1"
    local evento="$2"

    consultar "$id" |
        jq -r --arg evento "$evento" '
            .historialTransiciones[]
            | select(
                .tipo == "TRANSICION"
                and .evento == $evento
            )
            | .txId
        ' |
        tail -n 1
}

# ============================================================
# GENERAR NUEVA MATRÍCULA PARA PRUEBAS
# ============================================================

nuevo_id() {
    printf '99-9%02d-%04d' \
        "$((RANDOM % 100))" \
        "$((RANDOM % 10000))"
}

# ============================================================
# VERIFICAR ESTADO
# ============================================================

verificar_estado() {
    local id="$1"
    local esperado="$2"
    local actual

    actual="$(consultar "$id" | jq -r '.estadoActual')"

    echo "      Estado actual: $actual"

    [[ "$actual" == "$esperado" ]]
}

# ============================================================
# VERIFICAR SI EXISTE UN EXPEDIENTE
# Retorno:
#   0 = existe
#   1 = no existe
#   2 = error de consulta no reconocido
# ============================================================

existe_expediente() {
    local id="$1"
    local salida
    local rc

    salida="$(consultar "$id" 2>&1)"
    rc=$?

    if [[ "$rc" -eq 0 ]]; then
        if printf '%s\n' "$salida" | jq -e 'type == "object"' >/dev/null 2>&1; then
            return 0
        fi

        echo "ERROR: la consulta de $id no devolvió un objeto JSON válido." >&2
        return 2
    fi

    if printf '%s\n' "$salida" |
        grep -Fq "el expediente $id no existe"; then
        return 1
    fi

    echo "ERROR al consultar $id: $salida" >&2
    return 2
}