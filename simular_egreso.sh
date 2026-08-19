#!/bin/bash
# ================================================================================
# Proyecto UACM-Blockchain
# Simulación del Camino A del MED-EC
# Flujo:
# INSCRITO → DOC_VALIDADO → ACTIVO → CERTIFICADO → TITULADO
# ================================================================================

set -e

if [ $# -ne 1 ]; then
    echo "Uso: ./simular_egreso.sh <MATRICULA>"
    exit 1
fi

MATRICULA="$1"

echo "================================================================================"
echo "Simulación MED-EC - Camino A"
echo "INSCRITO → DOC_VALIDADO → ACTIVO → CERTIFICADO → TITULADO"
echo "Matrícula: $MATRICULA"
echo "================================================================================"

HASH_INSCR=$(echo -n "${MATRICULA}_FOL-2026-INSCRIPCION" | sha256sum | awk '{print $1}')
HASH_DOCS=$(echo -n "${MATRICULA}_FOL-2026-DOCS-UACM" | sha256sum | awk '{print $1}')
HASH_ACTIVO=$(echo -n "${MATRICULA}_FOL-2026-ACTIVO" | sha256sum | awk '{print $1}')
HASH_CERT=$(echo -n "${MATRICULA}_FOL-2026-CERTIFICADO" | sha256sum | awk '{print $1}')
HASH_TITULO=$(echo -n "${MATRICULA}_FOL-2026-TITULACION" | sha256sum | awk '{print $1}')

NETWORK_DIR="/home/rafa/hyperledger/fabric-samples/test-network"
export PATH="/home/rafa/hyperledger/fabric-samples/bin:$PATH"
export FABRIC_CFG_PATH="/home/rafa/hyperledger/fabric-samples/config/"
export CORE_PEER_TLS_ENABLED=true

ORDERER_ARGS="-o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $NETWORK_DIR/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt"
CHANNEL_ARGS="-C canal-uacm -n uacm-contract"
PEERS_ARGS="--peerAddresses localhost:7051 --tlsRootCertFiles $NETWORK_DIR/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem --peerAddresses localhost:9051 --tlsRootCertFiles $NETWORK_DIR/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem"

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

cargar_org1
echo
echo "========== ETAPA 1: Registro Escolar =========="
echo "CU-01 Registrar trayectoria académica"
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"RegistrarInscripcion\",\"$MATRICULA\",\"$HASH_INSCR\"]}"
sleep 3

echo "CU-02 Validar documentación"
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"ValidarDocumentos\",\"$MATRICULA\",\"$HASH_DOCS\"]}"
sleep 3

cargar_org2
echo
echo "========== ETAPA 2: Confirmación de activo =========="
echo "CU-03 Confirmar activo"
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"ConfirmarActivo\",\"$MATRICULA\",\"$HASH_ACTIVO\"]}"
sleep 3

echo
echo "========== ETAPA 3: Certificación =========="
echo "CU-06 Emitir certificado"
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"EmitirCertificado\",\"$MATRICULA\",\"$HASH_CERT\"]}"
sleep 3

echo
echo "========== ETAPA 4: Titulación =========="
echo "CU-07 Emitir título"
peer chaincode invoke $ORDERER_ARGS $CHANNEL_ARGS $PEERS_ARGS -c "{\"Args\":[\"EmitirTitulo\",\"$MATRICULA\",\"$HASH_TITULO\"]}"
sleep 3

echo
echo "========== EXPEDIENTE FINAL =========="
peer chaincode query $CHANNEL_ARGS -c "{\"Args\":[\"ConsultarExpediente\",\"$MATRICULA\"]}" | jq '.'
echo
echo "Simulación finalizada correctamente."
