# JSON-PRC 2.0 spec defines Error Object in chapter 5.1
# derived from http://xmlrpc-epi.sourceforge.net/specs/rfc.fault_codes.php

role X::JSON::RPC is Exception {

    # SPEC: When a rpc call encounters an error,
    # the Response Object MUST contain the error member
    # with a value that is a Object with the following members:

    # SPEC: A Number that indicates the error type that occurred.
    # This MUST be an integer.
    has Int $.code is rw;

    # SPEC: A String providing a short description of the error.
    # The message SHOULD be limited to a concise single sentence.
    has Str $.message is rw;

    # SPEC: A Primitive or Structured value that contains additional information about the error.
    # This may be omitted.
    has Any $.data is rw;

    # stringify output for debug purposes.
    method Str ( ) {
        my $error = $.message ~ ' (' ~ $.code ~ ')';
        $error ~= ': ' ~ $.data.perl if $.data.defined;

        return $error;
    }

    # make response error member for serving purposes.
    method Hash {
        my %error = (
            'code' => $.code,
            'message' => $.message,
        );
        %error{'data'} = $.data if $.data.defined;

        return %error;
    }

    # make gist output for console printing purposes
    method gist ( ) {
        return self.Str;
    }

}

# invalid JSON was received by the server.
# an error occurred on the server while parsing the JSON text.
class X::JSON::RPC::ParseError does X::JSON::RPC {

    method new ( :$data ) {
        self.bless( code => -32700, message => 'Parse error', data => $data );
    }

}

# the JSON sent is not a valid Request object
class X::JSON::RPC::InvalidRequest does X::JSON::RPC {

    method new ( :$data ) {
        self.bless( code => -32600, message => 'Invalid Request', data => $data );
    }

}

# the method does not exist / is not available
class X::JSON::RPC::MethodNotFound does X::JSON::RPC {

    method new ( :$data ) {
        self.bless( code => -32601, message => 'Method not found', data => $data );
    }

}

# invalid method parameter(s)
class X::JSON::RPC::InvalidParams does X::JSON::RPC {

    method new ( :$data ) {
        self.bless( code => -32602, message => 'Invalid params', data => $data );
    }

}

# internal JSON-RPC error
class X::JSON::RPC::InternalError does X::JSON::RPC {

    method new ( :$data ) {
        self.bless( code => -32603, message => 'Internal error', data => $data );
    }

}

# protocol error
class X::JSON::RPC::ProtocolError does X::JSON::RPC {

    method new ( :$message, :$data ) {
        self.bless( code => -32000, message => $message // 'Protocol Error', data => $data );
    }

}
