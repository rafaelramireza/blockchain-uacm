package main

import (
	"encoding/json"
	"fmt"

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

// ConsultarExpedientesPorEstado recupera todos los expedientes
// cuyo estadoActual coincide con el estado solicitado.
//
// Esta función utiliza una consulta rica de CouchDB sobre el
// World State.
func (s *SmartContract) ConsultarExpedientesPorEstado(
	ctx contractapi.TransactionContextInterface,
	estado string,
) ([]*Expediente, error) {

	if estado == "" {
		return nil, fmt.Errorf("el estado no puede estar vacío")
	}

	query := fmt.Sprintf(
		`{"selector":{"docType":"%s","estadoActual":"%s"}}`,
		TipoActivoExpediente,
		estado,
	)

	iterator, err := ctx.GetStub().GetQueryResult(query)
	if err != nil {
		return nil, err
	}
	defer iterator.Close()

	var expedientes []*Expediente

	for iterator.HasNext() {

		resultado, err := iterator.Next()
		if err != nil {
			return nil, err
		}

		var expediente Expediente

		if err := json.Unmarshal(resultado.Value, &expediente); err != nil {
			return nil, err
		}

		expedientes = append(expedientes, &expediente)
	}

	if expedientes == nil {
		expedientes = make([]*Expediente, 0)
	}

	return expedientes, nil
}
