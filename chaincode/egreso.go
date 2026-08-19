package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// ConfirmarEgreso registra la confirmación del egreso del expediente
// y realiza la transición de DOC_VALIDADO a ACTIVO.
func (s *SmartContract) ConfirmarEgreso(
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
	if expediente.EstadoActual != EstadoDocValidado {
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
		EvEgresoConfirmado,
		hash,
		txID,
		timestamp,
		msp,
	)

	// Cambiar estado
	expediente.EstadoActual = EstadoActivo

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}
