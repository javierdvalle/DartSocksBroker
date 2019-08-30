// Protocol: 
//
// (Worker -> Broker)Register worker message 
// version(0xff) | registerCode(0xf0) | portByte1 | portByte2
//
// (Broker -> Worker)Success/Failed
// 0x00 | SuccessCode(0x6a) | portByte1 | portByte2
// 0x00 | FailedCode(0x6b) | portByte1 | portByte2
//
// (Broker -> Worker) Open forwarding connection request
// version(0xff) | openForwardingCode(0xf1) | portByte1 | portByte2
//
// (Worker -> Broker) Worker connects to the given port
//
// (Broker -> Worker) Broker sends a typical SOCKS4 request, forwarded from browser
// version(0x04) | commandCode(0x01) | port (two bytes) | ip (two bytes) | userIdString (variable length, ending with 0x00) 
//

// commands
const CMD_SOCKS_OPEN_CONNECTION = 0x01;
const CMD_SOCKS_BIND_PORT = 0x02;
const CMD_REGISTER_WORKER = 0xf0;
const CMD_OPEN_FORWARDING = 0xf1;

// return codes
const RCODE_GRANTED = 0x5a;
const RCODE_REJECTED = 0x5b;
const RCODE_NO_IDENTD = 0x5c;
const RCODE_IDENTD_FAILED = 0x5d; 
const RCODE_REGISTER_SUCCESS = 0x6a;
const RCODE_REGISTER_FAILED = 0x6b;

Map parseProtocolMsg(List<int> data) {

	var version = data[0];

	if (version == 0x00) {
		// msg is a response
		var retCode = data[1];
		return {
			'version': version,
			'retCode': retCode,
		};

	} else if (version == 0xff) {
		// protocol extension
		var cmdCode = data[1];
		var portBytes = data.sublist(2,4);
		var port = portBytes[0] * 256 + portBytes[1];
		return {
			'version': version,
			'cmdCode': cmdCode,
			'portBytes': portBytes,
			'port': port,
		};
	} else if (version == 0x04) {
		// SOCKS4
		var cmdCode = data[1];
		var portBytes = data.sublist(2,4);
		var port = portBytes[0] * 256 + portBytes[1];
		var ipBytes = data.sublist(4, 8);
		var ip = "${ipBytes[0]}.${ipBytes[1]}.${ipBytes[2]}.${ipBytes[3]}";
		var userIdBytes = data.sublist(8, data.length-1);
		var userId = String.fromCharCodes(userIdBytes);
		var nullEnd = data[data.length-1];
		if (nullEnd != 0) {
		  print('error, invalid message');
		  return null;
		}
		return {
		  'version': version,
		  'cmdCode': cmdCode,
		  'port': port,
		  'portBytes': portBytes,
		  'ip': ip,
		  'ipBytes': ipBytes,
		  'userId': userId,
		  'userIdBytes': userIdBytes,
		};
	} else {
		print('version not supported');
		return null;
	}
}


List<int> buildGrantedResponse() {
  return [0x00, RCODE_GRANTED, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
}


List<int> buildRejectedResponse() {
  return [0x00, RCODE_REJECTED, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
}


List<int> buildRegisterWorkerMsg(port) {
	int portByte1 = port~/256;
	int portByte2 = port%256;
	return [0xff, CMD_REGISTER_WORKER, portByte1, portByte2];
}


List<int> buildOpenForwardingMsg(port) {
	int portByte1 = port~/256;
	int portByte2 = port%256;
	return [0xff, CMD_OPEN_FORWARDING, portByte1, portByte2];
}


List<int> buildRegisterSuccessResponse(port) {
	int portByte1 = port~/256;
	int portByte2 = port%256;
    return [0x00, RCODE_REGISTER_SUCCESS, portByte1, portByte2];
}


List<int> buildRegisterRejectedResponse(port) {
	int portByte1 = port~/256;
	int portByte2 = port%256;
    return [0x00, RCODE_REGISTER_FAILED, portByte1, portByte2];
}


