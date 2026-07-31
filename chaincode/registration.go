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

const (
	EvidenciaInscripcion = "INSCRIPCION"
)

func (s *SmartContract) RegistrarInscripcion(
	ctx contractapi.TransactionContextInterface,
	id string,
	hash string,
) error {

	// Validar identificador
	if id == "" {
		return fmt.Errorf("el identificador del expediente es obligatorio")
	}

	// Validar hash
	if hash == "" {
		return fmt.Errorf("el hash de la evidencia es obligatorio")
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
		return fmt.Errorf("la organización %s no está autorizada para registrar inscripciones", msp)
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
		Evidencias:   make(map[string]*HashEvidencia),
	}

	agregarEvidencia(
		expediente,
		EvInscripcion,
		hash,
		txID,
		timestamp,
		msp,
	)

	cambiarEstado(
		expediente,
		EstadoInscrito,
	)

	return s.guardarExpediente(ctx, expediente)

}
