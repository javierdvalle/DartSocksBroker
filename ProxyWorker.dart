import 'dart:core';
import 'dart:async';
import 'dart:io';
import 'Protocol.dart';


class ProxyWorker {

	void register(brokerHost, brokerPort, exposePort) {

		Socket.connect(brokerHost, brokerPort).then((Socket sock) {

			// send register request to the broker
			print('sending register request to broker at $brokerHost:$brokerPort for port $exposePort');
			List<int> msg = buildRegisterWorkerMsg(exposePort);
			sock.add(msg);

			// wait for messages from the broker in this "control" socket
			sock.listen((List<int> data) {

	            print('incoming ${data.length} bytes from broker');

  	            Map msg = parseProtocolMsg(data);

	            if (msg == null) {
	            	print('invalid msg');
	            	return;

	            } else if (msg['version'] == 0x00) {
	            	// response msg received

	            	if (msg['retCode'] == RCODE_REGISTER_SUCCESS) {
	            		print('registration succeeded');
	            		return;
	            	} else if (msg['retCode'] == RCODE_REGISTER_FAILED) {
	            		print('registration failed, closing connection');
	            		sock.close();
	            	}

	            } else if (msg['version'] == 0xff && msg['cmdCode'] == CMD_OPEN_FORWARDING) {
	            	// received a request to open a reverse connection
	            	print('request to open forwarding connection to port: ${msg['port']}');

	            	Socket.connect(brokerHost, msg['port']).then((Socket forwardSocket) {
	            		print('forwarding connection stablished!');

	            		bool granted = false;
				        Socket remoteSocket = null;

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

	            						remoteSocket.listen((List<int> data) {
	            						  print('received ${data.length} bytes from remote host, retransmiting to client host');
	            						  forwardSocket.add(data);
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
            			});
            		});
	            }

	        });
	    });
	}

}



void main(List<String> args) async {

	var exposePort = 8050;

	if (args.length > 0) {
		exposePort = int.parse(args[0]);
	} 

    var worker = new ProxyWorker();

    worker.register('localhost', 9999, exposePort);

}


