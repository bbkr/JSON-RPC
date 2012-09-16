# JSON-PRC 2.0 spec defines Error Object in chapter 5.1
# derived from http://xmlrpc-epi.sourceforge.net/specs/rfc.fault_codes.php

role JSON::RPC::Error is Exception {

    # When a rpc call encounters an error,
    # the Response Object MUST contain the error member
    # with a value that is a Object with the following members:

    # A Number that indicates the error type that occurred.
    # This MUST be an integer.
    has Int $.code is rw;

    # A String providing a short description of the error.
    # The message SHOULD be limited to a concise single sentence.
    has Str $.message is rw;

    # A Primitive or Structured value that contains additional information about the error.
    # This may be omitted.
    has Any $.data is rw;

    # Stringify output for debug purposes.
    method Str ( ) {
        my $error = $.message ~ ' (' ~ $.code ~ ')';
        $error ~= ': ' ~ $.data.perl if $.data.defined;

        return $error;
    }

    # Make response error member for serving purposes.
    method Hash {
        my %error = (
            'code' => $.code,
            'message' => $.message,
        );
        %error{'data'} = $.data if $.data.defined;

        return %error;
    }

    # Make gist output for console printing purposes
    method gist ( ) {
        return self.Str;
    }

}

# Invalid JSON was received by the server.
# An error occurred on the server while parsing the JSON text.
class JSON::RPC::ParseError does JSON::RPC::Error {

    method new ( :$data ) {
        self.bless( *, code => -32700, message => 'Parse error.', data => $data );
    }

}

# The JSON sent is not a valid Request object.
class JSON::RPC::InvalidRequest does JSON::RPC::Error {

    method new ( :$data ) {
        self.bless( *, code => -32600, message => 'Invalid Request.', data => $data );
    }

}

# The method does not exist / is not available.
class JSON::RPC::MethodNotFound does JSON::RPC::Error {

    method new ( :$data ) {
        self.bless( *, code => -32601, message => 'Method not found.', data => $data );
    }

}

# Invalid method parameter(s).
class JSON::RPC::InvalidParams does JSON::RPC::Error {

    method new ( :$data ) {
        self.bless( *, code => -32602, message => 'Invalid params.', data => $data );
    }

}

# Internal JSON-RPC error.
class JSON::RPC::InternalError does JSON::RPC::Error {

    method new ( :$data ) {
        self.bless( *, code => -32603, message => 'Internal error.', data => $data );
    }

}

# Transport error.
class JSON::RPC::TransportError does JSON::RPC::Error {

    method new ( :$data ) {
        self.bless( *, code => -32300, message => 'Transport error.', data => $data );
    }

}
