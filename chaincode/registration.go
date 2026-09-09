package main

import (
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// RegistrarInscripcion crea un nuevo expediente académico en estado
// INSCRITO y registra la evidencia criptográfica de inscripción.
//
// Reglas de negocio:
//   - El expediente no debe existir previamente.
//   - Solo puede ser ejecutado por OrgRegistro.
//   - El estado inicial será INSCRITO.

func (s *SmartContract) RegistrarInscripcion(
	ctx contractapi.TransactionContextInterface,
	id string,
) error {

	// Validar identificador
	if id == "" {
		return ErrIDVacio
	}

	// Verificar si el expediente ya existe
	existe, err := s.existeExpediente(ctx, id)
	if err != nil {
		return err
	}

	if existe {
		return fmt.Errorf("el expediente %s ya existe", id)
	}

	// Validar organización emisora
	msp, err := obtenerMSP(ctx)
	if err != nil {
		return err
	}

	if msp != OrgRegistro {
		return ErrMSPNoAutorizado
	}

	txID := obtenerTxID(ctx)

	timestamp, err := obtenerTimestamp(ctx)
	if err != nil {
		return err
	}

	expediente := &Expediente{
		DocType:      TipoActivoExpediente,
		ID:           id,
		EstadoActual: EstadoInscrito,
	}

	agregarEvidencia(
		expediente,
		"",
		EvInscripcion,
		EstadoInscrito,
		msp,
		timestamp,
		txID,
	)

	return s.guardarExpediente(ctx, expediente)
}
