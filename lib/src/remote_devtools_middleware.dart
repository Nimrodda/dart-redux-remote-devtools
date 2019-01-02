part of redux_remote_devtools;

/// The connection state of the middleware
enum RemoteDevToolsStatus {
  /// No socket connection to the remote host
  notConnected,

  /// Attempting to open socket
  connecting,

  /// Connected to remote, but not started
  connected,

  /// Awating start response
  starting,

  /// Sending and receiving actions
  started
}

class RemoteDevToolsMiddleware extends MiddlewareClass {
  /**
   * The remote-devtools server to connect to. Should include
   * protocol and port if necessary. For example:
   * 
   * example.lan:8000
   * 
   */
  String _host;
  SocketClusterWrapper socket;
  Store store;
  String _channel;
  RemoteDevToolsStatus status = RemoteDevToolsStatus.notConnected;

  ActionEncoder actionEncoder;
  StateEncoder stateEncoder;

  RemoteDevToolsMiddleware(this._host,
      {this.actionEncoder = const JsonActionEncoder(),
      this.stateEncoder = const JsonStateEncoder(),
      this.socket}) {
    if (socket == null) {
      this.socket = new SocketClusterWrapper('ws://${this._host}/socketcluster/');
    }
  }

  connect() async {
    _setStatus(RemoteDevToolsStatus.connecting);
    await this.socket.connect();
    _setStatus(RemoteDevToolsStatus.connected);
    this._channel = await this._login();
    _setStatus(RemoteDevToolsStatus.starting);
    this._relay('START');
    this.socket.on(_channel, (String name, dynamic data) {
      this.handleEventFromRemote(data as Map<String, dynamic>);
    });
    if (this.store != null) {
      this._relay('ACTION', store.state, 'CONNECT');
    }
  }

  Future<String> _login() {
    Completer<String> c = new Completer<String>();
    this.socket.emit('login', 'master', (String name, dynamic error, dynamic data) {
      c.complete(data as String);
    });
    return c.future;
  }

  _relay(String type, [Object state, dynamic action, String nextActionId]) {
    var message = {'type': type, 'id': socket.id, 'name': 'flutter'};

    if (state != null) {
      message['payload'] = this.stateEncoder.encode(state);
    }
    if (type == 'ACTION') {
      message['action'] = this.actionEncoder.encode(action);
      message['nextActionId'] = nextActionId;
    } else if (action != null) {
      message['action'] = action as String;
    }
    socket.emit(this.socket.id != null ? 'log' : 'log-noid', message);
  }

  void handleEventFromRemote(Map<String, dynamic> data) {
    switch (data['type'] as String) {
      case 'DISPATCH':
        _handleDispatch(data['action']);
        break;
      // The START action is a response indicating that remote devtools is up and running
      case 'START':
        _setStatus(RemoteDevToolsStatus.started);
        break;
      default:
        print('Unknown type:' + data['type'].toString());
    }
  }

  void _handleDispatch(dynamic action) {
    switch (action['type'] as String) {
      case 'JUMP_TO_STATE':
        if (this.store != null) {
          this.store.dispatch(new DevToolsAction.jumpToState(action['index'] as int));
        } else {
          print('No store reference set, cannot dispatch remote action');
        }
        break;
    }
  }

  /// Middleware function called by redux, dispatches actions to devtools
  call(Store store, dynamic action, NextDispatcher next) {
    next(action);
    if (this.status == RemoteDevToolsStatus.started && !(action is DevToolsAction)) {
      this._relay('ACTION', store.state, action);
    }
  }

  _setStatus(RemoteDevToolsStatus value) {
    this.status = value;
  }
}
