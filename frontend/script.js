// Configuración
const API_URL = window.location.origin;
const SOCKET_URL = window.location.protocol === 'https:' 
    ? window.location.origin 
    : window.location.origin.replace('3001', '3000');

// Variables globales
let socket = null;
let currentUser = null;
let currentRoom = 1;
let isConnected = false;
let rooms = [];

// Elementos del DOM
const usernameInput = document.getElementById('usernameInput');
const joinBtn = document.getElementById('joinBtn');
const disconnectBtn = document.getElementById('disconnectBtn');
const messageInput = document.getElementById('messageInput');
const sendBtn = document.getElementById('sendBtn');
const messagesContainer = document.getElementById('messagesContainer');
const roomsList = document.getElementById('roomsList');
const usersList = document.getElementById('usersList');
const statusSpan = document.getElementById('status');
const roomTitle = document.getElementById('roomTitle');
const roomDesc = document.getElementById('roomDesc');
const userCount = document.getElementById('userCount');
const typingIndicator = document.getElementById('typingIndicator');
const typingUser = document.getElementById('typingUser');
const notification = document.getElementById('notification');

// Inicializar
document.addEventListener('DOMContentLoaded', () => {
    loadRooms();
    setupEventListeners();
});

// Event Listeners
function setupEventListeners() {
    joinBtn.addEventListener('click', connectUser);
    disconnectBtn.addEventListener('click', disconnectUser);
    sendBtn.addEventListener('click', sendMessage);
    document.getElementById('createRoomBtn').addEventListener('click', createNewRoom);
    messageInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
        }
    });
    messageInput.addEventListener('input', () => {
        if (socket && isConnected) {
            socket.emit('typing', { roomId: currentRoom });
        }
    });
}

// Crear nueva sala
async function createNewRoom() {
    const roomName = prompt('Nombre de la sala:');
    if (!roomName || roomName.trim() === '') {
        showNotification('Nombre de sala inválido', 'error');
        return;
    }

    const description = prompt('Descripción (opcional):');
    
    try {
        const response = await fetch(`${API_URL}/api/rooms`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                room_name: roomName.trim(),
                description: description || 'Sala de chat'
            })
        });

        if (!response.ok) {
            throw new Error('Error al crear sala');
        }

        const newRoom = await response.json();
        rooms.push(newRoom);
        renderRooms();
        selectRoom(newRoom);
        showNotification(`Sala "${roomName}" creada exitosamente`, 'success');
    } catch (err) {
        console.error('Error al crear sala:', err);
        showNotification('Error al crear sala', 'error');
    }
}

// Cargar salas de chat
async function loadRooms() {
    try {
        const response = await fetch(`${API_URL}/api/rooms`);
        rooms = await response.json();
        renderRooms();
    } catch (err) {
        console.error('Error cargando salas:', err);
        showNotification('Error al cargar salas', 'error');
    }
}

// Renderizar salas
function renderRooms() {
    roomsList.innerHTML = '';
    rooms.forEach(room => {
        const roomItem = document.createElement('div');
        roomItem.className = `room-item ${room.id === currentRoom ? 'active' : ''}`;
        roomItem.textContent = room.room_name;
        roomItem.addEventListener('click', () => selectRoom(room));
        roomsList.appendChild(roomItem);
    });
}

// Seleccionar sala
function selectRoom(room) {
    currentRoom = room.id;
    roomTitle.textContent = room.room_name;
    roomDesc.textContent = room.description || 'Sala de chat';
    messagesContainer.innerHTML = '';
    renderRooms();
    loadMessages();
    
    if (isConnected) {
        socket.emit('user_join', {
            username: currentUser,
            roomId: currentRoom
        });
    }
}

// Cargar mensajes previos
async function loadMessages() {
    try {
        const response = await fetch(`${API_URL}/api/messages/${currentRoom}`);
        const messages = await response.json();
        messagesContainer.innerHTML = '';
        messages.forEach(msg => {
            displayMessage(msg.username, msg.message_text, msg.created_at, false);
        });
        scrollToBottom();
    } catch (err) {
        console.error('Error cargando mensajes:', err);
    }
}

// Conectar usuario
async function connectUser() {
    const username = usernameInput.value.trim();
    
    if (!username) {
        showNotification('Por favor ingresa un nombre de usuario', 'error');
        return;
    }

    if (username.length < 3) {
        showNotification('El nombre debe tener al menos 3 caracteres', 'error');
        return;
    }

    try {
        // Registrar o obtener usuario
        const userResponse = await fetch(`${API_URL}/api/users`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, email: `${username}@chat.local` })
        });

        if (!userResponse.ok) {
            throw new Error('Error al registrar usuario');
        }

        const user = await userResponse.json();
        currentUser = username;
        
        // Inicializar Socket.io
        if (!socket) {
            socket = io(SOCKET_URL, {
                reconnection: true,
                reconnectionDelay: 1000,
                reconnectionDelayMax: 5000,
                reconnectionAttempts: 5
            });

            setupSocketListeners();
        }

        // Unirse a la sala
        socket.emit('user_join', {
            username: currentUser,
            roomId: currentRoom
        });

        // Actualizar UI
        usernameInput.disabled = true;
        joinBtn.disabled = true;
        messageInput.disabled = false;
        sendBtn.disabled = false;
        disconnectBtn.style.display = 'block';
        isConnected = true;
        statusSpan.textContent = 'Conectado';
        statusSpan.classList.add('connected');
        
        showNotification(`¡Bienvenido ${username}!`, 'success');
    } catch (err) {
        console.error('Error al conectar:', err);
        showNotification('Error al conectar. Intenta de nuevo.', 'error');
    }
}

