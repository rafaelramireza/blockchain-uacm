package main

import (
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// ConsultarExpediente recupera un expediente académico
// a partir de su identificador único.
func (s *SmartContract) ConsultarExpediente(
	ctx contractapi.TransactionContextInterface,
	id string,
) (*Expediente, error) {

	if id == "" {
		return nil, ErrIDVacio
	}

	return s.obtenerExpediente(ctx, id)
}
