import 'dart:core';
import 'dart:io';
import 'Protocol.dart';


class ProxyWorker {

	Socket controlSocket;
  List forwardingSockets = [];
  List remoteSockets = [];

	void register(brokerHost, brokerPort, exposePort, {Function onDone, Function onError}) {

		if (onDone == null) {
		  onDone = () => print('worker registered');
		}

		if (onError == null) {
		  onError = (e) => print('registration failed');
		}

		if (controlSocket != null) {
			onError('already connected!');
      return;
		}

		Socket.connect(brokerHost, brokerPort).then((Socket sock) {
			
			controlSocket = sock;

			// send register request to the broker
			print('sending register request to broker at $brokerHost:$brokerPort for port $exposePort');
			List<int> msg = buildRegisterWorkerMsg(exposePort);
			controlSocket.add(msg);

			// wait for messages from the broker in this "control" socket
			controlSocket.listen((List<int> data) {

	      print('incoming ${data.length} bytes from broker');

  	    Map msg = parseProtocolMsg(data);

        if (msg == null) {
          print('invalid msg');
          return;

        } else if (msg['version'] == 0x00) {
          // response msg received

          if (msg['retCode'] == RCODE_REGISTER_SUCCESS) {
            print('registration succeeded');
            onDone();
            return;
          } else if (msg['retCode'] == RCODE_REGISTER_FAILED) {
            print('registration failed, closing connection');
            controlSocket.destroy();
            onError('registration failed');
            return;
          }

        } else if (msg['version'] == 0xff && msg['cmdCode'] == CMD_OPEN_FORWARDING) {
          // received a request to open a reverse connection
          print('request to open forwarding connection to port: ${msg['port']}');

          Socket.connect(brokerHost, msg['port']).then((Socket forwardSocket) {
            print('forwarding connection stablished!');

            bool granted = false;
            Socket remoteSocket;
            
            // save socket to close it later
            forwardingSockets.add(forwardSocket);

            forwardSocket.listen((List<int> data) {
              print('${data.length} bytes of data received from a forwarding connection');

              // NOTE: here starts the normal SOCKS protocol. The first msg should be a SOCKS4 request
              // to connect to some site. The following msgs just need to be forwarded 

              if (!granted) {
                // initial state: parse received message that should be a SOCKS request
                msg = parseProtocolMsg(data);
                print(msg);

                if (msg == null) {
                  print('invalid socks request, closing connection');
                  forwardSocket.close();
                  // TODO: should I return an error msg here instead of closing the connection?
                  return;

                } else if (msg['cmdCode'] == CMD_SOCKS_OPEN_CONNECTION) {
                  // received a valid SOCKS request, opening a connection with the remote host
                  print('valid socks request, stablishing connection with remote host');

                  Socket.connect(msg['ip'], msg['port']).then((Socket sock) {

                    remoteSocket = sock;

                    // save socket to close it later
                    remoteSockets.add(remoteSocket);

                    remoteSocket.listen((List<int> data) {
                      print('received ${data.length} bytes from remote host, retransmiting to client host');
                      forwardSocket.add(data);
                    }, onDone: () {
                      remoteSocket.close();
                    });

                    // connection with the remote host is stablised, inform the browser
                    print('connection stablished with remote host, sending back confirmation to the browser');
                    var resp = buildGrantedResponse();
                    forwardSocket.add(resp);

                    // set flag so following msgs are not interpreted as SOCKS
                    granted = true;
                  });

                } else {
                  // the msg is a valid SOCKS msg but is not a request. do nothing
                  print('valid socks msg received but is not of type request, closing the connection');
                  forwardSocket.close();
                  return;
                }

              } else {
                // already granted state: forward data to the remote host
                print('just retransmiting');
                remoteSocket.add(data);
              }
            }, onDone: () {
              print('forwardSocket was closed by the broker, closing here');
              forwardSocket.close();
            });
          });
        }

      }, onDone: () {
        print('controlSocket was closed by the broker, stopping');
        stop();
      });
    }).catchError( (e) => onError(e) );
	}


	void stop({Function() onDone, Function(String) onError}) {

	  if (onDone == null) {
	    onDone = () => print('worker stopped');
	  }

	  if (onError == null) {
	    onError = (e) => print('error stopping worker: $e');
	  }

    if (controlSocket == null) {
      onError('not connected');

    } else {

      for (var socket in forwardingSockets) {
        socket.destroy();
      }

      for (var socket in remoteSockets) {
        socket.destroy();
      }

      controlSocket.destroy();

      onDone();
      controlSocket = null;
    }
	}

}



void main(List<String> args) async {

	var exposePort = 8050;

	if (args.length > 0) {
		exposePort = int.parse(args[0]);
	} 

  var worker = new ProxyWorker();

  worker.register('localhost', 9999, exposePort);

  // wait 5 seconds
  // await new Future.delayed(const Duration(seconds : 5));

  // disconnect worker
  // worker.stop();
}


