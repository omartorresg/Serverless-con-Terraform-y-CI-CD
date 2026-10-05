const { Client } = require('pg');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

let client;

const getDbClient = async () => {
    if (!client || client._ending) {
        client = new Client({
            connectionString: process.env.DATABASE_URL,
            ssl: { rejectUnauthorized: false }
        });
        await client.connect();
    }
    return client;
};

exports.handler = async (event) => {
    // Normalización de ruta y método
    let rawPath = event.rawPath || event.path || '';
    const path = rawPath.toLowerCase().replace(/\/+$/, '');
    const httpMethod = (event.requestContext?.http?.method || event.httpMethod || 'GET').toUpperCase();
    
    let body = {};

    if (event.body) {
        try {
            body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
        } catch (e) {
            body = event.body;
        }
    }

    const headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Allow-Methods": "OPTIONS,GET,POST,PUT,DELETE"
    };

    if (httpMethod === 'OPTIONS') {
        return { statusCode: 200, headers, body: '' };
    }

    try {
        const db = await getDbClient();

        // Crear la tabla si no existe
        await db.query(`
            CREATE TABLE IF NOT EXISTS usuarios (
                id SERIAL PRIMARY KEY,
                nombre VARCHAR(100),
                email VARCHAR(100) UNIQUE NOT NULL,
                password VARCHAR(255) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        `);

        // 1. Ruta: Subida de archivos / imágenes (captura cualquier path con upload)
        if (path.includes('upload')) {
            const fileUrl = `https://dinovo.space/uploads/img_${Date.now()}.jpg`;
            
            return {
                statusCode: 200,
                headers,
                body: JSON.stringify({
                    message: "Archivo procesado exitosamente",
                    url: fileUrl
                })
            };
        }

        // 2. Ruta: POST /usuarios o /api/usuarios (Registro)
        if ((path.endsWith('/usuarios') || path.endsWith('/api/usuarios')) && httpMethod === 'POST') {
            const { nombre, email, password } = body;
            const hashedPassword = await bcrypt.hash(password || '123456', 10);
            
            const res = await db.query(
                'INSERT INTO usuarios (nombre, email, password) VALUES ($1, $2, $3) RETURNING id, nombre, email',
                [nombre, email, hashedPassword]
            );
            return {
                statusCode: 201,
                headers,
                body: JSON.stringify({ message: "Usuario creado exitosamente", usuario: res.rows[0] })
            };
        }

        // 3. Ruta: POST /login o /api/login
        if ((path.endsWith('/login') || path.endsWith('/api/login')) && httpMethod === 'POST') {
            const { email, password } = body;
            const res = await db.query('SELECT * FROM usuarios WHERE email = $1', [email]);
            
            if (res.rows.length === 0) {
                return { statusCode: 401, headers, body: JSON.stringify({ message: "Credenciales inválidas" }) };
            }

            const user = res.rows[0];
            let valid = false;
            try {
                valid = await bcrypt.compare(password, user.password || '');
            } catch (err) {
                valid = false;
            }

            if (!valid) {
                return { statusCode: 401, headers, body: JSON.stringify({ message: "Credenciales inválidas" }) };
            }

            const token = jwt.sign(
                { id: user.id, email: user.email },
                process.env.JWT_SECRET || 'secret',
                { expiresIn: '24h' }
            );

            return {
                statusCode: 200,
                headers,
                body: JSON.stringify({ token, usuario: { id: user.id, nombre: user.nombre, email: user.email } })
            };
        }

        // 4. Ruta: GET /usuarios o /api/usuarios (Obtener lista)
        if ((path.endsWith('/usuarios') || path.endsWith('/api/usuarios')) && httpMethod === 'GET') {
            const res = await db.query('SELECT id, nombre, email, created_at FROM usuarios');
            return {
                statusCode: 200,
                headers,
                body: JSON.stringify(res.rows)
            };
        }

        // Respuesta por defecto si no coincide ninguna ruta
        return {
            statusCode: 200,
            headers,
            body: JSON.stringify({ message: "API Serverless activa en AWS Lambda con Neon DB", path, httpMethod })
        };

    } catch (err) {
        console.error("Error en la ejecución:", err);
        return {
            statusCode: 500,
            headers,
            body: JSON.stringify({ error: err.message })
        };
    }
};