import 'dart:core';
import 'dart:async';
import 'dart:io';
import 'Protocol.dart';



class ProxyBroker {

  ServerSocket mainSocket;
  Map workers = {};
  List usedForwardingPorts = [];
  
  bool start(port, {Function onDone, Function onError}) {

    if (onDone == null) {
      onDone = () => print('server started on port $port');
    }

    if (onError == null) {
      onError = () => print('error stopping server');
    }

    // request the OS to bind a new socket to the specified port
    ServerSocket.bind('0.0.0.0', port).then((ServerSocket server) {

      mainSocket = server;

      // listen for incoming connections
      mainSocket.listen((Socket controlSocket) {

        var workerId;

        controlSocket.done.then((socket) {
          print('control socket for worker: $workerId fully disconnected');
        }).catchError((error) {
          print('error in controlSocket for worker: $workerId');
        });

        // listen for incoming data
        controlSocket.listen((List<int> data) {

          print('incoming ${data.length} bytes on main socket');

          Map msg = parseProtocolMsg(data);

          if (msg == null) {
          	print('invalid msg, closing connection');
          	controlSocket.close();
          	return;

          } else if (msg['version'] == 0xff && msg['cmdCode'] == CMD_REGISTER_WORKER) {
            // The port received from the worker in the register will be
            // used as worker id: The broker will open that port, and all
            // data comming to it will be forwarded to that worker 

          	print('new worker requesting to listen at port: ${msg['port']}');

          	if (workers.containsKey(msg['port'])) {
          		var resp = buildRegisterRejectedResponse(msg['port']);
          		print('error, a worker has already been registered for that port');
          		controlSocket.add(resp);
          		// TODO: close connection here? or wait for another msg?
          		// controlSocket.close(); 
          		return;
          	}

            workerId = msg['port'];

			      workers[workerId] = {'controlSocket': controlSocket,
                                 'forwardingSockets': [],
                                 'browserSockets': [],
                                 'proxySocket': null};

            // open the workerId port and listen (connections to that port will be forwarded to the worker)
            ServerSocket.bind('0.0.0.0', workerId).then((ServerSocket server) {
              
              print('worker listening at port: $workerId');
              
              workers[workerId]['proxySocket'] = server;

				      // wait for new client requesting a connection
              server.listen((Socket browserSocket) {
                print('new client for proxyPort $workerId');

                // save socket to close it later
                workers[workerId]['browserSockets'].add(browserSocket);

                browserSocket.done.catchError((error) => print('error on browserSocket for workerId: $workerId, : $error'));

                // request a forwarding connection to the worker
                requestForwardingConn(workerId, onDone: (workerForwSocket) {

                  // listen browserSocket for incoming data and forward it to the worker
                  browserSocket.listen((List<int> data) {
                    print('${data.length} bytes of data received from browser in port $workerId, forwarding them to the worker');
                    try {
                      workerForwSocket.add(data);
                    } on SocketException {
                      print('socket exception while adding data');
                    } catch (e) {
                      print('caught exception while adding data to socket: $e');
                    }
                  }, onError: (e) {
                    print('error listening from browserSocket: $e');
                    if (e.osError.errorCode == 104) {
                      // Connection reset by peer, errno = 104
                      print('connection reset by peer, closing socket');
                      browserSocket.close();
                    }
                  });

                  // listen workerSocket for incoming data and forward it to the browser
                  workerForwSocket.listen((List<int> data) {
                    print('${data.length} bytes of data received from worker, sending it back to the browser');
                    try {
                      browserSocket.add(data);
                    } on SocketException {
                      print('socket exception while adding data');
                    } catch (e) {
                      print('caught exception while adding data to socket: $e');
                    }
                  }, onError: (e) => print('error listening from workerForwSocket: $e'));
                });

              }, onError: (error) => print('error while listening for connections in proxy socket for workerId: $workerId. Error: $error'));

            }, onError: (error) => print('error binding socket for workerId: $workerId. Error: $error'));

            // send register success msg to the worker
            var resp = buildRegisterSuccessResponse(workerId);
            controlSocket.add(resp);
          }

        }, onDone: () {
          // worker controlSocket closed
          print('closed controlSocket for worker $workerId');
          removeWorker(workerId);
        }, onError: (error) {
          print('error on listen() for incoming data on controlSocket, workerId: $workerId');
          removeWorker(workerId);
        });

      }, onError: (error) => print('error while listening for connections in main socket'));

      onDone();

    }).catchError((error) => onError());

    return true;
  }

  int chooseNewForwardingPort() {

  	const BASE_PORT = 7000;

  	for (var i=0 ; i<=1000; i++) {
  		var chosenPort = BASE_PORT + i;
	  	if (!usedForwardingPorts.contains(chosenPort)) {
	  		return chosenPort;
        }
    }

    return -1;
  }

  void requestForwardingConn(workerId, {Function(Socket) onDone}) {

  	if (!workers.containsKey(workerId)) {
  		print('there is no worker with id: $workerId');
  		return;
  	}

  	var worker = workers[workerId];

  	var newPort = chooseNewForwardingPort();
    usedForwardingPorts.add(newPort);
    
  	print('opening port $newPort to wait the worker to make the reverse connection');

  	// open random port and wait for worker to make the reverse connection
  	ServerSocket.bind('0.0.0.0', newPort).then((ServerSocket server) {

      // listen for incoming connections
      server.listen((Socket workerForwSocket) {
	      print('forwarding connection stablished!');

        // close the server (only accept the first connection)
        server.close();
        usedForwardingPorts.remove(newPort);

        // save the socket to close it later
        worker['forwardingSockets'].add(workerForwSocket);

	      onDone(workerForwSocket);
      });

	  	// send request to the worker to ask him to connect the given port
	  	var msg = buildOpenForwardingMsg(newPort);
	  	worker['controlSocket'].add(msg);
  	});
  }


  void removeWorker(int workerId) {
    
    print('removing worker: $workerId');

    if (!workers.containsKey(workerId)) {
      print('error: worker with id: $workerId does not exist, unable to remove it');
      return;
    }

    var worker = workers[workerId];

    worker['controlSocket'].destroy();
    worker['proxySocket'].close();

    for (var socket in worker['forwardingSockets']) {
      socket.destroy();
    }

    for (var socket in worker['browserSockets']) {
      socket.destroy();
    }

    workers.remove(workerId);
  }



  void stop({Function onDone, Function onError}) {
    
    print('stopping server');

    if (onDone == null) {
      onError = () => print('server stopped');
    }

    if (onError == null) {
      onError = () => print('error stopping server');
    }

    var workerIds = workers.keys.toList();
    for (var workerId in workerIds) {
      removeWorker(workerId);
    }
    
    mainSocket.close()
      .then((socket) => onDone())
      .catchError((error) => onError());
  }
}


void main() async {

  var server = new ProxyBroker();

  server.start(9999);

  // wait 5 seconds
  await new Future.delayed(const Duration(seconds : 5));

  // server.stop();

}
