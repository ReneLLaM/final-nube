const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Middleware
app.use(cors());
app.use(express.json());

// Configuración de Base de Datos con reintentos
const pool = new Pool({
  user: process.env.DB_USER || 'chatuser',
  password: process.env.DB_PASSWORD || 'chatpass123',
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'chatdb',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Reintentos de conexión a BD
let dbConnected = false;
const connectDB = async () => {
  let retries = 0;
  const maxRetries = 30;
  
  while (retries < maxRetries && !dbConnected) {
    try {
      await pool.query('SELECT 1');
      dbConnected = true;
      console.log('✓ Conectado a PostgreSQL');
      return;
    } catch (err) {
      retries++;
      console.log(`Intento ${retries}/${maxRetries}: Esperando BD...`);
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  }
  
  if (!dbConnected) {
    console.error('✗ No se pudo conectar a la BD después de 30 intentos');
    process.exit(1);
  }
};

// Conectar a BD al iniciar
connectDB();

// Variables globales
const connectedUsers = new Map();
const userRooms = new Map();

// Rutas HTTP
app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date() });
});

// Obtener todas las salas
app.get('/api/rooms', async (req, res) => {
  try {
    const result = await pool.query('SELECT id, room_name, description FROM chat_rooms ORDER BY id');
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching rooms:', err);
    res.status(500).json({ error: 'Error fetching rooms' });
  }
});

// Crear nueva sala
app.post('/api/rooms', async (req, res) => {
  try {
    const { room_name, description } = req.body;
    
    if (!room_name || room_name.trim() === '') {
      return res.status(400).json({ error: 'Nombre de sala requerido' });
    }

    const result = await pool.query(
      'INSERT INTO chat_rooms (room_name, description) VALUES ($1, $2) RETURNING id, room_name, description',
      [room_name.trim(), description || 'Sala de chat']
    );
    
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Error creating room:', err);
    res.status(500).json({ error: 'Error creating room' });
  }
});

