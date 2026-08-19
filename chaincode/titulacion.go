package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// EmitirTitulo registra la emisión del título y realiza la transición
// desde CERTIFICADO o SS_LIBERADO a TITULADO.
func (s *SmartContract) EmitirTitulo(
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
	if expediente.EstadoActual != EstadoCertificado &&
		expediente.EstadoActual != EstadoSSLiberado {
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
		EvTitulacionRegistrada,
		hash,
		txID,
		timestamp,
		msp,
	)

	// Cambiar estado
	expediente.EstadoActual = EstadoTitulado

	// Persistir cambios
	return s.guardarExpediente(ctx, expediente)
}
