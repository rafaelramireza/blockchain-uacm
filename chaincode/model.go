package main

type HashEvidencia struct {
	Hash                 string `json:"hash"`
	EstadoAnterior       string `json:"estadoAnterior"`
	EstadoNuevo          string `json:"estadoNuevo"`
	Evento               string `json:"evento"`
	Timestamp            string `json:"timestamp"`
	Emisor               string `json:"emisor"`
	TxID                 string `json:"txId"`
	Tipo                 string `json:"tipo"`
	TxIDTransicionOrigen string `json:"txIdTransicionOrigen,omitempty"`
}

type Expediente struct {
	DocType               string           `json:"docType"`
	ID                    string           `json:"id"`
	EstadoActual          string           `json:"estadoActual"`
	HistorialTransiciones []*HashEvidencia `json:"historialTransiciones"`
}