// Obtener mensajes de una sala
app.get('/api/messages/:roomId', async (req, res) => {
  try {
    const { roomId } = req.params;
    const result = await pool.query(
      `SELECT m.id, m.message_text, m.created_at, u.username 
       FROM messages m 
       JOIN users u ON m.user_id = u.id 
       WHERE m.room_id = $1 
       ORDER BY m.created_at ASC LIMIT 100`,
      [roomId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching messages:', err);
    res.status(500).json({ error: 'Error fetching messages' });
  }
});

// Registrar nuevo usuario
app.post('/api/users', async (req, res) => {
  try {
    const { username, email } = req.body;
    
    if (!username || username.trim() === '') {
      return res.status(400).json({ error: 'Nombre de usuario requerido' });
    }

    // Verificar si el usuario ya existe
    const existingUser = await pool.query(
      'SELECT id FROM users WHERE username = $1',
      [username.trim()]
    );

    if (existingUser.rows.length > 0) {
      return res.json(existingUser.rows[0]);
    }

    // Crear nuevo usuario
    const result = await pool.query(
      'INSERT INTO users (username, email, password_hash) VALUES ($1, $2, $3) RETURNING id, username, email',
      [username.trim(), email || `${username}@chat.local`, 'temp_hash']
    );
    
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Error creating user:', err);
    res.status(500).json({ error: 'Error creating user' });
  }
});

// Obtener usuarios conectados en una sala
app.get('/api/rooms/:roomId/users', async (req, res) => {
  try {
    const { roomId } = req.params;
    const result = await pool.query(
      `SELECT DISTINCT u.id, u.username 
       FROM active_connections ac
       JOIN users u ON ac.user_id = u.id
       WHERE ac.room_id = $1 AND ac.disconnected_at IS NULL`,
      [roomId]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching room users:', err);
    res.status(500).json({ error: 'Error fetching room users' });
  }
});

// Socket.io eventos
io.on('connection', (socket) => {
  console.log(`Nuevo usuario conectado: ${socket.id}`);

  socket.on('user_join', async (data) => {
    const { username, roomId } = data;
    
    try {
      // Guardar usuario en base de datos si no existe
      let userId;
      const userResult = await pool.query(
        'SELECT id FROM users WHERE username = $1',
        [username]
      );
      
      if (userResult.rows.length === 0) {
        const newUserResult = await pool.query(
          'INSERT INTO users (username, email, password_hash) VALUES ($1, $2, $3) RETURNING id',
          [username, `${username}@chat.local`, 'temp_hash']
        );
        userId = newUserResult.rows[0].id;
      } else {
        userId = userResult.rows[0].id;
      }

      // Registrar conexión activa
      await pool.query(
        'INSERT INTO active_connections (user_id, socket_id, room_id) VALUES ($1, $2, $3)',
        [userId, socket.id, roomId]
      );

      connectedUsers.set(socket.id, { username, userId, roomId });
      userRooms.set(socket.id, roomId);

      socket.join(`room_${roomId}`);

      // Notificar a otros usuarios
      io.to(`room_${roomId}`).emit('user_joined', {
        username,
        message: `${username} se ha unido al chat`,
        timestamp: new Date()
      });

      // Enviar lista de usuarios conectados
      const usersInRoom = Array.from(connectedUsers.values())
        .filter(u => u.roomId === roomId)
        .map(u => u.username);
      
      io.to(`room_${roomId}`).emit('users_list', usersInRoom);

    } catch (err) {
      console.error('Error en user_join:', err);
      socket.emit('error', { message: 'Error al unirse a la sala' });
    }
  });

  socket.on('send_message', async (data) => {
    const { message, roomId } = data;
    const user = connectedUsers.get(socket.id);

    if (!user) {
      socket.emit('error', { message: 'Usuario no identificado' });
      return;
    }

    try {
      // Guardar mensaje en base de datos
      const result = await pool.query(
        'INSERT INTO messages (room_id, user_id, message_text) VALUES ($1, $2, $3) RETURNING id, created_at',
        [roomId, user.userId, message]
      );

      const messageData = {
        id: result.rows[0].id,
        username: user.username,
        message,
        timestamp: result.rows[0].created_at,
        roomId
      };

      // Enviar a todos en la sala
      io.to(`room_${roomId}`).emit('receive_message', messageData);

    } catch (err) {
      console.error('Error al guardar mensaje:', err);
      socket.emit('error', { message: 'Error al enviar mensaje' });
    }
  });

  socket.on('typing', (data) => {
    const { roomId } = data;
    const user = connectedUsers.get(socket.id);
    
    if (user) {
      socket.to(`room_${roomId}`).emit('user_typing', {
        username: user.username
      });
    }
  });

  socket.on('disconnect', async () => {
    const user = connectedUsers.get(socket.id);
    
    if (user) {
      try {
        // Actualizar registro de desconexión
        await pool.query(
          'UPDATE active_connections SET disconnected_at = NOW() WHERE socket_id = $1',
          [socket.id]
        );

        // Notificar desconexión
        io.to(`room_${user.roomId}`).emit('user_left', {
          username: user.username,
          message: `${user.username} ha salido del chat`
        });

        // Actualizar lista de usuarios
        const usersInRoom = Array.from(connectedUsers.values())
          .filter(u => u.roomId === user.roomId && u.username !== user.username)
          .map(u => u.username);
        
        io.to(`room_${user.roomId}`).emit('users_list', usersInRoom);

      } catch (err) {
        console.error('Error en disconnect:', err);
      }

      connectedUsers.delete(socket.id);
      userRooms.delete(socket.id);
    }

    console.log(`Usuario desconectado: ${socket.id}`);
  });

  socket.on('error', (error) => {
    console.error('Socket error:', error);
  });
});

// Manejo de errores de conexión a BD
pool.on('error', (err) => {
  console.error('Error en pool de conexiones:', err);
});

// Iniciar servidor
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`✓ Servidor backend corriendo en puerto ${PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM recibido, cerrando servidor...');
  server.close(() => {
    console.log('Servidor cerrado');
    pool.end();
    process.exit(0);
  });
});
