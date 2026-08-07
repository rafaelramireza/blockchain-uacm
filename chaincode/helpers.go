package main

import (
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

// agregarEvidencia registra una nueva evidencia criptográfica
// dentro del expediente.
func agregarEvidencia(
	expediente *Expediente,
	nombre string,
	hash string,
	txID string,
	timestamp string,
	emisor string,
) {

	if expediente.Evidencias == nil {
		expediente.Evidencias = make(map[string]*HashEvidencia)
	}

	expediente.Evidencias[nombre] = &HashEvidencia{
		Hash:      hash,
		Timestamp: timestamp,
		Emisor:    emisor,
		TxID:      txID,
	}
}

// cambiarEstado actualiza el estado actual del expediente.
func cambiarEstado(
	expediente *Expediente,
	nuevoEstado string,
) {
	expediente.EstadoActual = nuevoEstado
}
