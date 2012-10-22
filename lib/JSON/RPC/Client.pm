use URI;
use JSON::Tiny;
use JSON::RPC::Error;

class JSON::RPC::Client;

has Code $.transport is rw = die 'Transport is missing';

has Bool $!is_batch = False;
has Bool $!is_notification = False;

INIT {

    # use ::(name) declarations instead of using meta in Rakudo 2012.10 with RT #115334 fix
    $?PACKAGE.^add_method('rpc.batch', sub ( $object ) { return $object.clone( :is_batch ) } );
    $?PACKAGE.^add_method('rpc.notification', sub ( $object ) { return $object.clone( :is_notification ) } );

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

multi submethod BUILD ( URI :$uri! ) {

    $!transport = &transport.assuming( uri => $uri );
}

multi submethod BUILD ( Str :$url! ) {

    $!transport = &transport.assuming( uri => URI.new( $url, :is_validating ) );
}

multi submethod BUILD ( Code :$transport! ) {

    $!transport = $transport;
}

# TODO: Replace it with HTTP::Client in the future
sub transport ( URI :$uri, Str :$json ) {
    
    # wrap request in HTTP Request
    my $request = 'POST ' ~ $uri.Str ~ ' HTTP/1.0' ~ "\x0D\x0A"
        ~ 'Content-Type: application/json' ~ "\x0D\x0A"
        ~ 'Content-Length: ' ~ $json.encode( 'UTF-8' ).bytes ~ "\x0D\x0A"
        ~ "\x0D\x0A"
        ~ $json;

    # make new connection to server
    # no keep-alive yet
    my $connection = IO::Socket::INET.new( host => $uri.host, port => $uri.port );

    # send request to server
    $connection.send( $request );

    # process status line
    my ( $HTTP-Version, $Status-Code, $Reason-Phrase ) = $connection.get( ).comb( /\S+/ );

    unless $Status-Code ~~ '200' {
        $connection.close( );
        JSON::RPC::TransportError.new( data => 'HTTP response is - ' ~ $Status-Code ~ ' ' ~ $Reason-Phrase ).throw;
    }

    my $body;
    loop {
        my $line = $connection.get( );

        # line that ends header section
        last if $line ~~ "\x0D";

        # for now another headers are ignored
        # they will be parsed properly after switch to HTTP::Transport
        next unless $line ~~ m/:i ^ 'Content-Length:' <ws> (\d+) /;

        # store body length
        $body = $/[0];
    }

    # RFC 2616
    # For compatibility with HTTP/1.0 applications, HTTP/1.1 requests
    # containing a message-body MUST include a valid Content-Length header
    # field unless the server is known to be HTTP/1.1 compliant.
    unless $body {
        $connection.close( );
        JSON::RPC::TransportError.new( data => 'HTTP response has unknown body length' ).throw;
    }

    # receive message body 
    $body = $connection.read( $body ).decode( );

    # close connection with server, no keep-alive yet
    $connection.close();
    
    return $body;
}

method !handler( Str :$method!, :$params ) {

    # container for request
    my %request = (

        # A String specifying the version of the JSON-RPC protocol.
        # MUST be exactly "2.0".
        'jsonrpc' => '2.0',

        # A String containing the name of the method to be invoked.
        'method' => $method,

        # generate random id to identify remote procedure call and response
        'id' => ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 ).roll( 32 ).join( )
    );

    # A Structured value that holds the parameter values
    # to be used during the invocation of the method.
    # This member MAY be omitted.
    %request{'params'} = $params if $params.defined;


    my $request = to-json( %request );
    my $response = $!transport.( json => $request );
    my %response = self.parse_json( $response );
    my $version = self.validate_response( |%response );

    # check id of response
    unless %request{'id'} ~~ %response{'id'} {
        JSON::RPC::TransportError.new( data => 'JSON RPC request id is different than response id' ).throw;
    }

    # failed procedure call, throw exception
    if %response{'error'}.defined {
        self.bind_error( |%response{'error'} );
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
