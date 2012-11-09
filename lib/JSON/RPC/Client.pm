use URI;
use LWP::Simple;
use JSON::Tiny;
use JSON::RPC::Error;

class JSON::RPC::Client;

has Code $.transport is rw = die 'Transport is missing';

has Code $.sequencer is rw = sub {
    state @pool = 'a' .. 'z', 'A' .. 'Z', 0 .. 9;
    
    return @pool.roll( 32 ).join( );
};

has Bool $.is_batch = False;
has Bool $.is_notification = False;

INIT {

    # install method auto dispatch
    $?PACKAGE.^add_fallback(

        # must return True or False to indicate if it can handle the fallback
        sub ( $object, $name ) { return True },
    
        # should return the Code object to invoke
        sub ( $object, $name ) {

            # placeholder variables cannot be passed-through
            # so dispatch has to be done manually depending on nature of passed params
            return method ( *%named, *@positional ) {
                if ?%named {
                    return $object!handler( method => $name, params => %named );
                }
                elsif ?@positional {
                    return $object!handler( method => $name, params => @positional );
                }
                else {
                    return $object!handler( method => $name );
                }
            };

        }

    );
    
}

multi submethod BUILD ( URI :$uri!, Code :$sequencer? ) {

    $!transport = &transport.assuming( uri => $uri );
	$!sequencer = $sequencer if $sequencer.defined;
}

multi submethod BUILD ( Str :$url!, Code :$sequencer? ) {

    $!transport = &transport.assuming( uri => URI.new( $url, :is_validating ) );
	$!sequencer = $sequencer if $sequencer.defined;
}

multi submethod BUILD ( Code :$transport!, Code :$sequencer? ) {

    $!transport = $transport;
	$!sequencer = $sequencer if $sequencer.defined;
}

method ::('rpc.batch') {
	return self.clone( :is_batch );
}

method ::('rpc.notification') {
	return self.clone( :is_notification );
}

# TODO: Replace it with HTTP::Client in the future
sub transport ( URI :$uri, Str :$json, Bool :$get_response ) {
    
	# HTTP protocol always have response
	# so get_response flag is ignored
	return LWP::Simple.post( ~$uri, { 'Content-Type' => 'application/json' }, $json );
}

method !handler( Str :$method!, :$params ) {

    # Response object template
    my %template = (

        # A String specifying the version of the JSON-RPC protocol.
        # MUST be exactly "2.0".
        'jsonrpc' => '2.0',

        # A String containing the name of the method to be invoked.
        'method' => $method,
    );
    
    # An identifier established by the Client
    # that MUST contain a String, Number, or NULL value if included.
    # If it is not included it is assumed to be a notification.
    %template{'id'} = self.sequencer.( ) unless $.is_notification;

    # A Structured value that holds the parameter values
    # to be used during the invocation of the method.
    # This member MAY be omitted.
    %template{'params'} = $params if $params.defined;

    my $request = to-json( %template );
    my $response;
	
    # A Request object that is a Notification signifies
    # the Client's lack of interest in the corresponding Response object
	if $!is_notification {
		$!transport.( json => $request, get_response => False );
		return;
	}
	else {
		$response = $!transport.( json => $request, get_response => True );
	}
    
    my %response = self.parse_json( $response );
    my $version = self.validate_response( |%response );

    # failed procedure call, throw exception
    if %response{'error'}.defined {
        self.bind_error( |%response{'error'} );
    }

    # This member is REQUIRED.
    # It MUST be the same as the value of the id member in the Request Object.
    unless %template{'id'} eqv %response{'id'} {
        JSON::RPC::TransportError.new( data => 'JSON RPC request id is different than response id' ).throw;
    }

    # successful remote procedure call
    return %response{'result'};
}

method parse_json ( Str $body ) {

    my %parsed;

    try { %parsed = from-json( $body ); };

    JSON::RPC::TransportError.new( data => 'JSON parsing failed - ' ~ $! ).throw if defined $!;

    return %parsed;
}

multi method validate_response (

    # A String specifying the version of the JSON-RPC protocol. MUST be exactly "2.0".
    Str :$jsonrpc! where '2.0',

    # This member is REQUIRED on success.
    # This member MUST NOT exist if there was an error invoking the method.
    # INFO: as explained in RT 109182 lack of presence cannot be tested in signature
    # so "result":null is incorrectly assumed to be to be valid -
    # this is not dangerous because upper logic can recognize this case
    # HACK: mutually exclusive error and result members are checked later
    :$result?,

    # This member is REQUIRED on error.
    # This member MUST NOT exist if there was no error triggered during invocation.
    # INFO: as explained in RT 109182 lack of presence cannot be tested in signature
    # so "error":null is incorrectly assumed to be to be valid -
    # this is not dangerous because upper logic can recognize this case
    :$error? where {
        # test if error and result params are mutually exclusive
        # this check is performed even if error is not given
        ( $result.defined xor $error.defined )
        # INFO: error format is checked later
    },

    # This member is REQUIRED.
    # It MUST be the same as the value of the id member in the Request Object.
    # INFO: comparison with request id is on upper level 
    :$id!
) {
    # spec version number
    return 2.0;
}

multi method validate_response {

    # none of above spec signatures claimed protocol version number
    JSON::RPC::TransportError.new( data => 'JSON-RPC Response Object is not valid' ).throw;
}

multi method bind_error (
    # A Number that indicates the error type that occurred.
    # This MUST be an integer.
    Int :$code!,

    # A String providing a short description of the error.
    # The message SHOULD be limited to a concise single sentence.
    Str :$message!,

    # A Primitive or Structured value that contains additional information about the error.
    # This may be omitted.
    :$data?,
)
{
    given $code {
        when -32700 {
            JSON::RPC::ParseError.new( data => $data).throw;
        }
        when -32600 {
            JSON::RPC::InvalidRequest.new( data => $data).throw;
        }
        when -32601 {
            JSON::RPC::MethodNotFound.new( data => $data).throw;
        }
        when -32602 {
            JSON::RPC::InvalidParams.new( data => $data).throw;
        }
        when -32603 {
            JSON::RPC::InternalError.new( data => $data).throw;
        }
        default {
            JSON::RPC::Error.new( code => $code, message => $message, data => $data ).throw;
        }
    }

}

multi method bind_error {

    # none of above spec signatures claimed error field format
    JSON::RPC::TransportError.new( data => 'JSON-RPC Response Object is not valid' ).throw;
}
