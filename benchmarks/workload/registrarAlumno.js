'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class MyWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        const alumnoID = `ALUMNO_${this.workerIndex}_${this.txIndex}`;
        const nombre = `Estudiante Prueba ${this.txIndex}`;

        const request = {
            contractId: 'uacm-contract',
            contractFunction: 'RegistrarIngreso',
            invokerIdentity: 'User1',
            contractArguments: [alumnoID, nombre],
            readOnly: false
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new MyWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;