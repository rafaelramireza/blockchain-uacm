#!/bin/bash
# ================================================================================
# Proyecto UACM-Blockchain
# Simulación del Camino A del MED-EC
# Flujo:
# INSCRITO → DOCUMENTACIÓN_VALIDADA → EGRESADO →
# CERTIFICADO → SERVICIO_SOCIAL → TITULACIÓN
# ================================================================================

set -e

#------------------------------------------------------------------------------
# Parámetros
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Parámetros de entrada
#------------------------------------------------------------------------------

if [ $# -ne 1 ]; then
    echo
    echo "Uso:"
    echo "    ./simular_egreso.sh <MATRICULA>"

    echo
    echo "Ejemplo:"
    echo "    ./simular_egreso.sh 11-011-0654"
    echo
    exit 1
fi

MATRICULA="$1"

echo "================================================================================"
echo "Simulación MED-EC - Camino A: INSCRITO
      ↓
DOCUMENTACIÓN_VALIDADA
      ↓
EGRESADO
      ↓
CERTIFICADO
      ↓
SERVICIO_SOCIAL_EN_CURSO
      ↓
SERVICIO_SOCIAL_LIBERADO
      ↓
TITULADO"
echo "Matrícula: $MATRICULA"
echo "================================================================================"

#------------------------------------------------------------------------------
# Generación de evidencias criptográficas (Off-Chain)
#------------------------------------------------------------------------------

HASH_INSCR=$(echo -n "${MATRICULA}_FOL-2026-INSCRIPCION" | sha256sum | awk '{print $1}')
HASH_DOCS=$(echo -n "${MATRICULA}_FOL-2026-DOCS-UACM" | sha256sum | awk '{print $1}')
HASH_EGRESO=$(echo -n "${MATRICULA}_FOL-2026-EGRESO" | sha256sum | awk '{print $1}')
HASH_CERT=$(echo -n "${MATRICULA}_FOL-2026-CERTIFICADO" | sha256sum | awk '{print $1}')
HASH_SS_INI=$(echo -n "${MATRICULA}_FOL-2026-SS-INICIO" | sha256sum | awk '{print $1}')
HASH_SS_LIB=$(echo -n "${MATRICULA}_FOL-2026-SS-LIBERACION" | sha256sum | awk '{print $1}')
HASH_ACTA=$(echo -n "${MATRICULA}_FOL-2026-TITULACION" | sha256sum | awk '{print $1}')

#------------------------------------------------------------------------------
# Configuración de la red
#------------------------------------------------------------------------------

NETWORK_DIR="/home/rafa/hyperledger/fabric-samples/test-network"

export PATH="/home/rafa/hyperledger/fabric-samples/bin:$PATH"
export FABRIC_CFG_PATH="/home/rafa/hyperledger/fabric-samples/config/"
export CORE_PEER_TLS_ENABLED=true

ORDERER_ARGS="-o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $NETWORK_DIR/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt"

CHANNEL_ARGS="-C canal-uacm -n uacm-contract"

PEERS_ARGS="--peerAddresses localhost:7051 --tlsRootCertFiles $NETWORK_DIR/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem \
--peerAddresses localhost:9051 --tlsRootCertFiles $NETWORK_DIR/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem"

#------------------------------------------------------------------------------
# Funciones de organización
#------------------------------------------------------------------------------

cargar_org1() {

    export CORE_PEER_LOCALMSPID="Org1MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE=$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
    export CORE_PEER_ADDRESS=localhost:7051

}

cargar_org2() {

    export CORE_PEER_LOCALMSPID="Org2MSP"
    export CORE_PEER_TLS_ROOTCERT_FILE=$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
    export CORE_PEER_MSPCONFIGPATH=$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
    export CORE_PEER_ADDRESS=localhost:9051

}

cd "$NETWORK_DIR"

#------------------------------------------------------------------------------
# Etapa 1
#------------------------------------------------------------------------------

echo
echo "========== ETAPA 1: Registro Escolar =========="

cargar_org1

echo "CU-01 Registrar trayectoria académica"

peer chaincode invoke \
$ORDERER_ARGS \
$CHANNEL_ARGS \
$PEERS_ARGS \
-c "{\"Args\":[\"RegistrarInscripcion\",\"$MATRICULA\",\"$HASH_INSCR\"]}"

sleep 3

echo "CU-02 Validar documentación"

peer chaincode invoke \
$ORDERER_ARGS \
$CHANNEL_ARGS \
$PEERS_ARGS \
-c "{\"Args\":[\"ValidarDocumentos\",\"$MATRICULA\",\"$HASH_DOCS\"]}"

sleep 3

#------------------------------------------------------------------------------
# Etapa 2
#------------------------------------------------------------------------------

echo
echo "========== ETAPA 2: Confirmación de egreso =========="

cargar_org2

echo "CU-03 Confirmar egreso"

peer chaincode invoke \
$ORDERER_ARGS \
$CHANNEL_ARGS \
$PEERS_ARGS \
-c "{\"Args\":[\"ConfirmarEgreso\",\"$MATRICULA\",\"$HASH_EGRESO\"]}"

sleep 3

#------------------------------------------------------------------------------
# Etapa 3
#------------------------------------------------------------------------------

echo
echo "========== ETAPA 3: Certificación =========="

echo "CU-06 Emitir certificado"

peer chaincode invoke \
$ORDERER_ARGS \
$CHANNEL_ARGS \
$PEERS_ARGS \
-c "{\"Args\":[\"EmitirCertificado\",\"$MATRICULA\",\"$HASH_CERT\"]}"

sleep 3

#------------------------------------------------------------------------------
# Etapa 4
#------------------------------------------------------------------------------

echo
echo "========== ETAPA 4: Servicio Social =========="

cargar_org1

echo "CU-04 Registrar inicio del Servicio Social"

peer chaincode invoke \
$ORDERER_ARGS \
$CHANNEL_ARGS \
$PEERS_ARGS \
-c "{\"Args\":[\"IniciarServicioSocial\",\"$MATRICULA\",\"$HASH_SS_INI\"]}"

sleep 3

echo "CU-05 Registrar liberación del Servicio Social"

peer chaincode invoke \
$ORDERER_ARGS \
$CHANNEL_ARGS \
$PEERS_ARGS \
-c "{\"Args\":[\"LiberarServicioSocial\",\"$MATRICULA\",\"$HASH_SS_LIB\"]}"

sleep 3

#------------------------------------------------------------------------------
# Etapa 5
#------------------------------------------------------------------------------

echo
echo "========== ETAPA 5: Titulación =========="

cargar_org2

echo "CU-07 Registrar titulación"

peer chaincode invoke \
$ORDERER_ARGS \
$CHANNEL_ARGS \
$PEERS_ARGS \
-c "{\"Args\":[\"RegistrarTitulacion\",\"$MATRICULA\",\"$HASH_ACTA\"]}"

sleep 3

#------------------------------------------------------------------------------
# Consulta final
#------------------------------------------------------------------------------

echo
echo "========== EXPEDIENTE FINAL =========="

peer chaincode query \
$CHANNEL_ARGS \
-c "{\"Args\":[\"ConsultarExpediente\",\"$MATRICULA\"]}" | jq '.'

echo
echo "Simulación finalizada correctamente."