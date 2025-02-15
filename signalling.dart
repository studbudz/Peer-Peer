import 'dart:io';
import 'dart:convert';
import 'dart:math';

// Stores connected clients (clientId -> WebSocket)
final Map<String, WebSocket> clients = {};

void main() async {
  // Starts the WebSocket server on port 8080
  HttpServer server = await HttpServer.bind('0.0.0.0', 8080);
  print('WebSocket signaling server running on ws://localhost:8080');

  // Handles incoming connections
  await for (HttpRequest request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      WebSocket socket = await WebSocketTransformer.upgrade(request);
      handleConnection(socket);
    } else {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
    }
  }
}

// Handles a new WebSocket connection
void handleConnection(WebSocket socket) {
  String clientId = generateClientId();
  clients[clientId] = socket;
  print('Client connected: $clientId');

  // Send client their unique ID
  socket.add(jsonEncode({'type': 'welcome', 'id': clientId}));

  // Listen for messages from this client
  //continuously listens for messages from the client
  socket.listen(
    (message) {
      var data = jsonDecode(message);

      if (data['type'] == 'signal') {
        String targetId = data['target'];
        if (clients.containsKey(targetId)) {
          // Forward the signaling message to the intended client
          //add sends the message to the client
          clients[targetId]!.add(
            jsonEncode({
              'type': 'signal',
              'from': clientId,
              'data': data['data'],
            }),
          );
        }
      }
    },
    onDone: () {
      // Remove client when they disconnect
      clients.remove(clientId);
      print('Client disconnected: $clientId');
    },
  );
}

// Generates a random client ID (8 characters)
String generateClientId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  var rnd = Random();
  return List.generate(8, (index) => chars[rnd.nextInt(chars.length)]).join();
}
