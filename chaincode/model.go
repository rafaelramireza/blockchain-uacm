package main

type HashEvidencia struct {
	Hash      string `json:"hash"`
	Timestamp string `json:"timestamp"`
	Emisor    string `json:"emisor"`
	TxID      string `json:"txId"`
}

type Expediente struct {
	DocType      string                    `json:"docType"`
	ID           string                    `json:"id"`
	EstadoActual string                    `json:"estadoActual"`
	Evidencias   map[string]*HashEvidencia `json:"evidencias"`
}
