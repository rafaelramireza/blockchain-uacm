package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// EmitirCertificado registra la emisión del certificado de estudios
// sin modificar el estado administrativo del expediente.
func (s *SmartContract) EmitirCertificado(
	ctx contractapi.TransactionContextInterface,
	id string,
	hash string,
) error {

	// Validar parámetros
	if id == "" {
		return ErrIDVacio
	}

	if hash == "" {
		return ErrHashVacio
	}

	// Obtener expediente
	expediente, err := s.obtenerExpediente(ctx, id)
	if err != nil {
		return err
	}

	// Validar estado actual
	if expediente.EstadoActual != EstadoEgresado {
		return ErrEstadoInvalido
	}

	// Validar organización
	msp, err := obtenerMSP(ctx)
	if err != nil {
		return err
	}

	if msp != OrgCertificacion {
		return ErrMSPNoAutorizado
	}

	// Obtener metadatos
	txID := obtenerTxID(ctx)

	timestamp, err := obtenerTimestamp(ctx)
	if err != nil {
		return err
	}

	// Registrar evidencia
	agregarEvidencia(
		expediente,
		EvCertificadoEmitido,
		hash,
		txID,
		timestamp,
		msp,
	)

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}
