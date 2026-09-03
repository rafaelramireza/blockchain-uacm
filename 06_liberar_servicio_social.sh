#!/usr/bin/env bash

set -euo pipefail
export FABRIC_CFG_PATH="$HOME/hyperledger/fabric-samples/config"

# ============================================================
# OPERACIÓN 06 - LIBERAR SERVICIO SOCIAL
#
# Ejecuta únicamente:
#
# LiberarServicioSocial()
#        ↓
#    SS_LIBERADO
#
# Uso:
#   ./06_liberar_servicio_social.sh ##-###-####
#
# Ejemplo:
#   ./06_liberar_servicio_social.sh 13-011-1261
#
# ============================================================


# ------------------------------------------------------------
# Validar argumentos
# ------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    echo "Uso: $0 ##-###-####"
    echo "Ejemplo: $0 13-011-1261"
    exit 1
fi

MATRICULA="$1"


# ------------------------------------------------------------
# Validar formato de matrícula
# ------------------------------------------------------------

if [[ ! "$MATRICULA" =~ ^[0-9]{2}-[0-9]{3}-[0-9]{4}$ ]]; then
    echo "ERROR: la matrícula debe tener el formato ##-###-####"
    echo "Ejemplo válido: 13-011-1261"
    exit 1
fi


# ------------------------------------------------------------
# Rutas de Hyperledger Fabric
# ------------------------------------------------------------

TEST_NETWORK="$HOME/hyperledger/fabric-samples/test-network-4org"

CHAINCODE_NAME="uacm"
CHANNEL_NAME="uacmchannel"

ORDERER_ADDRESS="localhost:7050"
ORDERER_HOSTNAME="orderer.example.com"

ORDERER_CA="$TEST_NETWORK/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"


# ------------------------------------------------------------
# Organización: Registro Escolar
# ------------------------------------------------------------

REGISTRO_PEER="peer0.registroescolar.uacm.edu.mx:7051"

REGISTRO_TLS="$TEST_NETWORK/organizations/peerOrganizations/registroescolar.uacm.edu.mx/peers/peer0.registroescolar.uacm.edu.mx/tls/ca.crt"


# ------------------------------------------------------------
# Organización: Servicio Social
# ------------------------------------------------------------

SS_MSP="ServicioSocialMSP"

SS_MSP_PATH="$TEST_NETWORK/organizations/peerOrganizations/serviciosocial.uacm.edu.mx/users/Admin@serviciosocial.uacm.edu.mx/msp"

SS_PEER="peer0.serviciosocial.uacm.edu.mx:8051"

SS_TLS="$TEST_NETWORK/organizations/peerOrganizations/serviciosocial.uacm.edu.mx/peers/peer0.serviciosocial.uacm.edu.mx/tls/ca.crt"


# ------------------------------------------------------------
# Organización: Certificación
# ------------------------------------------------------------

CERT_PEER="peer0.certificacion.uacm.edu.mx:9051"

CERT_TLS="$TEST_NETWORK/organizations/peerOrganizations/certificacion.uacm.edu.mx/peers/peer0.certificacion.uacm.edu.mx/tls/ca.crt"


# ------------------------------------------------------------
# Organización: Titulación
# ------------------------------------------------------------

TIT_PEER="peer0.titulacion.uacm.edu.mx:10051"

TIT_TLS="$TEST_NETWORK/organizations/peerOrganizations/titulacion.uacm.edu.mx/peers/peer0.titulacion.uacm.edu.mx/tls/ca.crt"


# ============================================================
# FUNCIONES
# ============================================================


# ------------------------------------------------------------
# Configurar identidad del invocador
# ------------------------------------------------------------

usar_identidad() {

    local msp="$1"
    local msp_path="$2"
    local address="$3"
    local tls_ca="$4"

    export CORE_PEER_LOCALMSPID="$msp"
    export CORE_PEER_MSPCONFIGPATH="$msp_path"
    export CORE_PEER_ADDRESS="$address"
    export CORE_PEER_TLS_ENABLED=true
    export CORE_PEER_TLS_ROOTCERT_FILE="$tls_ca"

    unset CORE_PEER_TLS_SERVERHOSTOVERRIDE
}


# ------------------------------------------------------------
# Generar hash de prueba
# ------------------------------------------------------------

generar_hash() {

    local evento="$1"

    printf '%s|%s|%s' \
        "$MATRICULA" \
        "$evento" \
        "$(date +%s%N)" |
        sha256sum |
        awk '{print $1}'
}


# ------------------------------------------------------------
# Invocar transacción
#
# La política de endorsement actual exige la participación
# de las cuatro organizaciones.
# ------------------------------------------------------------

invocar() {

    local funcion="$1"
    local hash="$2"

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
        -c "{\"function\":\"$funcion\",\"Args\":[\"$MATRICULA\",\"$hash\"]}" \
        --waitForEvent
}


# ------------------------------------------------------------
# Consultar expediente
# ------------------------------------------------------------

consultar() {

    peer chaincode query \
        -C "$CHANNEL_NAME" \
        -n "$CHAINCODE_NAME" \
        -c "{\"function\":\"ConsultarExpediente\",\"Args\":[\"$MATRICULA\"]}"
}


# ============================================================
# INICIO
# ============================================================

echo
echo "============================================================"
echo "OPERACIÓN 06 - LIBERAR SERVICIO SOCIAL"
echo "============================================================"
echo
echo "Matrícula: $MATRICULA"
echo
echo "Operación:"
echo "    LiberarServicioSocial()"
echo
echo "Estado esperado:"
echo "    SS_LIBERADO"
echo


# ------------------------------------------------------------
# Configurar identidad de Servicio Social
# ------------------------------------------------------------

usar_identidad \
    "$SS_MSP" \
    "$SS_MSP_PATH" \
    "$SS_PEER" \
    "$SS_TLS"


# ------------------------------------------------------------
# Verificar que el expediente exista
# ------------------------------------------------------------

if ! consultar >/dev/null 2>&1; then

    echo "ERROR: el expediente $MATRICULA no existe."
    echo
    echo "Primero ejecute:"
    echo "./01_registrar_inscripcion.sh $MATRICULA"
    exit 1

fi

echo "Expediente encontrado: $MATRICULA"
echo


# ------------------------------------------------------------
# Ejecutar LiberarServicioSocial()
# ------------------------------------------------------------

echo "Ejecutando LiberarServicioSocial()..."

HASH="$(generar_hash "SERVICIO_SOCIAL_LIBERADO")"

invocar "LiberarServicioSocial" "$HASH"

echo
echo "LiberarServicioSocial() ejecutada correctamente."
echo


# ------------------------------------------------------------
# Consultar resultado
# ------------------------------------------------------------

echo "============================================================"
echo "EXPEDIENTE RESULTANTE"
echo "============================================================"
echo

consultar

echo
echo "============================================================"
echo "OPERACIÓN COMPLETADA"
echo "============================================================"
echo
echo "Estado esperado: SS_LIBERADO"
echo