// Desconectar usuario
function disconnectUser() {
    if (socket) {
        socket.disconnect();
    }
    
    currentUser = null;
    isConnected = false;
    usernameInput.disabled = false;
    usernameInput.value = '';
    joinBtn.disabled = false;
    messageInput.disabled = true;
    sendBtn.disabled = true;
    disconnectBtn.style.display = 'none';
    statusSpan.textContent = 'Desconectado';
    statusSpan.classList.remove('connected');
    usersList.innerHTML = '<p class="empty-state">Conectate para ver usuarios</p>';
    
    showNotification('Desconectado del chat', 'info');
}

// Enviar mensaje
function sendMessage() {
    const message = messageInput.value.trim();
    
    if (!message) return;
    
    if (!socket || !isConnected) {
        showNotification('No estás conectado', 'error');
        return;
    }

    socket.emit('send_message', {
        message,
        roomId: currentRoom
    });

    messageInput.value = '';
    messageInput.focus();
}

// Socket.io Listeners
function setupSocketListeners() {
    socket.on('connect', () => {
        console.log('Conectado al servidor');
    });

    socket.on('disconnect', () => {
        console.log('Desconectado del servidor');
        if (isConnected) {
            disconnectUser();
        }
    });

    socket.on('user_joined', (data) => {
        showNotification(data.message, 'info');
        displaySystemMessage(data.message);
    });

    socket.on('user_left', (data) => {
        showNotification(data.message, 'info');
        displaySystemMessage(data.message);
    });

    socket.on('receive_message', (data) => {
        const isOwn = data.username === currentUser;
        displayMessage(data.username, data.message, data.timestamp, isOwn);
    });

    socket.on('users_list', (users) => {
        renderUsersList(users);
    });

    socket.on('user_typing', (data) => {
        showTypingIndicator(data.username);
    });

    socket.on('error', (data) => {
        showNotification(data.message, 'error');
    });

    socket.on('connect_error', (error) => {
        console.error('Error de conexión:', error);
        showNotification('Error de conexión', 'error');
    });
}

// Mostrar mensaje
function displayMessage(username, message, timestamp, isOwn = false) {
    const messageDiv = document.createElement('div');
    messageDiv.className = `message ${isOwn ? 'own' : 'other'}`;
    
    const time = new Date(timestamp).toLocaleTimeString('es-ES', {
        hour: '2-digit',
        minute: '2-digit'
    });

    messageDiv.innerHTML = `
        <div class="message-username">${username}</div>
        <div class="message-bubble">${escapeHtml(message)}</div>
        <div class="message-info">${time}</div>
    `;

    messagesContainer.appendChild(messageDiv);
    scrollToBottom();
}

// Mostrar mensaje del sistema
function displaySystemMessage(message) {
    const messageDiv = document.createElement('div');
    messageDiv.style.cssText = `
        text-align: center;
        color: #6b7280;
        font-size: 13px;
        padding: 8px;
        margin: 8px 0;
        font-style: italic;
    `;
    messageDiv.textContent = message;
    messagesContainer.appendChild(messageDiv);
    scrollToBottom();
}

// Mostrar indicador de escritura
function showTypingIndicator(username) {
    typingUser.textContent = `${username} está escribiendo...`;
    typingIndicator.style.display = 'flex';
    
    setTimeout(() => {
        typingIndicator.style.display = 'none';
    }, 3000);
}

// Renderizar lista de usuarios
function renderUsersList(users) {
    usersList.innerHTML = '';
    
    if (users.length === 0) {
        usersList.innerHTML = '<p class="empty-state">No hay usuarios conectados</p>';
        userCount.textContent = '0 usuarios';
        return;
    }

    users.forEach(user => {
        const userItem = document.createElement('div');
        userItem.className = 'user-item';
        userItem.innerHTML = `<span style="margin-right: 8px;">👤</span>${user}`;
        usersList.appendChild(userItem);
    });

    userCount.textContent = `${users.length} ${users.length === 1 ? 'usuario' : 'usuarios'}`;
}

// Mostrar notificación
function showNotification(message, type = 'info') {
    notification.textContent = message;
    notification.className = `notification show ${type}`;
    
    setTimeout(() => {
        notification.classList.remove('show');
    }, 3000);
}

// Scroll al final
function scrollToBottom() {
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
}

// Escapar HTML
function escapeHtml(text) {
    const map = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
    };
    return text.replace(/[&<>"']/g, m => map[m]);
}
