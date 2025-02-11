// Simple WebSocket signaling server in Dart
import 'dart:io';
import 'dart:convert';
import 'dart:math';

final Map<String, WebSocket> clients = {};
void main() async {
  HttpServer server = await HttpServer.bind('0.0.0.0', 8080);
  print('WebSocket signaling server running on ws://localhost:8080');

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

void handleConnection(WebSocket socket) {
  String clientId = generateClientId();
  clients[clientId] = socket;
  print('Client connected: $clientId');

  socket.add(jsonEncode({'type': 'welcome', 'id': clientId}));

  socket.listen((message) {
    var data = jsonDecode(message);
    switch (data['type']) {
      case 'register':
        clients[clientId] = socket;
        print('Client registered: $clientId');
        break;
      case 'signal':
        String targetId = data['target'];
        if (clients.containsKey(targetId)) {
          clients[targetId]!.add(jsonEncode({
            'type': 'signal',
            'from': clientId,
            'data': data['data'],
          }));
        }
        break;
    }
  }, onDone: () {
    clients.remove(clientId);
    print('Client disconnected: $clientId');
  });
}

String generateClientId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  var rnd = Random();
  return List.generate(8, (index) => chars[rnd.nextInt(chars.length)]).join();
}
