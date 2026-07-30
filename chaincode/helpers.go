package main

import (
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// crearClaveExpediente genera la clave compuesta utilizada para
// almacenar un expediente en el World State.
func crearClaveExpediente(
	ctx contractapi.TransactionContextInterface,
	id string,
) (string, error) {

	return ctx.GetStub().CreateCompositeKey(
		TipoActivoExpediente,
		[]string{id},
	)
}
