package main

import (
	"encoding/json"
	"fmt"

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
