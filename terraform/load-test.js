import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
    duration: '5m',
    vus: 10, // 10 usuarios virtuales concurrentes atacando la API
};

export default function () {
    //const url = 'http://100.54.39.43:8080/api/historiausuario/generate';
    const url = 'http://host.docker.internal:8080/api/historiausuario/generate';

    const params = {
        headers: {
            'Content-Length': '0',
        },
    };

    http.post(url, null, params);
    sleep(1); // Espera 1 segundo entre peticiones para no saturar tu red local
}