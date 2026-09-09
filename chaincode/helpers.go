package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-chaincode-go/pkg/cid"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// crearClaveExpediente genera la clave compuesta utilizada para
// almacenar un expediente en el World State.
func (s *SmartContract) crearClaveExpediente(
	ctx contractapi.TransactionContextInterface,
	id string,
) (string, error) {

	return ctx.GetStub().CreateCompositeKey(
		TipoActivoExpediente,
		[]string{id},
	)
}

// existeExpediente verifica si un expediente ya existe en el ledger.
func (s *SmartContract) existeExpediente(
	ctx contractapi.TransactionContextInterface,
	id string,
) (bool, error) {

	clave, err := s.crearClaveExpediente(ctx, id)
	if err != nil {
		return false, err
	}

	datos, err := ctx.GetStub().GetState(clave)
	if err != nil {
		return false, err
	}

	return datos != nil, nil
}

// obtenerExpediente recupera un expediente del World State.
func (s *SmartContract) obtenerExpediente(
	ctx contractapi.TransactionContextInterface,
	id string,
) (*Expediente, error) {

	clave, err := s.crearClaveExpediente(ctx, id)
	if err != nil {
		return nil, err
	}

	datos, err := ctx.GetStub().GetState(clave)
	if err != nil {
		return nil, err
	}

	if datos == nil {
		return nil, fmt.Errorf("el expediente %s no existe", id)
	}

	var expediente Expediente

	if err := json.Unmarshal(datos, &expediente); err != nil {
		return nil, err
	}

	return &expediente, nil
}

// guardarExpediente serializa y almacena un expediente en el World State.
func (s *SmartContract) guardarExpediente(
	ctx contractapi.TransactionContextInterface,
	expediente *Expediente,
) error {

	datos, err := json.Marshal(expediente)
	if err != nil {
		return err
	}

	clave, err := s.crearClaveExpediente(ctx, expediente.ID)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(clave, datos)
}

// obtenerMSP devuelve el MSP del invocador de la transacción.
func obtenerMSP(
	ctx contractapi.TransactionContextInterface,
) (string, error) {

	return cid.GetMSPID(ctx.GetStub())
}

// obtenerTxID devuelve el identificador único de la transacción.
func obtenerTxID(
	ctx contractapi.TransactionContextInterface,
) string {

	return ctx.GetStub().GetTxID()
}

// obtenerTimestamp devuelve el timestamp oficial de la transacción
// en formato RFC3339.
func obtenerTimestamp(
	ctx contractapi.TransactionContextInterface,
) (string, error) {

	ts, err := ctx.GetStub().GetTxTimestamp()
	if err != nil {
		return "", err
	}

	t := time.Unix(ts.Seconds, int64(ts.Nanos)).UTC()

	return t.Format(time.RFC3339), nil
}

// generarHashEvidencia genera el SHA-256 de una operación
// mediante su representación canónica.
func generarHashEvidencia(
	id string,
	estadoAnterior string,
	evento string,
	estadoNuevo string,
	emisor string,
	timestamp string,
) string {

	datos := id + "|" +
		estadoAnterior + "|" +
		evento + "|" +
		estadoNuevo + "|" +
		emisor + "|" +
		timestamp

	hash := sha256.Sum256([]byte(datos))

	return hex.EncodeToString(hash[:])
}

// agregarEvidencia registra una nueva evidencia criptográfica
// asociada a una transición administrativa.
func agregarEvidencia(
	expediente *Expediente,
	estadoAnterior string,
	evento string,
	estadoNuevo string,
	emisor string,
	timestamp string,
	txID string,
) {

	// Representación canónica de la operación.
	hashHex := generarHashEvidencia(
		expediente.ID,
		estadoAnterior,
		evento,
		estadoNuevo,
		emisor,
		timestamp,
	)

	evidencia := &HashEvidencia{
		Hash:           hashHex,
		EstadoAnterior: estadoAnterior,
		EstadoNuevo:    estadoNuevo,
		Evento:         evento,
		Timestamp:      timestamp,
		Emisor:         emisor,
		TxID:           txID,
		Tipo:           "TRANSICION",
	}

	// Agregar la evidencia al final del historial.
	expediente.HistorialTransiciones = append(
		expediente.HistorialTransiciones,
		evidencia,
	)
}

// obtenerUltimaTransicion devuelve la última transición registrada
// en el historial del expediente.
func obtenerUltimaTransicion(
	expediente *Expediente,
) *HashEvidencia {

	if len(expediente.HistorialTransiciones) == 0 {
		return nil
	}

	return expediente.HistorialTransiciones[len(expediente.HistorialTransiciones)-1]
}

// buscarTransicionPorTxID busca una transición específica
// mediante su identificador de transacción.
func buscarTransicionPorTxID(
	expediente *Expediente,
	txID string,
) *HashEvidencia {

	for _, transicion := range expediente.HistorialTransiciones {
		if transicion.Tipo == "TRANSICION" &&
			transicion.TxID == txID {
			return transicion
		}
	}

	return nil
}

func existeTransicionVigente(
	expediente *Expediente,
	evento string,
) bool {

	for _, transicion := range expediente.HistorialTransiciones {

		if transicion.Tipo != "TRANSICION" ||
			transicion.Evento != evento {
			continue
		}

		rectificada := false

		for _, operacion := range expediente.HistorialTransiciones {
			if operacion.Tipo == "RECTIFICACION" &&
				operacion.TxIDTransicionOrigen == transicion.TxID {
				rectificada = true
				break
			}
		}

		if !rectificada {
			return true
		}
	}

	return false
}
