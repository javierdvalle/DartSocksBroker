import 'dart:core';
import 'dart:async';
import 'dart:io';
import 'Protocol.dart';



class ProxyBroker {

  ServerSocket mainSocket = null;
  Map workers = {};
  List usedForwardingPorts = [];
  
  bool start(port, {Function onDone, Function onError}) {

    if (onDone == null) {
      onDone = () => {print('server started on port $port')};
    }

    if (onError == null) {
      onError = () => {print('error stopping server')};
    }

    // request the OS to bind a new socket to the specified port
    ServerSocket.bind('0.0.0.0', port).then((ServerSocket server) {

      mainSocket = server;

      // listen for incoming connections
      mainSocket.listen((Socket socket) {

        Socket remoteSocket = null;

        // listen for incoming data
        socket.listen((List<int> data) {

          print('incoming ${data.length} bytes on main socket');

          Map msg = parseProtocolMsg(data);

          if (msg == null) {
          	print('invalid msg, closing connection');
          	socket.close();
          	return;

          } else if (msg['version'] == 0xff && msg['cmdCode'] == CMD_REGISTER_WORKER) {
			// The port received from the worker in the register will be
			// used as worker id: The broker will open that port, and all
			// data comming to it will be forwarded to that worker 

          	var workerId = msg['port'];
          	print('new worker requesting to listen at port: ${workerId}');

          	if (workers.containsKey(workerId)) {
          		print('error, a worker has already been registered for that port');
          		socket.close();
          		// TODO: handle this correctly: send an error message to the worker
          		// TODO: maybe a message should also be sent in case of success
          		return;
          	}

			workers[workerId] = {'controlSocket': socket};

			// open the workerId port and listen (connections to that port will be forwarded to the worker)
			ServerSocket.bind('0.0.0.0', workerId).then((ServerSocket server) {

				// wait for new client requesting a connection
				server.listen((Socket browserSocket) {
					print('new client for proxyPort $workerId');

					// request a forwarding connection to the worker
					requestForwardingConn(workerId, onDone: (workerSocket) {

						// listen in proxySocket for incoming data and forward it to the worker
						browserSocket.listen((List<int> data) {
							print('${data.length} bytes of data received from browser in port $workerId, forwarding them to the worker');
							workerSocket.add(data);
						});

						workerSocket.listen((List<int> data) {
							print('${data.length} bytes of data received from worker, sending it back to the browser');
							browserSocket.add(data);
						});
					});


				});
			});

          }

        });

      });

      onDone();

    }).catchError((error) => {onError()});

    return true;
  }

  int chooseNewForwardingPort() {
  	var BASE_PORT = 7000;
  	var MAX_TRIES = 100;

  	for (var i=0 ; i<=1000; i++) {
  		var chosenPort = BASE_PORT + i;
	  	if (!usedForwardingPorts.contains(chosenPort)) {
	  		usedForwardingPorts.add(chosenPort);
	  		return chosenPort;
	  	}
	}
  }

  bool requestForwardingConn(workerId, {Function(Socket) onDone}) {

  	if (!workers.containsKey(workerId)) {
  		print('there is no worker with id: $workerId');
  		return false;
  	}

  	var worker = workers[workerId];

  	var newPort = chooseNewForwardingPort();
  	print('opening port $newPort to wait the worker to make the reverse connection');

  	// open random port and wait for worker to make the reverse connection
  	ServerSocket.bind('0.0.0.0', newPort).then((ServerSocket server) {

        // listen for incoming connections
        server.listen((Socket workerSocket) {
	        print('forwarding connection stablished!');
	        onDone(workerSocket);
        });

	  	// send request to the worker to ask him to connect the given port
	  	var msg = buildOpenForwardingMsg(newPort);
	  	worker['controlSocket'].add(msg);
  	});
  }



  bool stop({Function onDone, Function onError}) {

    if (onDone == null) {
      onError = () => {print('server stopped')};
    }

    if (onError == null) {
      onError = () => {print('error stopping server')};
    }

    mainSocket.close()
      .then((socket) => {onDone()})
      .catchError((error) => {onError()});
  }
}


void main() async {

  var server = new ProxyBroker();

  server.start(9090);

  // wait 5 seconds
  await new Future.delayed(const Duration(seconds : 5));

  // server.stop();

  // server.requestForwardingConn(9050);
  // server.requestForwardingConn(8050, onDone: (socket) => print('hello'));


}
