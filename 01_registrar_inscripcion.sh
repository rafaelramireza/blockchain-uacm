#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 01_registrar_inscripcion.sh
#
# MED-EC
# RegistrarInscripcion()
#
# Registro de la inscripción inicial del expediente.
#
# Estado inicial:
#     INSCRITO
#
# La transacción es respaldada por las cuatro organizaciones
# de la red, de acuerdo con la política de endorsement actual.
# ============================================================

# ------------------------------------------------------------
# 0. Configuración
# ------------------------------------------------------------

export FABRIC_CFG_PATH="$HOME/hyperledger/fabric-samples/config"

TEST_NETWORK="$HOME/hyperledger/fabric-samples/test-network-4org"

CHAINCODE_NAME="uacm"
CHANNEL_NAME="uacmchannel"

ORDERER_ADDRESS="localhost:7050"
ORDERER_HOSTNAME="orderer.example.com"

ORDERER_CA="$TEST_NETWORK/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"

# ------------------------------------------------------------
# 1. Registro Escolar
# ------------------------------------------------------------

REGISTRO_MSP="RegistroEscolarMSP"

REGISTRO_MSP_PATH="$TEST_NETWORK/organizations/peerOrganizations/registroescolar.uacm.edu.mx/users/Admin@registroescolar.uacm.edu.mx/msp"

REGISTRO_PEER="peer0.registroescolar.uacm.edu.mx:7051"

REGISTRO_TLS="$TEST_NETWORK/organizations/peerOrganizations/registroescolar.uacm.edu.mx/peers/peer0.registroescolar.uacm.edu.mx/tls/ca.crt"

# ------------------------------------------------------------
# 2. Servicio Social
# ------------------------------------------------------------

SS_MSP="ServicioSocialMSP"

SS_MSP_PATH="$TEST_NETWORK/organizations/peerOrganizations/serviciosocial.uacm.edu.mx/users/Admin@serviciosocial.uacm.edu.mx/msp"

SS_PEER="peer0.serviciosocial.uacm.edu.mx:8051"

SS_TLS="$TEST_NETWORK/organizations/peerOrganizations/serviciosocial.uacm.edu.mx/peers/peer0.serviciosocial.uacm.edu.mx/tls/ca.crt"

# ------------------------------------------------------------
# 3. Certificación
# ------------------------------------------------------------

CERT_MSP="CertificacionMSP"

CERT_MSP_PATH="$TEST_NETWORK/organizations/peerOrganizations/certificacion.uacm.edu.mx/users/Admin@certificacion.uacm.edu.mx/msp"

CERT_PEER="peer0.certificacion.uacm.edu.mx:9051"

CERT_TLS="$TEST_NETWORK/organizations/peerOrganizations/certificacion.uacm.edu.mx/peers/peer0.certificacion.uacm.edu.mx/tls/ca.crt"

# ------------------------------------------------------------
# 4. Titulación
# ------------------------------------------------------------

TIT_MSP="TitulacionMSP"

TIT_MSP_PATH="$TEST_NETWORK/organizations/peerOrganizations/titulacion.uacm.edu.mx/users/Admin@titulacion.uacm.edu.mx/msp"

TIT_PEER="peer0.titulacion.uacm.edu.mx:10051"

TIT_TLS="$TEST_NETWORK/organizations/peerOrganizations/titulacion.uacm.edu.mx/peers/peer0.titulacion.uacm.edu.mx/tls/ca.crt"

# ------------------------------------------------------------
# 5. Validar argumentos
# ------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    echo
    echo "Uso:"
    echo "  $0 <matricula>"
    echo
    echo "Ejemplo:"
    echo "  $0 11-011-0656"
    echo
    exit 1
fi

MATRICULA="$1"

# ------------------------------------------------------------
# 6. Seleccionar identidad Fabric
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

    # Importante:
    # La invocación utiliza cuatro peers con diferentes nombres TLS.
    # No debe existir un override global de hostname.
    unset CORE_PEER_TLS_SERVERHOSTOVERRIDE
}

# ------------------------------------------------------------
# 7. Verificar infraestructura
# ------------------------------------------------------------

echo
echo "============================================================"
echo " MED-EC - REGISTRAR INSCRIPCIÓN"
echo "============================================================"
echo

echo "===== VERIFICANDO INFRAESTRUCTURA ====="

if [[ ! -d "$TEST_NETWORK" ]]; then
    echo "ERROR: no existe la red:"
    echo "$TEST_NETWORK"
    exit 1
fi

if [[ ! -f "$ORDERER_CA" ]]; then
    echo "ERROR: no existe el certificado TLS del orderer:"
    echo "$ORDERER_CA"
    exit 1
fi

if [[ ! -f "$REGISTRO_TLS" ]]; then
    echo "ERROR: no existe el certificado TLS de Registro Escolar:"
    echo "$REGISTRO_TLS"
    exit 1
fi

if [[ ! -f "$SS_TLS" ]]; then
    echo "ERROR: no existe el certificado TLS de Servicio Social:"
    echo "$SS_TLS"
    exit 1
fi

if [[ ! -f "$CERT_TLS" ]]; then
    echo "ERROR: no existe el certificado TLS de Certificación:"
    echo "$CERT_TLS"
    exit 1
fi

if [[ ! -f "$TIT_TLS" ]]; then
    echo "ERROR: no existe el certificado TLS de Titulación:"
    echo "$TIT_TLS"
    exit 1
fi

echo "Infraestructura TLS: OK"

# ------------------------------------------------------------
# 8. Identidad que ejecutará RegistrarInscripcion
# ------------------------------------------------------------

echo
echo "===== IDENTIDAD ====="

usar_identidad \
    "$REGISTRO_MSP" \
    "$REGISTRO_MSP_PATH" \
    "$REGISTRO_PEER" \
    "$REGISTRO_TLS"

echo "MSP     : $CORE_PEER_LOCALMSPID"
echo "Peer    : $CORE_PEER_ADDRESS"
echo "TLS CA  : $CORE_PEER_TLS_ROOTCERT_FILE"

# ------------------------------------------------------------
# 9. Invocar RegistrarInscripcion
# ------------------------------------------------------------

echo
echo "===== REGISTRANDO INSCRIPCIÓN ====="
echo
echo "Matrícula: $MATRICULA"
echo

HASH="hash-inscripcion-${MATRICULA}"

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
    -c "{\"function\":\"RegistrarInscripcion\",\"Args\":[\"$MATRICULA\",\"$HASH\"]}" \
    --waitForEvent

# ------------------------------------------------------------
# 10. Resultado
# ------------------------------------------------------------

echo
echo "============================================================"
echo " REGISTRAR INSCRIPCIÓN: OK"
echo "============================================================"
echo
echo "Matrícula : $MATRICULA"
echo "Estado    : INSCRITO"
echo
