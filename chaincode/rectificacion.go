package main

import "github.com/hyperledger/fabric-contract-api-go/contractapi"

// RectificarTransicion revierte una transición administrativa específica.
// La transición original permanece en el historial y se registra una nueva
// operación de tipo RECTIFICACION.
func (s *SmartContract) RectificarTransicion(
	ctx contractapi.TransactionContextInterface,
	id string,
	txIDTransicion string,
) error {

	// Obtener expediente.
	expediente, err := s.obtenerExpediente(ctx, id)
	if err != nil {
		return ErrExpedienteNoExiste
	}

	// Obtener MSP solicitante.
	msp, err := obtenerMSP(ctx)
	if err != nil {
		return err
	}

	// Buscar la transición original.
	transicion := buscarTransicionPorTxID(
		expediente,
		txIDTransicion,
	)

	if transicion == nil {
		return ErrTransicionNoExiste
	}

	// Verificar que la transición no haya sido rectificada previamente.
	for _, operacion := range expediente.HistorialTransiciones {

		if operacion.Tipo == "RECTIFICACION" &&
			operacion.TxIDTransicionOrigen == txIDTransicion {
			return ErrTransicionYaRectificada
		}
	}

	// Solo el MSP que ejecutó la transición original puede rectificarla.
	if transicion.Emisor != msp {
		return ErrRectificacionNoAutorizada
	}

	// La transición debe seguir siendo la última operación efectiva.
	ultimaTransicion := obtenerUltimaTransicion(expediente)

	if ultimaTransicion == nil ||
		ultimaTransicion.Tipo != "TRANSICION" ||
		ultimaTransicion.TxID != txIDTransicion {
		return ErrTransicionNoRectificable
	}

	// Obtener información de la nueva transacción.
	timestamp, err := obtenerTimestamp(ctx)
	if err != nil {
		return err
	}

	txID := obtenerTxID(ctx)

	// Registrar la rectificación como una nueva operación.
	hashHex := generarHashEvidencia(
		expediente.ID,
		transicion.EstadoNuevo,
		"RECTIFICACION",
		transicion.EstadoAnterior,
		msp,
		timestamp,
	)

	evidencia := &HashEvidencia{
		Hash:                 hashHex,
		EstadoAnterior:       transicion.EstadoNuevo,
		EstadoNuevo:          transicion.EstadoAnterior,
		Evento:               "RECTIFICACION",
		Timestamp:            timestamp,
		Emisor:               msp,
		TxID:                 txID,
		Tipo:                 "RECTIFICACION",
		TxIDTransicionOrigen: txIDTransicion,
	}

	expediente.HistorialTransiciones = append(
		expediente.HistorialTransiciones,
		evidencia,
	)

	// Restaurar el estado anterior a la transición rectificada.
	expediente.EstadoActual = transicion.EstadoAnterior

	// Persistir el expediente.
	return s.guardarExpediente(ctx, expediente)
}
